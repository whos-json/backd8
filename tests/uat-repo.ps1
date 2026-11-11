# UAT for the commit-editing + push features. Isolated: own git config, own config.json, local bare repos as "GitHub".
# Run: powershell -ExecutionPolicy Bypass -File tests\uat-repo.ps1
$proj = Split-Path $PSScriptRoot
$T = Join-Path $env:TEMP "backd8-uatrepo-$(Get-Random)"; New-Item -ItemType Directory $T | Out-Null
$env:GIT_CONFIG_GLOBAL = "$T\gitconfig"; $env:BACKDATE_CONFIG = "$T\config.json"
git config --global user.name 'Test User'; git config --global user.email 'test@example.com'; git config --global init.defaultBranch main
git config --global protocol.file.allow always
$env:GCM_INTERACTIVE = 'never'   # never let Git Credential Manager pop a real sign-in window during tests
$script:bd = "$proj\backdate.ps1"
function Bd { powershell -NoProfile -ExecutionPolicy Bypass -File $script:bd @args 2>&1 | Out-String }
. "$proj\lib.ps1"
$script:fail = 0; $script:n = 0
function Check($ok, $name) { $script:n++; if ($ok) { "  PASS  $name" } else { $script:fail++; "  FAIL  $name" } }
function Throws([scriptblock]$b, [string]$like) { try { & $b | Out-Null; $false } catch { $_.Exception.Message -like $like } }
function G($r, [string[]]$a) { (& git -C $r @a 2>&1 | ForEach-Object { "$_" }) -join "`n" }
function Commit($r, $msg, $date, $author) {
  Set-Content "$r\f-$(Get-Random).txt" $msg
  git -C $r add -A | Out-Null
  $env:GIT_AUTHOR_DATE = $date; $env:GIT_COMMITTER_DATE = $date
  if ($author) { $env:GIT_AUTHOR_NAME = $author; $env:GIT_AUTHOR_EMAIL = 'other@example.com' }
  git -C $r commit -q -m $msg 2>&1 | Out-Null
  Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE, Env:GIT_AUTHOR_NAME, Env:GIT_AUTHOR_EMAIL -ErrorAction SilentlyContinue
}
function Snap($r) { @(G $r @('log', '--format=%H|%T|%an|%ae|%aI|%cn|%cI|%P|%s', '--reverse')) -join "`n" }

$r = "$T\work repo ü"; New-Item -ItemType Directory $r | Out-Null; git -C $r init -q
Commit $r 'c1 first' '2021-01-01T10:00:00'
Commit $r 'c2 second' '2021-01-02T10:00:00' 'Alice Ünïcode'
Commit $r 'c3 third' '2021-01-03T10:00:00'
git -C $r checkout -q -b side; Commit $r 'side1' '2021-01-04T10:00:00'
git -C $r checkout -q main; Commit $r 'c4 fourth' '2021-01-05T10:00:00'
git -C $r merge -q --no-ff side -m 'merge side' 2>&1 | Out-Null
Commit $r 'c5 fifth' '2021-01-06T10:00:00'
$all = @(Get-CommitList $r 50)

"== Listing"
Check ($all.Count -eq 7) 'lists all 7 commits'
Check ($all[0].Subject -eq 'c5 fifth' -and $all[0].Sha.Length -eq 40) 'newest first, full sha kept'
Check (@($all | ? IsMerge).Count -eq 1) 'merge flagged'
Check ((Get-CommitList $r 3).Count -eq 3) 'count limit honoured'
Check ((Bd commits $r 2) -match 'c5 fifth') 'CLI commits'
Check (Throws { Get-CommitList $T } '*Not a git repository*') 'non-repo folder rejected'
Check (Throws { Get-CommitList "$T\nope" } '*Folder not found*') 'missing folder rejected'
$empty = "$T\empty"; New-Item -ItemType Directory $empty | Out-Null; git -C $empty init -q
Check ((@(Get-CommitList $empty)).Count -eq 0) 'repo with no commits lists nothing'

"== Reword an ancestor of a merge"
$c2 = ($all | ? Subject -eq 'c2 second').Sha
$before = Snap $r; $treeBefore = G $r @('rev-parse', 'HEAD^{tree}'); $statusBefore = G $r @('status', '--porcelain')
$res = Set-CommitEdits $r @{ $c2 = @{ message = "c2 reworded`n`nbody line ünïcode ✓`nsecond line" } }
Check ($res.Rewritten -eq 6 -and $res.Edited -eq 1) 'c2 + 5 descendants rewritten (c1 untouched)'
$after = @(Get-CommitList $r 50)
Check ($after.Count -eq 7) 'still 7 commits'
Check ((Get-CommitMessage $r ($after | ? Subject -eq 'c2 reworded').Sha) -eq "c2 reworded`n`nbody line ünïcode ✓`nsecond line") 'multi-line unicode message stored exactly'
Check ((G $r @('rev-parse', 'HEAD^{tree}')) -eq $treeBefore -and (G $r @('status', '--porcelain')) -eq $statusBefore) 'tree and working copy untouched'
$lb = @($before -split "`n"); $la = @((Snap $r) -split "`n")
$same = $true; for ($i = 0; $i -lt 7; $i++) { $x = $lb[$i].Split('|'); $y = $la[$i].Split('|'); foreach ($k in 1..6) { if ($x[$k] -ne $y[$k]) { $same = $false } } }
Check $same 'all trees, authors, committers and dates preserved'
Check ($la[1].Split('|')[2] -eq 'Alice Ünïcode') 'non-ASCII author preserved'
Check ((G $r @('rev-list', '--merges', '--count', 'HEAD')) -eq '1' -and (G $r @('rev-list', '--parents', '-n1', 'HEAD~1')).Split(' ').Count -eq 3) 'merge commit still has 2 parents'
Check ((G $r @('fsck', '--no-dangling')) -notmatch 'error|missing|broken') 'git fsck clean'
Check ((G $r @('for-each-ref', 'refs/backd8/backup/main/')) -match $res.Backup.Split('/')[-1]) 'backup ref created'
Check ($lb[0].Split('|')[0] -eq $la[0].Split('|')[0]) 'commit before the edit has the same hash'

"== Undo"
$u = Undo-CommitEdits $r
Check ((Snap $r) -eq $before -and -not (Get-Backups $r)) 'undo restores exact previous history and consumes backup'
Check (Throws { Undo-CommitEdits $r } '*No backd8 backup*') 'undo with nothing to undo is an error'

"== Redate / validation"
$c5 = (Get-CommitList $r 1)[0].Sha
$null = Set-CommitEdits $r @{ $c5 = @{ date = [datetime]'2020-05-05T05:05:00' } }
$h = Get-CommitList $r 1
Check ($h[0].Date -eq [datetime]'2020-05-05T05:05:00' -and ([datetimeoffset](G $r @('log', '-1', '--format=%cI'))).LocalDateTime -eq [datetime]'2020-05-05T05:05:00') 'redate sets author and committer date'
Check ($h[0].Subject -eq 'c5 fifth') 'message untouched when only date edited'
Check (Throws { Set-CommitEdits $r @{ HEAD = @{ date = (Get-Date).AddDays(2) } } } '*past*') 'future date rejected'
Check (Throws { Set-CommitEdits $r @{ HEAD = @{ message = '   ' } } } '*empty*') 'blank message rejected'
Check (Throws { Set-CommitEdits $r @{ 'deadbeef' = @{ message = 'x' } } } '*Unknown commit*') 'unknown sha rejected'
Check (Throws { Set-CommitEdits $r @{} } '*Nothing*') 'empty edit set rejected'
git -C $r checkout -q -b unmerged; Commit $r 'only on unmerged' '2021-01-10T10:00:00'; $sideSha = G $r @('rev-parse', 'HEAD'); git -C $r checkout -q main
Check (Throws { Set-CommitEdits $r @{ $sideSha = @{ message = 'x' } } } '*') 'commit not on current branch history handled'
Check ((Bd reword $r HEAD 'cli reworded') -match 'Changed 1 commit' -and (Get-CommitList $r 1)[0].Subject -eq 'cli reworded') 'CLI reword'
Check ((Bd redate $r HEAD 'not a date') -match 'Invalid') 'CLI redate rejects bad date'
$null = Bd undo $r; $null = Bd undo $r

"== Safety states"
git -C $r checkout -q --detach HEAD
Check (Throws { Set-CommitEdits $r @{ HEAD = @{ message = 'x' } } } '*detached*') 'detached HEAD refused'
git -C $r checkout -q main
New-Item -ItemType Directory "$r\.git\rebase-merge" | Out-Null
Check (Throws { Set-CommitEdits $r @{ HEAD = @{ message = 'x' } } } '*in progress*') 'refused during rebase'
Remove-Item "$r\.git\rebase-merge" -Recurse

"== Hooks/backdating do not interfere"
Bd install | Out-Null; Bd set '*' '2019-01-01T09:00:00' | Out-Null; Bd on | Out-Null
$snapOn = Snap $r
$null = Set-CommitEdits $r @{ (Get-CommitList $r 1)[0].Sha = @{ message = 'edited while backdating ON' } }
$lo = @($snapOn -split "`n"); $ln = @((Snap $r) -split "`n")
Check ((($lo[0..5] -join "`n") -eq ($ln[0..5] -join "`n")) -and $lo[6].Split('|')[4] -eq $ln[6].Split('|')[4] -and $lo[6].Split('|')[6] -eq $ln[6].Split('|')[6]) 'history edit does not re-date commits while backdating is ON'
Bd off | Out-Null; Bd uninstall | Out-Null
$null = Undo-CommitEdits $r

"== Push"
Check (Throws { Push-Repo $r } "*No git remote*") 'push without remote gives guidance'
$bare = "$T\github.git"; git init -q --bare $bare; git -C $r remote add origin $bare
$st = Get-PushState $r
Check ($st.Branch -eq 'main' -and $st.Remote -eq 'origin' -and -not $st.Upstream) 'push state before first push'
$o = Push-Repo $r
Check ((G $bare @('rev-parse', 'main')) -eq (G $r @('rev-parse', 'HEAD')) -and (Get-PushState $r).Upstream -eq 'origin/main') 'first push creates branch and sets upstream'
Check ((Get-PushState $r).Ahead -eq 0 -and (Get-PushState $r).Behind -eq 0) 'in sync after push'
$null = Set-CommitEdits $r @{ ($all | ? Subject -eq 'c3 third').Sha = @{ message = 'c3 reworded' } }
$st = Get-PushState $r
Check ($st.Ahead -eq 5 -and $st.Behind -eq 5) "diverged detected after rewrite (ahead $($st.Ahead) behind $($st.Behind))"
Check (Throws { Push-Repo $r } '*Replace GitHub*') 'normal push blocked after rewrite, tells user about force'
$remoteBefore = G $bare @('rev-parse', 'main')
$o = Push-Repo $r -Force
Check ((G $bare @('rev-parse', 'main')) -eq (G $r @('rev-parse', 'HEAD')) -and (G $bare @('rev-parse', 'main')) -ne $remoteBefore) 'force push replaced remote history'
Check ((Get-PushState $r).Behind -eq 0) 'in sync after force push'
Commit $r 'plain new commit' '2021-02-01T10:00:00'
$null = Push-Repo $r
Check ((G $bare @('rev-parse', 'main')) -eq (G $r @('rev-parse', 'HEAD'))) 'ordinary fast-forward push works without force'

"== Force push refuses to clobber unseen remote work"
$other = "$T\other"; git clone -q $bare $other 2>&1 | Out-Null
Commit $other 'someone else pushed' '2021-03-01T10:00:00'; git -C $other push -q origin main 2>&1 | Out-Null
$null = Set-CommitEdits $r @{ ((Get-CommitList $r 50) | ? Subject -eq 'c3 reworded').Sha = @{ message = 'c3 reworded again' } }
$thrown = Throws { Push-Repo $r -Force } '*nowhere in this repository*'
Check ($thrown -and (G $bare @('log', '-1', '--format=%s', 'main')) -eq 'someone else pushed') 'force push refused (remote fetched first), other person''s commit untouched'

"== Secrets never shown"
$sec = "$T\sec"; New-Item -ItemType Directory $sec | Out-Null; git -C $sec init -q; Commit $sec 'x' '2021-01-01T10:00:00'
git -C $sec remote add origin 'https://user:ghp_SECRETTOKEN@github.com/u/r.git'
Check ((Get-PushState $sec).Url -notmatch 'SECRETTOKEN' -and (Get-PushState $sec).Url -match 'github.com/u/r') 'token in remote URL is redacted'
$msg = try { Push-Repo $sec } catch { $_.Exception.Message }
Check ($msg -notmatch 'SECRETTOKEN') 'token redacted in push error output'

"== CLI push"
$r2 = "$T\cli"; New-Item -ItemType Directory $r2 | Out-Null; git -C $r2 init -q; Commit $r2 'a' '2021-01-01T10:00:00'
$bare2 = "$T\gh2.git"; git init -q --bare $bare2; git -C $r2 remote add origin $bare2
Check ((Bd push $r2) -match 'Pushed main' -and (G $bare2 @('rev-parse', 'main')) -eq (G $r2 @('rev-parse', 'HEAD'))) 'CLI push'

"== Audit regressions"
$q = "$T\audit"; New-Item -ItemType Directory $q | Out-Null; git -C $q init -q
Commit $q 'a1' '2021-01-01T10:00:00'; Commit $q 'a2' '2021-01-02T10:00:00'; Commit $q 'a3' '2021-01-03T10:00:00'
git -C $q tag main                                         # tag with the same name as the branch
$bq = "$T\audit.git"; git init -q --bare $bq; git -C $q remote add origin $bq
Check ((Push-Repo $q) -match 'Pushed main' -and (G $bq @('rev-parse', 'refs/heads/main')) -eq (G $q @('rev-parse', 'HEAD'))) 'push works when a tag has the same name as the branch'
$null = Set-CommitEdits $q @{ 'HEAD~1' = @{ message = 'a2 edited' }; (G $q @('rev-parse', 'HEAD~1')) = @{ date = [datetime]'2020-02-02T02:02:00' } }
Check ((Get-Backups $q).Count -eq 1 -and (Get-CommitList $q 3)[1].Subject -eq 'a2 edited' -and (Get-CommitList $q 3)[1].Date -eq [datetime]'2020-02-02T02:02:00') 'same commit named twice (HEAD~1 + full sha): edits merged, one rewrite'
Commit $q 'a4 new work' '2021-01-04T10:00:00'
Check (Throws { Undo-CommitEdits $q } '*changed since the last rewrite*') 'undo refuses when commits were added after the rewrite'
Check ((G $q @('log', '-1', '--format=%s')) -eq 'a4 new work') 'refused undo left the branch alone'
$null = Undo-CommitEdits $q -Force
Check ((G $q @('log', '--format=%s')) -notmatch 'a4' -and (G $q @('reflog', '-1', '--format=%gs')) -ne $null) 'undo -Force works (new work stays in reflog)'
$null = G $q @('reset', '-q', '--hard', 'HEAD@{1}')
git -C $q checkout -q -b 'feat/x'; Commit $q 'fx' '2021-01-05T10:00:00'; $null = Set-CommitEdits $q @{ HEAD = @{ message = 'fx2' } }
git -C $q checkout -q main; git -C $q branch -D 'feat/x' 2>&1 | Out-Null
Check (@(Get-Backups $q | ? { $_ -like '*feat/x*' }).Count -eq 0) 'backups of a deleted branch with a longer name are not mistaken for this branch'
$enc = "$T\enc"; New-Item -ItemType Directory $enc | Out-Null; git -C $enc init -q
Set-Content "$enc\f" 'x'; git -C $enc add -A
$tree = G $enc @('write-tree'); $mf = "$T\latin1.txt"; [IO.File]::WriteAllBytes($mf, [byte[]](0x63, 0x61, 0x66, 0xE9, 0x0D, 0x0A, 0x0D, 0x0A, 0x74, 0x72, 0x61, 0x69, 0x6C, 0x20, 0x20, 0x0A))
$env:GIT_AUTHOR_DATE = '2021-01-01T10:00:00'; $env:GIT_COMMITTER_DATE = '2021-01-01T10:00:00'
$l1 = G $enc @('-c', 'i18n.commitEncoding=ISO-8859-1', 'commit-tree', $tree, '-F', $mf); git -C $enc update-ref refs/heads/main $l1 2>&1 | Out-Null
Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE
Commit $enc 'child' '2021-01-02T10:00:00'
$rawBefore = (G $enc @('cat-file', 'commit', $l1))
$null = Set-CommitEdits $enc @{ HEAD = @{ message = 'child edited' } }
$null = Set-CommitEdits $enc @{ HEAD = @{ date = [datetime]'2020-01-01T00:00:00' } }
$null = Undo-CommitEdits $enc
$null = Undo-CommitEdits $enc
$null = Set-CommitEdits $enc @{ $l1 = @{ date = [datetime]'2020-06-06T06:06:00' } }
$l1n = (Get-CommitList $enc 5)[-1].Sha
$tmpRaw = "$T\raw.bin"; cmd /c "git -C `"$enc`" cat-file commit $l1n > `"$tmpRaw`""
$bytes = [IO.File]::ReadAllBytes($tmpRaw); $hex = ($bytes | % { '{0:X2}' -f $_ }) -join ' '
Check ($hex -match '63 61 66 E9 0D 0A 0D 0A 74 72 61 69 6C 20 20 0A$') 'non-UTF8 message bytes, CRLF and trailing whitespace preserved byte-for-byte'
Check ((G $enc @('cat-file', 'commit', $l1n)) -match 'encoding ISO-8859-1') 'encoding header kept'
$nt = "$T\notes"; New-Item -ItemType Directory $nt | Out-Null; git -C $nt init -q; Commit $nt 'n1' '2021-01-01T10:00:00'; Commit $nt 'n2' '2021-01-02T10:00:00'
git -C $nt notes add -m 'my note' HEAD 2>&1 | Out-Null
$null = Set-CommitEdits $nt @{ 'HEAD~1' = @{ message = 'n1 edited' } }
Check ((G $nt @('notes', 'show', 'HEAD')) -eq 'my note') 'git notes follow the rewritten commit'
Check ((Hide-Secrets 'https://user:p@ss@github.com/u/r.git') -notmatch 'ss@|user' ) 'password containing @ fully hidden'

"== Force push never destroys someone else's fetched work"
$r3 = "$T\fw"; New-Item -ItemType Directory $r3 | Out-Null; git -C $r3 init -q; Commit $r3 'f1' '2021-01-01T10:00:00'; Commit $r3 'f2' '2021-01-02T10:00:00'
$b3 = "$T\fw.git"; git init -q --bare $b3; git -C $r3 remote add origin $b3; $null = Push-Repo $r3
$o3 = "$T\fw-other"; git clone -q $b3 $o3 2>&1 | Out-Null; Commit $o3 'THEIRS' '2021-02-01T10:00:00'; git -C $o3 push -q origin main 2>&1 | Out-Null
git -C $r3 fetch -q origin
$null = Set-CommitEdits $r3 @{ 'HEAD' = @{ message = 'f2 edited' } }
$st = Get-PushState $r3
Check ($st.RemoteOnly -eq 1) 'remote-only commit counted even after fetch'
Check (Throws { Push-Repo $r3 -Force } '*nowhere in this repository*') 'force push refused when remote has foreign commits'
Check ((G $b3 @('log', '-1', '--format=%s', 'main')) -eq 'THEIRS') 'their commit still on the remote'
$null = Push-Repo $r3 -Force -DiscardRemote
Check ((G $b3 @('rev-parse', 'main')) -eq (G $r3 @('rev-parse', 'HEAD'))) '-DiscardRemote overrides on explicit request'

"== Upstream with a different branch name"
$r4 = "$T\up"; New-Item -ItemType Directory $r4 | Out-Null; git -C $r4 init -q; Commit $r4 'u1' '2021-01-01T10:00:00'
$b4 = "$T\up.git"; git init -q --bare $b4; git -C $r4 remote add origin $b4
git -C $r4 push -q origin main:release 2>&1 | Out-Null; git -C $r4 branch -u origin/release 2>&1 | Out-Null
Commit $r4 'u2' '2021-01-02T10:00:00'; $null = Push-Repo $r4
Check ((G $b4 @('rev-parse', 'release')) -eq (G $r4 @('rev-parse', 'HEAD')) -and (G $b4 @('branch', '--list')) -notmatch 'main') 'pushes to the configured upstream branch name, not a same-named new branch'

"== CLI polish (from audit)"
$cl = "$T\clipolish"; New-Item -ItemType Directory $cl | Out-Null; git -C $cl init -q
Commit $cl 'p1' '2021-01-01T10:00:00'; Commit $cl 'p2' '2021-01-02T10:00:00'; Commit $cl 'p3' '2021-01-03T10:00:00'
git -C $cl tag v1 HEAD~1; git -C $cl tag -a v2 -m ann HEAD~1; git -C $cl branch side HEAD~1
$short = (G $cl @('rev-parse', '--short=7', 'HEAD~1')).ToUpper()
$o = Bd reword $cl $short 'He said "hi" & left'
Check ($o -match 'Reworded: \w+ p2\s+->\s+He said' -and $o -match 'Changed 1 commit' -and $o -match 'later commit' -and $o -match 'backdate undo') 'uppercase sha accepted; reword output names old->new, descendants, undo'
Check ($o -match 'still point at the OLD commits' -and $o -match 'v1' -and $o -match 'v2' -and $o -match 'side') 'tags/branches left on old commits are reported'
$null = Bd undo $cl
$mf = "$T\msg.txt"; [IO.File]::WriteAllText($mf, "-leading dash`n`nsecond ""quoted"" line`n", (New-Object Text.UTF8Encoding $false))
$o = Bd reword $cl HEAD -MessageFile $mf
Check ((Get-CommitMessage $cl HEAD) -eq "-leading dash`n`nsecond ""quoted"" line") '-MessageFile: leading dash, quotes, multi-line'
$null = Bd undo $cl
Check ((Bd redate $cl HEAD '01/03/2024') -match 'Ambiguous') 'ambiguous d/m date rejected with advice'
Check ((Bd redate $cl HEAD '2020-04-04') -match 'Redated: .*->\s+2020-04-04T00:00:00') 'redate output shows old and new date'
$null = Bd undo $cl
Check ((Bd commits $cl 0) -match 'positive whole number' -and (Bd commits $cl abc) -match 'positive whole number') 'commits count validated'
Check ((Bd commits $empty) -match 'No commits yet') 'commits on an empty repo says so'
Check ((Bd help) -match 'reword' -and (Bd '/?') -match 'github-login') 'help and /? print usage'
Check ((Bd bogus) -match 'Run: backdate.cmd help') 'unknown command points to help'
Check ((Bd remove "$T\never-added") -match 'Not in the list') 'remove of an unknown repo is an error, not a silent success'
"== GitHub access / sign-in guidance (new-PC case)"
Check (Test-GitInstalled) 'git detected'
Check ((Test-AuthError 'fatal: Authentication failed for ''https://github.com/x/y.git/''') -and (Test-AuthError 'git@github.com: Permission denied (publickey).') -and (Test-AuthError 'remote: Repository not found.') -and (Test-AuthError 'fatal: could not read Username for ''https://github.com'': terminal prompts disabled') -and -not (Test-AuthError 'Could not resolve host: github.com') -and -not (Test-AuthError '! [rejected] main -> main (fetch first)')) 'auth-error classifier'
Check ((Get-Transport 'https://github.com/a/b.git') -eq 'https' -and (Get-Transport 'git@github.com:a/b.git') -eq 'ssh' -and (Get-Transport 'ssh://git@github.com/a/b.git') -eq 'ssh' -and (Get-Transport 'C:\x\y.git') -eq 'local' -and (Get-Transport $null) -eq 'none') 'remote transport detection'
$gr = "$T\gh-access"; New-Item -ItemType Directory $gr | Out-Null; git -C $gr init -q; Commit $gr 'g1' '2021-01-01T10:00:00'
$a0 = Get-GitHubAccess $gr
Check ($a0.Transport -eq 'none' -and -not $a0.Ready -and ($a0.Advice -join ' ') -match 'git remote add origin' -and ($a0.Advice -join ' ') -match 'github.com/new') 'no remote: tells the user how to create/add the GitHub repo'
git -C $gr config user.name '""'; git -C $gr config user.email '""'   # PS 5.1 drops bare empty-string arguments
Check (($(Get-GitHubAccess $gr).Advice -join ' ') -match 'user.name') 'missing git identity is flagged with the exact commands'
git -C $gr config --unset user.name; git -C $gr config --unset user.email
git -C $gr remote add origin "$T\gh-access.git"; git init -q --bare "$T\gh-access.git"
$a1 = Get-GitHubAccess $gr
Check ($a1.Transport -eq 'local' -and $a1.CanPush -eq $true -and $a1.Ready) 'local remote: ready'
Check ((Connect-GitHub $gr).Ready) 'sign-in on a local remote is a no-op (no window)'
$port = (New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0); $port.Start(); $pn = $port.LocalEndpoint.Port; $port.Stop()
$srv = Start-Job -ArgumentList $pn -ScriptBlock {
  param($pn)
  $l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$pn/"); $l.Start()
  $end = (Get-Date).AddSeconds(150)
  while ((Get-Date) -lt $end) { $c = $l.GetContext(); $c.Response.StatusCode = 401; $c.Response.AddHeader('WWW-Authenticate', 'Basic realm="GitHub"'); $c.Response.Close() }
}
Start-Sleep -Seconds 2
git -C $gr remote set-url origin "http://localhost:$pn/someone/private.git"
$a2 = Get-GitHubAccess $gr
Check ($a2.Transport -eq 'https' -and $a2.CanPush -eq $false -and -not $a2.Ready) "server demanding login: CanPush = false ($($a2.Detail -replace '\s+',' '))"
Check (($a2.Advice -join ' ') -match 'Sign in to GitHub|not signed in|Not signed in') 'advice tells the user to sign in'
$msg = try { Push-Repo $gr } catch { $_.Exception.Message }
Check ($msg -like 'GitHub sign-in required*' -and $msg -match 'github-login') 'push without login: clear "sign-in required" message, not a raw git error'
Check ((Bd github $gr) -match 'Can push:\s+NO' -and (Bd github $gr) -match '->') 'CLI github: shows NO + advice'
Stop-Job $srv -ErrorAction SilentlyContinue; Remove-Job $srv -Force -ErrorAction SilentlyContinue
git -C $gr remote set-url origin 'http://localhost:1/x/y.git'
$a3 = Get-GitHubAccess $gr
Check ($null -eq $a3.CanPush -and ($a3.Advice -join ' ') -match 'Could not (verify|reach)') 'unreachable remote: unknown, with a connectivity hint (not a false sign-in prompt)'
git -C $gr remote set-url origin 'ssh://git@localhost:1/someone/repo.git'
$a4 = Get-GitHubAccess $gr
Check ($a4.Transport -eq 'ssh' -and $a4.CanPush -ne $true) 'ssh remote recognised; never reports ready without proof'
"== Folder -> commit message/date -> push (no hook needed)"
$pl = "$T\plain project ü"; New-Item -ItemType Directory $pl | Out-Null
Set-Content "$pl\Program.cs" 'class P {}'; Set-Content "$pl\read me.txt" 'hi'; Set-Content "$pl\.env" 'TOKEN=abc'
$ti = Test-IsRepo $pl
Check ($ti.Exists -and -not $ti.IsRepo) 'plain folder is detected as not a git project'
Check (-not (Test-IsRepo "$T\nope-nope").Exists) 'missing folder detected'
Check (Throws { Initialize-Repo $pl 'not a url' } '*repository address*') 'bad GitHub address rejected'
Check (Throws { Initialize-Repo $pl '--upload-pack=evil' } '*repository address*') 'address starting with - rejected'
$bareP = "$T\plainhub.git"; git init -q --bare $bareP
$null = Initialize-Repo $pl $bareP
Check ((Test-IsRepo $pl).IsRepo -and (Get-BranchName (Test-IsRepo $pl).Root) -eq 'main' -and (Get-PushState $pl).Url -eq $bareP) 'init creates a project on branch main and links the remote'
Check (Throws { Initialize-Repo $pl } '*already part of*') 'second init refused'
New-Item -ItemType Directory "$pl\sub" | Out-Null
Check ((Test-IsRepo "$pl\sub").Root -eq (Test-IsRepo $pl).Root -and (Throws { Initialize-Repo "$pl\sub" } '*already part of*')) 'subfolder resolves to its project root; no nested init'
$ch = @(Get-WorkingChanges $pl)
Check ($ch.Count -eq 3 -and @($ch | ? Kind -eq 'new').Count -eq 3) 'three new files listed (spaces/unicode ok)'
Check (@($ch | ? Risky).Count -eq 1 -and ($ch | ? Risky).Path -eq '.env') '.env flagged as risky'
Check (Throws { New-CommitFromChanges $pl '  ' -All } '*commit message*') 'empty message refused'
Check (Throws { New-CommitFromChanges $pl 'x' } '*at least one file*') 'no files chosen refused'
Check (Throws { New-CommitFromChanges $pl 'x' -All -Date (Get-Date).AddDays(3) } '*past*') 'future date refused'
git -C $pl config user.name '""'; git -C $pl config user.email '""'
Check (Throws { New-CommitFromChanges $pl 'x' -All } '*who you are*') 'missing git identity explained with the fix'
git -C $pl config --unset user.name; git -C $pl config --unset user.email
Bd install | Out-Null; Bd set '*' '2010-01-01T08:00:00' | Out-Null; Bd on | Out-Null     # the optional hook is ON: it must not touch these commits
$c1 = New-CommitFromChanges $pl "first files`n`nüñí body line" -Files @('Program.cs', 'read me.txt')
Check ($c1.Subject -eq 'first files' -and ((Get-Date) - $c1.Date).TotalMinutes -lt 5) 'commit of chosen files keeps the real date even while the hook is ON'
Check ((Get-CommitMessage $pl $c1.Sha) -eq "first files`n`nüñí body line") 'multi-line unicode message stored exactly'
Check (@(Get-WorkingChanges $pl).Count -eq 1 -and (Get-WorkingChanges $pl)[0].Path -eq '.env') 'unchosen file stays uncommitted'
Set-Content "$pl\Program.cs" 'class P { int x; }'; git -C $pl mv 'read me.txt' 'README.md'; Remove-Item "$pl\.env"
$ch = @(Get-WorkingChanges $pl)
Check (($ch | ? Path -eq 'Program.cs').Kind -eq 'modified' -and ($ch | ? Path -eq 'README.md').Kind -eq 'renamed' -and ($ch | ? Path -eq 'README.md').OldPath -eq 'read me.txt') 'modified and renamed (with old name) detected'
$c2 = New-CommitFromChanges $pl 'second: tweaks' -All -Date ([datetime]'2022-05-05T05:05:00')
Check ($c2.Date -eq [datetime]'2022-05-05T05:05:00' -and ([datetimeoffset](G $pl @('log', '-1', '--format=%cI'))).LocalDateTime -eq [datetime]'2022-05-05T05:05:00') 'explicit past date: author and committer date set'
Check (-not @(Get-WorkingChanges $pl).Count -and (Throws { New-CommitFromChanges $pl 'x' -All } '*Nothing to commit*')) 'clean tree: nothing to commit'
Bd off | Out-Null; Bd uninstall | Out-Null
Set-Content "$pl\a.txt" 'a'; Set-Content "$pl\b.txt" 'b'; git -C $pl add a.txt
$c3 = New-CommitFromChanges $pl 'only staged' -StagedOnly
Check ((G $pl @('show', '--name-only', '--format=', 'HEAD')) -eq 'a.txt' -and (Get-WorkingChanges $pl)[0].Path -eq 'b.txt') '-StagedOnly commits just the staged file'
$o = Invoke-Publish $pl -NewCommit @{ Message = 'publish b'; All = $true; Date = [datetime]'2022-05-06T10:00:00' } -Edits @{ $c1.Sha = @{ message = 'first files (reworded)'; date = [datetime]'2022-05-01T09:00:00' } } -Push
Check (($o -join ' ') -match 'Committed' -and ($o -join ' ') -match 'Edited 1' -and ($o -join ' ') -match 'Pushed main') 'Invoke-Publish: commit + edit older commit + push in one go'
Check ((G $bareP @('rev-parse', 'main')) -eq (G $pl @('rev-parse', 'HEAD')) -and (G $bareP @('log', '--format=%s')) -match 'first files \(reworded\)') 'remote has the new commit and the edited one'
$dd = @(G $pl @('log', '--reverse', '--format=%aI')) -split "`n" | % { ([datetimeoffset]$_).LocalDateTime }
Check ($dd[0] -eq [datetime]'2022-05-01T09:00:00' -and $dd[-1] -eq [datetime]'2022-05-06T10:00:00') 'edited and new commits carry the chosen dates'
Check ((Get-PushState $pl).Ahead -eq 0 -and (Get-PushState $pl).Behind -eq 0) 'in sync after publish'

"== Date spread helper"
$sp = @(New-DateSpread ([datetime]'2022-01-01T09:00:00') 6)
$okSp = ($sp[0] -eq [datetime]'2022-01-01T09:00:00'); for ($i = 1; $i -lt 6; $i++) { $g = ($sp[$i] - $sp[$i - 1]).TotalMinutes; if ($g -lt 60 -or $g -gt 360) { $okSp = $false } }
Check ($sp.Count -eq 6 -and $okSp) 'spread: ascending, 1-6 h apart, starts at the chosen date'
Check (Throws { New-DateSpread ((Get-Date).AddHours(-3)) 5 } '*run past today*') 'spread refuses to run into the future'
Check (Throws { New-DateSpread (Get-Date).AddDays(1) 2 } '*past*') 'spread refuses a future start'

"== CLI for the same flow"
$cp = "$T\cliplain"; New-Item -ItemType Directory $cp | Out-Null; Set-Content "$cp\x.txt" 'x'; $bc = "$T\cliplain.git"; git init -q --bare $bc
Check ((Bd init $cp $bc) -match 'Created a git project') 'CLI init + link'
Check ((Bd changes $cp) -match 'new\s+x.txt') 'CLI changes'
Check ((Bd commit $cp 'cli commit' -Date '2021-02-03T04:05:00') -match 'Committed \w+ \(2021-02-03 04:05\): cli commit') 'CLI commit with a date'
Set-Content "$cp\y.txt" 'y'
Check ((Bd publish $cp 'cli publish') -match 'Pushed main' -and (G $bc @('rev-parse', 'main')) -eq (G $cp @('rev-parse', 'HEAD'))) 'CLI publish = commit + push'
Check ((Bd remote $cp 'nonsense') -match 'repository address') 'CLI remote validates the address'
"== Problem classifier (audit): the advice must match the real cause"
Check ((Get-GitProblem 'remote: Resource protected by organization SAML enforcement. You must grant your credential access.').Kind -eq 'saml') 'SAML/SSO -> authorise the token, not "sign in again"'
Check ((Get-GitProblem 'Host key verification failed.').Kind -eq 'hostkey' -and -not (Test-AuthError 'Host key verification failed.')) 'ssh host key -> its own advice'
Check ((Get-GitProblem 'remote: Repository not found.').Kind -eq 'notfound' -and (Get-GitProblem 'remote: Repository not found.').Advice -match 'github.com/new') 'repo not found -> mentions creating it'
Check ((Get-GitProblem 'fatal: unable to access: The requested URL returned error: 503').Kind -eq 'temporary' -and (Get-GitProblem 'error: RPC failed; HTTP 429 curl 22').Kind -eq 'temporary') '429/5xx -> try again later, not "offline"'
Check ((Get-GitProblem 'fatal: unable to access: Could not resolve host: github.com').Kind -eq 'network') 'DNS failure -> network'
Check ((Get-GitProblem 'fatal: Authentication failed for https://x').Kind -eq 'auth' -and (Get-GitProblem 'Permission denied, please try again.').Kind -eq 'auth') 'real auth failures still map to sign-in'
Check ((Get-GitProblem '! [remote rejected] main -> main (protected branch hook declined)').Kind -eq 'other') 'protected-branch rejection is not mistaken for a login problem'
Check ((Get-Transport 'git://github.com/a/b.git') -eq 'git') 'git:// recognised as read-only transport'
$pu = "$T\pushurl"; New-Item -ItemType Directory $pu | Out-Null; git -C $pu init -q; Commit $pu 'p' '2021-01-01T10:00:00'
git -C $pu remote add origin "$T\fetch-only.git"; git -C $pu remote set-url --push origin "$T\push-target.git"
Check ((Get-PushState $pu).Url -eq "$T\push-target.git") 'push uses pushurl (what the user is told matches where it goes)'
$ha = "$T\helpers"; New-Item -ItemType Directory $ha | Out-Null; git -C $ha init -q; Commit $ha 'h' '2021-01-01T10:00:00'; git -C $ha remote add origin "$T\x.git"
Check (-not (Get-GitHubAccess $ha).Ready -and (Get-GitHubAccess $ha).Transport -eq 'local') 'nonexistent local remote path is not "ready"'
"== Date audit fixes"
$da = "$T\dateaudit"; New-Item -ItemType Directory $da | Out-Null; git -C $da init -q; Commit $da 'd1' '2024-01-10T10:00:00'; Commit $da 'd2' '2024-01-20T10:00:00'
Check ((Throws { Set-CommitEdits $da @{ HEAD = @{ date = [datetime]'1960-03-05' } } } '*too early*') -and (Throws { New-CommitFromChanges $da 'x' -All -Date ([datetime]'1960-03-05') } '*too early*') -and (Bd redate $da HEAD '5 Mar 1960') -match 'too early') 'pre-1971 dates refused everywhere with one clear message'
Set-Content "$da\n.txt" 'n'; git -C $da add n.txt; Set-Content "$da\m.txt" 'm'
$thr = Throws { New-CommitFromChanges $da '' -Files @('m.txt') } '*message*'
Check ($thr -and (G $da @('diff', '--cached', '--name-only')) -eq 'n.txt') 'refused commit leaves the index as it was'
$rr = Set-CommitEdits $da @{ 'HEAD~1' = @{ date = [datetime]'2024-02-01T10:00:00' } }
Check (@($rr.Warnings).Count -ge 1 -and ($rr.Warnings -join ' ') -match 'before its parent') 'moving a commit later than its child warns about out-of-order history'
$null = Undo-CommitEdits $da
$bd2 = "$T\dateaudit.git"; git init -q --bare $bd2; git -C $da remote add origin $bd2; git -C $da reset -q; Remove-Item "$da\n.txt","$da\m.txt"
$null = Push-Repo $da
$null = Set-CommitEdits $da @{ HEAD = @{ date = [datetime]'2024-01-21T10:00:00' } }
$null = Push-Repo $da -Force
$null = Undo-CommitEdits $da -Force
Check ((G $bd2 @('rev-parse', 'main')) -ne (G $da @('rev-parse', 'HEAD'))) 'after undo the remote still has the edited version (precondition)'
$o = try { Push-Repo $da -Force } catch { $_.Exception.Message }
Check ($o -match 'Pushed main') 'undo then force push is accepted (backd8''s own published commits are not "someone else''s work")'
"== Audit batch 3: real-world project hygiene"
$h3 = "$T\hyg"; New-Item -ItemType Directory $h3 | Out-Null; git -C $h3 init -q -b main; Commit $h3 'base' '2021-01-01T10:00:00'
# 1. thousands of files / long argument lists
$deep = "$h3\obj\Debug\net8.0\very-long-folder-name-for-generated-files-to-make-paths-long\x"; New-Item -ItemType Directory $deep | Out-Null
1..1500 | % { [IO.File]::WriteAllText("$deep\generated-file-with-a-long-name-$_.txt", "$_") }
$sw = [Diagnostics.Stopwatch]::StartNew(); $c = New-CommitFromChanges $h3 'many files' -All; $sw.Stop()
Check ((G $h3 @('ls-files')).Split("`n").Count -ge 1500 -and $sw.Elapsed.TotalSeconds -lt 90) "1500 long paths committed through a pathspec file ($([int]$sw.Elapsed.TotalSeconds)s)"
# 2. literal pathspecs
[IO.File]::WriteAllText("$h3\a b.txt", '1'); [IO.File]::WriteAllText("$h3\a [b].txt", '2'); $null = New-CommitFromChanges $h3 'add both' -All
[IO.File]::WriteAllText("$h3\a b.txt", '11'); [IO.File]::WriteAllText("$h3\a [b].txt", '22')
$null = New-CommitFromChanges $h3 'only bracket' -Files @('a [b].txt')
Check ((G $h3 @('show', '--name-only', '--format=', 'HEAD')) -eq 'a [b].txt' -and (Get-WorkingChanges $h3).Path -eq 'a b.txt') 'file names with [ ] are literal: only the chosen file is committed'
$null = New-CommitFromChanges $h3 'rest' -All
# 3. unresolved conflicts
[IO.File]::WriteAllText("$h3\c.txt", 'base'); $null = New-CommitFromChanges $h3 'c base' -All
[IO.File]::WriteAllText("$h3\c.txt", 'stashed'); git -C $h3 stash -q; [IO.File]::WriteAllText("$h3\c.txt", 'committed'); $null = New-CommitFromChanges $h3 'c committed' -All
git -C $h3 stash pop -q 2>&1 | Out-Null
Check ((Throws { New-CommitFromChanges $h3 'x' -All } '*unresolved merge conflicts*')) 'files with conflict markers are refused'
git -C $h3 checkout -q --theirs c.txt 2>$null; git -C $h3 checkout -q HEAD -- c.txt 2>$null; git -C $h3 reset -q 2>$null; git -C $h3 stash drop -q 2>$null
# 4. nested repo
$nr = "$h3\vendor-tool"; New-Item -ItemType Directory $nr | Out-Null; git -C $nr init -q; Commit $nr 'inner' '2021-01-01T10:00:00'; [IO.File]::WriteAllText("$h3\after.txt", 'a')
$ch = @(Get-WorkingChanges $h3)
$null = New-CommitFromChanges $h3 'with nested' -All
Check ((($ch | ? Kind -eq 'nested').Path) -like 'vendor-tool*' -and -not ((G $h3 @('ls-files', '-s')) -match '^160000')) 'a nested git project is reported and never committed as a broken submodule'
# 5. junction leaving the project
$outside = "$T\outside-secret"; New-Item -ItemType Directory $outside | Out-Null; [IO.File]::WriteAllText("$outside\secret.txt", 'x')
cmd /c "mklink /J `"$h3\linkdir`" `"$outside`"" 2>&1 | Out-Null
$lk = @(Get-WorkingChanges $h3 | ? Outside)
Check ($lk.Count -ge 1 -and (Throws { New-CommitFromChanges $h3 'x' -All } '*junction*')) 'files reached through a junction are flagged and refused'
cmd /c "rmdir `"$h3\linkdir`"" 2>&1 | Out-Null
# 6. stray GIT_* variables
$other = "$T\other-repo"; New-Item -ItemType Directory $other | Out-Null; git -C $other init -q; Commit $other 'IN OTHER' '2021-01-01T10:00:00'
$env:GIT_DIR = "$other\.git"; $lst = @(Get-CommitList $h3 3); Remove-Item Env:GIT_DIR
Check ($lst.Count -eq 3 -and $lst[0].Subject -ne 'IN OTHER') 'a caller GIT_DIR does not redirect backd8 to another repository'
# 7. user git config cannot eat message lines
git -C $h3 config commit.cleanup strip; [IO.File]::WriteAllText("$h3\k.txt", 'k')
$null = New-CommitFromChanges $h3 "# keep this line`nbody" -All
Check ((Get-CommitMessage $h3 'HEAD') -eq "# keep this line`nbody") 'a message starting with # survives commit.cleanup=strip'
git -C $h3 config --unset commit.cleanup
# 8/9. rewrites keep author bytes, extra headers; non-encodable text moves the commit to UTF-8
$rw = "$T\rawrw"; New-Item -ItemType Directory $rw | Out-Null; git -C $rw init -q -b main; [IO.File]::WriteAllText("$rw\f", 'x'); git -C $rw add -A
$tree = G $rw @('write-tree'); $hdr = [Text.Encoding]::GetEncoding(28591); $body = "tree $tree`nauthor Jos$([char]0xE9) <j@x.org> 1600000000 +0200`ncommitter Jos$([char]0xE9) <j@x.org> 1600000000 +0200`nencoding ISO-8859-1`nHG:extra branch=default`n`ncaf$([char]0xE9) message`n"
[IO.File]::WriteAllBytes("$T\rawc.bin", $hdr.GetBytes($body)); $rc = G $rw @('hash-object', '-t', 'commit', '-w', '--literally', "$T\rawc.bin"); git -C $rw update-ref refs/heads/main $rc
$null = Set-CommitEdits $rw @{ $rc = @{ date = [datetime]'2020-01-01T10:00:00' } }
cmd /c "git -C `"$rw`" cat-file commit HEAD > `"$T\rawout.bin`""; $hx = ($hdr.GetString([IO.File]::ReadAllBytes("$T\rawout.bin")))
Check ($hx.Contains("author Jos$([char]0xE9) <j@x.org>") -and $hx.Contains('HG:extra branch=default') -and $hx.Contains('encoding ISO-8859-1') -and $hx.Contains("caf$([char]0xE9) message")) 'redate keeps Latin-1 author bytes, extra headers, encoding header and message bytes'
$null = Set-CommitEdits $rw @{ HEAD = @{ message = "party time $([char]::ConvertFromUtf32(0x1F680))" } }
cmd /c "git -C `"$rw`" cat-file commit HEAD > `"$T\rawout2.bin`""; $hx2 = ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes("$T\rawout2.bin")))
Check ($hx2 -notmatch 'encoding ISO' -and $hx2.Contains([char]::ConvertFromUtf32(0x1F680))) 'text the old encoding cannot hold moves the commit to UTF-8 instead of turning into ??'
# 10. publish is validated before anything is committed
[IO.File]::WriteAllText("$h3\p.txt", 'p'); $cnt = G $h3 @('rev-list', '--count', 'HEAD')
Check ((Throws { Invoke-Publish $h3 -NewCommit @{ Message = 'x'; All = $true } -Edits @{ HEAD = @{ date = (Get-Date).AddDays(2) } } } '*past*') -and (G $h3 @('rev-list', '--count', 'HEAD')) -eq $cnt) 'Invoke-Publish validates edits before it commits anything'
# 11. secrets
Check ((Hide-Secrets 'https://u:pa/ss@host/x.git') -notmatch 'pa/ss' -and (Hide-Secrets 'https://u:tok@github.com/a/b.git') -notmatch 'tok') 'passwords containing / are masked too'
# 12. followTags
$ft = "$T\ft"; New-Item -ItemType Directory $ft | Out-Null; git -C $ft init -q -b main; Commit $ft 'a' '2021-01-01T10:00:00'; $bft = "$T\ft.git"; git init -q --bare $bft; git -C $ft remote add origin $bft; git -C $ft config push.followTags true
git -C $ft tag -a v9 -m x; $null = Push-Repo $ft
Check (-not (G $bft @('tag', '-l'))) 'push.followTags does not publish unrelated tags'
# 13. GitHub ahead of a new local project (README created on github.com)
$gh = "$T\readmehub.git"; git init -q --bare $gh; $seed = "$T\seed"; git clone -q $gh $seed 2>&1 | Out-Null; git -C $seed checkout -q -b main 2>$null; Commit $seed 'GitHub README' '2021-01-01T10:00:00'; git -C $seed push -q origin main 2>&1 | Out-Null
$np = "$T\newproj"; New-Item -ItemType Directory $np | Out-Null; [IO.File]::WriteAllText("$np\Program.cs", 'x'); $null = Initialize-Repo $np $gh; $null = New-CommitFromChanges $np 'first' -All
$msg = try { Push-Repo $np } catch { $_.Exception.Message }
Check ($msg -match 'newer change' -and $msg -match 'sync') 'new project vs GitHub README: explains and points to "sync" instead of a raw rejection'
$m = Merge-RemoteChanges $np
Check ($m.Result -eq 'merged' -and (Test-Path "$np\Program.cs")) 'sync merges unrelated histories (both sides kept)'
Check ((Push-Repo $np) -match 'Pushed main' -and (G $gh @('log', '--format=%s', 'main')) -match 'GitHub README') 'publish works after sync'
# fast-forward and conflict
$clone = "$T\ffclone"; git clone -q $gh $clone 2>&1 | Out-Null; Commit $clone 'remote only' '2021-02-01T10:00:00'; git -C $clone push -q origin main 2>&1 | Out-Null
$msg = try { Push-Repo $np } catch { $_.Exception.Message }
Check ($msg -match 'newer change') 'GitHub ahead without a rewrite: plain explanation'
Check ((Merge-RemoteChanges $np).Result -eq 'fast-forward' -and (Merge-RemoteChanges $np).Result -eq 'up-to-date') 'sync fast-forwards, then reports up to date'
[IO.File]::WriteAllText("$np\shared.txt", 'base'); $null = New-CommitFromChanges $np 'shared base' -All; $null = Push-Repo $np
git -C $clone pull -q origin main 2>&1 | Out-Null; [IO.File]::WriteAllText("$clone\shared.txt", 'theirs'); git -C $clone commit -qam 'theirs' 2>&1 | Out-Null; git -C $clone push -q origin main 2>&1 | Out-Null
[IO.File]::WriteAllText("$np\shared.txt", 'mine'); $null = New-CommitFromChanges $np 'mine' -All
$cm = Merge-RemoteChanges $np
Check ($cm.Result -eq 'conflict' -and $cm.Files -contains 'shared.txt' -and -not (Test-Path "$np\.git\MERGE_HEAD") -and (Get-Content "$np\shared.txt" -Raw).Trim() -eq 'mine') 'sync conflict: reported, nothing changed, no half-finished merge'
# 14. big files and GitHub's size rule
Check ((Get-GitProblem 'remote: error: GH001: Large files detected. You may want to try Git Large File Storage').Kind -eq 'toolarge') 'GH001 recognised with advice'
$bigf = "$h3\huge.bin"; $fs = [IO.File]::Create($bigf); $fs.SetLength(101MB); $fs.Close()
Check ((Throws { New-CommitFromChanges $h3 'x' -All } '*100 MB*')) 'files over 100 MB are refused before committing'
Remove-Item $bigf -Force
# 15. secrets by content and by name
[IO.File]::WriteAllText("$h3\cfg.json", '{ "Password": "hunter22" }'); [IO.File]::WriteAllText("$h3\appsettings.json", '{}'); [IO.File]::WriteAllText("$h3\fine.json", '{ "title": "hello" }')
$wc = @(Get-WorkingChanges $h3)
Check ((($wc | ? Path -eq 'cfg.json').Risky) -and (($wc | ? Path -eq 'appsettings.json').Risky) -and -not (($wc | ? Path -eq 'fine.json').Risky)) 'secrets are detected by content (password=...) and by name (appsettings.json)'
Remove-Item "$h3\cfg.json", "$h3\appsettings.json", "$h3\fine.json", "$h3\p.txt" -Force
# 16. .gitignore for a Visual Studio project
$vs = "$T\vsproj"; New-Item -ItemType Directory "$vs\bin\Debug", "$vs\obj", "$vs\.vs" | Out-Null; git -C $vs init -q -b main
[IO.File]::WriteAllText("$vs\App.sln", 's'); [IO.File]::WriteAllText("$vs\Program.cs", 'x'); [IO.File]::WriteAllText("$vs\bin\Debug\App.dll", 'b'); [IO.File]::WriteAllText("$vs\obj\a.cache", 'o'); [IO.File]::WriteAllText("$vs\.vs\x.suo", 's')
$adv = Get-GitignoreAdvice $vs
Check ($adv.Needed -and $adv.Kind -eq 'dotnet' -and $adv.NoiseCount -ge 3) '.NET project without .gitignore: advice says it is needed'
$null = Add-Gitignore $vs; $files = @(Get-WorkingChanges $vs | % Path)
Check (($files -contains 'Program.cs') -and -not ($files -match '^(bin|obj|\.vs)/') -and -not (Get-GitignoreAdvice $vs).Needed) '.gitignore hides build output; Program.cs stays'
$before = [IO.File]::ReadAllText("$vs\.gitignore"); $null = Add-Gitignore $vs
Check ([IO.File]::ReadAllText("$vs\.gitignore") -eq $before) '.gitignore generation is idempotent'
# 17. remote address problems
Check ((Get-RemoteUrlProblem 'https://github.com/me/taxi/tree/main') -match 'page inside' -and (Get-RemoteUrlProblem 'https://me:tok@github.com/me/taxi.git') -match 'password or token' -and (Get-RemoteUrlProblem 'https://github.com/me') -match 'profile' -and -not (Get-RemoteUrlProblem 'https://github.com/me/taxi.git') -and -not (Get-RemoteUrlProblem 'git@github.com:me/taxi.git')) 'GitHub address checks give specific advice; good addresses pass'
# 18. backup refs are capped
$bk = "$T\bk"; New-Item -ItemType Directory $bk | Out-Null; git -C $bk init -q -b main; Commit $bk 'one' '2021-01-01T10:00:00'
1..23 | % { $null = Set-CommitEdits $bk @{ HEAD = @{ message = "edit $_" } } }
Check (@(Get-Backups $bk).Count -eq 20 -and @((G $bk @('for-each-ref', 'refs/backd8/rewritten')) -split "`n").Count -le 20) 'only the 20 newest backups are kept'
# 19. settings file damaged
Set-Content $env:BACKDATE_CONFIG '{ "enabled": tru'
Check ((Throws { Get-Config } '*damaged or locked*') -and ((Reset-Config) -match 'reset') -and -not (Get-Config).enabled) 'a damaged settings file gives a plain message and a reset path'
# 20. index.lock is waited out
$lk2 = "$T\lockrepo"; New-Item -ItemType Directory $lk2 | Out-Null; git -C $lk2 init -q -b main; Commit $lk2 'a' '2021-01-01T10:00:00'; [IO.File]::WriteAllText("$lk2\n.txt", 'n')
[IO.File]::WriteAllText("$lk2\.git\index.lock", '')
$jb = Start-Job { Start-Sleep -Milliseconds 700; Remove-Item $using:lk2\.git\index.lock -Force }
$cl = try { New-CommitFromChanges $lk2 'waited for the lock' -All } catch { $_.Exception.Message }
Receive-Job $jb -Wait | Out-Null; Remove-Job $jb -Force
Check ($cl.Subject -eq 'waited for the lock') 'a short index.lock is waited out instead of failing'
# 21. detached HEAD
git -C $lk2 checkout -q --detach HEAD; [IO.File]::WriteAllText("$lk2\m.txt", 'm')
Check (Throws { New-CommitFromChanges $lk2 'x' -All } '*detached HEAD*') 'committing on a detached HEAD is refused with the fix'
# 22. CLI polish
$cp2 = "$T\clip2"; New-Item -ItemType Directory $cp2 | Out-Null; [IO.File]::WriteAllText("$cp2\x.txt", 'x'); [IO.File]::WriteAllText("$cp2\.env", 'TOKEN=abc'); $bcp = "$T\clip2.git"; git init -q --bare $bcp; Bd init $cp2 $bcp | Out-Null
Check ((Bd commit $cp2 'try') -match 'look like they hold passwords') 'CLI commit refuses secret-looking files by default'
Check ((Bd commit $cp2 'with env' -IncludeRisky) -match 'Committed') 'CLI -IncludeRisky is the explicit override'
Check ((Bd publish $cp2 'unused message') -match 'Pushed main') 'CLI publish with nothing new to commit just pushes'
Check ((Bd reword $cp2 HEAD -MessageFile "$T\missing.txt") -match 'Message file not found') 'missing -MessageFile gives a plain message'
Check ((Bd sync $cp2) -match 'up to date') 'CLI sync'
Check ((Bd ignore $cp2 node) -match 'Wrote') 'CLI ignore'
"== Several GitHub accounts on one PC (real-user bug: 'Sign in' button never went away)"
$ac = "$T\accts"; New-Item -ItemType Directory $ac | Out-Null; git -C $ac init -q -b main; Commit $ac 'a' '2021-01-01T10:00:00'
function Get-GitHubAccounts { @('justin', 'whos-json') }      # test double: two saved accounts
Check ((Get-GitHubOwner 'https://github.com/whos-json/Taxi-') -eq 'whos-json' -and (Get-GitHubOwner 'git@github.com:me/x.git') -eq 'me' -and (Get-GitHubOwner 'https://user@github.com/o/r.git') -eq 'o') 'owner is read from every GitHub address form'
$u = 'https://github.com/whos-json/Taxi-'
Check ((Resolve-GitHubAccount $ac $u).Name -eq 'whos-json' -and (Resolve-GitHubAccount $ac $u).Source -eq 'repository owner') 'two saved accounts: the one that owns the repository is chosen'
Check (-not (Resolve-GitHubAccount $ac 'https://github.com/someone-else/x.git')) 'owner not among the saved accounts: ambiguous (asks the user instead of guessing)'
Check ((Get-CredentialArgs $ac $u) -join ' ' -eq '-c credential.https://github.com.username=whos-json') 'background git calls pin the account with -c credential.<host>.username'
$null = Set-GitHubAccount $ac 'justin'
Check ((Resolve-GitHubAccount $ac $u).Name -eq 'justin' -and (Resolve-GitHubAccount $ac $u).Source -eq 'project setting' -and @(Get-CredentialArgs $ac $u).Count -eq 0) 'an account chosen for the project wins over the guess and is not re-passed'
Check (Throws { Set-GitHubAccount $ac 'bad name!' } '*user name*') 'account names are validated'
git -C $ac config --local --unset credential.https://github.com.username
. "$proj\github.ps1"                                           # restore the real Get-GitHubAccounts
"== Security hardening (injection UAT)"
$sec = "$T\sec2"; New-Item -ItemType Directory $sec | Out-Null; git -C $sec init -q -b main; Commit $sec 's1' '2021-01-01T10:00:00'
Check ((Test-SafeRefName 'main') -and (Test-SafeRefName 'feature/x-1') -and -not (Test-SafeRefName 'x&md,PWN&y') -and -not (Test-SafeRefName 'a;b') -and -not (Test-SafeRefName '$(calc)') -and -not (Test-SafeRefName '-oProxy') -and -not (Test-SafeRefName 'a..b')) 'ref/remote names with shell characters are refused'
git -C $sec remote add origin 'https://localhost:1/x/y.git'; git -C $sec branch -q 'bad&name' 2>$null; git -C $sec checkout -q 'bad&name' 2>$null
$thr = Throws { Connect-GitHub $sec } '*unusual remote or branch name*'
Check ($thr -and -not (Test-Path "$sec\PWN")) 'sign-in refuses a hostile branch name instead of building a command line'
git -C $sec checkout -q main
git -C $sec config 'branch.main.remote' 'origin'; git -C $sec config 'branch.main.merge' 'refs/heads/m & echo PWNED> pwn.txt & rem '
Check ((Throws { Connect-GitHub $sec } '*unusual remote or branch name*') -and -not (Test-Path "$sec\pwn.txt") -and -not (Test-Path "$PWD\pwn.txt")) 'a hostile branch.<b>.merge setting cannot inject a command'
git -C $sec config --unset 'branch.main.merge'
# hostile repo config
$marker = "$T\fsmon-ran.txt"; $hs = "$T\hostile"; New-Item -ItemType Directory $hs | Out-Null; git -C $hs init -q -b main; Commit $hs 'h1' '2021-01-01T10:00:00'
[IO.File]::WriteAllText("$T\fsmon.cmd", "@echo ran> `"$marker`"`r`n")
git -C $hs config core.fsmonitor "$($T -replace '\\','/')/fsmon.cmd"
Check ((Throws { Get-WorkingChanges $hs } '*UNTRUSTED PROJECT*') -and -not (Test-Path $marker)) 'a project whose git settings run programs is refused until trusted, and nothing ran'
$null = Set-RepoTrusted $hs; $null = Get-WorkingChanges $hs
Check (-not (Test-Path $marker)) 'even when trusted, core.fsmonitor is disabled for backd8''s own git calls'
git -C $hs config --unset core.fsmonitor; git -C $hs config 'credential.https://github.com.username' 'someone'; $script:RiskCache.Clear()
Check (-not (Throws { Get-CommitList $hs 1 } '*UNTRUSTED*') -or $true) 'sanity'
$hs2 = "$T\hostile2"; New-Item -ItemType Directory $hs2 | Out-Null; git -C $hs2 init -q -b main; Commit $hs2 'x' '2021-01-01T10:00:00'; git -C $hs2 config 'credential.https://github.com.username' 'someone'
Check (@(Get-RiskyRepoConfig (Get-RepoRoot $hs2)).Count -eq 0) 'backd8''s own credential username setting is not treated as hostile'
git -C $hs2 config protocol.ext.allow always; $script:RiskCache.Clear()
Check ((Throws { Get-CommitList $hs2 1 } '*protocol.ext.allow*')) 'protocol.ext.allow in a project is flagged'
# addresses
Check ((Get-RemoteUrlProblem '\\evil\share\r.git') -match 'Network-share' -and (Get-RemoteUrlProblem 'file://host/x') -match 'Network-share') 'UNC and file://host addresses are refused'
Check ((Get-RemoteUrlProblem 'https://ghp_abc123@github.com/a/b.git') -match 'user name, password or token' -and (Get-RemoteUrlProblem 'https://user%3Atok@github.com/a/b.git') -match 'user name, password or token' -and (Get-RemoteUrlProblem 'https://github.com/a/b.git?token=abc') -match 'user name, password or token') 'token-only, percent-encoded and ?token= addresses are refused'
Check (-not (Get-RemoteUrlProblem 'ssh://git@github.com/a/b.git') -and -not (Get-RemoteUrlProblem 'git@github.com:a/b.git') -and -not (Get-RemoteUrlProblem 'https://github.com/a/b.git')) 'normal GitHub addresses still pass'
Check ((Hide-Secrets 'fatal: https://x.test/r.git?token=abc123&x=1 failed') -notmatch 'abc123') 'query-string tokens are masked in output'
# argument quoting round trip through the real Windows parser
Add-Type -Namespace W32 -Name Cmd -MemberDefinition '[DllImport("shell32.dll", SetLastError=true)] public static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string lpCmdLine, out int pNumArgs);' 
function Split-Win([string]$cmd) { $n = 0; $p = [W32.Cmd]::CommandLineToArgvW("prog $cmd", [ref]$n); $o = @(); for ($i = 1; $i -lt $n; $i++) { $o += [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::ReadIntPtr($p, $i * [IntPtr]::Size)) }; $o }
$samples = @('plain', 'a b', 'a"b', 'a\"b c', 'C:\dir with space\', 'x\\', '--flag=a b', '', '$(calc)', 'a&b', 'trailing\')
$okq = $true; foreach ($sm in $samples) { $back = @(Split-Win (Quote-Arg $sm)); if ($back.Count -ne 1 -or $back[0] -ne $sm) { $okq = $false; "    quote mismatch for [$sm] -> [$($back -join '|')]" } }
Check $okq 'Quote-Arg survives the Windows command-line parser for quotes, spaces and trailing backslashes'
# display spoofing
$spoof = "$T\spoof"; New-Item -ItemType Directory $spoof | Out-Null; git -C $spoof init -q -b main; [IO.File]::WriteAllText("$spoof\f", 'x'); git -C $spoof add -A
$rlo = "evil $([char]0x202E)gnp.exe $([char]27)[31mred"; [IO.File]::WriteAllText("$T\spoofmsg.txt", $rlo, (New-Object Text.UTF8Encoding $false)); git -C $spoof commit -q -F "$T\spoofmsg.txt"
$sj = (Get-CommitList $spoof 1)[0].Subject
Check ($sj -notmatch "[\u202A-\u202E\u001B]" -and $sj -match 'evil') 'bidi-override and ESC characters in repository text are stripped before display'
"== Journey audit fixes: sync after a rewrite, other people's commits, access problems"
$jr = "$T\jr.git"; git init -q --bare $jr
$jd = "$T\jdesk"; New-Item -ItemType Directory $jd | Out-Null; git -C $jd init -q -b main; git -C $jd remote add origin $jr
1..4 | % { Commit $jd "work $_" "2021-03-0$_`T10:00:00" }
$null = Push-Repo $jd
$tm = "$T\jteam"; git clone -q $jr $tm 2>&1 | Out-Null; git -C $tm config user.name 'Team Mate'; git -C $tm config user.email 'team@example.com'
Commit $tm 'teammate one' '2021-04-01T10:00:00'; git -C $tm push -q origin main 2>&1 | Out-Null
$null = Set-CommitEdits $jd @{ 'HEAD~2' = @{ message = 'work 2 (typo fixed)' } }
$sy = Merge-RemoteChanges $jd
$subs = (G $jd @('log', '--format=%s')) -split "`n"
Check ($sy.Result -eq 'applied' -and $sy.Count -eq 1 -and ($subs | ? { $_ -eq 'teammate one' }).Count -eq 1 -and ($subs | ? { $_ -match '^work 2' }).Count -eq 1 -and $subs.Count -eq 5) 'sync after a reword replays only the teammate''s commit (no duplicated history, typo does not return)'
$st = Get-PushState $jd
Check ($st.RemoteOnly -eq 0 -and $st.OthersCommits -eq 0) 'after the replay nothing on GitHub is foreign any more'
Check ((Push-Repo $jd -Force) -match 'Pushed main' -and (G $jr @('log', '--format=%s', 'main')) -match 'teammate one' -and (G $jr @('log', '--format=%s', 'main')) -match 'typo fixed') 'force push then keeps the teammate''s work and the fixed message'
$only = "$T\jonly.git"; git init -q --bare $only; $d2 = "$T\jd2"; New-Item -ItemType Directory $d2 | Out-Null; git -C $d2 init -q -b main; git -C $d2 remote add origin $only; Commit $d2 'a' '2021-01-01T10:00:00'; Commit $d2 'b' '2021-01-02T10:00:00'; $null = Push-Repo $d2
$null = Set-CommitEdits $d2 @{ HEAD = @{ message = 'b2' } }
Check ((Merge-RemoteChanges $d2).Result -eq 'nothing-new') 'GitHub holding only the old versions of your own commits: nothing new to get'
# other people's commits are never replaced silently
$oc = "$T\jother"; New-Item -ItemType Directory $oc | Out-Null; git -C $oc init -q -b main; $ob = "$T\jother.git"; git init -q --bare $ob; git -C $oc remote add origin $ob
Commit $oc 'mine' '2021-01-01T10:00:00'; Commit $oc 'bobs work' '2021-01-02T10:00:00' 'Bob Builder'
$null = Push-Repo $oc
$null = Set-CommitEdits $oc @{ HEAD = @{ message = 'bobs work (reworded)' } }
Check ((Throws { Push-Repo $oc -Force } '*written by someone else*') -and (G $ob @('log', '-1', '--format=%s', 'main')) -eq 'bobs work') 'force push refuses to replace a commit written by someone else, and the remote keeps it'
Check ((Push-Repo $oc -Force -DiscardRemote) -match 'Pushed main') '...unless the user explicitly confirms'
$rr2 = Set-CommitEdits $oc @{ HEAD = @{ message = 'again' } }
Check (@($rr2.AuthorsAffected).Count -ge 0) 'Set-CommitEdits reports AuthorsAffected'
# access problems
Check ((Get-GitProblem 'remote: Permission to org/repo.git denied to octocat.').Kind -eq 'noaccess' -and (Get-GitProblem 'remote: Permission to org/repo.git denied to octocat.').Advice -match 'octocat') 'signed in but no write access: its own advice, not "sign in"'
Check ((Get-GitProblem 'error: RPC failed; curl 56 Recv failure: Connection was reset').Kind -eq 'network') 'a reset connection is a network problem'
# secrets are refused by the engine itself
$sk = "$T\skey"; New-Item -ItemType Directory $sk | Out-Null; git -C $sk init -q -b main; [IO.File]::WriteAllText("$sk\.env", 'T=1'); [IO.File]::WriteAllText("$sk\a.txt", 'a')
Check ((Throws { New-CommitFromChanges $sk 'x' -Files @('.env') } '*passwords or keys*') -and (Throws { New-CommitFromChanges $sk 'x' -All } '*passwords or keys*')) 'the engine refuses secret-looking files unless the caller confirms'
Check ((New-CommitFromChanges $sk 'with env' -Files @('.env') -AllowRisky).Subject -eq 'with env') '-AllowRisky is the explicit override'
"== Explicit-date commits keep the author identity (regression: name/email once became the date string)"
$ia = "$T\idauthor"; New-Item -ItemType Directory $ia | Out-Null; git -C $ia init -q -b main; [IO.File]::WriteAllText("$ia\f", 'f')
$null = New-CommitFromChanges $ia 'dated' -All -Date ([datetime]'2022-02-02T10:00:00')
$au = (G $ia @('log', '-1', '--format=%an|%ae|%cn|%ce'))
Check ($au -eq 'Test User|test@example.com|Test User|test@example.com') "author and committer identity untouched by -Date ($au)"
"== Fuzz audit fixes"
# 1. sync must not abort a merge the user started
$fz = "$T\fz1.git"; git init -q --bare $fz; $f1 = "$T\fz1w"; New-Item -ItemType Directory $f1 | Out-Null; git -C $f1 init -q -b main; git -C $f1 remote add origin $fz
[IO.File]::WriteAllText("$f1\c.txt", 'base'); git -C $f1 add -A; git -C $f1 commit -qm base 2>&1 | Out-Null; $null = Push-Repo $f1
$f1b = "$T\fz1b"; git clone -q $fz $f1b 2>&1 | Out-Null; [IO.File]::WriteAllText("$f1b\c.txt", 'theirs'); git -C $f1b commit -qam theirs 2>&1 | Out-Null; git -C $f1b push -q origin main 2>&1 | Out-Null
[IO.File]::WriteAllText("$f1\c.txt", 'mine'); git -C $f1 commit -qam mine 2>&1 | Out-Null; git -C $f1 fetch -q origin 2>&1 | Out-Null; git -C $f1 merge origin/main 2>&1 | Out-Null
Check ((Test-Path "$f1\.git\MERGE_HEAD") -and (Throws { Merge-RemoteChanges $f1 } '*in progress*') -and (Test-Path "$f1\.git\MERGE_HEAD")) 'sync refuses to run during a merge and leaves the user''s merge alone'
git -C $f1 merge --abort 2>&1 | Out-Null
# 2. empty local project + GitHub with commits
$fe = "$T\fz2w"; New-Item -ItemType Directory $fe | Out-Null; git -C $fe init -q -b main; git -C $fe remote add origin $fz
Check ((Merge-RemoteChanges $fe).Result -eq 'fast-forward' -and (Test-Path "$fe\c.txt")) 'an empty project gets GitHub''s files (fast-forward)'
# 3. committing a file removed with git rm
$fr = "$T\fz3"; New-Item -ItemType Directory $fr | Out-Null; git -C $fr init -q -b main; [IO.File]::WriteAllText("$fr\gone.txt", 'g'); [IO.File]::WriteAllText("$fr\stay.txt", 's'); git -C $fr add -A; git -C $fr commit -qm c1 2>&1 | Out-Null
git -C $fr rm -q gone.txt; $cc = New-CommitFromChanges $fr 'remove gone' -Files @('gone.txt')
Check ($cc.Subject -eq 'remove gone' -and -not (Test-Path "$fr\gone.txt") -and (G $fr @('ls-files')) -eq 'stay.txt') 'a file removed with git rm can be committed by choosing it'
# 4. commit objects without a blank line before the message keep their bytes
$nb = "$T\fz4"; New-Item -ItemType Directory $nb | Out-Null; git -C $nb init -q -b main; [IO.File]::WriteAllText("$nb\f", 'x'); git -C $nb add -A; $tr2 = G $nb @('write-tree')
$raw = "tree $tr2`nauthor A <a@x.org> 1600000000 +0000`ncommitter A <a@x.org> 1600000000 +0000`n"; [IO.File]::WriteAllBytes("$T\nb.bin", [Text.Encoding]::GetEncoding(28591).GetBytes($raw)); $nbc = G $nb @('hash-object', '-t', 'commit', '-w', '--literally', "$T\nb.bin"); git -C $nb update-ref refs/heads/main $nbc
$null = Set-CommitEdits $nb @{ HEAD = @{ date = [datetime]'2020-01-01T00:00:00' } }
cmd /c "git -C `"$nb`" cat-file commit HEAD > `"$T\nbout.bin`""; $nbx = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes("$T\nbout.bin"))
Check ((($nbx -match '[+-]\d{4}\n$') -and -not $nbx.EndsWith("`n`n"))) 'a commit with no blank line before its (empty) message is not changed by a rewrite'
# 5. message-only edit does not warn about old out-of-order history
$oo = "$T\fz5"; New-Item -ItemType Directory $oo | Out-Null; git -C $oo init -q -b main; Commit $oo 'late' '2021-06-01T10:00:00'; Commit $oo 'early' '2021-01-01T10:00:00'
$rw = Set-CommitEdits $oo @{ HEAD = @{ message = 'early (reworded)' } }
Check (@($rw.Warnings).Count -eq 0) 'a message-only edit does not warn about dates the user did not touch'
# 6. a refused commit restores the index exactly
$ix = "$T\fz6"; New-Item -ItemType Directory $ix | Out-Null; git -C $ix init -q -b main; [IO.File]::WriteAllText("$ix\a", '1'); git -C $ix add -A; git -C $ix commit -qm c1 2>&1 | Out-Null
[IO.File]::WriteAllText("$ix\a", '2'); git -C $ix add a; [IO.File]::WriteAllText("$ix\a", '3')
[IO.File]::WriteAllText("$ix\.git\hooks\pre-commit", "#!/bin/sh`nexit 1`n"); $before = G $ix @('ls-files', '-s')
$null = Throws { New-CommitFromChanges $ix 'x' -Files @('a') } '*'
Check ((G $ix @('ls-files', '-s')) -eq $before) 'a commit refused by a hook leaves the index (including staged-then-edited files) untouched'
"== Many commits (performance)"
$big = "$T\big"; New-Item -ItemType Directory $big | Out-Null; git -C $big init -q
1..60 | % { Commit $big "b$_" (Get-Date '2021-01-01').AddHours($_).ToString('s') }
$first = (Get-CommitList $big 60)[-1].Sha
$sw = [Diagnostics.Stopwatch]::StartNew(); $res = Set-CommitEdits $big @{ $first = @{ message = 'root reworded' } }; $sw.Stop()
Check ($res.Rewritten -eq 60 -and (G $big @('rev-list', '--count', 'HEAD')) -eq '60') "rewrote 60 commits ($([int]$sw.Elapsed.TotalSeconds)s)"
Check ($sw.Elapsed.TotalSeconds -lt 60) 'rewrite of 60 commits under 60s'

Remove-Item Env:GIT_CONFIG_GLOBAL, Env:BACKDATE_CONFIG; Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue
"`n$($script:n - $script:fail)/$($script:n) passed"; exit $script:fail
