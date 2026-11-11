# backd8 workflow engine: a deterministic finite state machine for "choose folder -> edit -> publish".
# Dot-sourced by lib.ps1. The window (and the CLI `state` command) are views of THIS model, so labels, enabled buttons and next steps
# can never disagree with what the engine will accept.
#
#   Get-WorkflowFacts   -> observable facts about the project (every probe is guarded: a failing probe becomes a fact, never a crash)
#   Resolve-WorkflowState (PURE) -> exactly one named state, by a fixed priority list (deterministic and total)
#   Get-WorkflowActions (PURE) -> the actions of that state with Enabled / Why-not (guards = prerequisites)
#   Get-WorkflowPlan    -> state + plain-language title/help + actions + recommended action
#   Invoke-WorkflowAction -> re-derives the state, re-checks the guard, runs the engine call, re-derives the state again and returns
#                            the new state plus recovery actions: every failure lands in a state that has a way forward
#   Test-WorkflowModel  -> exhaustive proof: determinism, totality, no dead ends, every state can reach InSync, every error class has a recovery

# ---------- states ----------
# Terminal-ish goal: InSync. Everything else has at least one forward or recovery action.
$script:WfStates = [ordered]@{
  NoFolder        = @{ Title = 'Choose your project';                  Help = 'Pick the folder that holds your work. backd8 handles everything else from there.' }
  FolderNotFound  = @{ Title = 'That folder does not exist';           Help = 'The folder was moved, renamed or deleted. Choose it again.' }
  GitMissing      = @{ Title = 'Git is not installed';                 Help = 'backd8 uses Git, the free tool that keeps your project history. Install it once, then press Check again.' }
  NotAProject     = @{ Title = 'This folder is not a project yet';     Help = 'Turning a folder into a project adds a hidden .git folder. Your files are not changed.' }
  Untrusted       = @{ Title = 'This project can run programs';        Help = 'Its hidden git settings can start programs on your PC. Only continue if you made this folder or trust where it came from.' }
  NoIdentity      = @{ Title = 'Who are you?';                         Help = 'Git writes your name and email into every commit. Tell it once; it is saved for all your projects.' }
  Blocked         = @{ Title = 'Another git operation is unfinished';  Help = 'A merge, rebase or cherry-pick is half done in this folder. Finish or abort it in a git tool, then check again.' }
  Detached        = @{ Title = 'You are not on a branch';              Help = 'New commits made now are easy to lose. Switch to a branch first.' }
  EmptyProject    = @{ Title = 'Nothing saved yet';                    Help = 'This project has no files to save and no commits. Add some files to the folder, then check again.' }
  ChangesPending  = @{ Title = 'You have changes to save';             Help = 'Choose the files, write what you changed and pick the date. backd8 saves them as one commit.' }
  EditsPending    = @{ Title = 'Your edits are waiting to be applied'; Help = 'You changed older commits. Apply writes the changes into your project; a backup is kept so you can undo.' }
  NoRemote        = @{ Title = 'Connect to GitHub';                    Help = 'Create an EMPTY repository at github.com/new and paste its address here.' }
  GitHubAhead     = @{ Title = 'GitHub has newer changes';             Help = 'Someone (or another PC of yours) published changes your project does not have. Get them first.' }
  NeedsSync       = @{ Title = 'Get GitHub''s newer work first';       Help = 'GitHub holds work by other people (or from another computer) that exists nowhere on this PC. Get it before publishing.' }
  NeedsReplace    = @{ Title = 'Replace GitHub''s old version?';       Help = 'You changed commits that were already published. GitHub still has the old versions; publishing replaces them.' }
  NeedsSignIn     = @{ Title = 'Sign in to GitHub';                    Help = 'You are not signed in on this PC. Your browser opens once; Windows remembers you afterwards.' }
  ChooseAccount   = @{ Title = 'Which GitHub account?';                Help = 'Several GitHub accounts are saved on this PC. Choose the one this project should use.' }
  NoWriteAccess   = @{ Title = 'This account cannot publish here';     Help = 'You are signed in, but GitHub says this account may not write to the repository.' }
  RepoNotFound    = @{ Title = 'GitHub cannot find this repository';   Help = 'Check the address, or create an empty repository with exactly this name at github.com/new.' }
  SSORequired     = @{ Title = 'Single sign-on needed';                Help = 'Your organisation requires you to authorise your login for it on GitHub.' }
  HostKeyProblem  = @{ Title = 'SSH server not verified';              Help = 'SSH could not verify GitHub''s host key. Verify the fingerprint in a terminal, or use an https address.' }
  Offline         = @{ Title = 'Cannot reach GitHub';                  Help = 'Check your internet connection (or GitHub''s status page) and try again.' }
  ReadyToPublish  = @{ Title = 'Ready to publish';                     Help = 'Everything is saved. Publishing sends your project to GitHub.' }
  InSync          = @{ Title = 'Everything is saved and published';    Help = 'Your project and GitHub match. You can still change older commits or choose another folder.' }
}

# ---------- facts ----------
function New-WorkflowFacts { [ordered]@{
  FolderGiven = $false; FolderExists = $false; GitInstalled = $true; IsRepo = $false; Root = $null; Trusted = $true; RiskyKeys = @()
  IdentityOk = $true; InProgress = $false; Detached = $false; HasCommits = $false; Changes = 0; RiskyFiles = 0; TooBig = 0; NeedsIgnore = $false
  Linked = $false; Url = $null; Branch = $null; NoUpstream = $false; Ahead = 0; Behind = 0; RemoteOnly = 0; Others = 0; Backups = 0
  Access = 'Unknown'; AccessDetail = ''; EditsStaged = 0 } }

function Get-WorkflowFacts([string]$Path, [hashtable]$Ui = @{}, [switch]$CheckAccess, [switch]$Fetch) {
  $f = New-WorkflowFacts
  $f.GitInstalled = [bool](Test-GitInstalled)
  $f.FolderGiven = [bool]("$Path".Trim())
  if ($f.FolderGiven -and $f.GitInstalled) {
    try { $f.FolderExists = [bool](Test-Path -LiteralPath $Path -PathType Container) } catch { $f.FolderExists = $false }
    if ($f.FolderExists) {
      try {
        $t = Test-IsRepo $Path; $f.IsRepo = [bool]$t.IsRepo; $f.Root = $t.Root
        if ($f.IsRepo) {
          $risk = @(Get-RiskyRepoConfig $t.Root); $f.RiskyKeys = $risk; $f.Trusted = (-not $risk.Count) -or (Test-RepoTrusted $t.Root)
          if ($f.Trusted) { Get-WorkflowRepoFacts $f $t.Root $CheckAccess $Fetch }
        }
      } catch { $f.AccessDetail = "$($_.Exception.Message)" }
    }
  }
  foreach ($k in @($Ui.Keys)) { $f[$k] = $Ui[$k] }
  [pscustomobject]$f
}

# every probe below is isolated: a failure leaves the neutral default and is recorded, never thrown
function Get-WorkflowRepoFacts($f, [string]$root, [bool]$checkAccess, [bool]$fetch) {
  try { $f.IdentityOk = [bool](Get-GitIdentity $root).Ok } catch { }
  try {
    $g = (Git-Out $root @('rev-parse', '--absolute-git-dir')).Out | Select-Object -First 1
    foreach ($n in 'rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD') { if ($g -and (Test-Path -LiteralPath (Join-Path $g $n))) { $f.InProgress = $true } }
  } catch { }
  try { $f.Branch = Get-BranchName $root; $f.HasCommits = -not (Git-Out $root @('rev-parse', '--verify', '-q', 'HEAD')).Code; $f.Detached = (-not $f.Branch) -and $f.HasCommits } catch { }
  try {
    $ch = @(Get-WorkingChanges $root)
    $f.Changes = @($ch | Where-Object { -not $_.Noise -and $_.Kind -ne 'nested' }).Count
    $f.RiskyFiles = @($ch | Where-Object Risky).Count; $f.TooBig = @($ch | Where-Object { $_.SizeMB -gt $script:MaxFileMB }).Count
    $f.NeedsIgnore = (Get-GitignoreAdvice $root).Needed
  } catch { }
  try { $f.Backups = @(Get-Backups $root).Count } catch { }
  try {
    if ($f.Branch) {
      if ($fetch) { [void](Update-RemoteRefs $root) }
      $ps = Get-PushState $root
      $f.Linked = [bool]$ps.Url; $f.Url = $ps.Url; $f.NoUpstream = -not $ps.Upstream
      $f.Ahead = [int]$ps.Ahead; $f.Behind = [int]$ps.Behind; $f.RemoteOnly = [int]$ps.RemoteOnly; $f.Others = [int]$ps.OthersCommits
      if ($f.Linked -and $f.HasCommits -and $f.NoUpstream -and $null -eq $ps.Ahead) { $f.Ahead = 1 }   # never published: there is something to publish
    }
  } catch { }
  if ($checkAccess -and $f.Linked) {
    try {
      $a = Get-GitHubAccess $root
      $f.AccessDetail = $a.Detail
      $f.Access = if ($a.Transport -eq 'local') { 'Yes' }
        elseif ($a.CanPush -eq $true) { 'Yes' }
        elseif ($a.NeedsAccountChoice) { 'ChooseAccount' }
        elseif ($a.Problem -eq 'noaccess') { 'NoAccess' } elseif ($a.Problem -eq 'notfound') { 'NotFound' } elseif ($a.Problem -eq 'saml') { 'SSO' } elseif ($a.Problem -eq 'hostkey') { 'HostKey' }
        elseif ($a.CanPush -eq $false) { 'NotSignedIn' }
        elseif ($a.Problem -in 'network', 'temporary') { 'Offline' } else { 'Unknown' }
    } catch { $f.Access = 'Unknown' }
  }
}

# ---------- the state function (PURE: facts in, one state name out) ----------
function Resolve-WorkflowState($f) {
  if (-not $f.GitInstalled) { return 'GitMissing' }
  if (-not $f.FolderGiven) { return 'NoFolder' }
  if (-not $f.FolderExists) { return 'FolderNotFound' }
  if (-not $f.IsRepo) { return 'NotAProject' }
  if (-not $f.Trusted) { return 'Untrusted' }
  if (-not $f.IdentityOk) { return 'NoIdentity' }
  if ($f.InProgress) { return 'Blocked' }
  if ($f.Detached) { return 'Detached' }
  if ($f.Changes -gt 0) { return 'ChangesPending' }
  if ($f.EditsStaged -gt 0) { return 'EditsPending' }
  if (-not $f.HasCommits) { return 'EmptyProject' }
  if (-not $f.Linked) { return 'NoRemote' }
  if ($f.Behind -gt 0) {
    if ($f.Ahead -eq 0) { return 'GitHubAhead' }
    if ($f.RemoteOnly -gt 0 -or $f.Others -gt 0) { return 'NeedsSync' }
    return 'NeedsReplace'
  }
  $publishing = ($f.Ahead -gt 0)
  if ($publishing) {
    switch ($f.Access) {
      'NotSignedIn'   { return 'NeedsSignIn' }
      'ChooseAccount' { return 'ChooseAccount' }
      'NoAccess'      { return 'NoWriteAccess' }
      'NotFound'      { return 'RepoNotFound' }
      'SSO'           { return 'SSORequired' }
      'HostKey'       { return 'HostKeyProblem' }
      'Offline'       { return 'Offline' }
    }
    return 'ReadyToPublish'
  }
  'InSync'
}

# ---------- actions per state: Id, label, kind, possible next states ----------
# Kinds: engine (changes something), nav (UI only), info (shows an instruction, then the user re-checks).
$script:WfActions = [ordered]@{
  NoFolder       = @( @{ Id = 'ChooseFolder'; Label = 'Choose a folder...'; Kind = 'nav'; Next = @('NotAProject', 'Untrusted', 'NoIdentity', 'ChangesPending', 'NoRemote', 'InSync', 'EmptyProject', 'ReadyToPublish', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'Blocked', 'Detached', 'FolderNotFound', 'EditsPending') } )
  FolderNotFound = @( @{ Id = 'ChooseFolder'; Label = 'Choose another folder...'; Kind = 'nav'; Next = @('NoFolder', 'NotAProject', 'ChangesPending', 'InSync', 'NoRemote') }, @{ Id = 'Recheck'; Label = 'Check again'; Kind = 'nav'; Next = @('FolderNotFound', 'NotAProject', 'ChangesPending', 'InSync', 'NoRemote') } )
  GitMissing     = @( @{ Id = 'ShowGitInstall'; Label = 'How to install Git'; Kind = 'info'; Next = @('GitMissing') }, @{ Id = 'Recheck'; Label = 'Check again'; Kind = 'nav'; Next = @('GitMissing', 'NoFolder') } )
  NotAProject    = @( @{ Id = 'InitProject'; Label = 'Turn this folder into a project'; Kind = 'engine'; Next = @('NoIdentity', 'EmptyProject', 'ChangesPending', 'NoRemote') }, @{ Id = 'ChooseFolder'; Label = 'Choose a different folder...'; Kind = 'nav'; Next = @('NoFolder') } )
  Untrusted      = @( @{ Id = 'Trust'; Label = 'I made this project / I trust it'; Kind = 'engine'; Next = @('NoIdentity', 'ChangesPending', 'NoRemote', 'InSync', 'EmptyProject', 'ReadyToPublish', 'Blocked', 'Detached', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'EditsPending') }, @{ Id = 'ChooseFolder'; Label = 'Choose another folder...'; Kind = 'nav'; Next = @('NoFolder') } )
  NoIdentity     = @( @{ Id = 'SaveIdentity'; Label = 'Save my name and email'; Kind = 'engine'; Next = @('ChangesPending', 'EmptyProject', 'NoRemote', 'InSync', 'ReadyToPublish', 'Blocked', 'Detached', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'EditsPending') } )
  Blocked        = @( @{ Id = 'ShowFinishOperation'; Label = 'How to finish or abort it'; Kind = 'info'; Next = @('Blocked') }, @{ Id = 'Recheck'; Label = 'Check again'; Kind = 'nav'; Next = @('Blocked', 'ChangesPending', 'InSync', 'NoRemote', 'ReadyToPublish', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'Detached', 'EditsPending', 'EmptyProject') }, @{ Id = 'ChooseFolder'; Label = 'Choose another folder...'; Kind = 'nav'; Next = @('NoFolder') } )
  Detached       = @( @{ Id = 'ShowSwitchBranch'; Label = 'How to switch to a branch'; Kind = 'info'; Next = @('Detached') }, @{ Id = 'Recheck'; Label = 'Check again'; Kind = 'nav'; Next = @('Detached', 'ChangesPending', 'InSync', 'NoRemote', 'ReadyToPublish', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'EditsPending', 'EmptyProject') }, @{ Id = 'ChooseFolder'; Label = 'Choose another folder...'; Kind = 'nav'; Next = @('NoFolder') } )
  EmptyProject   = @( @{ Id = 'Recheck'; Label = 'I added files - check again'; Kind = 'nav'; Next = @('EmptyProject', 'ChangesPending') }, @{ Id = 'ChooseFolder'; Label = 'Choose another folder...'; Kind = 'nav'; Next = @('NoFolder') } )
  ChangesPending = @( @{ Id = 'Commit'; Label = 'Save these files as a commit'; Kind = 'engine'; Next = @('NoRemote', 'ReadyToPublish', 'InSync', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'ChangesPending', 'EditsPending', 'Blocked') }, @{ Id = 'AddGitignore'; Label = 'Leave out build and editor files'; Kind = 'engine'; Next = @('ChangesPending', 'NoRemote', 'ReadyToPublish', 'InSync') }, @{ Id = 'ChooseFolder'; Label = 'Choose another folder...'; Kind = 'nav'; Next = @('NoFolder') } )
  EditsPending   = @( @{ Id = 'ApplyEdits'; Label = 'Apply my edits'; Kind = 'engine'; Next = @('NoRemote', 'ReadyToPublish', 'NeedsReplace', 'InSync', 'GitHubAhead', 'NeedsSync', 'EditsPending') }, @{ Id = 'DiscardEdits'; Label = 'Discard my edits'; Kind = 'nav'; Next = @('NoRemote', 'ReadyToPublish', 'InSync', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'ChangesPending') } )
  NoRemote       = @( @{ Id = 'ConnectRemote'; Label = 'Connect'; Kind = 'engine'; Next = @('ReadyToPublish', 'InSync', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'NoRemote') }, @{ Id = 'OpenNewRepoPage'; Label = 'Open github.com/new'; Kind = 'nav'; Next = @('NoRemote') } )
  GitHubAhead    = @( @{ Id = 'Sync'; Label = 'Get the latest from GitHub'; Kind = 'engine'; Next = @('ReadyToPublish', 'InSync', 'GitHubAhead', 'NeedsReplace', 'NeedsSync', 'ChangesPending') } )
  NeedsSync      = @( @{ Id = 'Sync'; Label = 'Get the latest from GitHub'; Kind = 'engine'; Next = @('ReadyToPublish', 'InSync', 'NeedsReplace', 'NeedsSync', 'GitHubAhead') }, @{ Id = 'Undo'; Label = 'Undo my last change'; Kind = 'engine'; Next = @('NeedsSync', 'GitHubAhead', 'ReadyToPublish', 'InSync') } )
  NeedsReplace   = @( @{ Id = 'ReplaceRemote'; Label = 'Replace GitHub''s version...'; Kind = 'engine'; Next = @('InSync', 'NeedsSignIn', 'ChooseAccount', 'NoWriteAccess', 'RepoNotFound', 'SSORequired', 'HostKeyProblem', 'Offline', 'NeedsSync', 'NeedsReplace', 'GitHubAhead') }, @{ Id = 'Undo'; Label = 'Undo my last change'; Kind = 'engine'; Next = @('GitHubAhead', 'ReadyToPublish', 'InSync', 'NeedsSync', 'NeedsReplace') }, @{ Id = 'Sync'; Label = 'Get the latest from GitHub'; Kind = 'engine'; Next = @('NeedsReplace', 'InSync', 'ReadyToPublish', 'NeedsSync') } )
  NeedsSignIn    = @( @{ Id = 'SignIn'; Label = 'Sign in to GitHub'; Kind = 'engine'; Next = @('ReadyToPublish', 'InSync', 'ChooseAccount', 'NoWriteAccess', 'RepoNotFound', 'SSORequired', 'HostKeyProblem', 'Offline', 'NeedsSignIn') }, @{ Id = 'ChangeAddress'; Label = 'Change the GitHub address'; Kind = 'engine'; Next = @('ReadyToPublish', 'NeedsSignIn', 'NoRemote', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'InSync') } )
  ChooseAccount  = @( @{ Id = 'ChooseAccount'; Label = 'Use this account'; Kind = 'engine'; Next = @('ReadyToPublish', 'NeedsSignIn', 'NoWriteAccess', 'RepoNotFound', 'ChooseAccount', 'InSync') }, @{ Id = 'SignIn'; Label = 'Sign in with another account'; Kind = 'engine'; Next = @('ReadyToPublish', 'ChooseAccount', 'NeedsSignIn', 'NoWriteAccess', 'InSync') } )
  NoWriteAccess  = @( @{ Id = 'ChooseAccount'; Label = 'Use a different account'; Kind = 'engine'; Next = @('ReadyToPublish', 'NoWriteAccess', 'NeedsSignIn', 'RepoNotFound', 'ChooseAccount', 'InSync') }, @{ Id = 'ChangeAddress'; Label = 'Publish to a different repository'; Kind = 'engine'; Next = @('ReadyToPublish', 'NoWriteAccess', 'NeedsSignIn', 'RepoNotFound', 'NoRemote', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'InSync') } )
  RepoNotFound   = @( @{ Id = 'ChangeAddress'; Label = 'Fix the GitHub address'; Kind = 'engine'; Next = @('ReadyToPublish', 'RepoNotFound', 'NeedsSignIn', 'NoRemote', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'InSync') }, @{ Id = 'OpenNewRepoPage'; Label = 'Open github.com/new'; Kind = 'nav'; Next = @('RepoNotFound') }, @{ Id = 'Recheck'; Label = 'I created it - check again'; Kind = 'nav'; Next = @('ReadyToPublish', 'RepoNotFound', 'NeedsSignIn', 'InSync') } )
  SSORequired    = @( @{ Id = 'ShowSsoHelp'; Label = 'How to authorise single sign-on'; Kind = 'info'; Next = @('SSORequired') }, @{ Id = 'Recheck'; Label = 'I authorised it - check again'; Kind = 'nav'; Next = @('ReadyToPublish', 'SSORequired', 'NeedsSignIn', 'InSync') } )
  HostKeyProblem = @( @{ Id = 'ShowHostKeyHelp'; Label = 'How to verify the SSH host key'; Kind = 'info'; Next = @('HostKeyProblem') }, @{ Id = 'ChangeAddress'; Label = 'Use an https address instead'; Kind = 'engine'; Next = @('ReadyToPublish', 'HostKeyProblem', 'NeedsSignIn', 'InSync') }, @{ Id = 'Recheck'; Label = 'Check again'; Kind = 'nav'; Next = @('ReadyToPublish', 'HostKeyProblem', 'InSync') } )
  Offline        = @( @{ Id = 'Recheck'; Label = 'Try again'; Kind = 'nav'; Next = @('ReadyToPublish', 'Offline', 'NeedsSignIn', 'InSync', 'GitHubAhead', 'NeedsSync', 'NeedsReplace') } )
  ReadyToPublish = @( @{ Id = 'Publish'; Label = 'Publish to GitHub'; Kind = 'engine'; Next = @('InSync', 'GitHubAhead', 'NeedsSync', 'NeedsReplace', 'NeedsSignIn', 'ChooseAccount', 'NoWriteAccess', 'RepoNotFound', 'SSORequired', 'HostKeyProblem', 'Offline', 'ReadyToPublish') }, @{ Id = 'Undo'; Label = 'Undo my last change'; Kind = 'engine'; Next = @('ReadyToPublish', 'InSync', 'NoRemote') } )
  InSync         = @( @{ Id = 'EditOlder'; Label = 'Change an older commit...'; Kind = 'nav'; Next = @('EditsPending', 'InSync') }, @{ Id = 'ChooseFolder'; Label = 'Choose another folder...'; Kind = 'nav'; Next = @('NoFolder') }, @{ Id = 'Undo'; Label = 'Undo my last change'; Kind = 'engine'; Next = @('ReadyToPublish', 'InSync', 'NoRemote') } )
}

# Guards = prerequisites. Return $null when the action may run, otherwise the plain-language reason it may not.
function Get-ActionGuard([string]$id, $f, [hashtable]$p) {
  switch ($id) {
    'InitProject' { if (-not $f.FolderExists) { return 'Choose an existing folder first.' }; if ($f.IsRepo) { return 'This folder is already a project.' }; if ($p.Url) { $pr = Get-RemoteUrlProblem $p.Url; if ($pr) { return $pr } } }
    'Trust' { if (-not $f.IsRepo) { return 'Not a project.' } }
    'SaveIdentity' { if (-not "$($p.Name)".Trim()) { return 'Type your name first.' }; if ("$($p.Email)" -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return 'Type a valid email address, for example you@example.com.' } }
    'Commit' {
      if ($f.Changes -lt 1) { return 'Nothing has changed since your last save.' }
      if (-not "$($p.Message)".Trim()) { return 'Write what you changed first.' }
      if (-not $p.All -and -not @($p.Files).Count) { return 'Tick at least one file.' }
      if ($p.Date) { try { Assert-GitDate ([datetime]$p.Date) } catch { return $_.Exception.Message } }
    }
    'AddGitignore' { if (-not $f.NeedsIgnore) { return 'Nothing to leave out.' } }
    'ApplyEdits' { if ($f.EditsStaged -lt 1 -or -not $p.Edits -or -not $p.Edits.Count) { return 'You have not changed any commit yet.' } }
    'ConnectRemote' { $pr = Get-RemoteUrlProblem $p.Url; if ($pr) { return $pr } }
    'ChangeAddress' { $pr = Get-RemoteUrlProblem $p.Url; if ($pr) { return $pr } }
    'Sync' { if (-not $f.Linked) { return 'This project is not linked to GitHub yet.' } }
    'ReplaceRemote' {
      if (-not $f.Linked) { return 'This project is not linked to GitHub yet.' }
      if (($f.RemoteOnly -gt 0 -or $f.Others -gt 0) -and -not $p.Discard) { return 'GitHub holds work by someone else. Get it first, or confirm that you really want to delete it.' }
    }
    'Publish' { if (-not $f.Linked) { return 'This project is not linked to GitHub yet.' }; if ($f.Behind -gt 0) { return 'GitHub has newer changes. Get them first.' } }
    'ChooseAccount' { if ($p.Account -notmatch '^[\w.-]+$') { return 'Choose one of the saved accounts.' } }
    'Undo' { if ($f.Backups -lt 1) { return 'There is nothing to undo.' } }
  }
  $null
}

function Get-WorkflowActions([string]$State, $f, [hashtable]$p = @{}) {
  foreach ($a in $script:WfActions[$State]) {
    $why = Get-ActionGuard $a.Id $f $p
    [pscustomobject]@{ Id = $a.Id; Label = $a.Label; Kind = $a.Kind; Next = @($a.Next); Enabled = (-not $why); Why = $why }
  }
}

function Get-WorkflowPlan([string]$Path, [hashtable]$Ui = @{}, [hashtable]$Params = @{}, [switch]$CheckAccess, [switch]$Fetch) {
  $f = Get-WorkflowFacts $Path $Ui -CheckAccess:$CheckAccess -Fetch:$Fetch
  $s = Resolve-WorkflowState $f; $acts = @(Get-WorkflowActions $s $f $Params)
  # the recommended action = the state's main forward action (first engine action, else the first action), shown even while its
  # guard still needs input - the UI then displays it disabled together with Why (e.g. 'Write what you changed first')
  $rec = ($acts | Where-Object { $_.Kind -eq 'engine' } | Select-Object -First 1); if (-not $rec) { $rec = $acts | Select-Object -First 1 }
  [pscustomobject]@{ State = $s; Title = $script:WfStates[$s].Title; Help = $script:WfStates[$s].Help; Facts = $f; Actions = $acts; Recommended = $(if ($rec) { $rec.Id }); RecommendedEnabled = [bool]($rec -and $rec.Enabled); RecommendedWhy = $(if ($rec) { $rec.Why }) }
}

# ---------- errors: every engine failure maps to a class and a way forward ----------
$script:WfErrorClasses = @(
  @{ Class = 'untrusted';  Rx = 'UNTRUSTED PROJECT';                              Headline = 'This project can run programs on your PC.';                          Recovery = 'Trust' }
  @{ Class = 'signin';     Rx = 'GitHub sign-in required|not signed in';          Headline = 'GitHub needs you to sign in.';                                       Recovery = 'SignIn' }
  @{ Class = 'behind';     Rx = 'newer change|both changed|nowhere in this repository|written by someone else'; Headline = 'GitHub has work that your project does not.'; Recovery = 'Sync' }
  @{ Class = 'conflict';   Rx = 'changed the same file|merge conflicts|unresolved'; Headline = 'GitHub and your project changed the same files.';                Recovery = 'Recheck' }
  @{ Class = 'locked';     Rx = 'locked by another program|index\.lock|Permission denied'; Headline = 'Another program is using these files.';                      Recovery = 'Recheck' }
  @{ Class = 'identity';   Rx = 'who you are|Type your name';                     Headline = 'Git needs your name and email.';                                     Recovery = 'SaveIdentity' }
  @{ Class = 'date';       Rx = 'too early|must be in the past|Invalid or missing date'; Headline = 'That date cannot be used.';                                     Recovery = 'Recheck' }
  @{ Class = 'message';    Rx = 'commit message|Write what you changed';          Headline = 'Write what you changed first.';                                      Recovery = 'Recheck' }
  @{ Class = 'address';    Rx = 'repository address|page inside|profile|Network-share|inside the address'; Headline = 'That GitHub address cannot be used.';          Recovery = 'ChangeAddress' }
  @{ Class = 'secrets';    Rx = 'passwords or keys';                              Headline = 'Some files look like they hold passwords or keys.';                  Recovery = 'Recheck' }
  @{ Class = 'toolarge';   Rx = '100 MB|GH001';                                   Headline = 'A file is too big for GitHub.';                                      Recovery = 'Recheck' }
  @{ Class = 'branch';     Rx = 'detached HEAD|not on a branch';                  Headline = 'You are not on a branch.';                                           Recovery = 'Recheck' }
  @{ Class = 'inprogress'; Rx = 'in progress';                                    Headline = 'Another git operation is unfinished.';                               Recovery = 'Recheck' }
  @{ Class = 'network';    Rx = 'Could not reach|Could not verify|longer than 5 minutes|offline'; Headline = 'Cannot reach GitHub.';                                  Recovery = 'Recheck' }
  @{ Class = 'notfound';   Rx = 'was not found|not found';                        Headline = 'GitHub cannot find that repository.';                                Recovery = 'ChangeAddress' }
  @{ Class = 'sso';        Rx = 'single sign-on|SAML';                            Headline = 'Your organisation needs you to authorise your login.';               Recovery = 'ShowSsoHelp' }
  @{ Class = 'noaccess';   Rx = 'may not write to';                               Headline = 'This account cannot publish to that repository.';                    Recovery = 'ChooseAccount' }
)
function Get-WorkflowError([string]$Message) {
  foreach ($e in $script:WfErrorClasses) { if ($Message -match $e.Rx) { return [pscustomobject]@{ Class = $e.Class; Headline = $e.Headline; Recovery = $e.Recovery; Detail = $Message } } }
  [pscustomobject]@{ Class = 'other'; Headline = 'Something went wrong.'; Recovery = 'Recheck'; Detail = $Message }
}

# ---------- run one action: validate -> execute -> re-derive ----------
function Invoke-WorkflowAction([string]$Path, [string]$Id, [hashtable]$Params = @{}, [hashtable]$Ui = @{}, [scriptblock]$SignInHook) {
  $before = Get-WorkflowPlan $Path $Ui $Params
  $allowed = @($before.Actions | Where-Object { $_.Id -eq $Id })
  $res = [ordered]@{ Ok = $false; Action = $Id; From = $before.State; To = $before.State; Message = ''; Result = $null; ErrorClass = $null; Reason = $null; Recovery = @(); Plan = $null }
  if (-not $allowed.Count) { $res.Reason = 'stale'; $res.Message = "That step is not available any more (the project is now: $($before.Title)). Nothing was changed."; $res.Plan = $before; $res.Recovery = @($before.Actions | Where-Object Enabled | ForEach-Object Id); return [pscustomobject]$res }
  if (-not $allowed[0].Enabled) { $res.Reason = 'guard'; $res.Message = $allowed[0].Why; $res.Plan = $before; $res.Recovery = @($before.Actions | Where-Object Enabled | ForEach-Object Id); return [pscustomobject]$res }
  $p = $Params
  try {
    $root = if ($before.Facts.Root) { $before.Facts.Root } else { $Path }
    $res.Result = switch ($Id) {
      'InitProject'   { Initialize-Repo $Path $p.Url }
      'Trust'         { Set-RepoTrusted $Path }
      'SaveIdentity'  { Set-GitIdentity $p.Name $p.Email; 'Saved your name and email.' }
      'Commit'        { $a = @{ Path = $root; Message = $p.Message }; if ($p.All) { $a.All = $true } else { $a.Files = @($p.Files) }; if ($p.Date) { $a.Date = $p.Date }; if ($p.AllowRisky) { $a.AllowRisky = $true }; New-CommitFromChanges @a }
      'AddGitignore'  { Add-Gitignore $root $p.Kind }
      'ApplyEdits'    { Set-CommitEdits $root $p.Edits }
      'ConnectRemote' { Set-RemoteUrl $root $p.Url }
      'ChangeAddress' { Set-RemoteUrl $root $p.Url }
      'Sync'          { Merge-RemoteChanges $root }
      'ReplaceRemote' { Push-Repo $root -Force -DiscardRemote:([bool]$p.Discard) }
      'Publish'       {
        # the prerequisite that is not knowable offline: can this PC publish? A failure becomes the matching access state (not an exception).
        $f2 = Get-WorkflowFacts $Path $Ui -CheckAccess
        $st2 = Resolve-WorkflowState $f2
        if ($st2 -notin 'ReadyToPublish', 'InSync') { $res.Reason = 'prerequisite'; $res.Message = $script:WfStates[$st2].Help; 'blocked' } else { Push-Repo $root }
      }
      'SignIn'        { if ($SignInHook) { & $SignInHook $root } else { Connect-GitHub $root } }
      'ChooseAccount' { Set-GitHubAccount $root $p.Account }
      'Undo'          { Undo-CommitEdits $root -Force:([bool]$p.Force) }
      default         { $null }   # nav / info actions: nothing to execute, the caller shows the page or the instruction
    }
    if (-not $res.Reason) { $res.Ok = $true }
    if ($Id -eq 'Sync' -and $res.Result.Result -eq 'conflict') { $res.Ok = $false; $res.ErrorClass = 'conflict'; $res.Message = "GitHub and your project changed the same file(s): $($res.Result.Files -join ', '). Nothing was changed." }
  } catch {
    $res.Ok = $false; $e = Get-WorkflowError $_.Exception.Message; $res.ErrorClass = $e.Class; $res.Message = $_.Exception.Message
  }
  $uiAfter = @{}; foreach ($k in $Ui.Keys) { $uiAfter[$k] = $Ui[$k] }
  if ($Id -in 'ApplyEdits', 'DiscardEdits' -and $res.Ok) { $uiAfter.EditsStaged = 0 }                  # the staged edits were consumed
  $after = Get-WorkflowPlan $Path $uiAfter @{} -CheckAccess:($Id -in 'SignIn', 'ChooseAccount', 'Publish', 'ChangeAddress')
  $res.To = $after.State; $res.Plan = $after
  $res.Recovery = @($after.Actions | Where-Object Enabled | ForEach-Object Id)
  if (-not $res.Ok -and $res.ErrorClass) { $err = Get-WorkflowError $res.Message; if ($err.Recovery -and ($res.Recovery -notcontains $err.Recovery)) { $res.Recovery = @($res.Recovery) + $err.Recovery } }
  [pscustomobject]$res
}

# ---------- the model checker ----------
# Proves, for the whole fact space: (1) every combination resolves to exactly one known state, (2) every state has actions and at least
# one is enabled for a sensible parameter set (no dead end), (3) every action's declared next states exist, (4) InSync is reachable from
# every state through enabled actions, (5) every error class's recovery action exists. Returns the list of violations (empty = proven).
function Test-WorkflowModel {
  $bad = New-Object Collections.Generic.List[string]
  foreach ($s in $script:WfStates.Keys) {
    if (-not $script:WfActions.Contains($s)) { $bad.Add("state $s has no action table"); continue }
    foreach ($a in $script:WfActions[$s]) { foreach ($n in $a.Next) { if (-not $script:WfStates.Contains($n)) { $bad.Add("$s/$($a.Id) -> unknown state $n") } } }
  }
  # enumerate the fact space with pruning (a blocking fact makes the later ones irrelevant)
  $seen = @{}; $count = 0
  $accesses = 'Unknown', 'Yes', 'NotSignedIn', 'ChooseAccount', 'NoAccess', 'NotFound', 'SSO', 'HostKey', 'Offline'
  $bools = $false, $true
  $cases = New-Object Collections.Generic.List[object]
  function Add-Case($h) { $f = New-WorkflowFacts; foreach ($k in $h.Keys) { $f[$k] = $h[$k] }; $cases.Add([pscustomobject]$f) }
  Add-Case @{ GitInstalled = $false }; Add-Case @{ FolderGiven = $false }; Add-Case @{ FolderGiven = $true; FolderExists = $false }
  Add-Case @{ FolderGiven = $true; FolderExists = $true; IsRepo = $false }
  $base = @{ FolderGiven = $true; FolderExists = $true; IsRepo = $true }
  Add-Case ($base + @{ Trusted = $false }); Add-Case ($base + @{ IdentityOk = $false }); Add-Case ($base + @{ InProgress = $true }); Add-Case ($base + @{ Detached = $true; HasCommits = $true })
  foreach ($chg in 0, 2) { foreach ($ed in 0, 1) { foreach ($hc in $bools) { foreach ($lk in $bools) { foreach ($beh in 0, 1) { foreach ($ah in 0, 1) { foreach ($fo in 0, 1) { foreach ($ac in $accesses) { foreach ($bk in 0, 1) {
    Add-Case ($base + @{ Changes = $chg; EditsStaged = $ed; HasCommits = $hc; Linked = $lk; Behind = $beh; Ahead = $ah; RemoteOnly = $fo; Access = $ac; Backups = $bk; NeedsIgnore = ($chg -gt 0) })
  } } } } } } } } }
  $reach = @{}   # state -> $true when InSync can be reached
  foreach ($f in $cases) {
    $count++
    $s = Resolve-WorkflowState $f
    if (-not $s -or -not $script:WfStates.Contains($s)) { $bad.Add("facts resolve to unknown state '$s': $($f | ConvertTo-Json -Compress)"); continue }
    if ((Resolve-WorkflowState $f) -ne $s) { $bad.Add("non-deterministic for $($f | ConvertTo-Json -Compress)") }
    $seen[$s] = $true
    $params = @{ Url = 'https://github.com/a/b.git'; Message = 'm'; All = $true; Name = 'n'; Email = 'a@b.co'; Edits = @{ x = @{ message = 'm' } }; Account = 'acct'; Discard = $true }
    $f2 = $f.PSObject.Copy(); if ($s -eq 'EditsPending') { $f2.EditsStaged = 1 }
    $acts = @(Get-WorkflowActions $s $f2 $params)
    if (-not $acts.Count) { $bad.Add("${s}: no actions") } elseif (-not @($acts | Where-Object Enabled).Count) { $bad.Add("${s}: DEAD END - every action is disabled for $($f | ConvertTo-Json -Compress)") }
  }
  foreach ($s in $script:WfStates.Keys) { if (-not $seen[$s] -and $s -ne 'InSync') { $bad.Add("state $s is unreachable from any fact combination (orphaned)") } }
  if (-not $seen['InSync']) { $bad.Add('InSync is unreachable') }
  # reachability of InSync over the declared transition graph
  $reach['InSync'] = $true; $changed = $true
  while ($changed) { $changed = $false; foreach ($s in $script:WfStates.Keys) { if ($reach[$s]) { continue }; foreach ($a in $script:WfActions[$s]) { if ($a.Next | Where-Object { $reach[$_] }) { $reach[$s] = $true; $changed = $true; break } } } }
  foreach ($s in $script:WfStates.Keys) { if (-not $reach[$s]) { $bad.Add("state $s cannot reach InSync through any declared action") } }
  foreach ($e in $script:WfErrorClasses) { $ids = @($script:WfActions.Values | ForEach-Object { $_ } | ForEach-Object { $_.Id }); if ($ids -notcontains $e.Recovery) { $bad.Add("error class $($e.Class) points at unknown recovery action $($e.Recovery)") } }
  $script:WfModelCases = $count
  @($bad)
}
