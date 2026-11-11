# backd8 GitHub access helpers: check whether this PC can push to the repo's remote, and guide/perform sign-in.
# Dot-sourced by lib.ps1 (uses Git-Out / Get-RepoRoot / Get-PushState from repo.ps1).
# Nothing here stores credentials itself: sign-in is delegated to git's credential helper (Git Credential Manager ships
# with Git for Windows), to the GitHub CLI, or to SSH keys - whichever the repo's remote URL needs.

function Test-GitInstalled { [bool](Get-Command git -ErrorAction SilentlyContinue) }
$script:GitInstallHint = 'Git is not installed. Install it (it includes Git Credential Manager for GitHub sign-in):  winget install --id Git.Git -e   or  https://git-scm.com/download/win'

function Quote-Arg([string]$a) { if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }; $s = [regex]::Replace($a, '(\\*)"', '$1$1\"'); $s = [regex]::Replace($s, '(\\+)$', '$1$1'); '"' + $s + '"' }

# git with a hard timeout, optional extra environment variables; returns combined stdout+stderr text.
function Invoke-GitTimed([string]$Repo, [string[]]$GitArgs, [int]$TimeoutMs = 25000, [hashtable]$EnvVars = @{}) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = 'git'; $psi.WorkingDirectory = $Repo; $psi.Arguments = (@(@('-c', 'core.fsmonitor=false', '-c', 'protocol.ext.allow=never') + @($GitArgs) | ForEach-Object { Quote-Arg "$_" })) -join ' '
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutMs)) {
    try { & taskkill.exe /F /T /PID $p.Id *> $null } catch {}   # also kills git-remote-https / credential helpers
    try { $p.Kill() } catch {}
    return [pscustomobject]@{ Code = -1; Out = ''; TimedOut = $true }
  }
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = (($o.Result + "`n" + $e.Result).Trim()); TimedOut = $false }
}

# Does git's output mean "you are not signed in / not allowed", as opposed to a network or history problem?
function Test-AuthError([string]$t) {
  $t -match 'Authentication failed|could not read (Username|Password)|terminal prompts disabled|Permission denied \(publickey|Permission denied, please try again|Too many authentication failures|Repository not found|Invalid username or (password|token)|password authentication was removed|returned error: 40[13]|HTTP 40[13]|Permission to .* denied|Missing or invalid credentials|credential-manager.*(fail|cancel)|Support for password'
}

# What went wrong, in terms of what the user can do about it. Kind: saml | hostkey | notfound | auth | temporary | network | other
function Get-GitProblem([string]$t) {
  if ($t -match 'GH001|Large files detected|file size limit') { return [pscustomobject]@{ Kind = 'toolarge'; Advice = 'GitHub rejected a file bigger than 100 MB. It is already inside one of your commits, so it has to be removed from your history before GitHub accepts the push (for example: git rm --cached <file>, then git commit --amend), or use Git LFS (https://git-lfs.com). Files over 100 MB cannot be uploaded in a normal commit.' } }
  if ($t -match 'SAML|single sign-on|organization.*\bSSO\b|\bSSO\b.*organization') { return [pscustomobject]@{ Kind = 'saml'; Advice = 'Your login is fine, but this GitHub organization requires single sign-on (SSO). Open https://github.com/settings/tokens (or https://github.com/settings/keys for SSH), click "Configure SSO" next to your token/key and authorise the organization. Then try again.' } }
  if ($t -match 'Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED') { return [pscustomobject]@{ Kind = 'hostkey'; Advice = 'SSH could not verify the server''s host key. In a terminal run  ssh -T git@github.com  and accept the fingerprint only if it matches https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints  - or switch the remote to HTTPS.' } }
  if ($t -match 'Repository not found|returned error: 404') { return [pscustomobject]@{ Kind = 'notfound'; Advice = 'GitHub says the repository was not found. Check the address, create the empty repository at https://github.com/new if it does not exist yet, or sign in with an account that can write to it (GitHub gives this same answer for private repositories you cannot see).' } }
  if ($t -match 'Permission to (\S+) denied to (\S+)') { return [pscustomobject]@{ Kind = 'noaccess'; Advice = "You are signed in as '$($Matches[2])', but GitHub says that account may not write to $($Matches[1]). Ask the owner to add you as a collaborator, sign in with a different account (command line: backdate account <folder> <name>), or fork the repository and publish to your fork." } }
  if (Test-AuthError $t) { return [pscustomobject]@{ Kind = 'auth'; Advice = $null } }
  if ($t -match 'returned error: (429|5\d\d)|HTTP (429|5\d\d)|rate limit|Service Unavailable|Bad Gateway|Gateway Time-?out|Internal Server Error') { return [pscustomobject]@{ Kind = 'temporary'; Advice = 'GitHub (or a proxy in between) returned a temporary error or is rate-limiting you. Wait a minute and try again.' } }
  if ($t -match 'Could not resolve host|Failed to connect|Connection (timed out|refused|reset|was reset)|Recv failure|hung up unexpectedly|transfer closed|early EOF|RPC failed|Network is unreachable|SSL|schannel|certificate|proxy') { return [pscustomobject]@{ Kind = 'network'; Advice = 'Could not reach the server (offline, firewall, proxy or certificate problem). Check your internet connection and the address.' } }
  [pscustomobject]@{ Kind = 'other'; Advice = $null }
}

function Get-Transport([string]$url) {
  if (-not $url) { 'none' }
  elseif ($url -match '^https?://') { 'https' }
  elseif ($url -match '^git://') { 'git' }
  elseif ($url -match '^ssh://' -or $url -match '^[\w.-]+@[\w.-]+:') { 'ssh' }
  else { 'local' }
}

function Get-GitHubAccess([string]$Path) {
  if (-not (Test-GitInstalled)) { return [pscustomobject]@{ GitInstalled = $false; Ready = $false; CanPush = $null; Detail = $script:GitInstallHint; Advice = @($script:GitInstallHint) } }
  $repo = Get-RepoRoot $Path
  $s = Get-PushState $repo
  $transport = Get-Transport $s.Url
  $name = (Git-Out $repo @('config', 'user.name')).Out | Select-Object -First 1
  $mail = (Git-Out $repo @('config', 'user.email')).Out | Select-Object -First 1
  $helper = @(); foreach ($hv in (Git-Out $repo @('config', '--get-all', 'credential.helper')).Out) { if ($hv -eq '') { $helper = @() } else { $helper += $hv } }   # an empty entry resets the list
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  $ghIn = $false; if ($gh) { & gh auth status *> $null; $ghIn = ($LASTEXITCODE -eq 0) }
  $accounts = @(); $acctUsed = $null; $acctChoice = $false
  if (($helper -join ' ') -match 'manager') { $accounts = @(Get-GitHubAccounts); $ra = Resolve-GitHubAccount $repo $s.Url; if ($ra) { $acctUsed = $ra.Name } elseif ($accounts.Count -gt 1 -and $s.Url -match 'github\.com') { $acctChoice = $true } }

  $can = $null; $detail = ''; $problem = $null
  if ($s.Url -match '^(\\\\\\\\|//)' -or $s.Url -match '^(ext|fd)::') { $transport = 'blocked'; $detail = 'This remote address is not checked (network shares and special transports are not supported).' }
  elseif ($s.Url -and $transport -ne 'none') {
    # An unborn branch has nothing to push yet: probe with an unreferenced empty-tree commit so the sign-in check still tests real access.
    $src = "refs/heads/$($s.Branch)"; $penv = @{ GIT_TERMINAL_PROMPT = '0'; GCM_INTERACTIVE = 'never'; GIT_SSH_COMMAND = 'ssh -o BatchMode=yes -o ConnectTimeout=15' }
    if ((Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')).Code) {
      $pe = @{ GIT_AUTHOR_NAME = 'backd8'; GIT_AUTHOR_EMAIL = 'probe@backd8.invalid'; GIT_COMMITTER_NAME = 'backd8'; GIT_COMMITTER_EMAIL = 'probe@backd8.invalid' }
      $pc = Invoke-GitTimed $repo @('commit-tree', '4b825dc642cb6eb9a060e54bf8d69288fbee4904', '-m', 'backd8 access probe') 10000 $pe
      if (-not $pc.Code -and $pc.Out -match '^[0-9a-f]{40}$') { $src = $pc.Out.Trim() }
    }
    $r = Invoke-GitTimed $repo (@(Get-CredentialArgs $repo $s.Url) + @('push', '--dry-run', $s.Remote, "${src}:$($s.DestRef)")) 25000 $penv
    $detail = Hide-Secrets $r.Out
    if ($r.TimedOut) { $detail = 'Timed out contacting the remote.' }
    elseif ($r.Code -eq 0 -or $r.Out -match 'rejected|non-fast-forward|fetch first|Everything up-to-date') { $can = $true }
    else {
      $problem = Get-GitProblem $r.Out
      if ($problem.Kind -in 'auth', 'notfound', 'saml', 'hostkey', 'noaccess') { $can = $false }
    }
  }
  if ($transport -eq 'local' -and $s.Url -and $s.Url -notmatch '^file://' -and -not (Test-Path -LiteralPath $s.Url)) { $can = $false; $detail = "The folder $($s.Url) does not exist." }
  if ($transport -eq 'git') { $can = $false; $detail = 'git:// addresses are read-only.' }

  $adv = New-Object Collections.Generic.List[string]
  if (-not $name -or -not $mail) { $adv.Add('Git does not know who you are (needed for new commits). Run:  git config --global user.name "Your Name"  and  git config --global user.email "you@example.com"') }
  if (-not $s.Url) { $adv.Add("This repository has no remote named '$($s.Remote)'. Create an empty repository on GitHub (https://github.com/new), then run:  git remote add origin https://github.com/<you>/<repo>.git") }
  elseif ($transport -eq 'local') { }
  elseif ($transport -eq 'git') { $adv.Add('git:// is read-only. Use an https:// or ssh address for pushing:  git remote set-url origin https://github.com/<you>/<repo>.git') }
  elseif ($can -eq $false -and $transport -eq 'local') { $adv.Add("The remote path does not exist: $($s.Url)") }
  elseif ($can -eq $false -and $problem -and $problem.Kind -in 'saml', 'hostkey', 'notfound', 'noaccess') { $adv.Add($problem.Advice) }
  elseif ($can -eq $false -and $acctChoice) {
    $adv.Add("Several GitHub accounts are saved on this PC ($($accounts -join ', ')) and this project's address does not say which one to use. Choose the account for this project (window: 'Sign in to GitHub' > choose; command line: backdate account <folder> <name>).")
  }
  elseif ($can -eq $false) {
    if ($transport -eq 'ssh') {
      $adv.Add('Not authorised over SSH. Create a key with  ssh-keygen -t ed25519 -C "you@example.com"  and add the .pub file at https://github.com/settings/ssh/new , then run backdate github-login <folder> (or use "Sign in to GitHub") to test it - or switch the remote to HTTPS:  git remote set-url origin https://github.com/<you>/<repo>.git')
    } elseif ($helper -join ' ' -match 'manager') {
      $adv.Add('Not signed in to GitHub on this PC. Sign in (window: "Sign in to GitHub"; command line: backdate github-login <folder>): Git Credential Manager opens your browser; approve it once and Windows remembers you.')
    } elseif ($gh) {
      $adv.Add('Not signed in to GitHub on this PC. Sign in (window: "Sign in to GitHub"; command line: backdate github-login <folder>), or run gh auth login yourself.')
    } else {
      $adv.Add('Not signed in to GitHub and no credential helper was found. Install Git for Windows (includes Git Credential Manager) or the GitHub CLI:  winget install --id GitHub.cli -e  then sign in. A personal access token (https://github.com/settings/tokens, scope "repo") also works as the password.')
    }
    $adv.Add('If you ARE signed in: GitHub also says "not found" when the repository does not exist or your account lacks write access.')
  }
  elseif ($null -eq $can -and $s.Url) { $adv.Add($(if ($problem -and $problem.Advice) { $problem.Advice } else { 'Could not verify access (offline, firewall or timeout). Check your internet connection and the remote URL.' })) }

  [pscustomobject]@{
    GitInstalled = $true; Repo = $repo; Remote = $s.Remote; Url = $s.Url; Transport = $transport; IsGitHub = [bool]($s.Url -match 'github\.com')
    UserName = $name; UserEmail = $mail; Helpers = $helper; GhInstalled = [bool]$gh; GhLoggedIn = $ghIn; Accounts = $accounts; AccountInUse = $acctUsed; NeedsAccountChoice = $acctChoice
    CanPush = $can; Detail = $detail; Advice = @($adv); Problem = $(if ($problem) { $problem.Kind }); Ready = [bool]($can -eq $true)
  }
}

# Opens the right sign-in flow. GUI: a visible console window (the app itself has none). CLI: -Inline uses the current console.
# No cmd.exe and no string building: the commands travel as base64 JSON, so repository, remote and branch names (which come from a
# project's own .git/config and can contain & ; $ ( ) ...) can never be interpreted by a shell.
function Test-SafeRefName([string]$n) { $n -match '^[\w./+@-]+$' -and $n -notmatch '^-' -and $n -notmatch '\.\.' }

function Start-VisibleScript([object[]]$Commands) {
  $json = ConvertTo-Json -InputObject @{ cmds = @($Commands) } -Depth 6 -Compress
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
  $script = '$Host.UI.RawUI.WindowTitle = ''backd8 - GitHub sign-in''; Write-Host ''backd8: signing in to GitHub. A browser window or a prompt may appear. This window closes when finished.''; ' +
    '$j = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(''' + $b64 + ''')) | ConvertFrom-Json; $bad = $false; ' +
    'foreach ($c in $j.cmds) { $a = @($c.args); & $c.exe @a; if ($LASTEXITCODE) { $bad = $true } }; ' +
    'if ($bad) { Write-Host ''''; Write-Host ''If the message above says "rejected" or "fetch first", the sign-in itself worked.''; [void](Read-Host ''Press Enter to close'') }'
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc) -Wait
}

function Connect-GitHub([string]$Path, [switch]$Inline) {
  if (-not (Test-GitInstalled)) { throw $script:GitInstallHint }
  $a = Get-GitHubAccess $Path
  if (-not $a.Url) { throw ($a.Advice -join "`n") }
  if ($a.Transport -eq 'local') { return $a }
  $repo = $a.Repo; $s = Get-PushState $repo
  if (-not (Test-SafeRefName $s.Remote) -or $s.DestRef -notmatch '^refs/heads/' -or -not (Test-SafeRefName ($s.DestRef -replace '^refs/heads/', '')) -or -not (Test-SafeRefName $s.Branch)) {
    throw "This project uses an unusual remote or branch name ('$($s.Remote)', '$($s.DestRef)'), so backd8 will not start a sign-in for it. Sign in from a terminal with: git push --dry-run"
  }
  $refspec = "refs/heads/$($s.Branch):$($s.DestRef)"
  $cmds = New-Object Collections.Generic.List[object]
  if ($a.Transport -eq 'ssh') {
    $cmds.Add(@{ exe = 'ssh'; args = @('-T', 'git@github.com') })
  } elseif (-not ($a.Helpers -join ' ' -match 'manager') -and $a.GhInstalled -and -not $a.GhLoggedIn) {
    $cmds.Add(@{ exe = 'gh'; args = @('auth', 'login', '-w', '-p', 'https') }); $cmds.Add(@{ exe = 'gh'; args = @('auth', 'setup-git') })
  } else {
    # a real (dry-run) push is the one action every credential helper reacts to: GCM opens the browser, a plain console asks for user/token
    $src = if ((Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')).Code) { $null } else { "refs/heads/$($s.Branch)" }
    if (-not $src) {   # unborn branch: probe with an unreferenced empty-tree commit
      $pe = @{ GIT_AUTHOR_NAME = 'backd8'; GIT_AUTHOR_EMAIL = 'probe@backd8.invalid'; GIT_COMMITTER_NAME = 'backd8'; GIT_COMMITTER_EMAIL = 'probe@backd8.invalid' }
      $pc = Invoke-GitTimed $repo @('commit-tree', '4b825dc642cb6eb9a060e54bf8d69288fbee4904', '-m', 'backd8 access probe') 10000 $pe
      if (-not $pc.Code -and $pc.Out -match '^[0-9a-f]{40}$') { $src = $pc.Out.Trim() }
    }
    $cmds.Add(@{ exe = 'git'; args = @('-C', $repo) + @(Get-CredentialArgs $repo $s.Url) + @('push', '--dry-run', $s.Remote, "$($src):$($s.DestRef)") })
  }
  if ($Inline) {
    foreach ($c in $cmds) { Write-Host "> $($c.exe) $($c.args -join ' ')"; $ca = @($c.args); & $c.exe @ca }
  } else { Start-VisibleScript $cmds.ToArray() }
  $script:AcctCache.At = [datetime]::MinValue
  $ra = Resolve-GitHubAccount $repo $s.Url
  if ($ra -and $ra.Source -eq 'repository owner') { try { [void](Set-GitHubAccount $repo $ra.Name) } catch {} }   # remember it so plain git and later checks use the same account
  Get-GitHubAccess $Path
}
# ---------- several GitHub accounts on one PC ----------
# Git Credential Manager asks "which account?" when more than one github.com account is saved and the address names none.
# Background checks run without prompts, so they used to report "not signed in" forever. We pin the account that owns the repo.
$script:AcctCache = @{ At = [datetime]::MinValue; List = @() }
function Get-GitHubAccounts {
  if (((Get-Date) - $script:AcctCache.At).TotalSeconds -lt 60) { return @($script:AcctCache.List) }
  $l = @()
  if ((Test-GitInstalled) -and (@(git config --get-all credential.helper 2>$null) -join ' ') -match 'manager') {
    $r = Invoke-GitTimed $env:USERPROFILE @('credential-manager', 'github', 'list') 10000 @{ GCM_INTERACTIVE = 'never' }
    if (-not $r.TimedOut -and $r.Code -eq 0) { $l = @($r.Out -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -match '^[\w.-]+$' }) }
  }
  $script:AcctCache = @{ At = Get-Date; List = $l }
  $l
}
function Get-GitHubOwner([string]$Url) {
  if ($Url -match '^https?://(?:[^@/]+@)?github\.com/([^/]+)/') { return $Matches[1] }
  if ($Url -match '^(?:ssh://)?[\w.-]+@github\.com[:/]([^/]+)/') { return $Matches[1] }
  $null
}
# Which saved account this project should use: the one set for the project, else the owner of the repository address, else $null (ambiguous).
function Resolve-GitHubAccount([string]$Repo, [string]$Url) {
  if ($Url -notmatch '^https?://(?:[^@/]+@)?github\.com/') { return $null }
  $explicit = (Git-Out $Repo @('config', 'credential.https://github.com.username')).Out | Select-Object -First 1
  if ($explicit) { return [pscustomobject]@{ Name = "$explicit"; Source = 'project setting' } }
  $acc = @(Get-GitHubAccounts); if ($acc.Count -le 1) { return $null }
  $owner = Get-GitHubOwner $Url
  $hit = $acc | Where-Object { $_ -ieq $owner } | Select-Object -First 1
  if ($hit) { return [pscustomobject]@{ Name = $hit; Source = 'repository owner' } }
  $null
}
# "-c credential.https://github.com.username=<account>" when the account is known but not yet written into the project.
function Get-CredentialArgs([string]$Repo, [string]$Url) {
  if (-not $Repo -or -not $Url) { return @() }
  $explicit = (Git-Out $Repo @('config', 'credential.https://github.com.username')).Out | Select-Object -First 1
  if ($explicit) { return @() }
  $a = Resolve-GitHubAccount $Repo $Url
  if ($a) { @('-c', "credential.https://github.com.username=$($a.Name)") } else { @() }
}
function Set-GitHubAccount([string]$Path, [string]$Account) {
  $repo = Get-RepoRoot $Path
  if ($Account -notmatch '^[\w.-]+$') { throw 'That does not look like a GitHub user name.' }
  $r = Git-Out $repo @('config', '--local', 'credential.https://github.com.username', $Account)
  if ($r.Code) { throw "Could not save the account choice: $($r.Out -join ' ')" }
  $script:AcctCache.At = [datetime]::MinValue
  "This project will use the GitHub account '$Account'."
}