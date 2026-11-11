# End-to-end simulation of real use, against a fake "GitHub" (real smart-HTTP git server that demands a login):
#   new PC -> identity -> install hook -> backdated commits -> push refused (not signed in) -> sign in -> push ->
#   edit commit messages/dates -> force push -> second computer -> conflicts -> undo -> uninstall.
# Fully isolated (own git config, own config.json, own credential store); no internet, no real GitHub, no windows.
# Run: powershell -ExecutionPolicy Bypass -File tests\simulate.ps1
$proj = Split-Path $PSScriptRoot
$T = Join-Path $env:TEMP "backd8-sim-$(Get-Random)"; New-Item -ItemType Directory $T | Out-Null
$cfg = "$T\gitconfig"; $store = ($T -replace '\\', '/') + '/credentials'
# A brand-new PC: no identity, no saved credentials. credential.helper= (empty) first resets the system-level Git Credential Manager.
[IO.File]::WriteAllText($cfg, "[init]`n`tdefaultBranch = main`n[credential]`n`thelper =`n`thelper = store --file=$store`n", (New-Object Text.UTF8Encoding $false))
$env:GIT_CONFIG_GLOBAL = $cfg; $env:BACKDATE_CONFIG = "$T\config.json"; $env:GCM_INTERACTIVE = 'never'; $env:GIT_TERMINAL_PROMPT = '0'
$script:bd = "$proj\backdate.ps1"
function Bd { powershell -NoProfile -ExecutionPolicy Bypass -File $script:bd @args 2>&1 | Out-String }
. "$proj\lib.ps1"
$script:fail = 0; $script:n = 0
function Say($s) { "`n### $s" }
function Check($ok, $name) { $script:n++; if ($ok) { "  PASS  $name" } else { $script:fail++; "  FAIL  $name" } }
function G($r, [string[]]$a) { (& git -C $r @a 2>&1 | ForEach-Object { "$_" }) -join "`n" }
function Throws([scriptblock]$b, [string]$like) { try { & $b | Out-Null; $false } catch { $_.Exception.Message -like $like } }
function Dates($r) { @(G $r @('log', '--reverse', '--format=%aI')) -split "`n" | ForEach-Object { ([datetimeoffset]$_).LocalDateTime } }
function Work($r, $msg) { Set-Content "$r\f-$(Get-Random).txt" $msg; git -C $r add -A | Out-Null; $o = git -C $r commit -q -m $msg 2>&1; $o | Where-Object { $_ -match 'backdate:' } }

$tok = 'ghp_SIMULATEDTOKEN0123456789'
$pn = (New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0); $pn.Start(); $port = $pn.LocalEndpoint.Port; $pn.Stop()
$root = "$T\ghroot"; New-Item -ItemType Directory "$root\me" | Out-Null; git init -q --bare "$root\me\portfolio.git"
$ready = "$T\ready.flag"; $log = "$T\server.log"
$srv = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$PSScriptRoot\fake-github.ps1", '-Port', $port, '-Root', $root, '-Token', $tok, '-Log', $log, '-Ready', $ready
try {
  for ($i = 0; $i -lt 40 -and -not (Test-Path $ready); $i++) { Start-Sleep -Milliseconds 250 }
  Check (Test-Path $ready) 'fake GitHub server is up'
  $url = "http://localhost:$port/me/portfolio.git"

  Say 'DAY 1 - brand-new PC: git has no idea who I am'
  $pf = "$T\portfolio"; New-Item -ItemType Directory $pf | Out-Null; git -C $pf init -q; git -C $pf remote add origin $url
  $o = Bd github $pf
  Check ($o -match 'Git identity: NOT SET' -and $o -match 'user\.name') 'CLI warns the git identity is missing and shows the exact fix'
  git config --global user.name 'Sim User'; git config --global user.email 'sim@example.com'
  Check ((Bd github $pf) -match 'Git identity: Sim User') 'identity fixed'

  Say 'Install the hook, set a start date, turn backdating ON'
  Check ((Bd install) -match 'Installed') 'install'
  Check ((Bd set '*' '2023-03-01T09:00:00') -match 'Set \* ->') 'default start date'
  Check ((Bd on) -match 'ON') 'turn ON'
  Check ((Bd status) -match 'Hook installed: True' -and (Bd status) -match 'Backdating:\s+ON') 'status shows installed + ON'

  Say 'Work: 12 normal `git commit`s (the hook rewrites each date)'
  1..12 | ForEach-Object { [void](Work $pf "feature $_") }
  $d = @(Dates $pf)
  Check ($d.Count -eq 12 -and $d[0] -eq [datetime]'2023-03-01T09:00:00') 'first commit = start date'
  $mono = $true; $gapsOk = $true; for ($i = 1; $i -lt 12; $i++) { $g = ($d[$i] - $d[$i - 1]).TotalMinutes; if ($g -le 0) { $mono = $false }; if ($g -lt 60 -or $g -gt 360) { $gapsOk = $false } }
  Check ($mono -and $gapsOk) 'dates strictly increase, each +1..6 h'
  Check ($d[11] -lt (Get-Date).AddYears(-3)) 'all commits are in the past (2023)'
  Check ((G $pf @('log', '-1', '--format=%an|%ae')) -eq 'Sim User|sim@example.com') 'author identity untouched by backdating'
  Check ((G $pf @('rev-list', '--count', 'HEAD')) -eq '12' -and -not (G $pf @('status', '--porcelain'))) '12 commits, clean tree'

  Say 'First push: NOT signed in to GitHub yet'
  $a = Get-GitHubAccess $pf
  Check ($a.Transport -eq 'https' -and $a.CanPush -eq $false -and -not $a.Ready) 'access check: cannot push'
  $o = Bd push $pf
  Check ($o -match 'GitHub sign-in required' -and $o -match 'github-login') 'push says "sign-in required" + how'
  Check ($o -notmatch [regex]::Escape($tok)) 'no token in output'
  Check ((G "$root\me\portfolio.git" @('rev-list', '--all', '--count')) -eq '0') 'nothing reached the server'

  Say 'Wrong / expired token'
  [IO.File]::WriteAllText("$T\cred-bad.txt", "protocol=http`nhost=localhost:$port`nusername=sim`npassword=ghp_EXPIRED`n`n", (New-Object Text.UTF8Encoding $false))
  cmd /c "git credential approve < `"$T\cred-bad.txt`"" | Out-Null
  Check ((Get-GitHubAccess $pf).CanPush -eq $false) 'stale saved token is detected as not signed in'
  cmd /c "git credential reject < `"$T\cred-bad.txt`"" | Out-Null

  Say 'Sign in (what Git Credential Manager does after the browser login)'
  [IO.File]::WriteAllText("$T\cred-good.txt", "protocol=http`nhost=localhost:$port`nusername=sim`npassword=$tok`n`n", (New-Object Text.UTF8Encoding $false))
  cmd /c "git credential approve < `"$T\cred-good.txt`"" | Out-Null
  $a = Get-GitHubAccess $pf
  Check ($a.CanPush -eq $true -and $a.Ready) 'access check: can push'
  $o = Bd push $pf
  Check ($o -match 'Pushed main' -and $o -notmatch [regex]::Escape($tok)) 'push succeeds'
  Check ((G "$root\me\portfolio.git" @('rev-parse', 'main')) -eq (G $pf @('rev-parse', 'HEAD'))) 'server has exactly my history'
  Check ((Get-PushState $pf).Ahead -eq 0 -and (Get-PushState $pf).Behind -eq 0) 'in sync'
  $srvDates = @(G "$root\me\portfolio.git" @('log', '--reverse', '--format=%aI')) -split "`n" | ForEach-Object { ([datetimeoffset]$_).LocalDateTime }
  Check ($srvDates[0] -eq $d[0] -and $srvDates[11] -eq $d[11]) 'GitHub shows the backdated dates'

  Say 'Edit history: reword #4, redate #8, then publish'
  $c = @(Get-CommitList $pf 50) | Sort-Object Date
  $s4 = ($c | Where-Object Subject -eq 'feature 4').Sha; $s8 = ($c | Where-Object Subject -eq 'feature 8').Sha
  $o = Bd reword $pf $s4.Substring(0, 8) 'feature 4: polished wording'
  Check ($o -match 'Reworded' -and $o -match 'force push') 'reword explains it needs a force push'
  $s8 = (@(Get-CommitList $pf 50) | Where-Object Subject -eq 'feature 8').Sha   # hash changed: it descends from the reworded commit
  $o = Bd redate $pf $s8.Substring(0, 8) '2023-03-02T10:30:00'
  Check ($o -match 'Redated') 'redate'
  $st = Get-PushState $pf
  Check ($st.Ahead -gt 0 -and $st.Behind -gt 0) "state: diverged (ahead $($st.Ahead) / behind $($st.Behind))"
  Check ((Bd push $pf) -match 'use force push') 'plain push refused after the edit'
  $o = Bd push $pf -Force
  Check ($o -match 'Pushed main') 'force push (lease) succeeds'
  Check ((G "$root\me\portfolio.git" @('rev-parse', 'main')) -eq (G $pf @('rev-parse', 'HEAD'))) 'server history = edited local history'
  Check ((G "$root\me\portfolio.git" @('log', '--format=%s')) -match 'feature 4: polished wording') 'edited message visible on the server'

  Say 'Keep working after the edit while backdating is ON'
  [void](Work $pf 'after edit 1'); [void](Work $pf 'after edit 2')
  Check ((Get-CommitList $pf 2)[0].Date -gt (Get-CommitList $pf 3)[2].Date) 'new commits are dated after the (edited) history - no time travel backwards'
  Check ((Bd push $pf) -match 'Pushed main') 'ordinary push of new commits needs no force'

  Say 'Second computer (laptop) pushes while I edit locally'
  $lp = "$T\laptop"; git clone -q $url $lp 2>&1 | Out-Null
  Check ((Test-Path "$lp\.git") -and (G $lp @('rev-list', '--count', 'HEAD')) -eq '14') 'laptop clones the repo (auth via saved login)'
  [void](Work $lp 'LAPTOP: fix typo'); git -C $lp push -q origin main 2>&1 | Out-Null
  Check ((G "$root\me\portfolio.git" @('log', '-1', '--format=%s', 'main')) -eq 'LAPTOP: fix typo') 'laptop commit is on the server'
  $null = Bd reword $pf HEAD~1 'after edit 1 (reworded on desktop)'
  $o = Bd push $pf -Force
  Check ($o -match 'nowhere in this repository') 'force push REFUSED: it would erase the laptop commit'
  Check ((G "$root\me\portfolio.git" @('log', '-1', '--format=%s', 'main')) -eq 'LAPTOP: fix typo') 'laptop commit still safe on the server'
  $o = Bd undo $pf
  Check ($o -match 'Restored') 'undo the desktop edit'
  git -C $pf pull -q --rebase origin main 2>&1 | Out-Null
  Check ((G $pf @('log', '-1', '--format=%s')) -eq 'LAPTOP: fix typo' -and (Get-PushState $pf).Behind -eq 0) 'sync: pulled the laptop commit'
  Check ((Bd reword $pf HEAD~2 'edited after pulling') -match 'Reworded') 'edit again, now including laptop history'
  $o = Bd push $pf -Force
  Check ($o -match 'Pushed main' -and (G "$root\me\portfolio.git" @('rev-parse', 'main')) -eq (G $pf @('rev-parse', 'HEAD'))) 'force push OK now that nothing foreign would be lost'

  Say 'Explicit override'
  $x = "$T\laptop2"; git clone -q $url $x 2>&1 | Out-Null; [void](Work $x 'precious'); git -C $x push -q origin main 2>&1 | Out-Null
  $null = Bd reword $pf HEAD 'tip reworded'
  Check ((Bd push $pf -Force) -match 'nowhere in this repository') 'refused again for the new foreign commit'
  $o = Bd push $pf -Force -DiscardRemote
  Check ($o -match 'Pushed main' -and (G "$root\me\portfolio.git" @('log', '--format=%s')) -notmatch 'precious') '-DiscardRemote honours an explicit decision'

  Say 'Turn backdating OFF: real dates again'
  Check ((Bd off) -match 'OFF') 'off'
  [void](Work $pf 'real-time commit')
  Check (((Get-Date) - (Get-CommitList $pf 1)[0].Date).TotalMinutes -lt 5) 'commit has the real date'
  Check ((Bd push $pf) -match 'Pushed main') 'push'

  Say 'Uninstall leaves the PC clean'
  Check ((Bd uninstall) -match 'Uninstalled') 'uninstall'
  Check (-not (git config --global core.hooksPath)) 'core.hooksPath removed'
  Check (-not (Get-Config).enabled) 'backdating flag is OFF'
  Check ((Get-Content $log -Raw) -notmatch [regex]::Escape($tok)) 'token never appears in the server log'

  Say 'Server saw what we expect'
  $lines = Get-Content $log
  Check (@($lines | Where-Object { $_ -match 'auth=False' }).Count -ge 1 -and @($lines | Where-Object { $_ -match 'POST .*git-receive-pack auth=True' }).Count -ge 3) 'unauthenticated requests were rejected, authenticated pushes went through'
}
finally {
  if ($srv -and -not $srv.HasExited) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item Env:GIT_CONFIG_GLOBAL, Env:BACKDATE_CONFIG, Env:GCM_INTERACTIVE, Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
  Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue
}
"`n$($script:n - $script:fail)/$($script:n) passed"; exit $script:fail
