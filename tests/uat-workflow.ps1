# UAT for the workflow state machine (workflow.ps1): formal model proof + every state reached with REAL repositories +
# guarded actions + closed-loop recovery. Isolated (own git config, own config.json, local bare repos).
# Run: powershell -ExecutionPolicy Bypass -File tests\uat-workflow.ps1
$proj = Split-Path $PSScriptRoot
$T = Join-Path $env:TEMP "backd8-uatwf-$(Get-Random)"; New-Item -ItemType Directory $T | Out-Null
$env:GIT_CONFIG_GLOBAL = "$T\gitconfig"; $env:BACKDATE_CONFIG = "$T\config.json"; $env:GCM_INTERACTIVE = 'never'; $env:GIT_TERMINAL_PROMPT = '0'
. "$proj\lib.ps1"
git config --global init.defaultBranch main
$script:fail = 0; $script:n = 0
function Check($ok, $name) { $script:n++; if ($ok) { "  PASS  $name" } else { $script:fail++; "  FAIL  $name" } }
function G($r, [string[]]$a) { (& git -C $r @a 2>&1 | ForEach-Object { "$_" }) -join "`n" }
function St($path, $ui = @{}) { (Get-WorkflowPlan $path $ui).State }

"== The model itself"
$v = @(Test-WorkflowModel)
Check ($v.Count -eq 0) "model proven over $($script:WfModelCases) fact combinations$(if ($v.Count) { ': ' + ($v | Select-Object -First 3) -join '; ' })"
Check ($script:WfStates.Count -ge 20 -and @($script:WfActions.Keys).Count -eq $script:WfStates.Count) 'every state has an action table'
Check ((Resolve-WorkflowState (New-WorkflowFacts)) -eq 'NoFolder') 'defaults resolve to NoFolder'
$f = [pscustomobject](New-WorkflowFacts); $f.FolderGiven = $true; $f.FolderExists = $true; $f.IsRepo = $true; $f.HasCommits = $true; $f.Linked = $true
Check ((Resolve-WorkflowState $f) -eq 'InSync') 'a clean linked project is InSync'
$f.Ahead = 1; Check ((Resolve-WorkflowState $f) -eq 'ReadyToPublish') 'ahead of GitHub -> ReadyToPublish'
$f.Behind = 1; Check ((Resolve-WorkflowState $f) -eq 'NeedsReplace') 'ahead and behind with only my own commits -> NeedsReplace'
$f.Others = 2; Check ((Resolve-WorkflowState $f) -eq 'NeedsSync') '...but with someone else''s commits -> NeedsSync first'
$f.Ahead = 0; $f.Others = 0; Check ((Resolve-WorkflowState $f) -eq 'GitHubAhead') 'behind only -> GitHubAhead'
$f.Behind = 0; $f.Ahead = 1; $f.Access = 'NotSignedIn'; Check ((Resolve-WorkflowState $f) -eq 'NeedsSignIn') 'publishing while signed out -> NeedsSignIn'
$f.Changes = 1; Check ((Resolve-WorkflowState $f) -eq 'ChangesPending') 'uncommitted files always come first'
Check ((Get-WorkflowError 'GitHub sign-in required (or this account...)').Recovery -eq 'SignIn' -and (Get-WorkflowError 'GitHub has 2 newer change(s)').Recovery -eq 'Sync' -and (Get-WorkflowError 'UNTRUSTED PROJECT: x').Recovery -eq 'Trust' -and (Get-WorkflowError 'weird unknown text').Class -eq 'other') 'engine errors map to a class and a recovery action (unknown ones fall back to Recheck)'

"== Real projects land in the right state"
Check ((St '') -eq 'NoFolder' -and (St "$T\nope") -eq 'FolderNotFound') 'no folder / missing folder'
$plain = "$T\plain"; New-Item -ItemType Directory $plain | Out-Null; [IO.File]::WriteAllText("$plain\a.txt", 'a')
Check ((St $plain) -eq 'NotAProject') 'a plain folder -> NotAProject'
$null = Initialize-Repo $plain
Check ((St $plain) -eq 'NoIdentity') 'a new project without git identity -> NoIdentity (prerequisite, not an error)'
git config --global user.name 'WF Test'; git config --global user.email 'wf@example.com'
Check ((St $plain) -eq 'ChangesPending') 'identity set, files present -> ChangesPending'
$pl = Get-WorkflowPlan $plain
Check ($pl.Recommended -eq 'Commit' -and @($pl.Actions | Where-Object { $_.Id -eq 'Commit' -and -not $_.Enabled }).Count -eq 1) 'Commit is recommended but disabled until a message is given (guard says why)'
$e = Invoke-WorkflowAction $plain 'Commit' @{ Message = ''; All = $true }
Check (-not $e.Ok -and $e.Reason -eq 'guard' -and $e.Message -match 'what you changed' -and $e.To -eq 'ChangesPending') 'guard blocks an empty message and nothing is changed'
$e = Invoke-WorkflowAction $plain 'Publish'
Check (-not $e.Ok -and $e.Reason -eq 'stale' -and $e.Message -match 'not available any more') 'an action that is not valid in this state is refused as stale (no side effects)'
$e = Invoke-WorkflowAction $plain 'Commit' @{ Message = 'first version'; All = $true; Date = [datetime]'2022-02-02T10:00:00' }
Check ($e.Ok -and $e.From -eq 'ChangesPending' -and $e.To -eq 'NoRemote' -and $e.Plan.Recommended -eq 'ConnectRemote') 'Commit -> NoRemote, next step is Connect'
$e = Invoke-WorkflowAction $plain 'ConnectRemote' @{ Url = 'https://github.com/me/tree/main/x' }
Check (-not $e.Ok -and $e.Reason -eq 'guard' -and $e.Message -match 'page inside') 'a bad GitHub address is explained, state unchanged'
$bare = "$T\hub.git"; git init -q --bare $bare
$e = Invoke-WorkflowAction $plain 'ConnectRemote' @{ Url = $bare }
Check ($e.Ok -and $e.To -eq 'ReadyToPublish') 'Connect -> ReadyToPublish (never published = something to publish)'
$e = Invoke-WorkflowAction $plain 'Publish'
Check ($e.Ok -and $e.To -eq 'InSync' -and (G $bare @('rev-parse', 'main')) -eq (G $plain @('rev-parse', 'HEAD'))) 'Publish -> InSync and GitHub has the commit'
Check ((Get-WorkflowPlan $plain).Actions.Id -contains 'EditOlder') 'in sync, the user can still choose to edit older commits (no dead end)'

"== Edits, replacing, syncing"
$null = Invoke-WorkflowAction $plain 'Recheck'
$ed = @{ (G $plain @('rev-parse', 'HEAD')) = @{ message = 'first version (reworded)' } }
$e = Invoke-WorkflowAction $plain 'ApplyEdits' @{ Edits = $ed } @{ EditsStaged = 1 }
Check ($e.Ok -and $e.To -eq 'NeedsReplace') "Apply edits to a published commit -> NeedsReplace (Ok=$($e.Ok) To=$($e.To) Msg=$($e.Message) Err=$($e.ErrorClass))"
$e = Invoke-WorkflowAction $plain 'ReplaceRemote' @{}
Check ($e.Ok -and $e.To -eq 'InSync') 'Replace -> InSync'
$e = Invoke-WorkflowAction $plain 'Undo' @{ Force = $true }
Check ($e.Ok -and $e.To -eq 'NeedsReplace' -and ($e.Recovery -contains 'ReplaceRemote')) 'Undo after publishing -> NeedsReplace again, with a way forward'
$null = Invoke-WorkflowAction $plain 'ReplaceRemote' @{}
# a teammate pushes
$mate = "$T\mate"; git clone -q $bare $mate 2>&1 | Out-Null; git -C $mate config user.name 'Team Mate'; git -C $mate config user.email 'mate@example.com'
[IO.File]::WriteAllText("$mate\m.txt", 'm'); git -C $mate add -A; git -C $mate commit -q -m 'teammate' 2>&1 | Out-Null; git -C $mate push -q origin main 2>&1 | Out-Null
$null = Update-RemoteRefs $plain
Check ((St $plain) -eq 'GitHubAhead') 'a teammate pushed -> GitHubAhead'
$e = Invoke-WorkflowAction $plain 'Sync'
Check ($e.Ok -and $e.To -eq 'InSync') 'Sync -> InSync'
# conflict loop
[IO.File]::WriteAllText("$plain\a.txt", 'mine'); $null = Invoke-WorkflowAction $plain 'Commit' @{ Message = 'mine'; All = $true }
[IO.File]::WriteAllText("$mate\a.txt", 'theirs'); git -C $mate commit -qam 'theirs' 2>&1 | Out-Null; git -C $mate push -q origin main 2>&1 | Out-Null
$null = Update-RemoteRefs $plain
$e = Invoke-WorkflowAction $plain 'Sync'
Check (-not $e.Ok -and $e.ErrorClass -eq 'conflict' -and $e.Message -match 'a.txt' -and $e.Recovery.Count -ge 1 -and (Test-Path "$plain\.git\MERGE_HEAD") -eq $false) 'a sync conflict is reported, nothing is half-merged, a recovery exists'

"== Prerequisites and blockers"
$un = "$T\untrusted"; New-Item -ItemType Directory $un | Out-Null; git -C $un init -q -b main; git -C $un config core.fsmonitor 'x'
Check ((St $un) -eq 'Untrusted') 'hostile settings -> Untrusted'
$e = Invoke-WorkflowAction $un 'Trust'
Check ($e.Ok -and $e.To -ne 'Untrusted') 'Trust moves on'
$bl = "$T\blocked"; New-Item -ItemType Directory $bl | Out-Null; git -C $bl init -q -b main; [IO.File]::WriteAllText("$bl\f", 'f'); git -C $bl add -A; git -C $bl commit -qm c 2>&1 | Out-Null
New-Item -ItemType Directory "$bl\.git\rebase-merge" | Out-Null
Check ((St $bl) -eq 'Blocked' -and (Get-WorkflowPlan $bl).Actions.Id -contains 'ShowFinishOperation') 'half-finished rebase -> Blocked with instructions'
Remove-Item "$bl\.git\rebase-merge" -Recurse; git -C $bl checkout -q --detach HEAD
Check ((St $bl) -eq 'Detached') 'detached HEAD -> Detached'
git -C $bl checkout -q main
Check ((St $bl) -eq 'NoRemote') 'clean committed project without a remote -> NoRemote'
$empty = "$T\emptyproj"; New-Item -ItemType Directory $empty | Out-Null; git -C $empty init -q -b main
Check ((St $empty) -eq 'EmptyProject') 'no files and no commits -> EmptyProject (with a re-check action)'
$sg = Get-WorkflowFacts $plain
Check ($sg.Changes -ge 0 -and $sg.Linked -and $sg.GitInstalled) 'facts are collected without throwing'
# engine failures never throw out of Invoke-WorkflowAction
$e = Invoke-WorkflowAction "$T\nope" 'Publish'
Check (-not $e.Ok -and $e.Reason -eq 'stale' -and $e.To -eq 'FolderNotFound') 'a vanished folder is a state, not a crash'
# access states and the dynamic prerequisite check
$srv = "$T\hub2.git"; git init -q --bare $srv
$web = "$T\webproj"; New-Item -ItemType Directory $web | Out-Null; git -C $web init -q -b main; [IO.File]::WriteAllText("$web\w", 'w'); git -C $web add -A; git -C $web commit -qm w 2>&1 | Out-Null
git -C $web remote add origin 'http://localhost:1/x/y.git'
Check ((St $web) -eq 'ReadyToPublish') 'offline facts cannot know sign-in: ReadyToPublish (optimistic)'
$e = Invoke-WorkflowAction $web 'Publish'
Check (-not $e.Ok -and $e.To -in 'Offline', 'NeedsSignIn' -and $e.Recovery.Count -ge 1) 'Publish discovers the real prerequisite and lands in the matching state with a way forward'

Remove-Item Env:GIT_CONFIG_GLOBAL, Env:BACKDATE_CONFIG, Env:GCM_INTERACTIVE, Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue
"`n$($script:n - $script:fail)/$($script:n) passed"; exit $script:fail
