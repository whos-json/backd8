# UAT: end-to-end checks using real git against isolated config (never touches your real
# ~/.gitconfig or config.json).   Run: powershell -ExecutionPolicy Bypass -File tests\uat.ps1
$proj = Split-Path $PSScriptRoot
$T = Join-Path $env:TEMP "backd8-uat-$(Get-Random)"; New-Item -ItemType Directory $T | Out-Null
$env:GIT_CONFIG_GLOBAL = "$T\gitconfig"; $env:BACKDATE_CONFIG = "$T\config.json"
git config --global user.name 'UAT User'; git config --global user.email 'uat@example.com'; git config --global init.defaultBranch main
$script:bdScript = "$proj\backdate.ps1"
$gitBash = Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'bin\bash.exe'
function Bd { powershell -NoProfile -ExecutionPolicy Bypass -File $script:bdScript @args 2>&1 | Out-String }
$script:fail = 0; $script:n = 0
function Check($ok, $name) { $script:n++; if ($ok) { "  PASS  $name" } else { $script:fail++; "  FAIL  $name" } }
function NewRepo($name) { $p = "$T\$name"; New-Item -ItemType Directory $p | Out-Null; git -C $p init -q; $p }
function Commit($repo, $msg = 'c', [switch]$Empty) {
  Set-Content "$repo\f-$(Get-Random).txt" $msg
  git -C $repo add -A; git -C $repo commit -q -m $msg 2>&1 | Out-Null
  [datetimeoffset](git -C $repo log -1 --format=%aI) | % LocalDateTime
}
function CDate($repo) { [datetimeoffset](git -C $repo log -1 --format=%cI) | % LocalDateTime }
function Cfg { Get-Content $env:BACKDATE_CONFIG -Raw | ConvertFrom-Json }
$start = [datetime]'2022-06-15T12:00:00'
$s = '2022-06-15T12:00:00'

"== Install / uninstall"
Check ((Bd status) -match 'installed: False') 'status before install'
git config --global core.hooksPath 'C:/other/hooks'
$o = Bd install; Check ($o -match 'already set' -and (git config --global core.hooksPath) -eq 'C:/other/hooks') 'install refuses to clobber foreign hooksPath'
$o = Bd uninstall; Check ($o -match 'not backd8' -and (git config --global core.hooksPath) -eq 'C:/other/hooks') 'uninstall leaves foreign hooksPath'
$o = Bd install -Force; Check ((Bd status) -match 'installed: True') 'install -Force replaces'
$raw = [IO.File]::ReadAllBytes("$proj\hooks\post-commit"); Check (-not ($raw -contains 13)) 'hook files use LF (no CR)'
Check ((Get-ChildItem "$proj\hooks").Count -ge 14) 'all hook shims written'
Check ((Bd on) -match 'Set a start date first') 'ON refused with no start date'
Check ((Bd set '*' '2999-01-01') -match 'in the past') 'future start date rejected'
Check ((Bd set 'C:\nope\nope' $s) -match 'not found') 'missing repo folder rejected'
Check ((Bd set '*' 'garbage') -match 'Error') 'invalid date rejected'
Bd set '*' $s | Out-Null

"== Disabled = untouched"
$r = NewRepo 'disabled'; $d = Commit $r
Check (((Get-Date) - $d).TotalMinutes -lt 5) 'commit keeps real date while OFF'

"== Enabled: default start + auto-advance"
Bd on | Out-Null
$a = NewRepo 'a'; $d1 = Commit $a; $d2 = Commit $a; $d3 = Commit $a
Check ($d1 -eq $start) 'first commit = start date exactly'
Check (($d2 - $d1).TotalMinutes -ge 60 -and ($d2 - $d1).TotalMinutes -le 360) 'second commit +1..6h'
Check (($d3 -gt $d2) -and ($d3 - $d2).TotalMinutes -le 360) 'third commit later still (monotonic)'
Check ((CDate $a) -eq $d3) 'author date == committer date'
Check ((git -C $a log --format=%an%ae -1) -eq 'UAT Useruat@example.com') 'author identity preserved'
Check ((git -C $a rev-list --count HEAD) -eq '3' -and (git -C $a status --porcelain) -eq $null) '3 commits, clean tree (amend did not duplicate)'

"== Independent clocks / per-repo override / path-case normalisation"
$b = NewRepo 'b'; Check ((Commit $b) -eq $start) 'new repo starts at default, unaffected by repo a'
$c = NewRepo 'c Spaces üï'; Bd set $c '2021-03-01T09:30:00' | Out-Null
Check ((Commit $c) -eq [datetime]'2021-03-01T09:30:00') 'per-repo override (path with spaces/unicode)'
Bd set $c.ToUpper() '2020-01-01T08:00:00' | Out-Null
Check (@((Cfg).repos | ? { $_.path -like '*spaces*' }).Count -eq 1) 'case-insensitive path = same entry (no duplicate)'
$dc = Commit $c; Check ($dc -gt [datetime]'2021-03-01T09:30:00' -and ($dc - [datetime]'2021-03-01T09:30:00').TotalHours -le 6.1 -and (@((Cfg).repos) | ? { $_.path -like '*spaces*' }).start -like '2020-01-01*') 'resetting a repo date to before its last commit: clamped after parent, never goes backwards'

"== Repo-local hooks still work (global hooksPath must not disable them)"
$h = NewRepo 'hooks'
Set-Content "$h\.git\hooks\pre-commit" "#!/bin/sh`necho ran > '$($h -replace '\\','/')/pre.marker'" -Encoding ascii
Set-Content "$h\.git\hooks\commit-msg" "#!/bin/sh`ngrep -q OK `"`$1`" || { echo bad msg; exit 1; }" -Encoding ascii
Set-Content "$h\.git\hooks\post-commit" "#!/bin/sh`necho ran > '$($h -replace '\\','/')/post.marker'" -Encoding ascii
$null = Commit $h 'nope'
Check ((Test-Path "$h\pre.marker") -and (git -C $h rev-list --count HEAD 2>$null) -ne '1') 'repo pre-commit ran; commit-msg hook (with args) blocked bad message'
$d = Commit $h 'OK msg'
Check ((Test-Path "$h\post.marker") -and $d -eq $start) 'repo post-commit ran AND commit backdated'
Set-Content "$h\.git\hooks\pre-commit" "#!/bin/sh`nexit 1" -Encoding ascii
$cnt = git -C $h rev-list --count HEAD; $null = Commit $h 'OK again'
Check ((git -C $h rev-list --count HEAD) -eq $cnt) 'failing repo pre-commit still blocks commit'

"== Manual dates, amend, merge, rebase, empty, worktree"
$m = NewRepo 'manual'
$env:GIT_AUTHOR_DATE = '2020-02-02T10:00:00'; $env:GIT_COMMITTER_DATE = '2020-02-02T10:00:00'
$d = Commit $m; Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE
Check ($d -eq [datetime]'2020-02-02T10:00:00') 'manual env-var date respected (not overwritten)'
Check (-not (@((Cfg).repos) | ? { $_.path -like '*manual' })) 'manual commit did not advance a clock'
$before = (@((Cfg).repos) | ? { $_.path -like '*/a' }).next
git -C $a commit -q --amend -m 'reworded'
Check (([datetimeoffset](git -C $a log -1 --format=%aI)).LocalDateTime -eq $d3 -and (@((Cfg).repos) | ? { $_.path -like '*/a' }).next -eq $before) 'user amend of backdated commit: author date kept, clock not advanced'
git -C $a checkout -q -b feat; $df = Commit $a 'feat1'
git -C $a checkout -q main; $dm = Commit $a 'main2'
$nextBefore = (@((Cfg).repos) | ? { $_.path -like '*/a' }).next
git -C $a merge -q --no-ff feat -m 'merge feat' 2>&1 | Out-Null
$mp = (git -C $a rev-list --parents -n1 HEAD) -split ' '
Check ($mp.Count -eq 3 -and ((Get-Date) - (CDate $a)).TotalMinutes -lt 5 -and (@((Cfg).repos) | ? { $_.path -like '*/a' }).next -eq $nextBefore) 'merge commit skipped (real date, clock untouched)'
git -C $a checkout -q feat; $nb = (@((Cfg).repos) | ? { $_.path -like '*/a' }).next
git -C $a rebase -q main 2>&1 | Out-Null
Check ((git -C $a status --porcelain) -eq $null -and (@((Cfg).repos) | ? { $_.path -like '*/a' }).next -eq $nb) 'rebase leaves clock untouched'
$e = NewRepo 'empty'; git -C $e commit -q --allow-empty -m 'empty root' 2>&1 | Out-Null
Check (([datetimeoffset](git -C $e log -1 --format=%aI)).LocalDateTime -eq $start) 'empty root commit backdated'
$w = NewRepo 'wt-main'; $null = Commit $w; git -C $w worktree add -q "$T\wt-side" -b side 2>&1 | Out-Null
$dw = Commit "$T\wt-side" 'in worktree'
Check ($dw -gt $start -and $dw -lt (Get-Date).AddYears(-3)) 'commit inside git worktree backdated and advanced'

"== Caught up with real time"
$f1 = NewRepo 'future'; Bd set $f1 (Get-Date).AddMinutes(-30).ToString('s') | Out-Null
$x1 = Commit $f1; $x2 = Commit $f1
Check ($x1 -lt (Get-Date).AddMinutes(-20) -and ((Get-Date) - $x2).TotalMinutes -lt 5) 'stops backdating once clock passes now'

"== Concurrency (config lock)"
$cc = 1..6 | % { NewRepo "conc$_" }
$procs = $cc | % { Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:bdScript, 'set', "`"$_`"", '2018-01-01T08:00:00' }
$procs | % { [void]$_.WaitForExit(60000) }
Check (@((Cfg).repos | ? { $_.path -like '*/conc*' }).Count -eq 6) 'six parallel `set` calls all persisted (no lost updates)'
Check (-not (Get-ChildItem (Split-Path $env:BACKDATE_CONFIG) -Filter '*.tmp')) 'no leftover .tmp files'
$hp = $cc | % { $d = $_; Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command', "Set-Content '$d\x.txt' 1; git -C '$d' add -A; git -C '$d' commit -q -m par" }
$hp | % { [void]$_.WaitForExit(90000) }
Check (@($cc | ? { ([datetimeoffset](git -C $_ log -1 --format=%aI)).LocalDateTime -eq [datetime]'2018-01-01T08:00:00' }).Count -eq 6) 'six simultaneous commits in six repos all backdated, none blocked'
Check (@((Cfg).repos | ? { $_.path -like '*/conc*' -and $_.next }).Count -eq 6) 'each repo clock advanced exactly once'

"== Repo-local hooksPath warning"
$lh = NewRepo 'localhooks'; Bd set $lh $s | Out-Null; git -C $lh config --local core.hooksPath .githooks
Check ((Bd status) -match 'sets its own core.hooksPath') 'status warns about repos that override hooksPath'

"== Robustness"
Bd off | Out-Null; $r2 = NewRepo 'off2'; Check (((Get-Date) - (Commit $r2)).TotalMinutes -lt 5) 'OFF again -> real date'
Bd on | Out-Null; Set-Content $env:BACKDATE_CONFIG '{ corrupt'
$r3 = NewRepo 'corrupt'; $d = Commit $r3
Check (((Get-Date) - $d).TotalMinutes -lt 5 -and (git -C $r3 rev-list --count HEAD) -eq '1') 'corrupt config never breaks or blocks a commit'
Remove-Item $env:BACKDATE_CONFIG
Bd set '*' $s | Out-Null; Bd remove $a | Out-Null
Check ((Bd list) -notmatch '/a ') 'remove repo'
Bd uninstall | Out-Null; Check ((Bd status) -match 'installed: False' -and -not (git config --global core.hooksPath)) 'uninstall'

"== Claude-Code-style commit via Git Bash"
Bd install | Out-Null; Bd on | Out-Null
$bash = NewRepo 'bash'
& $gitBash -c "cd '$($bash -replace '\\','/')' && echo x > x && git add x && git commit -q -m viabash" 2>&1 | Out-Null
Check (([datetimeoffset](git -C $bash log -1 --format=%aI)).LocalDateTime -eq $start) 'git commit from bash backdated'
Bd uninstall | Out-Null

"== GUI self-test + exe launch"
Remove-Item $env:BACKDATE_CONFIG -ErrorAction SilentlyContinue; Bd uninstall | Out-Null   # known starting state
$env:BACKD8_TEST_REPO = (NewRepo 'gui')
$g2 = NewRepo 'gui2'; 1..4 | % { $null = Commit $g2 "g$_" }; $gb = "$T\gui2.git"; git init -q --bare $gb; git -C $g2 remote add origin $gb; $env:BACKD8_TEST_REPO2 = $g2   # editor self-test: several commits + local bare remote
$o = powershell -NoProfile -ExecutionPolicy Bypass -STA -File "$proj\gui.ps1" -SelfTest 2>&1 | Out-String
Check ($o -match 'selftest-editor-ok') 'GUI commit editor: load, stage, apply, push refused, force push, undo, sign-in routing'
Check ($o -match 'selftest-ok rows=0') "GUI handlers: install, default, add repo, toggle ON/OFF, update, remove ($($o.Trim().Split("`n")[-1]))"
Check (-not (git config --global core.hooksPath) -and ((Cfg).enabled -eq $false)) 'GUI end state: uninstalled, backdating OFF'
$exe = Start-Process "$proj\BackD8.exe" -PassThru; $ok = $false
for ($i = 0; $i -lt 20 -and -not $ok; $i++) {
  Start-Sleep -Milliseconds 500
  $ok = [bool](Get-Process powershell -ErrorAction SilentlyContinue | ? { $_.MainWindowTitle -like 'backd8*' })
}
Check $ok 'BackD8.exe opens the window'
Get-Process powershell -ErrorAction SilentlyContinue | ? { $_.MainWindowTitle -like 'backd8*' } | Stop-Process -Force

Remove-Item Env:GIT_CONFIG_GLOBAL, Env:BACKDATE_CONFIG; Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue
"`n$($script:n - $script:fail)/$($script:n) passed"; exit $script:fail

