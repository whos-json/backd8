# backd8 repo tools: list commits, edit commit messages/dates (history rewrite), undo, push.
# Dot-sourced by lib.ps1. Uses git plumbing only (commit-tree), so no hooks run and trees are never touched.

# Variables that would silently point git at another repository/index if the caller had them set.
$script:CleanEnvKeys = 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_COMMON_DIR', 'GIT_NAMESPACE', 'GIT_ALTERNATE_OBJECT_DIRECTORIES'
function Enter-CleanGitEnv { $s = @{}; foreach ($k in $script:CleanEnvKeys) { $v = [Environment]::GetEnvironmentVariable($k); if ($null -ne $v) { $s[$k] = $v; [Environment]::SetEnvironmentVariable($k, $null) } }; $s }
function Exit-CleanGitEnv($s) { foreach ($k in $s.Keys) { [Environment]::SetEnvironmentVariable($k, $s[$k]) } }

function Git-Out([string]$Repo, [string[]]$GitArgs) {
  $env0 = Enter-CleanGitEnv
  try {
    $o = & git -C $Repo -c core.longpaths=true -c core.fsmonitor=false -c protocol.ext.allow=never @GitArgs 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" } }
    $code = $LASTEXITCODE
  } finally { Exit-CleanGitEnv $env0 }
  [pscustomobject]@{ Code = $code; Out = @($o) }
}

# Retries once or twice when another git process holds index.lock (parallel commits, editors, IDE git integrations).
function Git-Retry([string]$Repo, [string[]]$GitArgs) {
  for ($i = 0; $i -lt 4; $i++) {
    $r = Git-Out $Repo $GitArgs
    if (-not $r.Code -or ($r.Out -join ' ') -notmatch '\.lock') { return $r }
    Start-Sleep -Milliseconds (300 * ($i + 1))
  }
  $r
}

# Raw stdout bytes (PowerShell's text pipeline would decode/normalise commit messages).
function Read-GitBytes([string]$Repo, [string[]]$GitArgs) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = 'git'; $psi.WorkingDirectory = $Repo
  $GitArgs = @('-c', 'core.longpaths=true', '-c', 'core.fsmonitor=false', '-c', 'protocol.ext.allow=never') + @($GitArgs)
  foreach ($k in $script:CleanEnvKeys) { [void]$psi.EnvironmentVariables.Remove($k) }
  $psi.Arguments = (@($GitArgs | ForEach-Object { Quote-Arg "$_" })) -join ' '
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $err = $p.StandardError.ReadToEndAsync()
  $ms = New-Object IO.MemoryStream
  $p.StandardOutput.BaseStream.CopyTo($ms)
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Bytes = $ms.ToArray(); Err = $err.Result }
}

# "epoch +hhmm" in the machine's local zone for that wall-clock time (what git stores).
function Format-GitDate([datetime]$dt) {
  if ($dt.Kind -eq 'Utc') { $dt = $dt.ToLocalTime() }
  $off = [TimeZoneInfo]::Local.GetUtcOffset($dt)
  $ts = [DateTimeOffset]::new([datetime]::SpecifyKind($dt, 'Unspecified'), $off).ToUnixTimeSeconds()
  '{0} {1}{2:00}{3:00}' -f $ts, $(if ($off -lt [TimeSpan]::Zero) { '-' } else { '+' }), [Math]::Abs($off.Hours), [Math]::Abs($off.Minutes)
}

# One rule for every date the user can give us (git cannot store dates before 1970 reliably).
function Assert-GitDate([datetime]$d) {
  if ($d -lt [datetime]'1971-01-01') { throw "The date $($d.ToString('yyyy-MM-dd')) is too early for git. Use 1971 or later." }
  if ($d -gt (Get-Date)) { throw 'Date must be in the past.' }
}

# Hides user:password@ in URLs (everything up to the last @ of the authority).
function Hide-Secrets([string]$s) { ($s -replace '(://)\S*@(?=[^@\s/]+(/|:|\s|$))', '$1***@') -replace '(?i)([?&](token|access_token|auth|key|password|pwd|secret)=)[^&\s]+', '$1***' }

# A downloaded project can carry git settings that run programs whenever git looks at it (core.fsmonitor, filters, credential helpers, ...).
$script:RiskyCfgRx = '^(core\.(fsmonitor|sshcommand|gitproxy|askpass|worktree|attributesfile)|credential\..*(?<!\.username)|filter\..+\.(clean|smudge|process)|diff\..+\.(command|textconv)|merge\..+\.driver|protocol\..*|include(if\..+)?\.path|remote\..+\.(uploadpack|receivepack|proxy|vcs)|gpg\..*program)$'
$script:RiskCache = @{}
function Get-RiskyRepoConfig([string]$Root) {
  $k = $Root.ToLowerInvariant(); $c = $script:RiskCache[$k]
  if ($c -and ((Get-Date) - $c.At).TotalSeconds -lt 30) { return @($c.Items) }
  $items = @()
  $x = Read-GitBytes $Root @('config', '--local', '--list', '-z')
  if (-not $x.Code) {
    foreach ($e in ((New-Object Text.UTF8Encoding $false).GetString($x.Bytes) -split "`0")) {
      if (-not $e) { continue }
      $nl = $e.IndexOf("`n"); $key = if ($nl -ge 0) { $e.Substring(0, $nl) } else { $e }; $val = if ($nl -ge 0) { $e.Substring($nl + 1) } else { '' }
      if ($key -match $script:RiskyCfgRx -or ($key -match '^remote\..+\.(url|pushurl)$' -and $val -match '^(ext|fd)::|^\\\\|^//')) { $items += $key }
    }
  }
  $script:RiskCache[$k] = @{ At = Get-Date; Items = $items }
  @($items)
}
function Test-RepoTrusted([string]$Root) { try { @((Get-Config).trusted) -contains (Norm $Root) } catch { $false } }
function Set-RepoTrusted([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Folder not found: $Path" }
  $t = Test-IsRepo $Path; if (-not $t.IsRepo) { throw "Not a git repository: $Path" }
  Use-ConfigLock { $c = Get-Config; $c.trusted = @(@($c.trusted) + (Norm $t.Root) | Select-Object -Unique); Save-Config $c }
  $script:RiskCache.Remove($t.Root.ToLowerInvariant())
  "backd8 will now open $($t.Root) even though its git settings can run programs."
}

function Get-RepoRoot([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Folder not found: $Path" }
  $full = (Resolve-Path -LiteralPath $Path).Path
  $r = Git-Out $full @('rev-parse', '--show-toplevel')
  if ($r.Code -or -not $r.Out) { throw "Not a git repository: $Path" }
  $root = $r.Out[0] -replace '/', '\'
  $risk = @(Get-RiskyRepoConfig $root)
  if ($risk.Count -and -not (Test-RepoTrusted $root)) {
    throw "UNTRUSTED PROJECT: this folder's own git settings ($($risk -join ', ')) can run programs on your PC whenever git looks at it. If you got this folder from someone you do not know, do not open it. If you made it or trust it, confirm with: backdate trust ""$root""  (window: 'I trust this project')."
  }
  $root
}

# Branch name without refs/heads/ (symbolic-ref --short is ambiguous when a tag has the same name).
function Get-BranchName([string]$Repo) {
  $r = Git-Out $Repo @('symbolic-ref', '-q', 'HEAD')
  if ($r.Code -or -not $r.Out) { return $null }
  $r.Out[0] -replace '^refs/heads/', ''
}

# Text from a repository is untrusted: drop control and bidi-override characters (display spoofing) and cap the length.
function Clean-Text([string]$s, [int]$max = 500) {
  $t = [regex]::Replace("$s", '[\u0000-\u0008\u000B-\u001F\u007F\u200E\u200F\u202A-\u202E\u2066-\u2069]', '')
  if ($t.Length -gt $max) { $t = $t.Substring(0, $max - 1) + '...' }
  $t
}

function Get-CommitList([string]$Path, [int]$Max = 100) {
  $repo = Get-RepoRoot $Path
  $r = Git-Out $repo @('log', "-n$Max", '--format=%H%x1f%aI%x1f%an%x1f%s%x1f%P')
  if ($r.Code) {
    if ((Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')).Code) { return @() }   # no commits yet
    throw 'git could not read this project''s history (the repository may be damaged). Run "git fsck" in the folder for details.'
  }
  foreach ($l in $r.Out) {
    $f = $l -split [string][char]0x1F, 5
    [pscustomobject]@{
      Sha = $f[0]; Short = $f[0].Substring(0, 7); Date = ([datetimeoffset]$f[1]).LocalDateTime
      Author = (Clean-Text $f[2] 200); Subject = (Clean-Text $f[3] 500); IsMerge = (@($f[4] -split ' ' | Where-Object { $_ }).Count -gt 1)
    }
  }
}

function Parse-Ident([string]$s) {
  if ($s -notmatch '^(.*) <(.*)> (\d+) ([+-]\d{4})$') { throw "Unrecognised identity line: $s" }
  [pscustomobject]@{ Name = $Matches[1]; Email = $Matches[2]; Date = "$($Matches[3]) $($Matches[4])" }
}

function Get-MsgEncoding([string]$Name) {
  if (-not $Name) { return (New-Object Text.UTF8Encoding $false) }
  try { [Text.Encoding]::GetEncoding($Name) } catch { [Text.Encoding]::GetEncoding(28591) }
}

function Read-CommitRaw([string]$Repo, [string]$Sha) {
  $r = Read-GitBytes $Repo @('cat-file', 'commit', $Sha)
  if ($r.Code) { throw "Cannot read commit $Sha" }
  $b = $r.Bytes; $split = -1
  for ($i = 0; $i -lt $b.Length - 1; $i++) { if ($b[$i] -eq 10 -and $b[$i + 1] -eq 10) { $split = $i; break } }
  $latin = [Text.Encoding]::GetEncoding(28591); $utf8 = New-Object Text.UTF8Encoding $false
  $hdrLen = if ($split -ge 0) { $split } else { $b.Length }
  $msgBytes = New-Object byte[] 0
  if ($split -ge 0 -and $split + 2 -lt $b.Length) { $msgBytes = New-Object byte[] ($b.Length - $split - 2); [Array]::Copy($b, $split + 2, $msgBytes, 0, $msgBytes.Length) }
  $hdrLines = @($latin.GetString($b, 0, $hdrLen) -split "`n"); if ($hdrLines.Count -and $hdrLines[-1] -eq '') { $hdrLines = @($hdrLines[0..($hdrLines.Count - 2)]) }
  $c = [pscustomobject]@{ Tree = $null; Parents = @(); Author = $null; Committer = $null; Encoding = $null; Message = ''; MessageBytes = $msgBytes; Signed = $false; HeaderLines = $hdrLines; HadBlank = ($split -ge 0) }
  foreach ($l in $hdrLines) {
    if ($l.StartsWith(' ')) { continue }                 # continuation of a multi-line header (gpgsig, mergetag)
    $sp = $l.IndexOf(' '); if ($sp -lt 1) { continue }
    $v = $l.Substring($sp + 1)
    switch ($l.Substring(0, $sp)) {
      'tree' { $c.Tree = $v }
      'parent' { $c.Parents += $v }
      'author' { $c.Author = $utf8.GetString($latin.GetBytes($v)) }
      'committer' { $c.Committer = $utf8.GetString($latin.GetBytes($v)) }
      'encoding' { $c.Encoding = $v }
      { $_ -like 'gpgsig*' } { $c.Signed = $true }
    }
  }
  $c.Message = (Get-MsgEncoding $c.Encoding).GetString($msgBytes)
  $c
}

function Get-CommitMessage([string]$Path, [string]$Sha) {
  $repo = Get-RepoRoot $Path
  (Read-CommitRaw $repo $Sha).Message.TrimEnd()
}

# Edits: @{ '<sha>' = @{ message = '...'; date = [datetime] } }  (either key optional)
# Rewrites the commit(s) and every descendant on the current branch. Trees, authors, untouched dates and untouched
# message bytes are preserved exactly. Signatures cannot survive (reported in SignaturesDropped).
function Set-CommitEdits([string]$Path, [hashtable]$Edits) {
  $repo = Get-RepoRoot $Path
  if (-not $Edits -or $Edits.Count -eq 0) { throw 'Nothing to change.' }
  $g = (Git-Out $repo @('rev-parse', '--absolute-git-dir')).Out[0]
  foreach ($f in 'rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD') {
    if (Test-Path -LiteralPath (Join-Path $g $f)) { throw 'A rebase, merge or cherry-pick is in progress. Finish or abort it first.' }
  }
  $branch = Get-BranchName $repo
  if (-not $branch) { throw 'HEAD is detached (or the branch has no commits). Check out a branch first.' }
  $ref = "refs/heads/$branch"
  $old = (Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')).Out[0]

  $plan = @{}
  foreach ($k in @($Edits.Keys)) {
    $kk = if ($k -match '^[0-9A-Fa-f]{4,40}$') { $k.ToLowerInvariant() } else { $k }   # abbreviated shas must be lowercase for git
    $full = Git-Out $repo @('rev-parse', '--verify', '-q', "$kk^{commit}")
    if ($full.Code -or -not $full.Out) { throw "Unknown commit: $k" }
    $sha = $full.Out[0]
    if ((Git-Out $repo @('merge-base', '--is-ancestor', $sha, 'HEAD')).Code) { throw "Commit $k is not in the current branch's history." }
    $ed = $Edits[$k]
    if ($ed.date) { Assert-GitDate ([datetime]$ed.date) }
    if ($null -ne $ed.message -and -not "$($ed.message)".Trim()) { throw "Commit message for $k cannot be empty." }
    if ($plan.ContainsKey($sha)) {                       # same commit named twice (e.g. short sha and HEAD): merge the edits
      foreach ($key in 'message', 'date') { if ($null -ne $ed[$key]) { $plan[$sha][$key] = $ed[$key] } }
    } else { $plan[$sha] = @{ message = $ed.message; date = $ed.date } }
  }

  $affected = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($sha in @($plan.Keys)) {
    [void]$affected.Add($sha)
    foreach ($x in (Git-Out $repo @('rev-list', '--ancestry-path', "$sha..HEAD")).Out) { if ($x) { [void]$affected.Add($x) } }
  }
  $order = @((Git-Out $repo @('rev-list', '--reverse', '--topo-order', 'HEAD')).Out | Where-Object { $affected.Contains($_) })

  $tmp = Join-Path ([IO.Path]::GetTempPath()) "backd8-msg-$PID.txt"
  Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'backd8-*.txt' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force -ErrorAction SilentlyContinue   # leftovers of killed runs
  $map = @{}; $signed = 0; $epoch = @{}; $warn = New-Object Collections.Generic.List[string]; $authors = @{}; $meEmail = (Get-GitIdentity $repo).Email
  $latin = [Text.Encoding]::GetEncoding(28591); $utf8 = New-Object Text.UTF8Encoding $false
  try {
    foreach ($sha in $order) {
      $c = Read-CommitRaw $repo $sha
      if ($c.Signed) { $signed++ }
      $ed = $plan[$sha]
      if ($c.Author -match '<([^>]*)>' -and $Matches[1] -ine $meEmail) { $authors[$Matches[1]] = $true }   # reported so the UI can warn before rewriting other people's commits
      $msgBytes = $c.MessageBytes; $dropEnc = $false
      if ($ed -and $null -ne $ed.message) {
        $text = ("$($ed.message)" -replace "`r`n", "`n").TrimEnd() + "`n"
        $enc = Get-MsgEncoding $c.Encoding; $msgBytes = $enc.GetBytes($text)
        if ($c.Encoding -and $enc.GetString($msgBytes) -ne $text) { $msgBytes = $utf8.GetBytes($text); $dropEnc = $true }   # characters the old encoding cannot hold: store as UTF-8
      }
      $newDate = $(if ($ed -and $ed.date) { Format-GitDate ([datetime]$ed.date) })
      $ad = if ($newDate) { $newDate } elseif ($c.Author -match '(\d+) ([+-]\d{4})$') { "$($Matches[1]) $($Matches[2])" } else { '0 +0000' }
      $epoch[$sha] = [long](($ad -split ' ')[0])
      foreach ($p in $c.Parents) {
        $pe = if ($epoch.ContainsKey($p)) { $epoch[$p] } else { $x = Git-Out $repo @('log', '-1', '--format=%at', $p); if ($x.Out -and $x.Out[0] -match '^\d+$') { [long]$x.Out[0] } else { $null } }
        if ($null -ne $pe -and $epoch[$sha] -lt $pe -and (($plan.ContainsKey($sha) -and $plan[$sha].date) -or ($plan.ContainsKey($p) -and $plan[$p].date))) {
          $warn.Add("$($sha.Substring(0, 7)) is dated before its parent $($p.Substring(0, 7)); history will look out of order.")
        }
      }
      $outl = New-Object Collections.Generic.List[string]; $keep = $true
      foreach ($l in $c.HeaderLines) {
        if ($l.StartsWith(' ')) { if ($keep) { $outl.Add($l) }; continue }
        $sp = $l.IndexOf(' '); $k = if ($sp -gt 0) { $l.Substring(0, $sp) } else { $l }
        if ($k -like 'gpgsig*') { $keep = $false; continue }
        $keep = $true
        if ($k -eq 'parent') { $pp = $l.Substring(7); $outl.Add('parent ' + $(if ($map.ContainsKey($pp)) { $map[$pp] } else { $pp })) }
        elseif ($k -eq 'encoding' -and $dropEnc) { $keep = $false }
        elseif (($k -eq 'author' -or $k -eq 'committer') -and $newDate) { $outl.Add(($l -replace ' \d+ [+-]\d{4}$', " $newDate")) }
        else { $outl.Add($l) }
      }
      $hdr = $latin.GetBytes((($outl -join "`n") + $(if ($c.HadBlank) { "`n`n" } else { "`n" })))
      $all = New-Object byte[] ($hdr.Length + $msgBytes.Length); [Array]::Copy($hdr, 0, $all, 0, $hdr.Length); [Array]::Copy($msgBytes, 0, $all, $hdr.Length, $msgBytes.Length)
      [IO.File]::WriteAllBytes($tmp, $all)
      $r = Git-Out $repo @('hash-object', '-t', 'commit', '-w', $tmp)
      if ($r.Code -or -not $r.Out) {
        $hint = if (Test-Path -LiteralPath (Join-Path $g 'shallow')) { ' This is a shallow clone: run "git fetch --unshallow" first.' } else { '' }
        throw "Rewriting $sha failed: $($r.Out -join ' ')$hint"
      }
      $map[$sha] = $r.Out[-1].Trim()
    }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
  $new = $map[$old]
  $base = (Get-Date).ToString('yyyyMMdd-HHmmss-fff'); $stamp = $base; $n = 1
  while (-not (Git-Out $repo @('rev-parse', '--verify', '-q', "refs/backd8/backup/$branch/$stamp")).Code) { $n++; $stamp = "$base-$n" }
  $backup = "refs/backd8/backup/$branch/$stamp"
  if ((Git-Out $repo @('update-ref', $backup, $old)).Code) { throw 'Could not create the backup ref; nothing was changed.' }
  $u = Git-Out $repo @('update-ref', $ref, $new, $old)       # compare-and-swap: fails if the branch moved meanwhile
  if ($u.Code) { [void](Git-Out $repo @('update-ref', '-d', $backup)); throw "Branch moved while rewriting; nothing was changed. $($u.Out -join ' ')" }
  [void](Git-Out $repo @('update-ref', "refs/backd8/rewritten/$branch/$stamp", $new))   # lets undo verify nothing was added since
  $olds = @(Get-Backups $repo)
  if ($olds.Count -gt 20) {                                   # keep the 20 newest per branch so refs (and old objects) do not pile up
    foreach ($ob in $olds[20..($olds.Count - 1)]) { $st = ($ob -split '/')[-1]; foreach ($pre in 'backup', 'rewritten', 'undone') { [void](Git-Out $repo @('update-ref', '-d', "refs/backd8/$pre/$branch/$st")) } }
  }

  $nl = Git-Out $repo @('notes', 'list')                      # carry git notes over to the new commits
  if (-not $nl.Code) {
    $has = @{}; foreach ($l in $nl.Out) { $x = $l -split ' '; if ($x.Count -eq 2) { $has[$x[1]] = $true } }
    foreach ($o in @($map.Keys)) { if ($has.ContainsKey($o)) { [void](Git-Out $repo @('notes', 'copy', '-f', $o, $map[$o])) } }
  }
  $stale = @()                                                # other branches/tags still pointing at the old commits
  foreach ($l in (Git-Out $repo @('for-each-ref', '--format=%(refname)|%(objectname)|%(*objectname)', 'refs/heads', 'refs/tags')).Out) {
    $f = $l -split '\|'; if ($f[0] -ne $ref -and ($map.ContainsKey($f[1]) -or ($f.Count -gt 2 -and $f[2] -and $map.ContainsKey($f[2])))) { $stale += $f[0] }
  }
  [pscustomobject]@{ Rewritten = $order.Count; Edited = $plan.Count; Backup = $backup; NewHead = $new; SignaturesDropped = $signed; StaleRefs = $stale; Warnings = @($warn); AuthorsAffected = @($authors.Keys) }
}

function Get-Backups([string]$Path) {
  $repo = Get-RepoRoot $Path
  $branch = Get-BranchName $repo; if (-not $branch) { return @() }
  $re = '^refs/backd8/backup/' + [regex]::Escape($branch) + '/\d{8}-\d{6}-\d{3}(-\d+)?$'
  @((Git-Out $repo @('for-each-ref', '--sort=-refname', '--format=%(refname)', 'refs/backd8/backup/')).Out | Where-Object { $_ -match $re })
}

# Restores the branch to just before the last rewrite. Refuses when commits were added since (they would be lost).
function Undo-CommitEdits([string]$Path, [switch]$Force) {
  $repo = Get-RepoRoot $Path
  $bk = @(Get-Backups $repo)
  if (-not $bk.Count) { throw 'No backd8 backup found for this branch.' }
  $branch = Get-BranchName $repo; $ref = "refs/heads/$branch"
  $stamp = ($bk[0] -split '/')[-1]; $rw = "refs/backd8/rewritten/$branch/$stamp"
  $cur = (Git-Out $repo @('rev-parse', 'HEAD')).Out[0]
  if (-not $Force) {
    $tip = Git-Out $repo @('rev-parse', '--verify', '-q', $rw)
    if ($tip.Code -or $tip.Out[0] -ne $cur) {
      throw 'The branch has changed since the last rewrite (new commits, another rewrite or a reset). Undo would discard that work. Use Undo anyway in the window, or run: backdate undo <folder> -Force (the current commits stay reachable through the reflog).'
    }
  }
  $target = (Git-Out $repo @('rev-parse', $bk[0])).Out[0]
  $u = Git-Out $repo @('update-ref', $ref, $target, $cur)
  if ($u.Code) { throw "Undo failed: $($u.Out -join ' ')" }
  $pin = Git-Out $repo @('rev-parse', '--verify', '-q', $rw)
  [void](Git-Out $repo @('update-ref', "refs/backd8/undone/$branch/$stamp", $(if (-not $pin.Code -and $pin.Out) { $pin.Out[0] } else { $cur })))   # the undone tip may be on the remote: it is OUR commit, not someone else's
  [void](Git-Out $repo @('update-ref', '-d', $bk[0])); [void](Git-Out $repo @('update-ref', '-d', $rw))
  "Restored branch to $($target.Substring(0, 7)) (backup $($bk[0]) consumed)."
}

function Get-PushState([string]$Path) {
  $repo = Get-RepoRoot $Path
  $branch = Get-BranchName $repo
  if (-not $branch) { throw 'HEAD is detached (or the branch has no commits). Check out a branch first.' }
  $rc = Git-Out $repo @('config', "branch.$branch.remote")
  $remote = if ($rc.Code -or -not $rc.Out -or -not $rc.Out[0]) { 'origin' } else { $rc.Out[0] }
  $mc = Git-Out $repo @('config', "branch.$branch.merge")
  $destRef = if (-not $mc.Code -and $mc.Out -and $mc.Out[0] -like 'refs/heads/*' -and $rc.Out -and -not $rc.Code) { $mc.Out[0] } else { "refs/heads/$branch" }
  $u = Git-Out $repo @('remote', 'get-url', '--push', $remote)   # pushurl, when set, is where a push really goes
  $url = if ($u.Code -or -not $u.Out) { $null } else { Hide-Secrets $u.Out[0] }
  $up = Git-Out $repo @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
  $upstream = if ($up.Code -or -not $up.Out) { $null } else { $up.Out[0] }
  $cmp = if ($upstream) { '@{u}' } elseif (-not (Git-Out $repo @('rev-parse', '--verify', '-q', "refs/remotes/$remote/$branch")).Code) { "refs/remotes/$remote/$branch" } else { $null }
  $ahead = $null; $behind = $null; $track = $null; $remoteOnly = 0
  if ($cmp) {
    $t = Git-Out $repo @('rev-parse', '--verify', '-q', $cmp)
    if (-not $t.Code -and $t.Out) {
      $track = $t.Out[0]
      $lr = Git-Out $repo @('rev-list', '--left-right', '--count', "HEAD...$track")
      if (-not $lr.Code -and $lr.Out -and $lr.Out[0] -match '^(\d+)\s+(\d+)') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
      # commits on the remote that exist in no local branch, tag or backup: force pushing would destroy them
      # remote commits whose CHANGE already exists in our history under a new hash (a teammate's commit we replayed with sync) are not lost by replacing
      $equiv = @{}
      $cy = Git-Out $repo @('cherry', 'HEAD', $track)
      if (-not $cy.Code) { foreach ($cl in $cy.Out) { if ($cl -match '^- ([0-9a-f]{40})') { $equiv[$Matches[1]] = $true } } }
      $ro = Git-Out $repo @('rev-list', $track, '--not', '--branches', '--tags', '--glob=refs/backd8/*')
      if (-not $ro.Code) { $remoteOnly = @($ro.Out | Where-Object { $_ -match '^[0-9a-f]{40}$' -and -not $equiv.ContainsKey($_) }).Count }
    }
  }
  $others = 0; if (-not $equiv) { $equiv = @{} }             # commits a force push would remove from GitHub that were written by someone else
  if ($track) {
    $me = (Get-GitIdentity $repo).Email
    $em = Git-Out $repo @('log', '-n', '2000', '--format=%H|%ae|%at|%s', $track, '--not', 'HEAD')
    $mine = @{}   # same author, time and subject as something we have: a replayed copy; a REWORDED commit of someone else is not
    if ($equiv.Count) { $lc = Git-Out $repo @('log', '-n', '2000', '--format=%ae|%at|%s', 'HEAD'); if (-not $lc.Code) { foreach ($l in $lc.Out) { $mine[$l] = $true } } }
    if (-not $em.Code) { $others = @($em.Out | Where-Object { $_ -match '^([0-9a-f]{40})\|([^|]*)\|(\d+)\|(.*)$' -and $Matches[2] -ine $me -and -not ($equiv.ContainsKey($Matches[1]) -and $mine.ContainsKey("$($Matches[2])|$($Matches[3])|$($Matches[4])")) }).Count }
  }
  [pscustomobject]@{ Repo = $repo; Branch = $branch; Remote = $remote; DestRef = $destRef; Url = $url; Upstream = $upstream; Ahead = $ahead; Behind = $behind; TrackingSha = $track; RemoteOnly = $remoteOnly; OthersCommits = $others }
}

# Plain push when fast-forward. -Force = --force-with-lease pinned to the remote state you were shown; it refuses if the
# remote moved, and also if the remote holds commits you have nowhere locally unless -DiscardRemote is given.
function Push-Repo([string]$Path, [switch]$Force, [switch]$DiscardRemote) {
  [void](Update-RemoteRefs $Path 60000)                         # always look at GitHub as it is now: exact ahead/behind, lease and foreign-commit check (failure is not fatal)
  $s = Get-PushState $Path
  if (-not $s.Url) { throw "No git remote named '$($s.Remote)'. Add your GitHub repo first:  git remote add origin https://github.com/<user>/<repo>.git" }
  if (-not $Force -and $s.Behind -gt 0 -and ($s.Ahead -eq 0 -or $s.RemoteOnly -gt 0)) {   # GitHub holds work we have never seen: bring it in first, do not suggest replacing it
    throw "GitHub has $($s.Behind) newer change(s) that your project does not have yet (made on another computer or on github.com). Get them first (backdate sync `"$($s.Repo)`"), then publish again."
  }
  if (-not $Force -and $s.Behind -gt 0) {
    throw "Your project has $($s.Ahead) change(s) that GitHub does not have, and GitHub has $($s.Behind) that your project does not. If you edited commits that were already published, publish with 'Replace GitHub's version' (command line: backdate push <folder> -Force); if someone else added work, get the latest from GitHub first (command line: backdate sync <folder>)."
  }
  if ($Force -and $s.OthersCommits -gt 0 -and $s.RemoteOnly -eq 0 -and -not $DiscardRemote) {
    throw "Replacing GitHub's version would remove $($s.OthersCommits) commit(s) written by someone else (not your git identity). Make sure that is what you want: command line  backdate push <folder> -Force -DiscardRemote ; window: the second confirmation."
  }
  if ($Force -and $s.RemoteOnly -gt 0 -and -not $DiscardRemote) {
    throw "The remote branch has $($s.RemoteOnly) commit(s) that exist nowhere in this repository (not in any branch, tag or backd8 backup) - probably someone else's work (or the old version of a commit you changed outside backd8, e.g. with git commit --amend). Force push would delete them. Get them first (window: 'Get latest'; command line: backdate sync <folder>), or confirm replacing them (window: second confirmation; command line: backdate push <folder> -Force -DiscardRemote)."
  }
  $a = @(Get-CredentialArgs $s.Repo $s.Url) + @('push', '--no-follow-tags')
  if ($Force) { $a += $(if ($s.TrackingSha) { "--force-with-lease=$($s.DestRef):$($s.TrackingSha)" } else { '--force-with-lease' }) }
  if (-not $s.Upstream) { $a += '-u' }
  $a += @($s.Remote, "refs/heads/$($s.Branch):$($s.DestRef)")
  # 5 minute limit (a browser sign-in may take a while); a hung server can no longer freeze the caller for ever
  $r = Invoke-GitTimed $s.Repo $a 300000 @{ GIT_TERMINAL_PROMPT = '0' }
  if ($r.TimedOut) { throw 'Pushing took longer than 5 minutes and was stopped (server not answering, or a sign-in window was left open). Check your connection and try again.' }
  $out = Hide-Secrets $r.Out
  if ($r.Code) {
    $pb = Get-GitProblem $out
    switch ($pb.Kind) {
      { $_ -in 'auth', 'notfound' } { throw "GitHub sign-in required (or this account cannot write to the repository / it was not found). Use ""Sign in to GitHub"" in the window, or run: backdate.cmd github-login `"$($s.Repo)`"`n$(if ($pb.Advice) { $pb.Advice + "`n" })$out" }
      { $_ -in 'saml', 'hostkey', 'temporary', 'network', 'toolarge', 'noaccess' } { throw "$($pb.Advice)`n$out" }
      default {
        if (-not $Force -and $out -match 'fetch first|non-fast-forward|\[rejected\]') { throw "GitHub has newer changes than your project (probably made elsewhere). Get them first (backdate sync `"$($s.Repo)`") and publish again.`n$out" }
        throw "git push failed:`n$out"
      }
    }
  }
  $note = if ($out -match 'redirecting to (\S+)') { "`nNote: GitHub says this repository moved to $($Matches[1]). Update the address with: backdate remote <folder> $($Matches[1])" } else { '' }
  "Pushed $($s.Branch) to $($s.Url)`n$out$note".Trim()
}

# ---------- working-tree changes: choose a folder, write the commit message, commit ----------
function Test-IsRepo([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return [pscustomobject]@{ Exists = $false; IsRepo = $false; Root = $null; Folder = $null } }
  $full = (Resolve-Path -LiteralPath $Path).Path
  $r = Git-Out $full @('rev-parse', '--show-toplevel')
  $ok = (-not $r.Code -and [bool]$r.Out)
  [pscustomobject]@{ Exists = $true; IsRepo = $ok; Root = $(if ($ok) { $r.Out[0] -replace '/', '\' } else { $null }); Folder = $full }
}

# Names that usually hold secrets; the UI should make the user confirm before committing them.
function Test-RiskyPath([string]$p) {
  $p -match '(^|/)\.env($|\.)|\.(pem|key|pfx|p12|ppk|kdbx|publishsettings)$|(^|/)id_(rsa|dsa|ecdsa|ed25519)($|\.)|(^|/)(credentials|secrets?)(\.[A-Za-z]+)?$|(^|/)appsettings([.\w-]*)\.json$|(^|/)web\.config$|\.csproj\.user$|(^|/)\.(npmrc|pypirc|netrc)$|\.tfvars$|(^|/)\.aws/credentials$|(^|/)\.vs/.*\.(sqlite3?|db)$' -and $p -notmatch '(^|/)\.vs/'
}
# Build output / IDE clutter that normally belongs in .gitignore, not in a commit.
function Test-NoisePath([string]$p) { $p -match '(^|/)(bin|obj|\.vs|node_modules|packages|__pycache__|\.idea)/|\.(suo|pdb|pyc)$|(^|/)(\.DS_Store|Thumbs\.db)$|\.csproj\.user$' }

$script:SecretContentRx = '(?i)((password|passwd|pwd|secret|apikey|api_key|accountkey|connectionstring)["'']?\s*[:=]\s*["'']?[^\s"''<>;]{4,})|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'
$script:ScanExt = '\.(json|config|xml|ya?ml|env|ini|txt|cs|vb|js|ts|py|properties|cfg|conf|ps1|sh|toml|csproj)$'

# One entry per changed file: Path, OldPath (renames), Status (XY), Kind, Staged, Risky, RiskReason, Noise, SizeMB.
function Get-WorkingChanges([string]$Path) {
  $repo = Get-RepoRoot $Path
  $r = Read-GitBytes $repo @('status', '--porcelain=v1', '-z', '-uall')
  if ($r.Code) { throw "git status failed: $($r.Err)" }
  $parts = (New-Object Text.UTF8Encoding $false).GetString($r.Bytes) -split "`0"
  $out = New-Object Collections.Generic.List[object]; $i = 0; $scanned = 0; $dirLink = @{}
  while ($i -lt $parts.Count) {
    $e = $parts[$i]; $i++
    if ($e.Length -lt 4) { continue }
    $x = [string]$e[0]; $y = [string]$e[1]; $p = $e.Substring(3); $old = $null
    if ($x -eq 'R' -or $x -eq 'C') { $old = $parts[$i]; $i++ }
    $kind = if ($p.EndsWith('/')) { 'nested' } elseif ($x + $y -eq '??') { 'new' } elseif ($x -eq 'R' -or $x -eq 'C') { 'renamed' } elseif ($x -eq 'D' -or $y -eq 'D') { 'deleted' } elseif ($x -eq 'A') { 'new' } else { 'modified' }
    $risky = Test-RiskyPath $p; $reason = $(if ($risky) { 'file name suggests passwords or keys' })
    $size = 0.0; $outside = $false
    if ($kind -eq 'new' -and $p.Contains('/')) {            # a junction/symlink inside the project can lead anywhere
      $dir = $p.Substring(0, $p.LastIndexOf('/'))
      if (-not $dirLink.ContainsKey($dir)) {
        $isL = $false; $acc = ''
        foreach ($seg in ($dir -split '/')) { $acc = $(if ($acc) { "$acc/$seg" } else { $seg }); try { if ([IO.File]::GetAttributes((Join-Path $repo ($acc -replace '/', '\'))) -band [IO.FileAttributes]::ReparsePoint) { $isL = $true; break } } catch {} }
        $dirLink[$dir] = $isL
      }
      $outside = $dirLink[$dir]
    }
    if ($kind -ne 'deleted' -and $kind -ne 'nested') {
      $fi = New-Object IO.FileInfo (Join-Path $repo ($p -replace '/', '\'))
      if ($fi.Exists) {
        $size = [Math]::Round($fi.Length / 1MB, 2)
        if (-not $risky -and $scanned -lt 400 -and $fi.Length -lt 262144 -and $p -match $script:ScanExt) {
          $scanned++
          try { if ([IO.File]::ReadAllText($fi.FullName) -match $script:SecretContentRx) { $risky = $true; $reason = 'looks like it contains a password, token or key' } } catch {}
        }
      }
    }
    $out.Add([pscustomobject]@{ Path = $p; OldPath = $old; Status = "$x$y"; Kind = $kind; Staged = ($x -ne ' ' -and $x -ne '?'); Risky = $risky; RiskReason = $reason; Noise = (Test-NoisePath $p); SizeMB = $size; Outside = $outside })
  }
  $out.ToArray()
}

# GitHub refuses files over 100 MB (and warns above 50 MB).
$script:MaxFileMB = 100; $script:WarnFileMB = 50

function Get-GitignoreKind([string]$Path) {
  $f = (Test-IsRepo $Path).Folder; if (-not $f) { return 'generic' }
  if (Get-ChildItem -LiteralPath $f -Filter *.sln -ErrorAction SilentlyContinue | Select-Object -First 1) { return 'dotnet' }
  if (Get-ChildItem -LiteralPath $f -Include *.csproj, *.vbproj, *.fsproj -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1) { return 'dotnet' }
  if (Test-Path -LiteralPath (Join-Path $f 'package.json')) { return 'node' }
  if ((Test-Path -LiteralPath (Join-Path $f 'requirements.txt')) -or (Test-Path -LiteralPath (Join-Path $f 'pyproject.toml'))) { return 'python' }
  if ((Test-Path -LiteralPath (Join-Path $f 'pom.xml')) -or (Test-Path -LiteralPath (Join-Path $f 'build.gradle'))) { return 'java' }
  'generic'
}
$script:GitignoreText = @{
  dotnet  = ".vs/`nbin/`nobj/`npackages/`n*.user`n*.suo`n*.pdb`n*.nupkg`nTestResults/`npublish/`n*.publishsettings`nsecrets.json`n.DS_Store`nThumbs.db"
  node    = "node_modules/`ndist/`n.env`n.env.*`nnpm-debug.log*`n.DS_Store`nThumbs.db"
  python  = "__pycache__/`n*.pyc`n.venv/`nvenv/`n.env`n*.egg-info/`n.DS_Store`nThumbs.db"
  java    = "target/`nbuild/`n.gradle/`n*.class`n.idea/`n.DS_Store`nThumbs.db"
  generic = ".DS_Store`nThumbs.db`n.env`n*.log"
}
# Does this project need a .gitignore? (none exists and build/IDE clutter would be committed)
function Get-GitignoreAdvice([string]$Path) {
  $repo = Get-RepoRoot $Path
  $has = Test-Path -LiteralPath (Join-Path $repo '.gitignore')
  $noise = @(Get-WorkingChanges $repo | Where-Object Noise).Count
  [pscustomobject]@{ Needed = (-not $has -and $noise -gt 0); HasFile = $has; NoiseCount = $noise; Kind = (Get-GitignoreKind $repo) }
}
function Add-Gitignore([string]$Path, [string]$Kind) {
  $repo = Get-RepoRoot $Path; if (-not $Kind) { $Kind = Get-GitignoreKind $repo }
  $file = Join-Path $repo '.gitignore'
  $have = if (Test-Path -LiteralPath $file) { @([IO.File]::ReadAllLines($file)) } else { @() }
  $add = @($script:GitignoreText[$Kind] -split "`n" | Where-Object { $_ -and $have -notcontains $_ })
  if ($add.Count) { [IO.File]::AppendAllText($file, $(if ($have.Count) { "`r`n# added by backd8 ($Kind)`r`n" } else { "# generated by backd8 ($Kind)`r`n" }) + ($add -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false)) }
  $file
}

function Write-PathspecFile([string[]]$Paths) {
  $f = Join-Path ([IO.Path]::GetTempPath()) "backd8-paths-$PID-$([guid]::NewGuid().ToString('N').Substring(0,6)).txt"
  [IO.File]::WriteAllBytes($f, (New-Object Text.UTF8Encoding $false).GetBytes((($Paths | ForEach-Object { $_ }) -join "`0") + "`0")); $f
}

# Commits the chosen files (or everything with -All) with your message. Hooks run as usual, so backdating applies when ON.
# -Date sets an explicit author+committer date instead. Returns the new commit.
function New-CommitFromChanges([string]$Path, [string]$Message, [string[]]$Files, [switch]$All, [switch]$StagedOnly, $Date, [switch]$AllowLarge, [switch]$AllowRisky) {
  $repo = Get-RepoRoot $Path
  if (-not $Message -or -not $Message.Trim()) { throw 'Write a commit message first.' }
  $id = Get-GitIdentity $repo
  if (-not $id.Ok) { throw 'Git does not know who you are yet. Run:  git config --global user.name "Your Name"  and  git config --global user.email "you@example.com"' }
  if ($Date) { Assert-GitDate ([datetime]$Date) }
  $g = (Git-Out $repo @('rev-parse', '--absolute-git-dir')).Out[0]
  foreach ($f in 'rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD') {
    if (Test-Path -LiteralPath (Join-Path $g $f)) { throw 'A rebase, merge or cherry-pick is in progress. Finish or abort it first.' }
  }
  if (-not (Get-BranchName $repo) -and -not (Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')).Code) { throw 'You are not on a branch (detached HEAD): a commit made now would be easy to lose. Switch to a branch first (git switch <branch>).' }
  $ch = @(Get-WorkingChanges $repo)
  if (-not $ch.Count) { throw 'Nothing to commit: no files have changed.' }
  $by = @{}; foreach ($c in $ch) { $by[$c.Path] = $c }
  $paths = @(); $wasStaged = @($ch | Where-Object Staged | ForEach-Object { $_.Path })
  $chosen = @(if ($StagedOnly) { @($ch | Where-Object Staged) } elseif ($All) { $ch } else {
    if (-not $Files -or -not $Files.Count) { throw 'Choose at least one file to commit.' }
    foreach ($f in $Files) { if (-not $by.ContainsKey($f)) { throw "'$f' has no changes." } }
    @($Files | ForEach-Object { $by[$_] })
  })
  if ($StagedOnly -and -not $chosen.Count) { throw 'Nothing is staged. Stage files first or commit everything.' }
  $bad = @($chosen | Where-Object { $_.Status -match '^(U.|.U|AA|DD)$' })
  if ($bad.Count) { throw "These files have unresolved merge conflicts (<<<<<<< markers): $(@($bad | Select-Object -First 3 | ForEach-Object { $_.Path }) -join ', '). Fix them first." }
  $nest = @($chosen | Where-Object { $_.Kind -eq 'nested' })
  if ($nest.Count -and ($All -or $StagedOnly)) { $chosen = @($chosen | Where-Object { $_.Kind -ne 'nested' }) }
  elseif ($nest.Count) { throw "$($nest[0].Path) is a separate git project inside this folder, so it cannot be committed as part of this one." }
  $lnk = @($chosen | Where-Object Outside)
  if ($lnk.Count) { throw "$($lnk[0].Path) is reached through a shortcut/junction that leads outside this project, so it was not committed. Remove the link or leave the file out." }
  if (-not $chosen.Count) { throw 'Nothing to commit: only separate projects or linked folders changed.' }
  $risk = @($chosen | Where-Object { $_.Risky -and $_.Kind -ne 'deleted' })
  if ($risk.Count -and -not $AllowRisky) { throw "These files look like they hold passwords or keys: $(@($risk | Select-Object -First 5 | ForEach-Object { $_.Path }) -join ', '). Leave them out (or add them to .gitignore), or confirm that you really want them committed." }
  $big = @($chosen | Where-Object { $_.SizeMB -gt $script:MaxFileMB })
  if ($big.Count -and -not $AllowLarge) { throw "GitHub rejects files over $($script:MaxFileMB) MB: $(@($big | Select-Object -First 3 | ForEach-Object { "$($_.Path) ($([int]$_.SizeMB) MB)" }) -join ', '). Leave them out, or use Git LFS (https://git-lfs.com)." }
  $idxFile = $null; $idxBak = $null
  try { $ip = (Git-Out $repo @('rev-parse', '--git-path', 'index')).Out | Select-Object -First 1; if ($ip) { $idxFile = if ([IO.Path]::IsPathRooted($ip)) { $ip } else { Join-Path $repo $ip }; if (Test-Path -LiteralPath $idxFile) { $idxBak = [IO.File]::ReadAllBytes($idxFile) } } } catch { }   # so a refused commit leaves the index exactly as it was
  $pf = $null; $pfc = $null                                     # pathspec files for add / for commit
  if (-not $StagedOnly) {
    $plain = ($All -and -not $nest.Count)                       # everything: no pathspec at all (no argument-length limit, renames just work)
    $addPaths = @($chosen | Where-Object { $_.Status -notmatch '^D' } | ForEach-Object { $_.Path })   # a staged deletion is already in the index: nothing to add
    $paths = if ($plain) { @() } else { @($chosen | ForEach-Object { $_.Path; if ($_.OldPath) { $_.OldPath } }) }   # commit needs the old name of a rename too
    if ($plain) { $a = Git-Retry $repo @('add', '-A') }
    elseif ($addPaths.Count) { $pf = Write-PathspecFile $addPaths; $a = Git-Retry $repo @('--literal-pathspecs', 'add', '-A', "--pathspec-from-file=$pf", '--pathspec-file-nul') }
    else { $a = [pscustomobject]@{ Code = 0; Out = @() } }
    if ($paths.Count) { $pfc = Write-PathspecFile $paths }
    if ($a.Code) {
      foreach ($x in $pf, $pfc) { if ($x) { Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue } }
      $why = ($a.Out -join ' ')
      if ($why -match 'Permission denied|unable to index|Device or resource busy|being used by another process') { throw "A file is locked by another program (often Visual Studio). Close it, or leave that file out and try again. ($why)" }
      throw "git add failed: $why"
    }
  }  $tmp = Join-Path ([IO.Path]::GetTempPath()) "backd8-commit-$PID.txt"
  [IO.File]::WriteAllText($tmp, ($Message -replace "`r`n", "`n").TrimEnd() + "`n", (New-Object Text.UTF8Encoding $false))
  $envKeys = 'GIT_AUTHOR_DATE', 'GIT_COMMITTER_DATE', 'BACKDATE_RUNNING', 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL'; $saved = @{}; foreach ($k in $envKeys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
  try {
    foreach ($k in 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL') { [Environment]::SetEnvironmentVariable($k, $null) }   # the identity must come from git config, not a stray variable
    [Environment]::SetEnvironmentVariable('BACKDATE_RUNNING', '1')   # the optional auto-backdate hook must never touch commits made here
    if ($Date) { $iso = Iso ([datetime]$Date); foreach ($k in 'GIT_AUTHOR_DATE', 'GIT_COMMITTER_DATE') { [Environment]::SetEnvironmentVariable($k, $iso) } }
    $ca = @('--literal-pathspecs', 'commit', '-q', '--cleanup=verbatim', '-F', $tmp); if ($paths.Count) { $ca += "--pathspec-from-file=$pfc"; $ca += '--pathspec-file-nul' }
    $r = Git-Retry $repo $ca
  } finally {
    foreach ($k in $envKeys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    foreach ($x in $pf, $pfc) { if ($x) { Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue } }
  }
  if ($r.Code) {
    if ($idxFile -and $null -ne $idxBak) { try { [IO.File]::WriteAllBytes($idxFile, $idxBak) } catch { } }   # leave the index as we found it
    $why = ($r.Out -join ' ')
    if ($why -match 'does not have a commit checked out') { throw "A file and a folder swapped places (a file became a folder or the reverse), which git cannot commit file by file. Commit everything instead of choosing files, or commit the old and the new names together. ($why)" }
    throw "git commit failed:`n$((Hide-Secrets ($r.Out -join "`n")))"
  }
  $c = @(Get-CommitList $repo 1)[0]
  [pscustomobject]@{ Sha = $c.Sha; Short = $c.Short; Subject = $c.Subject; Date = $c.Date; Output = ($r.Out -join "`n") }
}

# Why an address cannot be used (null = fine). Plain language, shown to the user as is.
function Get-RemoteUrlProblem([string]$Url) {
  $u = "$Url".Trim()
  if (-not $u) { return 'Paste the address of your GitHub repository, for example https://github.com/<you>/<repo>.git' }
  $shape = ($u -notmatch '^-') -and ($u -match '^(https?|ssh|git|file)://\S+$' -or $u -match '^[\w.-]+@[\w.-]+:\S+$' -or $u -match '^[A-Za-z]:[\\/]' -or $u -match '^\\\\')
  if (-not $shape) { return 'That does not look like a repository address. Example: https://github.com/<you>/<repo>.git' }
  if ($u -match '^\\\\' -or $u -match '^file://[^/]' -or $u -match '^//') { return 'Network-share addresses are not supported (opening them can leak your Windows login to that server). Use a GitHub address or a folder on this PC.' }
  if (($u -match '^[a-z]+://[^/?#]*@' -and $u -notmatch '^ssh://git@') -or $u -match '[?#]') { return 'Do not put a user name, password or token inside the address (it would be stored in plain text), and leave out ? and # parts. Use the plain address and sign in to GitHub instead.' }
  if ($u -match '^https?://(www\.)?github\.com/([^/\s]+)/?$') { return 'That is a GitHub profile, not a repository. Use https://github.com/<you>/<repo>.git' }
  if ($u -match '^https?://(www\.)?github\.com/[^/\s]+/[^/\s]+/[^\s]+$') { return 'That is a page inside the repository (tree, issues, ...). Use the short address: https://github.com/<you>/<repo>.git' }
  $null
}
function Test-RemoteUrl([string]$Url) { -not (Get-RemoteUrlProblem $Url) }

function Set-RemoteUrl([string]$Path, [string]$Url, [string]$Name = 'origin') {
  $repo = Get-RepoRoot $Path; $Url = "$Url".Trim()
  $pr = Get-RemoteUrlProblem $Url; if ($pr) { throw $pr }
  $has = Git-Out $repo @('remote', 'get-url', $Name)
  $changed = (-not $has.Code) -and (($has.Out | Select-Object -First 1) -ne $Url)
  $r = if ($has.Code) { Git-Out $repo @('remote', 'add', $Name, $Url) } else { Git-Out $repo @('remote', 'set-url', $Name, $Url) }
  if ($r.Code) { throw "Could not set the remote: $($r.Out -join ' ')" }
  if ($changed) {   # what we remembered about the OLD address must not make the project look in sync with the new one
    foreach ($ref in (Git-Out $repo @('for-each-ref', '--format=%(refname)', "refs/remotes/$Name/")).Out) { if ($ref) { [void](Git-Out $repo @('update-ref', '-d', $ref)) } }
  }
  "Remote '$Name' = $(Hide-Secrets $Url)"
}

function Initialize-Repo([string]$Path, [string]$RemoteUrl, [string]$Branch = 'main') {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Folder not found: $Path" }
  $t = Test-IsRepo $Path
  if ($t.IsRepo) { throw "This folder is already part of the git project at $($t.Root)." }
  if ($RemoteUrl) { $pr = Get-RemoteUrlProblem $RemoteUrl; if ($pr) { throw $pr } }
  $r = Git-Out $t.Folder @('init', '-q', '-b', $Branch)
  if ($r.Code) { throw "git init failed: $($r.Out -join ' ')" }
  if ($RemoteUrl) { [void](Set-RemoteUrl $t.Folder $RemoteUrl) }
  $t.Folder
}

# Bring GitHub's newer work into your project (fetch, then fast-forward or merge). Never rewrites your commits.
# Result: nothing-on-github | up-to-date | fast-forward | merged | conflict (nothing is changed on conflict).
function Merge-RemoteChanges([string]$Path) {
  $repo = Get-RepoRoot $Path
  $gd = (Git-Out $repo @('rev-parse', '--absolute-git-dir')).Out | Select-Object -First 1
  foreach ($n in 'rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD') { if ($gd -and (Test-Path -LiteralPath (Join-Path $gd $n))) { throw 'A merge, rebase or cherry-pick is in progress in this project. Finish or abort it first; backd8 will not touch it.' } }
  [void](Update-RemoteRefs $repo 30000)
  $s = Get-PushState $repo
  if (-not $s.Url) { throw "This project is not linked to GitHub yet." }
  $dest = $s.DestRef -replace '^refs/heads/', ''; $tr = "refs/remotes/$($s.Remote)/$dest"
  if ((Git-Out $repo @('rev-parse', '--verify', '-q', $tr)).Code) { return [pscustomobject]@{ Result = 'nothing-on-github'; Files = @(); Count = 0 } }
  $head = Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')
  if ($head.Code) {
    $count = [int]((Git-Out $repo @('rev-list', '--count', $tr)).Out | Select-Object -First 1); $m = Git-Out $repo @('merge', '--ff-only', $tr); if ($m.Code) { throw "Could not get GitHub's files: $($m.Out -join ' ')" }; return [pscustomobject]@{ Result = 'fast-forward'; Files = @(); Count = $count } }
  $count = [int]((Git-Out $repo @('rev-list', '--count', "HEAD..$tr")).Out | Select-Object -First 1)
  if (-not (Git-Out $repo @('merge-base', '--is-ancestor', $tr, 'HEAD')).Code) { return [pscustomobject]@{ Result = 'up-to-date'; Files = @(); Count = 0 } }
  $saved = $env:BACKDATE_RUNNING; $env:BACKDATE_RUNNING = '1'
  try {
    if (-not (Git-Out $repo @('merge-base', '--is-ancestor', 'HEAD', $tr)).Code) {
      $m = Git-Out $repo @('merge', '--ff-only', $tr)
      if ($m.Code) { throw "Could not get GitHub's changes (your uncommitted files may be in the way): $($m.Out -join ' ')" }
      return [pscustomobject]@{ Result = 'fast-forward'; Files = @(); Count = $count }
    }
    # GitHub still holds OLD versions of commits we rewrote: merging its tip would bring the old copies back (duplicated history, the typo returns).
    # Take only the commits that exist nowhere on this PC (e.g. a teammate's) and replay them on top of our rewritten history.
    $remoteNew = @((Git-Out $repo @('rev-list', "HEAD..$tr")).Out | Where-Object { $_ })
    $foreign = @((Git-Out $repo @('rev-list', '--reverse', '--topo-order', $tr, '--not', '--branches', '--tags', '--glob=refs/backd8/*')).Out | Where-Object { $_ })
    if ($remoteNew.Count -gt $foreign.Count) {
      if (-not $foreign.Count) { return [pscustomobject]@{ Result = 'nothing-new'; Files = @(); Count = 0 } }   # GitHub only has the old versions of your own commits
      foreach ($f in $foreign) { if (@((Git-Out $repo @('rev-list', '--parents', '-n', '1', $f)).Out[0] -split ' ').Count -gt 2) { throw 'GitHub contains merge commits made by someone else on top of the history you rewrote. backd8 cannot replay those safely: use a git tool (git pull) or undo your edit first.' } }
      $cp = Git-Out $repo (@('cherry-pick', '--allow-empty', '--keep-redundant-commits') + $foreign)
      if ($cp.Code) {
        $files = @((Git-Out $repo @('diff', '--name-only', '--diff-filter=U')).Out | Where-Object { $_ })
        [void](Git-Out $repo @('cherry-pick', '--abort'))
        return [pscustomobject]@{ Result = 'conflict'; Files = $files; Count = $foreign.Count }
      }
      return [pscustomobject]@{ Result = 'applied'; Files = @(); Count = $foreign.Count }
    }
    $m = Git-Out $repo @('merge', '--no-edit', '--allow-unrelated-histories', '-m', "Merge GitHub's changes into your project", $tr)
    if ($m.Code) {
      $files = @((Git-Out $repo @('diff', '--name-only', '--diff-filter=U')).Out | Where-Object { $_ })
      [void](Git-Out $repo @('merge', '--abort'))
      if (-not $files.Count) { throw "Could not combine your work with GitHub's: $($m.Out -join ' ')" }
      return [pscustomobject]@{ Result = 'conflict'; Files = $files; Count = $count }
    }
    [pscustomobject]@{ Result = 'merged'; Files = @(); Count = $count }
  } finally { $env:BACKDATE_RUNNING = $saved }
}
# Ascending dates starting at $Start, about 1-6 hours apart (like the old auto-backdating clock), never in the future.
function New-DateSpread([datetime]$Start, [int]$Count, [int]$MinMinutes = 60, [int]$MaxMinutes = 360) {
  if ($Count -lt 1) { throw 'Count must be at least 1.' }
  if ($Start -gt (Get-Date)) { throw 'Start date must be in the past.' }
  $d = $Start; $out = @($d)
  for ($i = 1; $i -lt $Count; $i++) { $d = $d.AddMinutes((Get-Random -Minimum $MinMinutes -Maximum ($MaxMinutes + 1))); $out += $d }
  if ($out[-1] -gt (Get-Date)) { throw "These $Count commits would run past today if spaced 1-6 hours apart. Choose an earlier start date." }
  $out
}

# Commit new work, apply edits to older commits, then push - in that order, stopping at the first problem.
# -NewCommit @{ Message='..'; Files=@(..) | All=$true; Date=<datetime> }   -Edits @{ '<sha>' = @{ message='..'; date=<datetime> } }
function Invoke-Publish([string]$Path, [hashtable]$NewCommit, [hashtable]$Edits, [switch]$Push, [switch]$Force, [switch]$DiscardRemote) {
  $log = New-Object Collections.Generic.List[string]
  if ($NewCommit -and $NewCommit.Date) { Assert-GitDate ([datetime]$NewCommit.Date) }                 # fail before anything is committed
  if ($NewCommit -and -not "$($NewCommit.Message)".Trim()) { throw 'Write a commit message first.' }
  if ($Push -and -not (Get-PushState $Path).Url) { throw 'This project is not linked to GitHub yet, so nothing was saved or published. Paste your GitHub repository address first (command line: backdate remote <folder> <address>).' }   # checked BEFORE committing
  if ($Edits) { foreach ($k in @($Edits.Keys)) { $ed = $Edits[$k]; if ($ed.date) { Assert-GitDate ([datetime]$ed.date) }; if ($null -ne $ed.message -and -not "$($ed.message)".Trim()) { throw "Commit message for $k cannot be empty." } } }
  if ($NewCommit) {
    $a = @{ Path = $Path; Message = $NewCommit.Message }
    if ($NewCommit.All) { $a.All = $true } elseif ($NewCommit.Files) { $a.Files = @($NewCommit.Files) }
    if ($NewCommit.Date) { $a.Date = $NewCommit.Date }
    if ($NewCommit.AllowRisky) { $a.AllowRisky = $true }
    $c = New-CommitFromChanges @a
    $log.Add("Committed $($c.Short): $($c.Subject)")
  }
  if ($Edits -and $Edits.Count) {
    $r = Set-CommitEdits $Path $Edits
    $log.Add("Edited $($r.Edited) commit(s); $($r.Rewritten) rewritten in total. Backup: $($r.Backup)")
    if (@($r.StaleRefs).Count) { $log.Add("Note: still on the old commits: $(@($r.StaleRefs) -join ', ')") }
    if ($r.SignaturesDropped) { $log.Add("Note: $($r.SignaturesDropped) signed commit(s) lost their signature.") }
  }
  if ($Push) { $log.Add((Push-Repo $Path -Force:$Force -DiscardRemote:$DiscardRemote)) }
  @($log)
}

# Refresh what we know about GitHub (fetch with a hard timeout, no prompts). Returns $true when it worked.
function Update-RemoteRefs([string]$Path, [int]$TimeoutMs = 20000) {
  $repo = Get-RepoRoot $Path; $b = Get-BranchName $repo; if (-not $b) { return $false }
  $rm = Git-Out $repo @('config', "branch.$b.remote"); $rn = if ($rm.Code -or -not $rm.Out -or -not $rm.Out[0]) { 'origin' } else { $rm.Out[0] }
  if ((Git-Out $repo @('remote', 'get-url', $rn)).Code) { return $false }
  $ur = (Git-Out $repo @('remote', 'get-url', $rn)).Out | Select-Object -First 1
  $r = Invoke-GitTimed $repo (@(Get-CredentialArgs $repo $ur) + @('fetch', '--quiet', '--prune', $rn)) $TimeoutMs @{ GIT_TERMINAL_PROMPT = '0'; GCM_INTERACTIVE = 'never' }
  (-not $r.TimedOut -and $r.Code -eq 0)
}

# The identity git will really use in this project (repo config overrides global), not just the global one.
function Get-GitIdentity([string]$Path) {
  $repo = Get-RepoRoot $Path
  $n = (Git-Out $repo @('config', 'user.name')).Out | Select-Object -First 1; $e = (Git-Out $repo @('config', 'user.email')).Out | Select-Object -First 1
  [pscustomobject]@{ Name = $n; Email = $e; Ok = [bool]($n -and $e) }
}

# The user's global git identity (what `git config --global` holds), read with a clean environment and a captured message.
function Get-GlobalGitIdentity {
  $n = (Git-Out $env:USERPROFILE @('config', '--global', 'user.name')).Out | Select-Object -First 1
  $m = (Git-Out $env:USERPROFILE @('config', '--global', 'user.email')).Out | Select-Object -First 1
  [pscustomobject]@{ Name = "$n".Trim(); Mail = "$m".Trim(); Ok = [bool]("$n".Trim() -and "$m".Trim()) }
}

# Saves name + email into the global git config. Throws a plain message that includes what git really said.
function Set-GitIdentity([string]$Name, [string]$Email) {
  $Name = "$Name".Trim(); $Email = "$Email".Trim()
  if (-not $Name) { throw 'Type your name first.' }
  if ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'Type a valid email address, for example you@example.com.' }
  foreach ($kv in @(@('user.name', $Name, 'name'), @('user.email', $Email, 'email'))) {
    $r = Git-Retry $env:USERPROFILE @('config', '--global', $kv[0], $kv[1])
    if ($r.Code) {
      $why = ($r.Out -join ' ').Trim()
      $hint = if ($why -match 'lock') { "another program is using your git settings file ($(Join-Path $env:USERPROFILE '.gitconfig')). Close other git tools and try again." } elseif ($why) { $why } else { "git exited with code $($r.Code) and no message" }
      throw "Git could not save your $($kv[2]): $hint"
    }
  }
}

# ---------- the easy path: what can the user do right now, and one call to do the common thing ----------
# A commit message suggestion from what changed ("First version", "Update Program.cs and 2 other files", ...).
function Get-SuggestedMessage([string]$Path, [string[]]$Files) {
  $repo = Get-RepoRoot $Path
  $ch = @(Get-WorkingChanges $repo | Where-Object { -not $_.Noise -and $_.Kind -ne 'nested' })
  if ($Files) { $ch = @($ch | Where-Object { $Files -contains $_.Path }) }
  if (-not $ch.Count) { return '' }
  if ((Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')).Code) { return 'First version' }
  $leaf = { param($p) ($p -split '/')[-1] }
  $first = $ch[0]; $name = & $leaf $first.Path
  $verb = switch ($first.Kind) { 'new' { 'Add' } 'deleted' { 'Remove' } 'renamed' { 'Rename' } default { 'Update' } }
  if ($ch.Count -eq 1) { return "$verb $name" }
  $kinds = @($ch | ForEach-Object { $_.Kind } | Select-Object -Unique)
  $verb = if ($kinds.Count -eq 1 -and $kinds[0] -eq 'new') { 'Add' } elseif ($kinds.Count -eq 1 -and $kinds[0] -eq 'deleted') { 'Remove' } else { 'Update' }
  $others = $ch.Count - 1
  "$verb $name and $others other file$(if ($others -ne 1) { 's' })"
}

# Everything a wizard needs to decide what to offer. -Fetch also asks GitHub (slower, needs a network).
function Get-WorkflowState([string]$Path, [switch]$Fetch) {
  $t = Test-IsRepo $Path
  $s = [ordered]@{ Exists = $t.Exists; IsRepo = $t.IsRepo; Root = $t.Root; Branch = $null; HasCommits = $false; Changes = 0; Risky = 0; Noise = 0; TooBig = 0
    Linked = $false; Url = $null; Ahead = $null; Behind = $null; RemoteOnly = 0; Backups = 0; IdentityOk = $true; NeedsIgnore = $false; SignedIn = $null; Options = @(); Recommended = $null }
  if (-not $t.IsRepo) { $s.Options = @([pscustomobject]@{ Id = 'init'; Title = 'Turn this folder into a project'; Available = $t.Exists; Why = $(if (-not $t.Exists) { 'Choose a folder first.' }) }); $s.Recommended = if ($t.Exists) { 'init' } else { $null }; return [pscustomobject]$s }
  $repo = $t.Root
  $s.Branch = Get-BranchName $repo
  $s.HasCommits = -not (Git-Out $repo @('rev-parse', '--verify', '-q', 'HEAD')).Code
  $ch = @(Get-WorkingChanges $repo)
  $s.Changes = @($ch | Where-Object { -not $_.Noise -and $_.Kind -ne 'nested' }).Count; $s.Noise = @($ch | Where-Object Noise).Count
  $s.Risky = @($ch | Where-Object Risky).Count; $s.TooBig = @($ch | Where-Object { $_.SizeMB -gt $script:MaxFileMB }).Count
  $s.IdentityOk = (Get-GitIdentity $repo).Ok
  $s.NeedsIgnore = (Get-GitignoreAdvice $repo).Needed
  $s.Backups = @(Get-Backups $repo).Count
  if ($s.Branch) {
    if ($Fetch) { [void](Update-RemoteRefs $repo) }
    $ps = Get-PushState $repo
    $s.Linked = [bool]$ps.Url; $s.Url = $ps.Url; $s.Ahead = $ps.Ahead; $s.Behind = $ps.Behind; $s.RemoteOnly = $ps.RemoteOnly
  }
  $detached = -not $s.Branch
  $opts = @()
  $opts += [pscustomobject]@{ Id = 'express'; Title = 'Save my changes and put them on GitHub'; Available = ($s.Changes -gt 0 -or ($s.Linked -and ($s.Ahead -gt 0 -or -not $s.HasCommits))) -and -not $detached; Why = $(if ($detached) { 'You are not on a branch.' } elseif (-not $s.Changes -and -not ($s.Linked -and $s.Ahead -gt 0)) { 'Nothing has changed since your last save.' }) }
  $opts += [pscustomobject]@{ Id = 'edit'; Title = 'Change an older commit (message or date)'; Available = ($s.HasCommits -and -not $detached); Why = $(if (-not $s.HasCommits) { 'There are no commits yet.' } elseif ($detached) { 'You are not on a branch.' }) }
  $opts += [pscustomobject]@{ Id = 'spread'; Title = 'Spread my commits over a period of time'; Available = ($s.HasCommits -and -not $detached); Why = $(if (-not $s.HasCommits) { 'There are no commits yet.' }) }
  $opts += [pscustomobject]@{ Id = 'sync'; Title = 'Get the latest from GitHub'; Available = ($s.Linked -and $s.Behind -gt 0); Why = $(if (-not $s.Linked) { 'This project is not linked to GitHub yet.' } elseif (-not ($s.Behind -gt 0)) { 'GitHub has nothing newer.' }) }
  $opts += [pscustomobject]@{ Id = 'undo'; Title = 'Undo my last change'; Available = ($s.Backups -gt 0); Why = $(if ($s.Backups -eq 0) { 'There is nothing to undo.' }) }
  $s.Options = $opts
  $s.Recommended = if (($s.Linked -and $s.Behind -gt 0 -and $s.Ahead -eq 0)) { 'sync' } elseif (($opts | Where-Object Id -eq 'express').Available) { 'express' } elseif (($opts | Where-Object Id -eq 'edit').Available) { 'edit' } else { $null }
  [pscustomobject]$s
}

# The common thing in one call: save files -> (get GitHub's newer work) -> check sign-in -> send. -OnStep receives (n, total, text, state).
# Stops at the first problem with the engine's plain message (e.g. "GitHub sign-in required ...") so a wizard can offer the fix and call it again.
function Publish-Express([string]$Path, [string]$Message, $Date, [string[]]$Files, [switch]$All, [scriptblock]$OnStep) {
  $repo = Get-RepoRoot $Path
  $step = { param($n, $total, $text, $state) if ($OnStep) { & $OnStep $n $total $text $state } }
  $log = New-Object Collections.Generic.List[string]
  $hasChanges = @(Get-WorkingChanges $repo | Where-Object { -not $_.Noise -and $_.Kind -ne 'nested' }).Count -gt 0
  $n = 0; $total = 4
  $n++; if ($hasChanges) {
    & $step $n $total 'Saving your files as a commit' 'run'
    $a = @{ Path = $repo; Message = $Message }; if ($Date) { $a.Date = $Date }
    if ($Files -and $Files.Count) { $a.Files = $Files } else { $a.All = $true }
    $c = New-CommitFromChanges @a; $log.Add("Saved $($c.Short): $($c.Subject)"); & $step $n $total 'Saved your files as a commit' 'done'
  } else { & $step $n $total 'Nothing new to save' 'skip' }
  $n++; $s = Get-PushState $repo
  if (-not $s.Url) { throw "This project is not linked to GitHub yet. Paste your GitHub repository address first." }
  & $step $n $total 'Checking GitHub for newer changes' 'run'
  [void](Update-RemoteRefs $repo 30000); $s = Get-PushState $repo
  if ($s.Behind -gt 0) {
    $m = Merge-RemoteChanges $repo
    if ($m.Result -eq 'conflict') { throw "GitHub and your project changed the same file(s): $($m.Files -join ', '). Nothing was changed. Resolve this in a git tool, then try again." }
    $log.Add("Got $($m.Count) newer change(s) from GitHub ($($m.Result))"); & $step $n $total "Got GitHub's newer changes" 'done'
  } else { & $step $n $total 'GitHub has nothing newer' 'done' }
  $n++; & $step $n $total 'Sending to GitHub' 'run'
  $log.Add((Push-Repo $repo)); & $step $n $total 'Sent to GitHub' 'done'
  $n++; & $step $n $total 'Finished' 'done'
  @($log.ToArray())
}

# Leave specific files out of future commits (writes anchored entries to .gitignore). Returns the .gitignore path.
function Add-GitignoreEntries([string]$Path, [string[]]$Entries) {
  $repo = Get-RepoRoot $Path; $file = Join-Path $repo '.gitignore'
  $have = if (Test-Path -LiteralPath $file) { @([IO.File]::ReadAllLines($file)) } else { @() }
  $add = @($Entries | Where-Object { $_ } | ForEach-Object { '/' + ($_ -replace '\\', '/').TrimStart('/') } | Where-Object { $have -notcontains $_ } | Select-Object -Unique)
  if ($add.Count) { [IO.File]::AppendAllText($file, $(if ($have.Count) { "`r`n" } else { '' }) + "# left out by backd8 (looks like it holds secrets)`r`n" + ($add -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false)) }
  $file
}
