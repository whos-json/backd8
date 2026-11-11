# Checks assets\strings.en.psd1 against the real workflow model (workflow.ps1), the glossary and the length / placeholder /
# access-key rules. Fails (exit 1) when anything is missing, too long, jargon, or inconsistent.
# Isolated: own git config and config.json in a temp folder, no network, no repositories touched.
# Run: powershell -ExecutionPolicy Bypass -File tests\strings-check.ps1 [-Path <strings file>]
param([string]$Path)
$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot
if (-not $Path) { $Path = Join-Path $proj 'assets\strings.en.psd1' }

$T = Join-Path ([IO.Path]::GetTempPath()) "backd8-strings-$(Get-Random)"; New-Item -ItemType Directory $T | Out-Null
$saved = @{}; foreach ($ev in 'GIT_CONFIG_GLOBAL', 'BACKDATE_CONFIG', 'GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE') { $saved[$ev] = [Environment]::GetEnvironmentVariable($ev) }
$env:GIT_CONFIG_GLOBAL = "$T\gitconfig"; $env:BACKDATE_CONFIG = "$T\config.json"; $env:GIT_TERMINAL_PROMPT = '0'; $env:GCM_INTERACTIVE = 'never'
Set-Content -LiteralPath "$T\gitconfig" -Value ''

$script:n = 0; $script:fails = New-Object Collections.Generic.List[string]
function Check($ok, [string]$name) { $script:n++; if (-not $ok) { $script:fails.Add($name); "  FAIL  $name" } }
function Section([string]$s) { "== $s" }

try {
  . "$proj\lib.ps1"
  $AstNs = 'System.Management.Automation.Language'

  # ---------- load ----------
  Section 'File'
  Check (Test-Path -LiteralPath $Path) "strings file exists: $Path"
  $bytes = [IO.File]::ReadAllBytes($Path)
  Check ($bytes.Length -gt 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'file is UTF-8 with BOM'
  try { $null = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes, 3, $bytes.Length - 3); $utf8ok = $true } catch { $utf8ok = $false }
  Check $utf8ok 'file is valid UTF-8'
  $Str = Import-PowerShellDataFile -LiteralPath $Path
  Check ($Str -is [hashtable]) 'Import-PowerShellDataFile returns a table'

  foreach ($sec in 'Meta', 'Glossary', 'Placeholders', 'Chrome', 'TechInfo', 'Messages', 'Pages', 'Welcome', 'FirstRun', 'States', 'Actions', 'ActionOverrides', 'Guards', 'AddressProblems', 'ErrorLabels', 'Problem', 'ErrorClasses', 'Dialogs', 'Progress', 'EmptyStates', 'Success', 'StatusBar', 'Dates', 'FileChecklist', 'Help') {
    Check ($Str.ContainsKey($sec)) "section present: $sec"
  }

  # ---------- limits, placeholders, helpers ----------
  # first matching pattern wins; the number is the maximum length (the & access marker is not counted)
  $limits = @(
    '40|^States\.\w+\.Title$'
    '220|^States\.\w+\.Help$'
    '60|^States\.\w+\.Heading$'
    '100|^States\.\w+\.Instruction$'
    '36|^Actions\.\w+\.Label$'
    '36|^Actions\.\w+\.Access$'
    '120|^Actions\.\w+\.Tooltip$'
    '36|^ActionOverrides\.[^.]+\.(Label|Access)$'
    '120|^ActionOverrides\.[^.]+\.Tooltip$'
    '120|^Guards\[\d+\]\.Why$'
    '110|^AddressProblems\[\d+\]\.Text$'
    '70|^ErrorClasses\.\w+\.Headline$'
    '150|^ErrorClasses\.\w+\.(Happened|Todo)$'
    '400|\.Details$'
    '50|^Dialogs\.\w+\.Title$'
    '70|^Dialogs\.\w+\.Heading$'
    '330|^Dialogs\.\w+\.Body'
    '120|^Dialogs\.\w+\.(IfPublished|Intro|Outro)$'
    '70|^Dialogs\.\w+\.Lines\.'
    '90|^Dialogs\.\w+\.Checkbox$'
    '32|^Dialogs\.\w+\.Buttons\[\d+\]\.Label'
    '60|^Progress\.Steps\[\d+\]\.(Running|Done|Failed)$'
    '60|^Progress\.(Heading)$'
    '100|^Progress\.(Instruction|CancelDisabled)$'
    '90|^EmptyStates\.'
    '50|^StatusBar\.\w+\.Text'
    '100|^StatusBar\.\w+\.Tip$'
    '20|^Dates\.Presets\[\d+\]\.Label$'
    '60|^Dates\.Presets\[\d+\]\.Description$'
    '110|^Dates\.Errors\[\d+\]\.Text$'
    '100|^Dates\.(Hint|Preview|Caution)$'
    '60|^FileChecklist\.Reasons\.\w+\.Text$'
    '100|^FileChecklist\.Reasons\.\w+\.Tip$'
    '20|^FileChecklist\.(Columns|Kinds)\.'
    '60|^FileChecklist\.Hint$'
    '40|^Pages\.\w+\.Controls\.'
    '14|^Chrome\.Buttons\.'
    '60|^Welcome\.Heading$'
    '100|^Welcome\.Instruction$'
    '200|^Welcome\.(Intro|Explain|Caution|Safe)$'
    '60|^Welcome\.Steps\[\d+\]$'
    '60|^Success\.Heading$'
    '100|^Success\.Instruction$'
    '110|^Success\.Variants\.'
    '70|^Success\.NextSteps\[\d+\]\.Text$'
    '60|^Success\.NextHeading$'
    '60|^Problem\.Heading$'
    '100|^Problem\.Instruction$'
    '30|^Help\.F1\.Shortcuts\[\d+\]\.Keys$'
    '70|^Help\.F1\.Shortcuts\[\d+\]\.Does$'
    '60|^FirstRun\.\w+\.Heading$'
    '200|^FirstRun\.\w+\.(Body)$'
    '80|^FirstRun\.GitMissing\.Steps\[\d+\]$'
    '80|^FirstRun\.Identity\.(Note|NameHint|EmailHint|NameMissing|EmailBad)$'
    '100|^TechInfo\.'
    '110|^Messages\.'
    '40|^Chrome\.'
  )
  $allowedGlobal = @('count', 'total', 'current', 'branch', 'folder', 'name', 'email', 'url', 'account', 'files', 'sizeMB', 'limitMB', 'date', 'when', 'settings', 'changes', 'edits', 'unpublished')
  # which placeholders each top-level section may use (Dialogs: the dialog's own Uses list)
  $allowedBySection = @{ ErrorClasses = @('limitMB'); Progress = @(); StatusBar = @('count', 'branch', 'account'); Dates = @('date'); FileChecklist = @('sizeMB', 'limitMB'); Success = @('count'); Chrome = @('current', 'total') }

  # words that must never appear in text the user reads first (technical wording belongs under Details only)
  $forbidden = '\b(repository|repositories|repo|repos|push|pushed|pushing|pull|pulled|pulling|sync|synchronize|synchronise|fetch|fetched|rebase|cherry-pick|upstream|origin|remote|sha|hash|head|amend|force|commits?|merge|merged|junction|symlink|refs?|conflicts?|terminal|powershell|console|credentials?|authenticate|authenticated|authenticating|authorize|authorise|authorised|authorized|organisation|url|urls|reflog|ssh-keygen)\b'
  $usSpelling = '\b(organisation|authorise|authorised|colour|behaviour|favourite|cancelled|licence)\b'

  function Strip([string]$s) { $s -replace '&(?=[A-Za-z0-9])', '' }
  function AccessKey([string]$s) { if ($s -match '&([A-Za-z0-9])') { $Matches[1].ToLowerInvariant() } }
  function Placeholders([string]$s) { @([regex]::Matches($s, '\{(\w+)\}') | ForEach-Object { $_.Groups[1].Value }) }
  function IsPlural($h) { $h -is [hashtable] -and $h.ContainsKey('Other') -and (@($h.Values | Where-Object { $_ -isnot [string] }).Count -eq 0) -and (@($h.Keys | Where-Object { $_ -notin 'Zero', 'One', 'Other' }).Count -eq 0) }
  function Variants($v) { if (IsPlural $v) { @($v.Values) } else { @($v) } }

  # every string leaf: Path, Value, Plural (is it inside a One/Other pair)
  $leaves = New-Object Collections.Generic.List[object]
  function Walk($node, [string]$path, [bool]$plural) {
    if ($node -is [string]) { $leaves.Add([pscustomobject]@{ Path = $path; Value = $node; Plural = $plural }); return }
    if ($node -is [hashtable]) { $p2 = IsPlural $node; foreach ($k in @($node.Keys | Sort-Object)) { Walk $node[$k] "$path.$k" $p2 }; return }
    if ($node -is [System.Collections.IEnumerable]) { $i = 0; foreach ($e in $node) { Walk $e "$path[$i]" $plural; $i++ } }
  }
  foreach ($k in $Str.Keys) { Walk $Str[$k] $k $false }
  "  $($leaves.Count) strings loaded"

  function IsTech($p) { $p -match '(^|\.)(Details\w*|Technical)(\.|\[|$)' -or $p -match '^(Meta|Glossary|Placeholders)\.' -or $p -match '\.(Match|Dynamic|Key|Id|Role|Requires|Default|Icon|Page|Uses|Action)(\[\d+\])?$' }
  function IsPrimary($p) { -not (IsTech $p) }

  # ---------- general rules on every string ----------
  Section 'Every string: single line, limits, placeholders, plurals, glossary'
  $phSeen = @{}
  foreach ($l in $leaves) {
    $p = $l.Path; $v = $l.Value
    if ($p -match '^(Meta|Glossary|Placeholders)\.' -or $p -match '\.(Match|Key|Id|Role|Requires|Default|Icon|Page|Dynamic|Action)(\[\d+\])?$') { continue }
    Check ($v -notmatch "[\r\n\t]") "$p is a single line"
    Check ($v -eq $v.Trim() -and $v.Length -gt 0) "$p has no stray spaces and is not empty"
    $limit = 400; foreach ($pair in $limits) { $lm, $rx = $pair -split '\|', 2; if ($p -match $rx) { $limit = [int]$lm; break } }
    $len = (Strip $v).Length
    Check ($len -le $limit) "$p is $len characters (limit $limit)"
    $ph = @(Placeholders $v)
    foreach ($x in $ph) { $phSeen[$x] = $true }
    if ((IsTech $p) -and $ph.Count) { Check $false "$p (details text) must not contain placeholders" }
    if (-not (IsTech $p)) {
      $root = ($p -split '[.\[]')[0]
      $allowed = if ($root -eq 'Dialogs') { @($Str.Dialogs[($p -split '\.')[1]].Uses) } elseif ($allowedBySection.ContainsKey($root)) { $allowedBySection[$root] } else { @() }
      foreach ($x in $ph) {
        Check ($x -in $allowedGlobal) "$p uses unknown placeholder {$x}"
        Check ($x -in $allowed) "$p uses {$x}, which is not allowed in section $root$(if ($root -eq 'Dialogs') { ' (see the dialog Uses list)' })"
      }
      if ($v -match '\{count\}') { Check $l.Plural "$p shows a number, so it needs a One/Other pair" }
      if ($v -match '[{}]' -and $v -notmatch '^[^{}]*(\{\w+\}[^{}]*)*$') { Check $false "$p has a broken {placeholder}" }
      if ($v -match '\$|`|"') { Check $false "$p contains a `$, backtick or double quote" }
    }
    if ($p -notmatch '^(Glossary|Meta|Placeholders)\.') { Check ($v -notmatch $usSpelling) "$p uses non-US spelling" }
  }
  foreach ($x in $phSeen.Keys) { Check ($Str.Placeholders.ContainsKey($x)) "placeholder {$x} is used but not described in Placeholders" }
  foreach ($x in $Str.Placeholders.Keys) { Check ($x -in $allowedGlobal) "Placeholders lists {$x}, which the checker does not allow" }
  # plural pairs
  function PluralNodes($node, [string]$path) {
    if ($node -is [hashtable]) {
      if (@($node.Keys) -ccontains 'One' -or @($node.Keys) -ccontains 'Other') {
        Check (IsPlural $node) "$path is a broken plural pair (needs One and Other, nothing else but Zero)"
        Check ($node.ContainsKey('One') -and $node.ContainsKey('Other')) "$path needs both One and Other"
        if ($node.ContainsKey('Other') -and $path -notmatch '\.Buttons\[\d+\]\.Label') { Check ($node.Other -match '\{count\}') "$path.Other must show {count}" }
        if ($node.ContainsKey('One')) { Check ($node.One -ne $node.Other) "$path.One must differ from Other" }
      }
      foreach ($k in $node.Keys) { PluralNodes $node[$k] "$path.$k" }
    } elseif ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) { $i = 0; foreach ($e in $node) { PluralNodes $e "$path[$i]"; $i++ } }
  }
  foreach ($k in $Str.Keys) { PluralNodes $Str[$k] $k }

  # glossary: forbidden words in primary text; 'commit' only where the glossary says it is explained
  $commitHome = $Str.Glossary.Terms.commit.ExplainedIn
  Check ($commitHome -eq 'Welcome.Explain') 'Glossary says commit is explained in Welcome.Explain'
  $commitHits = 0
  foreach ($l in $leaves) {
    if (-not (IsPrimary $l.Path)) { continue }
    $v = $l.Value -replace '(https?://\S+|github\.com/\S+|\S+@\S+|\.git\b)', ' '
    $m = [regex]::Matches($v, $forbidden, 'IgnoreCase')
    foreach ($x in $m) {
      if ($x.Value -ieq 'commit' -and $l.Path -eq $commitHome) { $commitHits++; continue }
      Check $false "$($l.Path) uses the jargon word '$($x.Value)'"
    }
  }
  Check ($commitHits -eq 1) "the word commit is explained exactly once (found $commitHits)"
  Check ($Str.Welcome.Explain -match 'save point') 'Welcome.Explain names the save point'

  # ---------- states ----------
  Section 'States'
  $stateNames = @($script:WfStates.Keys)
  foreach ($s in $stateNames) {
    Check ($Str.States.ContainsKey($s)) "state $s has strings"
    if (-not $Str.States.ContainsKey($s)) { continue }
    $e = $Str.States[$s]
    foreach ($f in 'Title', 'Help', 'Heading', 'Instruction', 'Page') { Check ($e[$f] -is [string] -and $e[$f]) "state $s has $f" }
    if ($e.Page) { Check ($Str.Pages.ContainsKey($e.Page)) "state $s names a page that exists ($($e.Page))" }
  }
  foreach ($s in $Str.States.Keys) { Check ($s -in $stateNames) "strings for unknown state $s (not in the model)" }
  foreach ($f in 'Title', 'Heading') {
    $byVal = @{}; foreach ($s in $stateNames) { if ($Str.States[$s]) { $v = $Str.States[$s][$f]; if ($byVal.ContainsKey($v)) { Check $false "states $($byVal[$v]) and $s share the same $f '$v'" }; $byVal[$v] = $s } }
  }
  foreach ($pg in $Str.Pages.Keys) { Check ((@($Str.States.Values | Where-Object { $_.Page -eq $pg }).Count -gt 0) -or $pg -in 'Welcome', 'Progress', 'Problem') "page $pg is used by a state" }

  # ---------- actions ----------
  Section 'Actions'
  $ids = @($script:WfActions.Values | ForEach-Object { $_ } | ForEach-Object { $_.Id } | Sort-Object -Unique)
  foreach ($id in $ids) {
    Check ($Str.Actions.ContainsKey($id)) "action $id has strings"
    if ($Str.Actions.ContainsKey($id)) {
      $a = $Str.Actions[$id]
      foreach ($f in 'Label', 'Access', 'Tooltip') { Check ($a[$f] -is [string] -and $a[$f]) "action $id has $f" }
      Check ((Strip $a.Access) -ceq $a.Label) "action $id Access matches Label"
      Check ((@([regex]::Matches($a.Access, '&[A-Za-z0-9]')).Count) -eq 1) "action $id Access has exactly one access key"
    }
  }
  foreach ($id in $Str.Actions.Keys) { Check ($id -in $ids) "strings for unknown action $id" }
  $pairs = @{}; foreach ($s in $stateNames) { foreach ($a in $script:WfActions[$s]) { $pairs["$s/$($a.Id)"] = $true } }
  foreach ($k in $Str.ActionOverrides.Keys) {
    Check ($pairs.ContainsKey($k)) "override $k is not a state/action pair of the model"
    $o = $Str.ActionOverrides[$k]
    Check ($o.Label -and $o.Access -and (Strip $o.Access) -ceq $o.Label) "override $k has Label and a matching Access"
    Check ((@([regex]::Matches("$($o.Access)", '&[A-Za-z0-9]')).Count) -eq 1) "override $k Access has exactly one access key"
  }
  function Resolve-Act([string]$state, [string]$id) { $k = "$state/$id"; $d = $Str.Actions[$id]; $o = $Str.ActionOverrides[$k]; @{ Label = $(if ($o) { $o.Label } else { $d.Label }); Access = $(if ($o) { $o.Access } else { $d.Access }) } }
  # every model label must have a close counterpart: the verbs of the model labels that were reworded stay recognisable
  foreach ($k in $pairs.Keys) { $st, $id = $k -split '/'; $r = Resolve-Act $st $id; Check ($r.Label -and $r.Access) "state/action $k resolves to a label" }

  # ---------- guards ----------
  Section 'Guards (why an action is disabled)'
  $guardFn = (Get-Command Get-ActionGuard -CommandType Function).ScriptBlock.Ast
  $sw = @($guardFn.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))[0]
  Check ($null -ne $sw) 'Get-ActionGuard has a switch over action ids'
  $dynMap = @{ '$pr' = 'Get-RemoteUrlProblem'; '$_.Exception.Message' = 'Assert-GitDate' }
  $modelGuards = @()   # Action, Literal | Dynamic
  foreach ($c in $sw.Clauses) {
    $aid = "$($c.Item1.Value)"
    foreach ($r in @($c.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst] }, $true))) {
      $expr = $null; $pl = $r.Pipeline
      if ($pl -is [System.Management.Automation.Language.PipelineAst] -and $pl.PipelineElements.Count -eq 1 -and $pl.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) { $expr = $pl.PipelineElements[0].Expression }
      if ($expr -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $modelGuards += [pscustomobject]@{ Action = $aid; Literal = $expr.Value; Dynamic = $null } }
      else {
        $txt = if ($expr) { $expr.Extent.Text } else { $r.Extent.Text }
        if ($dynMap.ContainsKey($txt)) { $modelGuards += [pscustomobject]@{ Action = $aid; Literal = $null; Dynamic = $dynMap[$txt] } }
        else { Check $false "guard of $aid returns '$txt', which the checker does not know how to cover" }
      }
    }
  }
  "  $(@($modelGuards | Where-Object Literal).Count) literal guard texts and $(@($modelGuards | Where-Object Dynamic).Count) dynamic ones in the model"
  foreach ($g in $modelGuards) {
    if ($g.Literal) {
      $hits = @($Str.Guards | Where-Object { $_.Action -eq $g.Action -and $_.Match -and $g.Literal -match $_.Match })
      Check ($hits.Count -eq 1) "guard '$($g.Literal)' of $($g.Action) is covered by exactly one entry in Guards (found $($hits.Count))"
    } else {
      $hits = @($Str.Guards | Where-Object { $_.Action -eq $g.Action -and $_.Dynamic -eq $g.Dynamic })
      Check ($hits.Count -eq 1) "dynamic guard ($($g.Dynamic)) of $($g.Action) is covered by exactly one entry in Guards (found $($hits.Count))"
    }
  }
  $seenKeys = @{}
  foreach ($e in $Str.Guards) {
    Check ($e.Action -in $ids) "Guards entry for unknown action $($e.Action)"
    Check ($e.Key -and $e.Why) "Guards entry $($e.Action)/$($e.Key) has Key and Why"
    Check (-not $seenKeys.ContainsKey("$($e.Action)/$($e.Key)")) "Guards key $($e.Action)/$($e.Key) is unique"; $seenKeys["$($e.Action)/$($e.Key)"] = $true
    if ($e.Match) { Check (@($modelGuards | Where-Object { $_.Action -eq $e.Action -and $_.Literal -and $_.Literal -match $e.Match }).Count -ge 1) "Guards entry $($e.Action)/$($e.Key) matches nothing in the model any more" }
    elseif ($e.Dynamic) { Check (@($modelGuards | Where-Object { $_.Action -eq $e.Action -and $_.Dynamic -eq $e.Dynamic }).Count -ge 1) "Guards entry $($e.Action)/$($e.Key) refers to a dynamic guard the model no longer has" }
    else { Check $false "Guards entry $($e.Action)/$($e.Key) needs Match or Dynamic" }
  }
  # the texts those dynamic guards come from
  $urlFn = (Get-Command Get-RemoteUrlProblem -CommandType Function).ScriptBlock.Ast
  $urlLits = @($urlFn.FindAll({ param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst] }, $true) | ForEach-Object { $x = $_.Pipeline.PipelineElements[0]; if ($x -is [System.Management.Automation.Language.CommandExpressionAst] -and $x.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $x.Expression.Value } })
  Check ($urlLits.Count -ge 5) "found the address problems in Get-RemoteUrlProblem ($($urlLits.Count))"
  foreach ($t in $urlLits) { Check (@($Str.AddressProblems | Where-Object { $t -match $_.Match }).Count -eq 1) "address problem '$($t.Substring(0, [Math]::Min(50, $t.Length)))...' has exactly one entry in AddressProblems" }
  foreach ($e in $Str.AddressProblems) { Check (@($urlLits | Where-Object { $_ -match $e.Match }).Count -ge 1) "AddressProblems entry $($e.Key) matches nothing in the model any more" }
  $dateLits = @()
  foreach ($fn in 'Assert-GitDate', 'Parse-Date') {
    $ast = (Get-Command $fn -CommandType Function).ScriptBlock.Ast
    $dateLits += @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ThrowStatementAst] }, $true) | ForEach-Object { $x = $_.Pipeline.PipelineElements[0]; if ($x -is [System.Management.Automation.Language.CommandExpressionAst] -and $x.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $x.Expression -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { $x.Expression.Value } })
  }
  Check ($dateLits.Count -ge 4) "found the date errors in Assert-GitDate and Parse-Date ($($dateLits.Count))"
  foreach ($t in $dateLits) { Check (@($Str.Dates.Errors | Where-Object { $_.Match -and $t -match $_.Match }).Count -ge 1) "date error '$($t.Substring(0, [Math]::Min(50, $t.Length)))...' has an entry in Dates.Errors" }
  foreach ($e in $Str.Dates.Errors) { if ($e.Match) { Check (@($dateLits | Where-Object { $_ -match $e.Match }).Count -ge 1) "Dates.Errors entry $($e.Key) matches nothing in the model any more" } }
  # smoke test: real guards produce texts that Guards covers
  $f0 = [pscustomobject](New-WorkflowFacts)
  foreach ($case in @(@('Undo', $f0, @{}), @('Commit', $f0, @{ Message = 'x'; All = $true }), @('Publish', $f0, @{}), @('SaveIdentity', $f0, @{ Name = 'a'; Email = 'bad' }), @('ChooseAccount', $f0, @{ Account = '!' }), @('ApplyEdits', $f0, @{}))) {
    $why = Get-ActionGuard $case[0] $case[1] $case[2]
    Check ($why -and @($Str.Guards | Where-Object { $_.Action -eq $case[0] -and $_.Match -and $why -match $_.Match }).Count -eq 1) "live guard of $($case[0]) ('$why') maps to a Guards entry"
  }

  # ---------- error classes ----------
  Section 'Error classes'
  $classNames = @($script:WfErrorClasses | ForEach-Object { $_.Class }) + 'other'
  foreach ($c in $classNames) {
    Check ($Str.ErrorClasses.ContainsKey($c)) "error class $c has strings"
    if (-not $Str.ErrorClasses.ContainsKey($c)) { continue }
    $e = $Str.ErrorClasses[$c]
    foreach ($f in 'Headline', 'Happened', 'Todo', 'Details') { Check ($e[$f] -is [string] -and $e[$f]) "error class $c has $f" }
    foreach ($f in 'Happened', 'Todo') {
      $v = "$($e[$f])"; $stripped = $v -replace "'[^']*'", 'X'
      Check ($v.EndsWith('.') -and @([regex]::Matches($stripped, '[.!?](\s|$)')).Count -eq 1) "error class $c $f is exactly one sentence"
    }
    Check ($e.Headline.EndsWith('.')) "error class $c Headline ends with a period"
  }
  foreach ($c in $Str.ErrorClasses.Keys) { Check ($c -in $classNames) "strings for unknown error class $c" }
  # the 'what to do' names the button that fixes it
  foreach ($ec in $script:WfErrorClasses) {
    if ($ec.Recovery -in 'Recheck') { continue }
    $variants = @($Str.Actions[$ec.Recovery].Label) + @($Str.ActionOverrides.Keys | Where-Object { $_ -like "*/$($ec.Recovery)" } | ForEach-Object { $Str.ActionOverrides[$_].Label })
    $todo = $Str.ErrorClasses[$ec.Class].Todo
    Check (@($variants | Where-Object { $todo.Contains("'$_'") }).Count -ge 1) "error class $($ec.Class): Todo names the recovery button '$($variants -join "' or '")'"
  }

  # ---------- dialogs ----------
  Section 'Dialogs'
  foreach ($d in 'ApplyEdits', 'ReplaceRemote', 'ReplaceRemoteOthers', 'DiscardRemote', 'Undo', 'UndoForce', 'DiscardEdits', 'LeaveWithPending', 'ExitSetup', 'TrustProject', 'RiskyFiles') { Check ($Str.Dialogs.ContainsKey($d)) "dialog $d exists" }
  $badLabels = 'OK', 'Yes', 'No', 'Ok', 'Okay'
  foreach ($dn in $Str.Dialogs.Keys) {
    $d = $Str.Dialogs[$dn]
    foreach ($f in 'Title', 'Heading', 'Buttons', 'Default') { Check ($d.ContainsKey($f) -and $d[$f]) "dialog $dn has $f" }
    if (-not ($d.ContainsKey('Body') -or $d.ContainsKey('Lines'))) { Check $false "dialog $dn has a Body" }
    foreach ($x in @($d.Uses | Where-Object { $_ })) { Check ($x -in $allowedGlobal) "dialog $dn Uses unknown placeholder $x" }
    $btns = @($d.Buttons); $keys = @{}
    Check (@($btns | Where-Object { $_.Role -eq 'cancel' }).Count -eq 1) "dialog $dn has exactly one cancel button (Esc)"
    Check (@($btns | Where-Object { $_.Id -eq $d.Default }).Count -eq 1) "dialog $dn default button '$($d.Default)' exists"
    $def = $btns | Where-Object { $_.Id -eq $d.Default } | Select-Object -First 1
    if ($d.Danger) { Check ($def -and $def.Role -ne 'accept') "dialog $dn is risky, so its default button must be the safe one, not the accept button" }
    foreach ($b in $btns) {
      foreach ($lab in (Variants $b.Label)) {
        Check ((Strip $lab) -notin $badLabels) "dialog $dn button '$lab' needs an explicit verb (not OK / Yes / No)"
        if ($b.Role -ne 'cancel' -or $lab -ne 'Cancel') { Check ($lab -match '^[^&]*(&[A-Za-z0-9])?[^&]*$') "dialog $dn button '$lab' has at most one access key" }
      }
      if ($b.Requires) { Check ($d.ContainsKey($b.Requires)) "dialog $dn button $($b.Id) requires $($b.Requires), which is missing" }
      # keys must match across the One/Other variants and be unique in the dialog
      $kk = @(Variants $b.Label | ForEach-Object { AccessKey $_ } | Sort-Object -Unique)
      Check ($kk.Count -le 1) "dialog $dn button $($b.Id) uses different access keys for singular and plural"
      if ($kk.Count -eq 1) { Check (-not $keys.ContainsKey($kk[0])) "dialog ${dn}: access key '$($kk[0])' is used twice"; $keys[$kk[0]] = $true }
    }
    if ($d.Checkbox) { $ck = AccessKey $d.Checkbox; if ($ck) { Check (-not $keys.ContainsKey($ck)) "dialog ${dn}: checkbox access key '$ck' collides with a button" } }
    if ($d.Danger -and @($btns | Where-Object { $_.Requires }).Count -eq 0 -and $dn -in 'ReplaceRemoteOthers', 'DiscardRemote', 'UndoForce') { Check $false "dialog $dn needs a confirmation checkbox on its destructive button" }
  }
  foreach ($dn in 'ReplaceRemoteOthers', 'DiscardRemote') { Check ($Str.Dialogs[$dn].Buttons | Where-Object { $_.Id -eq 'GetFirst' } | Where-Object { (Strip $_.Label) -ceq $Str.Actions.Sync.Label }) "dialog $dn offers the safe alternative with the same words as the Sync action" }
  foreach ($dn in 'LeaveWithPending') { foreach ($ln in 'Changes', 'Edits', 'Unpublished') { Check (IsPlural $Str.Dialogs[$dn].Lines[$ln]) "dialog $dn line $ln has singular and plural" } }

  # ---------- quoted button names must exist ----------
  Section 'Button names quoted in text exist'
  $quoteRx = "(?<![\w])'((?:[^']|(?<=\w)'(?=\w))+?)'(?!\w)"
  function Quoted([string]$s) { @([regex]::Matches($s, $quoteRx) | ForEach-Object { $_.Groups[1].Value }) }
  $chromeNames = @('Next', 'Back', 'Cancel', 'Finish', 'Close', 'Help') + @($Str.TechInfo.Show, $Str.TechInfo.Hide, $Str.TechInfo.Copy)
  $everyLabel = @($Str.Actions.Values | ForEach-Object { $_.Label }) + @($Str.ActionOverrides.Values | ForEach-Object { $_.Label }) + $chromeNames
  foreach ($s in $stateNames) {
    $own = @($script:WfActions[$s] | ForEach-Object { (Resolve-Act $s $_.Id).Label }) + $chromeNames
    foreach ($f in 'Help', 'Instruction') { foreach ($q in (Quoted $Str.States[$s][$f])) { Check ($q -in $own) "state $s $f quotes '$q', which is not a button of that page" } }
    if ($s -ne 'InSync') { Check (@(Quoted $Str.States[$s].Instruction).Count -ge 1) "state $s Instruction names the button to click" }
  }
  foreach ($l in $leaves) {
    if (-not (IsPrimary $l.Path) -or $l.Path -match '^States\.') { continue }
    foreach ($q in (Quoted $l.Value)) { Check ($q -in $everyLabel -or $q -in @($Str.Dialogs.Values | ForEach-Object { $_.Buttons } | ForEach-Object { Variants $_.Label } | ForEach-Object { Strip $_ })) "$($l.Path) quotes '$q', which is not a button anywhere" }
  }

  # ---------- reading level ----------
  Section 'Reading level (plain words, short sentences)'
  function Syl([string]$w) { $w = ($w.ToLowerInvariant() -replace '[^a-z]', ''); if ($w.Length -le 3) { return 1 }; $w = $w -replace '(?:[^laeiouy]es|ed|[^laeiouy]e)$', '' -replace '^y', ''; [Math]::Max(1, [regex]::Matches($w, '[aeiouy]{1,2}').Count) }
  function Grade([string]$t) {
    $t = $t -replace "'[^']*'", 'it' -replace '\{\w+\}', 'it'
    $sents = @($t -split '(?<=[.!?])\s+' | Where-Object { $_ -match '\w' }); $words = @($t -split '\s+' | Where-Object { $_ -match '[A-Za-z]' })
    if (-not $words.Count -or -not $sents.Count) { return 0 }
    $syl = 0; foreach ($w in $words) { $syl += (Syl $w) }
    [pscustomobject]@{ Grade = (0.39 * $words.Count / $sents.Count + 11.8 * $syl / $words.Count - 15.59); MaxWords = ($sents | ForEach-Object { @($_ -split '\s+').Count } | Measure-Object -Maximum).Maximum }
  }
  $grades = @()
  foreach ($s in $stateNames) {
    $g = Grade $Str.States[$s].Help; $grades += $g.Grade
    Check ($g.MaxWords -le 26) "state $s Help has a sentence of $($g.MaxWords) words (max 26)"
    Check ($g.Grade -le 9.0) ("state $s Help reads at grade {0:N1} (max 9.0)" -f $g.Grade)
  }
  $avg = ($grades | Measure-Object -Average).Average
  Check ($avg -le 7.0) ("average reading grade of the state help texts is {0:N1} (max 7.0)" -f $avg)
  "  state help: average grade {0:N1}, worst {1:N1}" -f $avg, ($grades | Measure-Object -Maximum).Maximum
  foreach ($l in $leaves) { if ($l.Path -match '^(Dialogs\.\w+\.Body|Welcome\.(Intro|Explain)|FirstRun\.\w+\.Body)') { $g = Grade $l.Value; Check ($g.MaxWords -le 32) "$($l.Path) has a sentence of $($g.MaxWords) words (max 32)" } }

  # ---------- access keys ----------
  Section 'Access keys are unique on every page'
  $chromeKeys = @(AccessKey $Str.Chrome.Buttons.Back; AccessKey $Str.Chrome.Buttons.Next)
  Check ($chromeKeys.Count -eq 2 -and $chromeKeys[0] -ne $chromeKeys[1]) 'Back and Next have access keys (B and N)'
  foreach ($b in 'Cancel', 'Finish') { Check ($Str.Chrome.Buttons[$b] -notmatch '&') "$b has no access key (Esc / Enter do that job)" }
  function Dupes($list) { @($list | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) }
  function PageKeys([string]$page) {
    $ks = @(); foreach ($c in $Str.Pages[$page].Controls.GetEnumerator()) {
      $k = AccessKey $c.Value; Check ($k -and @([regex]::Matches($c.Value, '&[A-Za-z0-9]')).Count -eq 1) "Pages.$page.$($c.Key) has exactly one access key"
      if ($c.Key -like '*Toggled') { $base = $c.Key -replace 'Toggled$', ''; Check ((AccessKey $Str.Pages[$page].Controls[$base]) -eq $k) "Pages.$page.$($c.Key) keeps the access key of $base"; continue }
      $ks += $k
    }
    $ks
  }
  foreach ($pg in $Str.Pages.Keys) { $d = Dupes (@($chromeKeys) + @(PageKeys $pg)); Check ($d.Count -eq 0) "page ${pg}: access key(s) used twice: $($d -join ', ')" }
  foreach ($s in $stateNames) {
    $pg = $Str.States[$s].Page
    $ak = @($script:WfActions[$s] | ForEach-Object { AccessKey (Resolve-Act $s $_.Id).Access })
    $d = Dupes (@($chromeKeys) + @(PageKeys $pg) + $ak); Check ($d.Count -eq 0) "state $s (page $pg): access key(s) used twice: $($d -join ', ')"
    $d2 = Dupes (@($chromeKeys) + @(PageKeys 'Problem') + $ak); Check ($d2.Count -eq 0) "state $s with the problem box: access key(s) used twice: $($d2 -join ', ')"
  }

  # ---------- the remaining required content ----------
  Section 'Required content'
  Check ($Str.Progress.Steps.Count -ge 6) 'progress has the publish steps'
  foreach ($need in 'CheckSetup', 'SaveFiles', 'Publish', 'Verify') { Check (@($Str.Progress.Steps | Where-Object { $_.Id -eq $need }).Count -eq 1) "progress step $need exists" }
  foreach ($st in $Str.Progress.Steps) { foreach ($f in 'Running', 'Done', 'Failed') { Check ($st[$f]) "progress step $($st.Id) has $f" } }
  Check (@($Str.Dates.Presets | ForEach-Object { $_.Label }) -join '|' -eq 'Now|Yesterday|1 week ago|1 month ago|Pick a date...') 'date presets are Now, Yesterday, 1 week ago, 1 month ago, Pick a date...'
  foreach ($p in $Str.Dates.Presets) { Check ($p.Id -and $p.Description) "date preset $($p.Label) has an id and a description" }
  foreach ($k in 'SecretName', 'SecretContent', 'BuildFile', 'TooBig', 'Linked', 'Separate') { Check ($Str.FileChecklist.Reasons.ContainsKey($k)) "file reason $k exists" }
  foreach ($k in 'NoProject', 'Branch', 'Unpublished', 'Unsaved', 'InSync', 'Newer', 'SignedIn', 'SignedOut', 'Offline') { Check ($Str.StatusBar.ContainsKey($k)) "status bar text $k exists" }
  foreach ($k in 'NoSavePoints', 'NoChangedFiles', 'NoRecentFolders', 'NoAccounts', 'NoEdits', 'NoUndo') { Check ($Str.EmptyStates.ContainsKey($k)) "empty state $k exists" }
  foreach ($k in 'Published', 'Saved', 'EditsApplied', 'GotLatest', 'UndoDone', 'Replaced', 'Connected') { Check ($Str.Success.Variants.ContainsKey($k)) "success variant $k exists" }
  Check ($Str.Success.NextSteps.Count -ge 3) 'success page suggests next steps'
  Check ($Str.Welcome.Heading -eq 'Welcome to backd8' -and $Str.Success.Heading -eq 'backd8 is complete') 'Welcome and complete headings use the Setup wording'
  Check ((@($Str.Help.F1.Shortcuts | ForEach-Object { $_.Keys }) -join ' ') -match 'F1' -and (@($Str.Help.F1.Shortcuts).Count -ge 8)) 'F1 help lists the keyboard shortcuts'
  Check ($Str.TechInfo.Show -eq 'Show details' -and $Str.TechInfo.Copy -eq 'Copy details') "'Show details' and 'Copy details' labels"
} finally {
  foreach ($ev in $saved.Keys) { [Environment]::SetEnvironmentVariable($ev, $saved[$ev]) }
  Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

''
if ($script:fails.Count) { "strings-check: $($script:fails.Count) problem(s) in $($script:n) checks"; exit 1 }
"strings-check: all $($script:n) checks passed"
