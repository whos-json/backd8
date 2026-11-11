# CLI + git hook entry. Usage:
#   backdate install [-Force] | uninstall | on | off | status | list
#   backdate set <repo-folder|*> <date> | remove <folder> | hook
#   backdate commits <folder> [count]          list recent commits (default 20)
#   backdate reword  <folder> <sha> <message>   change a commit message (rewrites history, keeps a backup ref)
#   backdate reword  <folder> <sha> -MessageFile <file>   same, message (multi-line ok) read from a UTF-8 file
#   backdate redate  <folder> <sha> <date>      change a commit date
#   backdate undo    <folder> [-Force]          undo the last reword/redate on the current branch
#   backdate push    <folder> [-Force] [-DiscardRemote]   push the current branch to its remote (GitHub)
#   backdate init    <folder> [github-url]             turn a plain folder into a git project (and link it to GitHub)
#   backdate remote  <folder> <github-url>             link (or re-link) the project to its GitHub repository
#   backdate changes <folder>                          list files changed since the last commit
#   backdate commit  <folder> <message> [-Staged] [-Date <date>]   commit all changes (or only staged ones) with your message / date
#   backdate publish <folder> <message>|-MessageFile <file> [-Date <date>] [-Force]   commit all changes (if any), then push (one step)
#     commit/publish refuse secret-looking files (.env, keys, ...) unless you add -IncludeRisky
#   backdate sync    <folder>                          get newer changes from GitHub (fast-forward or merge; never rewrites your commits)
#   backdate ignore  <folder> [dotnet|node|python|java|generic]   add a .gitignore so build/IDE files are not committed
#   backdate account <folder> [name]                   show / choose which saved GitHub account this project uses (when you have several)
#   backdate trust   <folder>                          allow backd8 to open a project whose own git settings can run programs (only for projects you made or trust)
#   backdate state   <folder> [-Online]                where is this project in the workflow? shows the state, what you can do next and why other actions are disabled
#   backdate state-model                               prove the workflow model: deterministic, total, no dead ends, every state can reach "everything is published"
#   backdate github       <folder>   check this PC can push (git identity, remote, GitHub sign-in)
#   backdate github-login <folder>   sign in to GitHub (browser via Git Credential Manager, gh, or SSH test)
# <sha> may be a short/full sha, HEAD~2, a branch or a tag. Dates: 2024-03-01 or 2024-03-01T14:30:00.
# Tips: a message starting with '-' or containing quotes is easiest via -MessageFile. In cmd.exe quote '&'.
param([string]$Command = 'status', [string]$Arg1, [string]$Arg2, [string]$Arg3, [string]$MessageFile, [string]$Date, [switch]$Staged, [switch]$IncludeRisky, [switch]$Online, [switch]$Force, [switch]$DiscardRemote)
. "$PSScriptRoot\lib.ps1"
function Need([string]$v, [string]$what) { if (-not $v) { throw "Missing argument: $what" }; $v }
function Read-MessageText([string]$file, [string]$inline, [string]$what) {
  if ($file) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Message file not found: $file" }; return [IO.File]::ReadAllText((Resolve-Path -LiteralPath $file).Path, [Text.Encoding]::UTF8) }
  Need $inline $what
}
# CLI safety net: secret-looking files are not committed unless you say -IncludeRisky.
function Assert-NoRisky([string]$folder, [switch]$ok) {
  if ($ok) { return }
  $r = @(Get-WorkingChanges $folder | Where-Object { $_.Risky -and $_.Kind -ne 'deleted' })
  if ($r.Count) { throw "These files look like they hold passwords or keys: $(@($r | Select-Object -First 5 | ForEach-Object { $_.Path }) -join ', '). Add them to .gitignore, or commit anyway with -IncludeRisky." }
}
function Show-Usage { foreach ($l in (Get-Content -LiteralPath $PSCommandPath)) { if ($l -notmatch '^#') { break }; $l -replace '^# ?', '' } }
function Show-Rewrite($r, [string]$repoArg, [string]$what) {
  $what
  "Done. Changed $($r.Edited) commit(s)$(if ($r.Rewritten -gt $r.Edited) { ", and $($r.Rewritten - $r.Edited) later commit(s) were re-saved with new IDs" }). To go back: backdate undo `"$repoArg`""
  foreach ($w in @($r.Warnings)) { if ($w) { "Warning: $w" } }
  if ($r.SignaturesDropped) { "Warning: $($r.SignaturesDropped) rewritten commit(s) were signed; the signatures could not be kept." }
  if (@($r.StaleRefs).Count) { "Note: these still point at the OLD commits: $(@($r.StaleRefs) -join ', ')" }
  $ps = try { Get-PushState $repoArg } catch { $null }
  if ($ps -and $ps.Url -and $null -ne $ps.Behind -and $ps.Behind -gt 0) { "These commits are already on GitHub. To publish the change: backdate push `"$repoArg`" -Force   (GitHub's old version is replaced)" }
}
function Show-Access($a) {
  if (-not $a.GitInstalled) { return $a.Detail }
  "Repository:   $($a.Repo)"
  "Remote:       $(if ($a.Url) { "$($a.Remote) = $($a.Url) ($($a.Transport))" } else { '(none)' })"
  "Git identity: $(if ($a.UserName -and $a.UserEmail) { "$($a.UserName) <$($a.UserEmail)>" } else { 'NOT SET' })"
  "Sign-in:      credential helper = $(if ($a.Helpers) { $a.Helpers -join ', ' } else { '(none)' }); GitHub CLI = $(if (-not $a.GhInstalled) { 'not installed' } elseif ($a.GhLoggedIn) { 'logged in' } else { 'not logged in' })$(if (@($a.Accounts).Count) { '; saved GitHub accounts: ' + @($a.Accounts).Count })"
  "Can push:     $(if ($a.CanPush -eq $true) { 'YES' } elseif ($a.CanPush -eq $false) { 'NO - not signed in / no access' } elseif ($a.Transport -eq 'local') { 'n/a (local remote)' } else { 'unknown' })"
  foreach ($x in @($a.Advice)) { "-> $x" }
}
if ($Command -notin 'help', '/?' -and -not (Test-GitInstalled)) { Write-Host "Error: $script:GitInstallHint"; exit 1 }
try {
  switch ($Command) {
    'install'   { Install-Hooks -Force:$Force; if ((Get-Status).Enabled) { 'Installed. Backdating is still ON from before (turn it off with: off).' } else { 'Installed. Backdating stays OFF until you run: set * <date>, then on' } }
    'uninstall' { Uninstall-Hooks }
    'on'        { Set-Enabled $true;  'Backdating ON - every commit on this PC is now backdated' }
    'off'       { Set-Enabled $false; 'Backdating OFF' }
    'set'       { $d = Parse-Date $Arg2; Set-StartDate (Need $Arg1 '<repo-folder|*>') $d; "Set $Arg1 -> $(Iso $d)" }
    'remove'    { Remove-Repo $Arg1; "Removed $Arg1" }
    'list'      { $c = Get-Config; "backdating: $(if ($c.enabled) {'ON'} else {'OFF'})"; "default: $(if ($c.default.start) { $c.default.start } else { '(not set)' })"; if (@($c.repos).Count) { (@($c.repos) | Format-Table path, start, next -AutoSize | Out-String).Trim() } }
    'status'    { $s = Get-Status; "Hook installed: $($s.Installed)  (core.hooksPath = $($s.HooksPath))"; "Backdating:     $(if ($s.Enabled) {'ON'} else {'OFF'})"; if ($s.HooksFolderMissing) { "WARNING: the hooks folder $($s.HooksPath) no longer exists, so git ignores ALL repo hooks and backdating does nothing. Run: backdate uninstall   (then install again from the folder you keep)." } elseif ($s.OtherCopy) { "Note: the installed hook belongs to another copy of backd8 ($($s.HooksPath)). Run install from this copy to switch (no -Force needed)." }; foreach ($o in @(Get-HookOverrides)) { "Warning: $($o.Path) sets its own core.hooksPath ($($o.HooksPath)); backdating will not run there." } }
    'hook'      { Invoke-Hook }
    'commits'   {
      $n = 20; if ($Arg2) { if (-not [int]::TryParse($Arg2, [ref]$n) -or $n -lt 1) { throw "Count must be a positive whole number, got '$Arg2'." } }
      $l = @(Get-CommitList (Need $Arg1 '<folder>') $n)
      if (-not $l.Count) { 'No commits yet.' }
      foreach ($c in $l) { $sub = if ($c.Subject.Length -gt 100) { $c.Subject.Substring(0, 97) + '...' } else { $c.Subject }; '{0}  {1:yyyy-MM-dd HH:mm}  {2}{3}' -f $c.Short, $c.Date, $(if ($c.IsMerge) { '(merge) ' }), $sub }
    }
    'reword'    {
      $msg = Read-MessageText $MessageFile $Arg3 '<message> (or -MessageFile <file>; a message starting with - must use -MessageFile)'
      $repo = Need $Arg1 '<folder>'; $sha = Need $Arg2 '<sha>'
      $old = (Git-Out (Get-RepoRoot $repo) @('log', '-1', '--format=%h %s', $sha)).Out | Select-Object -First 1
      $r = Set-CommitEdits $repo @{ $sha = @{ message = $msg } }
      Show-Rewrite $r $repo "Reworded: $old  ->  $(($msg -split "`n")[0].Trim())"
    }
    'redate'    {
      $repo = Need $Arg1 '<folder>'; $sha = Need $Arg2 '<sha>'; $d = Parse-Date $Arg3
      $old = (Git-Out (Get-RepoRoot $repo) @('log', '-1', '--format=%h %s (%ad)', '--date=format:%Y-%m-%d %H:%M', $sha)).Out | Select-Object -First 1
      $r = Set-CommitEdits $repo @{ $sha = @{ date = $d } }
      Show-Rewrite $r $repo "Redated: $old  ->  $(Iso $d)"
    }
    'undo'      { Undo-CommitEdits (Need $Arg1 '<folder>') -Force:$Force }
    'push'      { Push-Repo (Need $Arg1 '<folder>') -Force:$Force -DiscardRemote:$DiscardRemote }
    'init'      { $p = Initialize-Repo (Need $Arg1 '<folder>') $Arg2; "Created a git project in $p$(if ($Arg2) { ' and linked it to ' + (Hide-Secrets $Arg2) } else { '. Link it to GitHub with: backdate remote <folder> <github-url>' })" }
    'remote'    { Set-RemoteUrl (Need $Arg1 '<folder>') (Need $Arg2 '<github-url>') }
    'changes'   { $ch = @(Get-WorkingChanges (Need $Arg1 '<folder>')); if (-not $ch.Count) { 'No changes.' }; foreach ($c in $ch) { '{0,-9} {1}{2}{3}' -f $c.Kind, $c.Path, $(if ($c.OldPath) { "  (was $($c.OldPath))" }), $(if ($c.Risky) { '   <-- looks like a secret/key file' }) } }
    'commit'    {
      $msg = Read-MessageText $MessageFile $Arg2 '<message> (or -MessageFile <file>)'
      $dt = if ($Date) { Parse-Date $Date } else { $null }
      Assert-NoRisky (Need $Arg1 '<folder>') -ok:$IncludeRisky
      $c = New-CommitFromChanges (Need $Arg1 '<folder>') $msg -All:(-not $Staged) -StagedOnly:$Staged -Date $dt -AllowRisky:$IncludeRisky
      "Committed $($c.Short) ($('{0:yyyy-MM-dd HH:mm}' -f $c.Date)): $($c.Subject)"
    }
    'publish'   {
      $folder = Need $Arg1 '<folder>'
      if (@(Get-WorkingChanges $folder).Count) {
        $msg = if (-not $MessageFile -and -not $Arg2) { $n = @(Get-WorkingChanges $folder).Count; "Update $n file$(if ($n -ne 1) { 's' })" } else { Read-MessageText $MessageFile $Arg2 '<message> (or -MessageFile <file>)' }
        Assert-NoRisky $folder -ok:$IncludeRisky
        $nc = @{ Message = $msg; All = $true; AllowRisky = [bool]$IncludeRisky }; if ($Date) { $nc.Date = Parse-Date $Date }
        Invoke-Publish $folder -NewCommit $nc -Push -Force:$Force -DiscardRemote:$DiscardRemote
      } else { Invoke-Publish $folder -Push -Force:$Force -DiscardRemote:$DiscardRemote }   # nothing new to commit: just publish what is there
    }
    'sync'      { $m = Merge-RemoteChanges (Need $Arg1 '<folder>'); switch ($m.Result) { 'nothing-on-github' { 'GitHub has nothing on this branch yet.' } 'up-to-date' { 'Already up to date with GitHub.' } 'fast-forward' { "Got $($m.Count) change(s) from GitHub." } 'applied' { "Replayed $($m.Count) change(s) from GitHub that exist nowhere else on top of your edited history. GitHub still has the old versions of your own commits: publish with 'backdate push <folder> -Force'." } 'nothing-new' { 'GitHub only has the old versions of your own commits - nothing new to get. Publish with: backdate push <folder> -Force' } 'merged' { "Combined your work with $($m.Count) change(s) from GitHub (a merge commit was created)." } 'conflict' { "GitHub and your project changed the same files: $($m.Files -join ', '). Nothing was changed. Resolve it in a git tool (git pull) or choose which version to keep." } } }
    'ignore'    { $f = Add-Gitignore (Need $Arg1 '<folder>') $Arg2; "Wrote $f" }
    'account'   { $f = Need $Arg1 '<folder>'; if ($Arg2) { Set-GitHubAccount $f $Arg2 } else { $ps = Get-PushState $f; $ra = Resolve-GitHubAccount (Get-RepoRoot $f) $ps.Url; "Saved GitHub accounts: $((@(Get-GitHubAccounts)) -join ', ')"; "This project uses: $(if ($ra) { $ra.Name + ' (' + $ra.Source + ')' } else { '(not decided)' })" } }
    'trust'     { Set-RepoTrusted (Need $Arg1 '<folder>') }
    'state'     {
      $pl = Get-WorkflowPlan (Need $Arg1 '<folder>') -CheckAccess:$Online -Fetch:$Online
      "State:        $($pl.State) - $($pl.Title)"; "What it means: $($pl.Help)"
      if (-not $Online -and $pl.Facts.Linked) { 'Note:         based on what this PC last saw of GitHub; add -Online to look at GitHub now.' }
      $f = $pl.Facts; "Facts:        changes=$($f.Changes) ahead=$($f.Ahead) behind=$($f.Behind) foreign=$($f.RemoteOnly)/$($f.Others) linked=$($f.Linked) access=$($f.Access)"
      foreach ($a in $pl.Actions) { '  [{0}] {1}{2}' -f $(if ($a.Enabled) { 'x' } else { ' ' }), $a.Label, $(if (-not $a.Enabled -and $a.Why) { '   (' + $a.Why + ')' }) }
      "Next step:    $($pl.Recommended)"
    }
    'state-model' { $v = @(Test-WorkflowModel); if ($v.Count) { $v; throw "Workflow model has $($v.Count) violation(s)." } else { "Workflow model proven: $($script:WfModelCases) fact combinations, $($script:WfStates.Count) states - deterministic, total, no dead ends, every state reaches InSync." } }
    'github'    { Show-Access (Get-GitHubAccess (Need $Arg1 '<folder>')) }
    'github-login' { Show-Access (Connect-GitHub (Need $Arg1 '<folder>') -Inline) }
    { $_ -in 'help', '/?' } { Show-Usage }
    default     { throw "Unknown command '$Command'. Run: backdate.cmd help" }
  }
} catch { Write-Host "Error: $($_.Exception.Message)"; exit 1 }
