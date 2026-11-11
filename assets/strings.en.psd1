# backd8 copy deck (English, US spelling). Load with Import-PowerShellDataFile. UTF-8 with BOM.
# Check it with:  powershell -ExecutionPolicy Bypass -File tests\strings-check.ps1
#
# ---------------------------------------------------------------------------------------------
# GLOSSARY (the checker enforces this in every string that a user reads first)
#   project                  never "repository" or "repo"
#   save point               "commit" is explained ONCE (Welcome.Explain) and never used again outside Details
#   publish to GitHub        never "push"
#   get the latest from GitHub   never "pull", "sync" or "fetch"
#   replace GitHub's version never "force push"
#   address                  never "URL" or "remote"
#   approve                  never "authorize" / "authenticate"
#   organization             US spelling everywhere (organization, approve, color)
# Technical wording (git commands, refs, error text) lives ONLY under keys named Details*, never in a
# heading, help text, button, tooltip, dialog or message.
#
# CONVENTIONS
#   {placeholder}   a value the UI fills in. Allowed names are listed in Placeholders.
#   @{ One; Other } plural pair (Zero is optional). Any text that shows a number uses a pair and {count}.
#   Access          the same text as Label with ONE & before the access key (Alt+letter).
#   Pages.*.Controls  every control text on that page, with & before its access key. Back and Next
#                   are always on screen, so B and N are reserved on every page.
#   Role            accept / alt / cancel. Esc = the cancel button. Default = the SAFE button.
# ---------------------------------------------------------------------------------------------
@{
  Meta = @{
    Version  = 1
    Language = 'en-US'
    Notes    = 'Single source of all user-facing text. Primary text must pass tests\strings-check.ps1.'
  }

  Glossary = @{
    Terms = @{
      project   = @{ Use = 'project';                      Avoid = 'repository, repo';                Meaning = 'A folder that backd8 keeps track of.' }
      commit    = @{ Use = 'save point';                   Avoid = 'commit';                          Meaning = 'A snapshot of your files with a short note and a date.'; ExplainedIn = 'Welcome.Explain' }
      publish   = @{ Use = 'publish to GitHub';            Avoid = 'push';                            Meaning = 'Send your save points to GitHub so they are online.' }
      getLatest = @{ Use = 'get the latest from GitHub';   Avoid = 'pull, sync, fetch';               Meaning = 'Bring work that GitHub has into your project.' }
      replace   = @{ Use = "replace GitHub's version";     Avoid = 'force push';                      Meaning = "Publish edited save points over GitHub's old copies." }
      address   = @{ Use = 'address';                      Avoid = 'URL, remote, origin';             Meaning = 'The web address of your project on GitHub.' }
      edit      = @{ Use = 'change an older save point';   Avoid = 'rewrite history, rebase, amend'; Meaning = 'Change the note or date of a save point you made earlier.' }
      undo      = @{ Use = 'undo my last change';          Avoid = 'reset, restore backup';           Meaning = 'Put the project back as it was before your last edit.' }
      approve   = @{ Use = 'approve';                      Avoid = 'authorize, authenticate';         Meaning = 'Say yes to a sign-in on the GitHub website.' }
    }
  }

  Placeholders = @{
    count       = 'A whole number. Only used inside plural pairs (One / Other).'
    total       = 'A total number of steps.'
    current     = 'The current step number.'
    branch      = 'Name of the current branch, for example main.'
    folder      = 'Full path of the project folder.'
    name        = 'The name of the person (from the identity page).'
    email       = 'The email address (from the identity page).'
    url         = 'A GitHub web address.'
    account     = 'A GitHub user name.'
    files       = 'A comma separated list of up to 5 file names.'
    sizeMB      = 'File size in megabytes, whole number.'
    limitMB     = 'GitHub file size limit in megabytes (100).'
    date        = 'A date and time, formatted for the user.'
    when        = 'The date and time of a backup, formatted for the user.'
    settings    = 'Names of the risky hidden settings, comma separated.'
    changes     = 'Number of changes not saved yet (used with Lines).'
    edits       = 'Number of edits not applied yet (used with Lines).'
    unpublished = 'Number of save points not on GitHub yet (used with Lines).'
  }

  # ---------- window chrome ----------
  Chrome = @{
    WindowTitle     = 'backd8 Setup'
    SidebarHeading  = 'About this step'
    Step            = 'Step {current} of {total}'
    Buttons         = @{
      Back   = '< &Back'
      Next   = '&Next >'
      Cancel = 'Cancel'
      Finish = 'Finish'
      Close  = 'Close'
      Help   = 'Help'
    }
    Wait            = 'Please wait...'
    Loading         = 'Looking at your project...'
  }

  TechInfo = @{
    Show    = 'Show details'
    Hide    = 'Hide details'
    Copy    = 'Copy details'
    Copied  = 'Copied. You can paste it into a message to get help.'
    Heading = 'Details for the curious'
    Note    = 'Your files and save points are safe. Copy the details if you want someone to help you.'
  }

  Messages = @{
    Stale = 'Things changed while you were looking, so backd8 did nothing. The page is updated now.'
    Busy  = 'backd8 is working. Please wait until it is finished.'
  }

  # ---------- pages: every control on a page, with its access key ----------
  # Pages without states: Welcome, Progress, Problem. All other pages are named by States.*.Page.
  Pages = @{
    Welcome  = @{ Controls = @{ DontShow = "&Don't show this again" } }
    Folder   = @{ Controls = @{ Path = 'Your &project folder:'; Recent = 'Recent &folders:'; Url = 'Your &GitHub address (optional):' } }
    Identity = @{ Controls = @{ Name = 'Full na&me:'; Email = 'Email &address:' } }
    Info     = @{ Controls = @{ } }
    Changes  = @{ Controls = @{ Files = '&Files to include:'; Message = 'Describe &what changed:'; Date = 'Save point &date:'; SelectAll = 'Select &all'; ClearAll = 'Clear &ticks' } }
    History  = @{ Controls = @{ List = '&Save points:'; Message = 'New &message:'; Date = 'New &date:' } }
    Connect  = @{ Controls = @{ Url = 'Address on &GitHub:' } }
    Access   = @{ Controls = @{ Accounts = 'Saved &GitHub accounts:'; Url = 'GitHub a&ddress:' } }
    Update   = @{ Controls = @{ } }
    Publish  = @{ Controls = @{ } }
    Complete = @{ Controls = @{ ViewOnGitHub = 'View on &GitHub'; ShowFolder = 'Show in &Explorer' } }
    Progress = @{ Controls = @{ ShowDetails = 'Show &details'; ShowDetailsToggled = 'Hide &details' } }
    Problem  = @{ Controls = @{ ShowDetails = 'Show &details'; ShowDetailsToggled = 'Hide &details'; CopyDetails = 'Cop&y details' } }
  }

  # ---------- first run ----------
  Welcome = @{
    Heading     = 'Welcome to backd8'
    Instruction = 'Click Next to continue.'
    Intro       = 'backd8 helps you choose a folder, tidy up the notes and dates of your work, and publish it to GitHub.'
    Explain     = 'A save point (Git calls it a commit) is a snapshot of your files with a short note and a date.'
    Steps       = @(
      '1. Choose the folder that holds your work.'
      '2. Describe your changes and pick a date.'
      '3. Publish your project to GitHub.'
    )
    Caution     = 'Changing dates can mislead other people. Use it only where that is fair.'
    Safe        = 'backd8 never changes your files unless you press a button that says so.'
  }

  FirstRun = @{
    GitMissing = @{
      Heading = 'backd8 needs Git'
      Body    = 'Git is a free program that keeps the history of your project. backd8 uses it behind the scenes. You only install it once.'
      Steps   = @(
        "1. Click 'How to install Git' and follow the steps."
        "2. Come back here and click 'Check again'."
      )
      Details = 'Install with: winget install --id Git.Git -e   or download https://git-scm.com/download/win'
    }
    Identity = @{
      Heading     = 'Who are you?'
      Body        = 'Your name and email are saved with every save point you make. People who can see your project on GitHub will see them too.'
      Note        = 'backd8 saves them once, for all your projects.'
      NameHint    = 'For example: Alex Morgan'
      EmailHint   = 'you@example.com'
      NameMissing = 'Type your name first.'
      EmailBad    = 'Type a valid email address, such as you@example.com.'
    }
  }

  # ---------- the 24 states ----------
  States = @{
    NoFolder = @{
      Page = 'Folder'
      Title = 'Choose your project'
      Help = 'Pick the folder that holds your work. backd8 will look at it and tell you what to do next. Your files stay where they are.'
      Heading = 'Which folder do you want to use?'
      Instruction = "Click 'Choose a folder...' and pick the folder that holds your work."
    }
    FolderNotFound = @{
      Page = 'Folder'
      Title = 'That folder is missing'
      Help = 'The folder was moved, renamed, or deleted. Choose it again, or pick a different folder.'
      Heading = 'backd8 cannot find that folder'
      Instruction = "Click 'Choose another folder...' to pick it again."
    }
    GitMissing = @{
      Page = 'Info'
      Title = 'Git is not installed'
      Help = "backd8 needs Git, a free program that keeps the history of your project. Install it once. Then click 'Check again'."
      Heading = 'backd8 needs Git first'
      Instruction = "Click 'How to install Git', follow the steps, then click 'Check again'."
      Details = 'Install with: winget install --id Git.Git -e   or download https://git-scm.com/download/win'
    }
    NotAProject = @{
      Page = 'Folder'
      Title = 'Turn this folder into a project'
      Help = 'backd8 will add a hidden folder named .git to keep track of your work. Your own files are not changed or moved.'
      Heading = 'This folder is not a project yet'
      Instruction = "Click 'Turn this folder into a project' to start."
    }
    Untrusted = @{
      Page = 'Folder'
      Title = 'Do you trust this project?'
      Help = 'This folder has hidden settings that can start programs on your PC. Go on only if you made it, or you trust where it came from.'
      Heading = 'This project can run programs'
      Instruction = "Click 'I made this / I trust it' only if you are sure."
      Details = 'The .git/config of this folder sets options (for example core.fsmonitor, core.sshCommand or hooks) that run programs whenever git looks at it.'
    }
    NoIdentity = @{
      Page = 'Identity'
      Title = 'Tell backd8 who you are'
      Help = 'Every save point carries your name and email. Type them once. They are saved on this PC and used for all your projects.'
      Heading = 'Who are you?'
      Instruction = "Type your name and email, then click 'Save my name and email'."
      Details = 'Saved with: git config --global user.name and git config --global user.email'
    }
    Blocked = @{
      Page = 'Info'
      Title = 'A task is still unfinished'
      Help = 'Git started a job in this folder, such as combining changes, and did not finish it. Finish or cancel it first. backd8 will not touch it.'
      Heading = 'Something is half done in this project'
      Instruction = "Click 'How to finish or cancel it', then click 'Check again'."
      Details = 'A merge, rebase, cherry-pick or revert is in progress (.git/MERGE_HEAD, rebase-merge, ...). Run git status, then git merge --abort or git rebase --abort.'
    }
    Detached = @{
      Page = 'Info'
      Title = 'You are not on a branch'
      Help = 'Your project is looking at an old save point instead of a branch. A branch is a line of save points, often called main. Switch to one first.'
      Heading = 'Switch to a branch first'
      Instruction = "Click 'How to switch to a branch', then click 'Check again'."
      Details = 'HEAD is detached. Run git switch <branch>, or git switch -c <new-name> to keep the commits you made here.'
    }
    EmptyProject = @{
      Page = 'Info'
      Title = 'Nothing to save yet'
      Help = "This project has no files and no save points yet. Put your files in the folder, then click 'I added files - check again'."
      Heading = 'This folder is empty'
      Instruction = "Add your files to the folder, then click 'I added files - check again'."
    }
    ChangesPending = @{
      Page = 'Changes'
      Title = 'You have changes to save'
      Help = 'Tick the files you want to include. Say what you changed and pick a date. backd8 saves them together as one save point.'
      Heading = 'Save your changes'
      Instruction = "Tick your files, describe the change, then click 'Save these files'."
    }
    EditsPending = @{
      Page = 'History'
      Title = 'Your edits are not applied yet'
      Help = 'You changed older save points. Apply writes those changes into your project. backd8 keeps a backup, so you can undo.'
      Heading = 'Apply your edits?'
      Instruction = "Click 'Apply my edits' to keep them, or 'Discard my edits' to drop them."
    }
    NoRemote = @{
      Page = 'Connect'
      Title = 'Connect to GitHub'
      Help = 'Create a new, empty project on GitHub, then paste its address here. backd8 will connect your folder to it.'
      Heading = 'Where should your project go on GitHub?'
      Instruction = "Paste the GitHub address, then click 'Connect'."
    }
    GitHubAhead = @{
      Page = 'Update'
      Title = 'GitHub has newer changes'
      Help = 'GitHub has work that your project does not. It may come from another PC or another person. Get it before you publish.'
      Heading = 'GitHub has newer work'
      Instruction = "Click 'Get the latest from GitHub' to bring it in."
    }
    NeedsSync = @{
      Page = 'Update'
      Title = "Get GitHub's newer work first"
      Help = 'GitHub holds work from someone else, or from another PC, that this PC does not have. Get it first so it is not lost.'
      Heading = 'GitHub has work you do not have'
      Instruction = "Click 'Get the latest from GitHub', or 'Undo my last change'."
    }
    NeedsReplace = @{
      Page = 'Update'
      Title = "Replace GitHub's old version?"
      Help = 'You changed save points that are already on GitHub. GitHub still has the old versions. Publishing replaces them.'
      Heading = "Replace GitHub's version of your work?"
      Instruction = "Click 'Replace GitHub's version...' to publish your edits."
    }
    NeedsSignIn = @{
      Page = 'Access'
      Title = 'Sign in to GitHub'
      Help = 'GitHub does not know this PC yet. Your web browser opens once so you can sign in. Windows remembers you after that.'
      Heading = 'Sign in to GitHub'
      Instruction = "Click 'Sign in to GitHub' and finish in your web browser."
    }
    ChooseAccount = @{
      Page = 'Access'
      Title = 'Which GitHub account?'
      Help = 'This PC has more than one saved GitHub account. Choose the one this project should use.'
      Heading = 'Choose your GitHub account'
      Instruction = "Pick an account in the list, then click 'Use this account'."
    }
    NoWriteAccess = @{
      Page = 'Access'
      Title = 'This account cannot publish here'
      Help = 'You are signed in, but GitHub says this account may not add work to this project. Use a different account, or a different address.'
      Heading = 'GitHub said this account cannot publish'
      Instruction = "Click 'Use a different account', or 'Publish to a different address'."
      Details = 'GitHub answered 403: Permission to <owner>/<project> denied to <user>. Ask the owner to add you as a collaborator, or fork the project.'
    }
    RepoNotFound = @{
      Page = 'Connect'
      Title = 'GitHub cannot find this address'
      Help = 'Check the address for typing mistakes. Or create an empty project with exactly this name on GitHub. If it is private, sign in with the right account.'
      Heading = 'GitHub cannot find that address'
      Instruction = "Click 'Fix the GitHub address', or 'Open github.com/new' to create the project."
      Details = "GitHub answers 'Repository not found' both for projects that do not exist and for private ones you cannot see."
    }
    SSORequired = @{
      Page = 'Access'
      Title = 'Your organization must approve you'
      Help = 'Your organization on GitHub wants you to approve your sign-in for it. Do this once on the GitHub website, then come back.'
      Heading = 'One more approval is needed'
      Instruction = "Click 'How to approve your sign-in', approve it, then click 'I approved it - check again'."
      Details = 'Open https://github.com/settings/tokens (or /settings/keys for SSH) and click Configure SSO next to your token or key.'
    }
    HostKeyProblem = @{
      Page = 'Access'
      Title = 'Cannot confirm it is GitHub'
      Help = 'backd8 could not be sure it is really talking to GitHub. The easy fix is to use a web address that starts with https.'
      Heading = 'backd8 cannot confirm it is GitHub'
      Instruction = "Click 'Use an https address instead' to fix this."
      Details = 'SSH host key verification failed. Run ssh -T git@github.com in a terminal and accept the fingerprint only if it matches the list published by GitHub.'
    }
    Offline = @{
      Page = 'Access'
      Title = 'Cannot reach GitHub'
      Help = 'backd8 could not connect. Check your internet connection. GitHub may also be having a problem. Then try again.'
      Heading = 'No connection to GitHub'
      Instruction = "Check your internet, then click 'Try again'."
      Details = 'Could not resolve host, connection timed out, or GitHub answered with a temporary 5xx error.'
    }
    ReadyToPublish = @{
      Page = 'Publish'
      Title = 'Ready to publish'
      Help = 'Everything is saved on this PC. Publishing sends your save points to GitHub, so they are online.'
      Heading = 'Ready to publish to GitHub'
      Instruction = "Click 'Publish to GitHub' to send your work."
    }
    InSync = @{
      Page = 'Complete'
      Title = 'Everything is saved and published'
      Help = 'Your project and GitHub match. You can still change an older save point or choose another folder.'
      Heading = 'Your project is up to date'
      Instruction = 'Click Finish to close, or pick something to do next.'
    }
  }

  # ---------- actions (by id) with per-state overrides ----------
  Actions = @{
    ChooseFolder        = @{ Label = 'Choose another folder...';        Access = '&Choose another folder...';        Tooltip = 'Pick the folder that holds your work.' }
    Recheck             = @{ Label = 'Check again';                     Access = 'Check &again';                     Tooltip = 'Look at your project again.' }
    ShowGitInstall      = @{ Label = 'How to install Git';              Access = 'How to &install Git';              Tooltip = 'Shows the steps to install Git.' }
    InitProject         = @{ Label = 'Turn this folder into a project'; Access = '&Turn this folder into a project'; Tooltip = 'Adds a hidden .git folder so backd8 can track your work. Your files are not changed.' }
    Trust               = @{ Label = 'I made this / I trust it';        Access = 'I &made this / I trust it';        Tooltip = 'Only click this if you made the project or trust where it came from.' }
    SaveIdentity        = @{ Label = 'Save my name and email';         Access = '&Save my name and email';         Tooltip = 'Saves your name and email on this PC for all your projects.' }
    ShowFinishOperation = @{ Label = 'How to finish or cancel it';     Access = 'How to &finish or cancel it';     Tooltip = 'Shows how to finish or cancel the unfinished task.' }
    ShowSwitchBranch    = @{ Label = 'How to switch to a branch';      Access = 'How to &switch to a branch';      Tooltip = 'Shows how to switch to a branch.' }
    Commit              = @{ Label = 'Save these files';                Access = '&Save these files';                Tooltip = 'Saves the ticked files as one save point with your note and date.' }
    AddGitignore        = @{ Label = 'Leave out build and editor files'; Access = 'Leave &out build and editor files'; Tooltip = 'Tells backd8 to skip build and editor files from now on.' }
    IgnoreRiskyFiles    = @{ Label = 'Leave out the secret-looking files'; Access = 'Leave out the secret-loo&king files'; Tooltip = 'Keeps files that look like passwords or keys out of your save points and GitHub.' }
    ApplyEdits          = @{ Label = 'Apply my edits';                  Access = '&Apply my edits';                  Tooltip = 'Writes your edits into the project. A backup is kept so you can undo.' }
    DiscardEdits        = @{ Label = 'Discard my edits';                Access = 'Discard my &edits';                Tooltip = 'Forgets your edits. Nothing in your project changes.' }
    ConnectRemote       = @{ Label = 'Connect';                         Access = '&Connect';                         Tooltip = 'Connects this project to the GitHub address you pasted.' }
    OpenNewRepoPage     = @{ Label = 'Open github.com/new';            Access = '&Open github.com/new';            Tooltip = 'Opens github.com/new in your browser so you can create an empty project.' }
    Sync                = @{ Label = 'Get the latest from GitHub';      Access = '&Get the latest from GitHub';      Tooltip = "Brings GitHub's newer work into your project. Your own save points are not changed." }
    Undo                = @{ Label = 'Undo my last change';            Access = '&Undo my last change';            Tooltip = 'Puts your project back the way it was before your last edit.' }
    ReplaceRemote       = @{ Label = "Replace GitHub's version...";     Access = "&Replace GitHub's version...";     Tooltip = "Publishes your project over GitHub's old version. You will be asked to confirm." }
    SignIn              = @{ Label = 'Sign in to GitHub';               Access = 'Sign &in to GitHub';               Tooltip = 'Opens your browser so you can sign in to GitHub. You only do this once.' }
    ChangeAddress       = @{ Label = 'Change the GitHub address';       Access = 'Change the GitHub add&ress';       Tooltip = 'Connects this project to a different GitHub address.' }
    ChooseAccount       = @{ Label = 'Use this account';                Access = 'Use &this account';                Tooltip = 'Uses the selected saved account for this project.' }
    ShowSsoHelp         = @{ Label = 'How to approve your sign-in';     Access = 'How to &approve your sign-in';     Tooltip = 'Shows how to approve your sign-in for your organization.' }
    ShowHostKeyHelp     = @{ Label = 'How to verify the connection';    Access = 'How to &verify the connection';    Tooltip = 'Shows how to confirm that you are really talking to GitHub.' }
    Publish             = @{ Label = 'Publish to GitHub';               Access = '&Publish to GitHub';               Tooltip = 'Sends your save points to GitHub.' }
    EditOlder           = @{ Label = 'Change an older save point...';   Access = 'Change an &older save point...';   Tooltip = 'Opens your older save points so you can change a note or a date.' }
  }

  # Same action, different wording in one state. Key = State/ActionId.
  ActionOverrides = @{
    'NoFolder/ChooseFolder'    = @{ Label = 'Choose a folder...';              Access = '&Choose a folder...' }
    'EmptyProject/Recheck'     = @{ Label = 'I added files - check again';     Access = 'I &added files - check again' }
    'RepoNotFound/Recheck'     = @{ Label = 'I created it - check again';      Access = 'I &created it - check again' }
    'SSORequired/Recheck'      = @{ Label = 'I approved it - check again';     Access = 'I approved it - &check again' }
    'Offline/Recheck'          = @{ Label = 'Try again';                       Access = 'Try &again'; Tooltip = 'Tries to reach GitHub again.' }
    'RepoNotFound/ChangeAddress'  = @{ Label = 'Fix the GitHub address';       Access = 'Fix the GitHub add&ress'; Tooltip = 'Type the right address for your project on GitHub.' }
    'NoWriteAccess/ChangeAddress' = @{ Label = 'Publish to a different address'; Access = 'Publish to a different add&ress'; Tooltip = 'Connects this project to a different place on GitHub.' }
    'HostKeyProblem/ChangeAddress' = @{ Label = 'Use an https address instead'; Access = 'Use an &https address instead'; Tooltip = 'Switches to the web address that starts with https.' }
    'NoWriteAccess/ChooseAccount' = @{ Label = 'Use a different account';     Access = 'Use a different &account'; Tooltip = 'Picks another saved GitHub account for this project.' }
    'ChooseAccount/SignIn'     = @{ Label = 'Sign in with another account';    Access = 'Sign in with &another account'; Tooltip = 'Opens your browser so you can sign in with a different account.' }
  }

  # ---------- why an action is disabled (one entry per guard reason in Get-ActionGuard) ----------
  # Match = regex for the engine's own text (the checker keeps this list in step with workflow.ps1).
  # Dynamic = the engine reuses another function's text (address or date problems): see AddressProblems / Dates.Errors.
  Guards = @(
    @{ Action = 'InitProject';    Key = 'NoFolder';        Match = '^Choose an existing folder';        Why = 'Choose a folder that exists first.' }
    @{ Action = 'InitProject';    Key = 'AlreadyProject';  Match = '^This folder is already a project'; Why = 'This folder is already a project.' }
    @{ Action = 'InitProject';    Key = 'BadAddress';      Dynamic = 'Get-RemoteUrlProblem';            Why = 'Fix the GitHub address first, or leave it empty.' }
    @{ Action = 'Trust';          Key = 'NotProject';      Match = '^Not a project';                    Why = 'This folder is not a project, so there is nothing to trust.' }
    @{ Action = 'SaveIdentity';   Key = 'NoName';          Match = '^Type your name first';             Why = 'Type your name first.' }
    @{ Action = 'SaveIdentity';   Key = 'BadEmail';        Match = '^Type a valid email';               Why = 'Type a valid email address, such as you@example.com.' }
    @{ Action = 'Commit';         Key = 'NoChanges';       Match = '^Nothing has changed';              Why = 'Nothing has changed since your last save point.' }
    @{ Action = 'Commit';         Key = 'NoMessage';       Match = '^Write what you changed';           Why = 'Describe what you changed first.' }
    @{ Action = 'Commit';         Key = 'NoFiles';         Match = '^Tick at least one file';           Why = 'Tick at least one file.' }
    @{ Action = 'Commit';         Key = 'BadDate';         Dynamic = 'Assert-GitDate';                  Why = 'Pick a valid date in the past first.' }
    @{ Action = 'Commit';         Key = 'RiskyFiles';      Match = '^Some files look like';             Why = 'Some files look like they hold passwords or keys. Leave them out, or confirm that you want them saved.' }
    @{ Action = 'IgnoreRiskyFiles'; Key = 'NoRisky';       Match = '^No file looks like it holds';      Why = 'No file looks like it holds a password or key.' }
    @{ Action = 'AddGitignore';   Key = 'NothingToSkip';   Match = '^Nothing to leave out';            Why = 'There are no build or editor files to leave out.' }
    @{ Action = 'ApplyEdits';     Key = 'NoEdits';         Match = '^You have not changed any commit'; Why = 'You have not changed any older save point yet.' }
    @{ Action = 'ConnectRemote';  Key = 'BadAddress';      Dynamic = 'Get-RemoteUrlProblem';            Why = 'Fix the GitHub address first.' }
    @{ Action = 'ChangeAddress';  Key = 'BadAddress';      Dynamic = 'Get-RemoteUrlProblem';            Why = 'Fix the GitHub address first.' }
    @{ Action = 'Sync';           Key = 'NotConnected';    Match = '^This project is not linked';       Why = 'This project is not connected to GitHub yet.' }
    @{ Action = 'ReplaceRemote';  Key = 'NotConnected';    Match = '^This project is not linked';       Why = 'This project is not connected to GitHub yet.' }
    @{ Action = 'ReplaceRemote';  Key = 'OthersWork';      Match = '^GitHub holds work by someone';     Why = 'GitHub has work by someone else. Get it first, or confirm that you want to delete it.' }
    @{ Action = 'Publish';        Key = 'NotConnected';    Match = '^This project is not linked';       Why = 'This project is not connected to GitHub yet.' }
    @{ Action = 'Publish';        Key = 'GitHubAhead';     Match = '^GitHub has newer changes';        Why = "GitHub has newer changes. Click 'Get the latest from GitHub' first." }
    @{ Action = 'ChooseAccount';  Key = 'NoAccount';       Match = '^Choose one of the saved';          Why = 'Pick one of the saved accounts first.' }
    @{ Action = 'Undo';           Key = 'NothingToUndo';   Match = '^There is nothing to undo';         Why = 'There is nothing to undo.' }
  )

  AddressProblems = @(
    @{ Key = 'Empty';        Match = '^Paste the address';                  Text = 'Paste the address of your project on GitHub.' }
    @{ Key = 'Shape';        Match = '^That does not look like';            Text = 'That does not look like a GitHub address. It should start with https://github.com/' }
    @{ Key = 'NetworkShare'; Match = '^Network-share';                      Text = 'Addresses on other computers are not supported. Use a GitHub address.' }
    @{ Key = 'Secrets';      Match = '^Do not put a user name';             Text = 'Do not type a password or token into the address. Use the plain address, then sign in.' }
    @{ Key = 'Profile';      Match = '^That is a GitHub profile';           Text = 'That is a GitHub profile, not a project. Add the project name: https://github.com/you/project.git' }
    @{ Key = 'InnerPage';    Match = '^That is a page inside';              Text = 'That is a page inside a project. Use the short address: https://github.com/you/project.git' }
  )

  # ---------- errors ----------
  ErrorLabels = @{ WhatHappened = 'What happened'; WhatToDo = 'What to do' }

  Problem = @{
    Heading     = 'backd8 could not finish'
    Instruction = 'Your files are safe. Read what happened, then follow the next step.'
  }

  ErrorClasses = @{
    untrusted  = @{
      Headline = 'This project can run programs on your PC.'
      Happened = 'Its hidden settings can start programs, and you have not said that you trust it.'
      Todo     = "If you made it or trust it, click 'I made this / I trust it', otherwise choose another folder."
      Details  = 'The engine refused with UNTRUSTED PROJECT because the repository config sets keys that execute programs.'
    }
    signin     = @{
      Headline = 'GitHub needs you to sign in.'
      Happened = 'GitHub did not accept this PC, so nothing was published.'
      Todo     = "Click 'Sign in to GitHub' and finish in your browser, then try again."
      Details  = 'The push was rejected with an authentication error (HTTP 401/403) or git asked for credentials.'
    }
    behind     = @{
      Headline = 'GitHub has work that your project does not.'
      Happened = 'GitHub holds newer work, maybe from another PC or person, so publishing now could erase it.'
      Todo     = "Click 'Get the latest from GitHub', then publish again."
      Details  = 'The remote branch contains commits that are not in your branch (behind > 0, or commits by other authors).'
    }
    conflict   = @{
      Headline = 'GitHub and your project changed the same files.'
      Happened = 'Both sides edited the same lines, so backd8 could not combine them and changed nothing.'
      Todo     = 'Nothing is half-done, so click Check again, or combine the two versions of those files in a git tool first.'
      Details  = 'The merge stopped with conflicts (conflict markers in the files listed in the message). Nothing was committed.'
    }
    protected  = @{
      Headline = 'GitHub does not allow publishing straight to this branch.'
      Happened = 'The branch is protected on GitHub, so it only accepts changes that someone has reviewed first.'
      Todo     = 'Publish to a different branch or ask the owner of the GitHub project to change the rule, then check again.'
      Details  = 'The push was rejected with GH006 / protected branch hook declined.'
    }
    stale      = @{
      Headline = 'That was already done.'
      Happened = 'The project changed since this page was shown, so there was nothing left for this step to do.'
      Todo     = 'Click Check again to see where the project stands now.'
      Details  = 'The action found no changes to save or nothing new to get.'
    }
    undo       = @{
      Headline = 'Undo is not possible any more.'
      Happened = 'The project has changed since the edit, so going back would throw away newer work.'
      Todo     = 'Click Check again; to go back anyway use Undo anyway in the window, which keeps the newer work in the git history.'
      Details  = 'The branch is newer than the last backd8 backup, so Undo refused unless forced.'
    }
    locked     = @{
      Headline = 'Another program is using these files.'
      Happened = 'Windows would not let backd8 use a file because another program, often an editor, has it open.'
      Todo     = 'Close that program, or leave the file out, then try again.'
      Details  = 'git add failed with Permission denied / index.lock / file in use.'
    }
    identity   = @{
      Headline = 'Git needs your name and email.'
      Happened = 'Every save point must say who made it, and this PC does not know that yet.'
      Todo     = "Type your name and email, then click 'Save my name and email'."
      Details  = 'git config user.name and user.email are not set.'
    }
    date       = @{
      Headline = 'That date cannot be used.'
      Happened = 'Dates must be real, in the past, and in 1971 or later.'
      Todo     = 'Pick a different date, then try again.'
      Details  = 'Git cannot store dates before 1971-01-01, and backd8 does not accept dates in the future.'
    }
    message    = @{
      Headline = 'Describe what you changed first.'
      Happened = 'A save point needs a short note about what changed.'
      Todo     = 'Type a note in the box, then try again.'
      Details  = 'The commit message was empty.'
    }
    address    = @{
      Headline = 'That GitHub address cannot be used.'
      Happened = 'The address is a profile page, a page inside a project, or it has a password in it.'
      Todo     = "Click 'Change the GitHub address' and paste the short address from your project's GitHub page."
      Details  = 'Accepted forms: https://github.com/<owner>/<project>.git, git@github.com:<owner>/<project>.git. Credentials, ? and # are refused.'
    }
    secrets    = @{
      Headline = 'Some files look like they hold passwords or keys.'
      Happened = 'The names or contents of these files suggest secrets that anyone could read on GitHub.'
      Todo     = 'Leave them out, or confirm that you really want them included, then try again.'
      Details  = 'Matched by file name (.env, *.pem, id_rsa, appsettings*.json, ...) or by content patterns such as password=, BEGIN PRIVATE KEY, ghp_.'
    }
    toolarge   = @{
      Headline = 'A file is too big for GitHub.'
      Happened = 'GitHub refuses any single file over {limitMB} MB.'
      Todo     = 'Leave that file out, then try again.'
      Details  = 'GH001: Large files detected. Use git rm --cached <file> and amend, or Git LFS (https://git-lfs.com).'
    }
    branch     = @{
      Headline = 'You are not on a branch.'
      Happened = 'Your project is looking at an old save point, so new work could easily be lost.'
      Todo     = 'Switch to a branch in a Git program, then check again.'
      Details  = 'HEAD is detached. Use git switch <branch>.'
    }
    inprogress = @{
      Headline = 'Another task is unfinished.'
      Happened = 'Git started a task here, such as combining changes, and it is still open.'
      Todo     = 'Finish or cancel that task in a Git program, then check again.'
      Details  = 'A rebase, merge, cherry-pick or revert is in progress.'
    }
    network    = @{
      Headline = 'Cannot reach GitHub.'
      Happened = 'backd8 could not connect, or GitHub took too long to answer.'
      Todo     = 'Check your internet connection, then try again.'
      Details  = 'Could not resolve host / connection refused / timed out, or the push ran longer than 5 minutes and was stopped.'
    }
    notfound   = @{
      Headline = 'GitHub cannot find that project.'
      Happened = 'GitHub says nothing exists at this address, or your account may not see it.'
      Todo     = "Check the address, or click 'Change the GitHub address' to fix it."
      Details  = "GitHub answers 'Repository not found' (HTTP 404) for both missing and private repositories."
    }
    sso        = @{
      Headline = 'Your organization needs you to approve your login.'
      Happened = 'Your sign-in works, but your organization has not approved it for this project yet.'
      Todo     = "Click 'How to approve your sign-in' and follow the steps."
      Details  = 'SAML single sign-on is enforced: authorize the token or SSH key for the organization on github.com.'
    }
    noaccess   = @{
      Headline = 'This account cannot publish to that project.'
      Happened = 'You are signed in, but GitHub says this account may not add work there.'
      Todo     = "Click 'Use a different account', or ask the owner to add you."
      Details  = 'Permission to <owner>/<project> denied to <user> (HTTP 403).'
    }
    other      = @{
      Headline = 'Something went wrong.'
      Happened = 'backd8 hit a problem that it cannot explain in simple words.'
      Todo     = "Your files are safe, so click 'Show details', then 'Copy details' if you want help."
      Details  = 'Unclassified engine error. The raw message is shown in the details box.'
    }
  }

  # ---------- confirmation dialogs ----------
  Dialogs = @{
    ApplyEdits = @{
      Title = 'backd8 Setup - Apply edits'
      Heading = 'Apply your edits?'
      Icon = 'question'
      Uses = @('count')
      Body = @{
        One = 'You changed {count} older save point. backd8 will write that change into your project. It keeps a backup, so you can undo it later.'
        Other = 'You changed {count} older save points. backd8 will write those changes into your project. It keeps a backup, so you can undo them later.'
      }
      IfPublished = "If these save points are already on GitHub, you will need to replace GitHub's version afterwards."
      Buttons = @(
        @{ Id = 'Apply';  Role = 'accept'; Label = '&Apply edits' }
        @{ Id = 'Cancel'; Role = 'cancel'; Label = '&Keep editing' }
      )
      Default = 'Cancel'
      Details = 'Rewrites the commit and every later commit on this branch. The old tip is saved as refs/backd8/backup/<branch>/<time>. Signatures are dropped; tags and other branches keep pointing at the old commits.'
    }
    ReplaceRemote = @{
      Title = "backd8 Setup - Replace GitHub's version"
      Heading = "Replace GitHub's old version?"
      Icon = 'warning'
      Danger = $true
      Uses = @('count')
      Body = @{
        One = "{count} save point that you changed is already on GitHub. If you go on, GitHub's old version is replaced with yours. Anyone who has the old version must download your project again."
        Other = "{count} save points that you changed are already on GitHub. If you go on, GitHub's old versions are replaced with yours. Anyone who has the old versions must download your project again."
      }
      Buttons = @(
        @{ Id = 'Replace'; Role = 'accept'; Label = "&Replace GitHub's version" }
        @{ Id = 'Cancel';  Role = 'cancel'; Label = "&Don't publish" }
      )
      Default = 'Cancel'
      Details = 'Runs a force push with --force-with-lease, pinned to what backd8 just fetched, so it only overwrites GitHub if nobody pushed in between.'
    }
    ReplaceRemoteOthers = @{
      Title = 'backd8 Setup - Work by someone else'
      Heading = 'GitHub has work by someone else'
      Icon = 'warning'
      Danger = $true
      Uses = @('count')
      Body = @{
        One = 'GitHub holds {count} save point written by someone else. If you go on, it is deleted from GitHub. backd8 cannot bring it back.'
        Other = 'GitHub holds {count} save points written by someone else. If you go on, they are deleted from GitHub. backd8 cannot bring them back.'
      }
      Checkbox = 'I &understand that this work will be deleted from GitHub.'
      Buttons = @(
        @{ Id = 'Delete';   Role = 'accept'; Requires = 'Checkbox'; Label = @{ One = '&Delete it and publish'; Other = '&Delete them and publish' } }
        @{ Id = 'GetFirst'; Role = 'alt';    Label = '&Get the latest from GitHub' }
        @{ Id = 'Cancel';   Role = 'cancel'; Label = 'Cancel' }
      )
      Default = 'GetFirst'
      Details = 'Commits on the remote branch whose author is not your git identity would be removed by the force push (-DiscardRemote).'
    }
    DiscardRemote = @{
      Title = 'backd8 Setup - Work only on GitHub'
      Heading = 'Delete work that is only on GitHub?'
      Icon = 'warning'
      Danger = $true
      Uses = @('count')
      Body = @{
        One = 'GitHub has {count} save point that is not on this PC. It may come from another computer, or be an old version of work you changed. If you go on, it is deleted from GitHub.'
        Other = 'GitHub has {count} save points that are not on this PC. They may come from another computer, or be old versions of work you changed. If you go on, they are deleted from GitHub.'
      }
      Checkbox = 'I &understand that this work will be deleted from GitHub.'
      Buttons = @(
        @{ Id = 'Delete';   Role = 'accept'; Requires = 'Checkbox'; Label = @{ One = '&Delete it and publish'; Other = '&Delete them and publish' } }
        @{ Id = 'GetFirst'; Role = 'alt';    Label = '&Get the latest from GitHub' }
        @{ Id = 'Cancel';   Role = 'cancel'; Label = 'Cancel' }
      )
      Default = 'GetFirst'
      Details = 'The remote branch has commits that exist in none of your branches, tags or backd8 backups. A force push would delete them.'
    }
    Undo = @{
      Title = 'backd8 Setup - Undo'
      Heading = 'Undo your last change?'
      Icon = 'question'
      Uses = @('when')
      Body = 'backd8 will put your project back the way it was on {when}, before your last edit.'
      IfPublished = "If you already published that edit, you will need to replace GitHub's version again."
      Buttons = @(
        @{ Id = 'Undo';   Role = 'accept'; Label = '&Undo the change' }
        @{ Id = 'Cancel'; Role = 'cancel'; Label = '&Keep my change' }
      )
      Default = 'Cancel'
      Details = 'Moves the branch back to the newest refs/backd8/backup/<branch>/<time>.'
    }
    UndoForce = @{
      Title = 'backd8 Setup - Undo refused'
      Heading = 'Undo anyway and drop the newer save points?'
      Icon = 'error'
      Danger = $true
      Uses = @('count')
      Body = @{
        One = 'You saved {count} new save point after your last edit. Undoing now takes it out of your project. backd8 cannot bring it back for you.'
        Other = 'You saved {count} new save points after your last edit. Undoing now takes them out of your project. backd8 cannot bring them back for you.'
      }
      Checkbox = 'I &understand that the newer save points will be dropped.'
      Buttons = @(
        @{ Id = 'Undo';   Role = 'accept'; Requires = 'Checkbox'; Label = @{ One = '&Drop it and undo'; Other = '&Drop them and undo' } }
        @{ Id = 'Cancel'; Role = 'cancel'; Label = 'Keep my &work' }
      )
      Default = 'Cancel'
      Details = 'The branch changed since the last rewrite. With -Force the new commits are dropped from the branch but stay reachable through the reflog.'
    }
    DiscardEdits = @{
      Title = 'backd8 Setup - Discard edits'
      Heading = 'Discard your edits?'
      Icon = 'question'
      Uses = @('count')
      Body = @{
        One = 'You changed {count} older save point but have not applied it. If you discard, the change is forgotten. Your project is not touched.'
        Other = 'You changed {count} older save points but have not applied them. If you discard, the changes are forgotten. Your project is not touched.'
      }
      Buttons = @(
        @{ Id = 'Discard'; Role = 'accept'; Label = '&Discard edits' }
        @{ Id = 'Cancel';  Role = 'cancel'; Label = '&Keep editing' }
      )
      Default = 'Cancel'
    }
    LeaveWithPending = @{
      Title = 'backd8 Setup - Exit'
      Heading = 'Leave with unfinished work?'
      Icon = 'warning'
      Uses = @('count')
      Intro = 'You still have work that is not finished:'
      Lines = @{
        Changes = @{ One = '{count} change is not saved yet.'; Other = '{count} changes are not saved yet.' }
        Edits = @{ One = '{count} edit to an older save point is not applied yet.'; Other = '{count} edits to older save points are not applied yet.' }
        Unpublished = @{ One = '{count} save point is not on GitHub yet.'; Other = '{count} save points are not on GitHub yet.' }
      }
      Outro = 'Your files are safe. You can finish this the next time you open backd8.'
      Buttons = @(
        @{ Id = 'Leave'; Role = 'accept'; Label = '&Leave anyway' }
        @{ Id = 'Stay';  Role = 'cancel'; Label = '&Stay in backd8' }
      )
      Default = 'Stay'
    }
    ExitSetup = @{
      Title = 'backd8 Setup - Exit'
      Heading = 'Exit backd8?'
      Icon = 'question'
      Body = 'You can open backd8 again at any time. Your files and save points are safe.'
      Buttons = @(
        @{ Id = 'Exit'; Role = 'accept'; Label = '&Exit' }
        @{ Id = 'Stay'; Role = 'cancel'; Label = '&Stay' }
      )
      Default = 'Stay'
    }
    TrustProject = @{
      Title = 'backd8 Setup - Untrusted project'
      Heading = 'Do you trust this project?'
      Icon = 'warning'
      Danger = $true
      Uses = @('folder', 'settings')
      Body = 'The folder {folder} has hidden settings that can start programs on your PC: {settings}. Go on only if you made this folder or trust where it came from.'
      Buttons = @(
        @{ Id = 'Trust';  Role = 'accept'; Label = 'I made this / I &trust it' }
        @{ Id = 'Cancel'; Role = 'cancel'; Label = 'Choose another &folder' }
      )
      Default = 'Cancel'
      Details = 'The listed keys come from .git/config (for example core.fsmonitor, core.sshCommand, credential.helper).'
    }
    RiskyFiles = @{
      Title = 'backd8 Setup - Possible secrets'
      Heading = 'Include files that may hold secrets?'
      Icon = 'warning'
      Danger = $true
      Uses = @('count', 'files')
      Body = @{
        One = 'This file looks like it holds a password or key: {files}. Anyone who can see your project on GitHub could read it.'
        Other = 'These {count} files look like they hold passwords or keys: {files}. Anyone who can see your project on GitHub could read them.'
      }
      Buttons = @(
        @{ Id = 'LeaveOut'; Role = 'alt';    Label = @{ One = '&Leave it out'; Other = '&Leave them out' } }
        @{ Id = 'Include';  Role = 'accept'; Label = @{ One = 'Include it &anyway'; Other = 'Include them &anyway' } }
        @{ Id = 'Cancel';   Role = 'cancel'; Label = 'Go &back' }
      )
      Default = 'LeaveOut'
    }
  }

  # ---------- progress of a publish run ----------
  Progress = @{
    Heading        = 'Please wait while backd8 works'
    Instruction    = 'This can take a minute. Please do not turn off your PC.'
    CancelDisabled = 'Cancel is off while backd8 works, so nothing is left half done.'
    Steps = @(
      @{ Id = 'CheckSetup'; Running = 'Checking your folder and your sign-in';     Done = 'Folder and sign-in look good';        Failed = 'Could not check your folder or sign-in' }
      @{ Id = 'SaveFiles';  Running = 'Saving your files as a save point';        Done = 'Files saved as a save point';         Failed = 'Could not save your files' }
      @{ Id = 'Backup';     Running = 'Keeping a backup so you can undo';         Done = 'Backup kept';                         Failed = 'Could not make a backup' }
      @{ Id = 'ApplyEdits'; Running = 'Writing your edits to older save points';  Done = 'Edits written to your project';      Failed = 'Could not write your edits' }
      @{ Id = 'GetLatest';  Running = 'Getting the latest from GitHub';           Done = 'Got the latest from GitHub';          Failed = 'Could not get the latest from GitHub' }
      @{ Id = 'SignIn';     Running = 'Waiting for you to sign in to GitHub';     Done = 'Signed in to GitHub';                 Failed = 'Could not sign in to GitHub' }
      @{ Id = 'Publish';    Running = 'Publishing your save points to GitHub';    Done = 'Save points published';               Failed = 'Could not publish to GitHub' }
      @{ Id = 'Replace';    Running = "Replacing GitHub's old version";           Done = "GitHub's old version replaced";       Failed = "Could not replace GitHub's version" }
      @{ Id = 'Verify';     Running = 'Checking that GitHub has your work';       Done = 'GitHub has your work';                Failed = 'Could not check GitHub' }
      @{ Id = 'Undo';       Running = 'Putting your project back';                Done = 'Project put back as it was';          Failed = 'Could not undo your change' }
    )
  }

  # ---------- empty states ----------
  EmptyStates = @{
    NoSavePoints   = 'No save points yet. Save your files first.'
    NoChangedFiles = 'No changed files to show.'
    NoRecentFolders = 'No folders yet. Choose one to start.'
    NoAccounts     = 'No saved GitHub accounts were found on this PC.'
    NoEdits        = 'You have not changed any save points yet.'
    NoUndo         = 'There is nothing to undo yet.'
    NoMessageHint  = 'Describe what you changed, for example: fixed the menu'
  }

  # ---------- success ----------
  Success = @{
    Heading        = 'backd8 is complete'
    Instruction    = 'Click Finish to close backd8.'
    NextHeading    = 'What would you like to do next?'
    Variants = @{
      Published = @{
        Body = @{
          One   = 'Your {count} new save point is now on GitHub.'
          Other = 'Your {count} new save points are now on GitHub.'
        }
      }
      Replaced      = @{ Body = "GitHub now has your edited save points instead of the old ones." }
      Saved         = @{ Body = 'Your files are saved on this PC. They are not on GitHub yet.' }
      EditsApplied  = @{ Body = 'Your edits are applied. A backup was kept, so you can undo them.' }
      GotLatest     = @{ Body = 'Your project now has the latest work from GitHub.' }
      UndoDone      = @{ Body = 'Your last change is undone.' }
      Connected     = @{ Body = 'Your project is connected to GitHub.' }
    }
    NextSteps = @(
      @{ Id = 'View';    Text = 'View your project on GitHub.' }
      @{ Id = 'Edit';    Text = 'Change the note or date of an older save point.' }
      @{ Id = 'Folder';  Text = 'Choose another folder to work on.' }
      @{ Id = 'Return';  Text = 'Come back any time. backd8 remembers your folders.' }
    )
  }

  # ---------- status bar ----------
  StatusBar = @{
    NoProject   = @{ Text = 'No project chosen';             Tip = 'Choose a folder to begin.' }
    Checking    = @{ Text = 'Checking your project...';      Tip = 'backd8 is looking at your project.' }
    Branch      = @{ Text = 'Branch: {branch}';              Tip = 'A branch is the line of save points you are working on. Most projects use main.' }
    NoBranch    = @{ Text = 'Not on a branch';               Tip = 'Switch to a branch before you save new work.' }
    Unpublished = @{
      Text = @{ One = '{count} save point not on GitHub yet'; Other = '{count} save points not on GitHub yet' }
      Tip  = 'Publish to GitHub to put them online.'
    }
    Unsaved     = @{
      Text = @{ One = '{count} change not saved or published yet'; Other = '{count} changes not saved or published yet' }
      Tip  = 'Save your changed files as a save point first.'
    }
    Newer       = @{
      Text = @{ One = '{count} newer save point on GitHub'; Other = '{count} newer save points on GitHub' }
      Tip  = 'Get the latest from GitHub before you publish.'
    }
    InSync      = @{ Text = 'Up to date with GitHub';        Tip = 'Everything is saved and published.' }
    SignedIn    = @{ Text = 'Signed in as {account}';        Tip = 'This PC can publish to GitHub.' }
    SignedOut   = @{ Text = 'Not signed in to GitHub';       Tip = 'You will be asked to sign in when you publish.' }
    Offline     = @{ Text = 'Cannot reach GitHub';           Tip = 'Check your internet connection.' }
  }

  # ---------- dates ----------
  Dates = @{
    Presets = @(
      @{ Id = 'Now';      Label = 'Now';            Description = 'Use the current date and time.' }
      @{ Id = 'Yesterday'; Label = 'Yesterday';      Description = 'The same time as now, one day ago.' }
      @{ Id = 'WeekAgo';  Label = '1 week ago';     Description = 'The same time as now, seven days ago.' }
      @{ Id = 'MonthAgo'; Label = '1 month ago';    Description = 'The same time as now, one month ago.' }
      @{ Id = 'Pick';     Label = 'Pick a date...'; Description = 'Choose any day and time in the past.' }
    )
    Hint    = 'Type a date like 2024-03-01, or pick one.'
    Preview = 'This save point will be dated {date}.'
    Caution = 'A date in the past can mislead other people. Use it only where that is fair.'
    # Match = the engine text this entry explains (Parse-Date / Assert-GitDate). No Match = shown by the date box only.
    Errors = @(
      @{ Key = 'Empty';     Text = 'Pick a date.' }
      @{ Key = 'Ambiguous'; Match = '^Ambiguous date';            Text = 'That date could mean two things. Type it as year-month-day, such as 2024-03-01.' }
      @{ Key = 'TooEarly';  Match = 'is too early for git';       Text = 'Dates before 1971 do not work. Pick a later date.' }
      @{ Key = 'HasZone';   Match = '^Times with a zone';         Text = 'Type the time as it is on your PC, without a zone such as +09:00 or Z.' }
      @{ Key = 'Invalid';   Match = '^Invalid or missing date';   Text = 'backd8 cannot read that date. Try 2024-03-01 or 2024-03-01 14:30.' }
      @{ Key = 'Future';    Match = '^Date must be in the past';  Text = 'The date must be in the past. Pick a time that has already passed.' }
    )
  }

  # ---------- file checklist ----------
  FileChecklist = @{
    Columns = @{ File = 'File'; Change = 'Change'; Note = 'Note' }
    Hint    = 'Tick the files to include.'
    Kinds   = @{ New = 'New'; Changed = 'Changed'; Deleted = 'Deleted'; Renamed = 'Renamed' }
    Reasons = @{
      SecretName    = @{ Text = 'Name looks like a password or key file'; Tip = 'Files like this often hold secrets. Leave it out unless you are sure.' }
      SecretContent = @{ Text = 'Seems to contain a password or key';     Tip = 'The text inside looks like a password or key. Leave it out unless you are sure.' }
      BuildFile     = @{ Text = 'Build or editor file';                   Tip = 'Programs make these files by themselves. You usually do not need them on GitHub.' }
      TooBig        = @{ Text = 'Too big for GitHub ({sizeMB} MB)';       Tip = 'GitHub refuses files over {limitMB} MB, so this file is left out.' }
      Linked        = @{ Text = 'Linked folder';                          Tip = 'This folder points to somewhere outside your project, so backd8 skips it.' }
      Separate      = @{ Text = 'Separate project';                       Tip = 'This folder is a project of its own, so it cannot be saved inside this one.' }
    }
  }

  # ---------- F1 ----------
  Help = @{
    F1 = @{
      Title  = 'backd8 Help'
      Intro  = 'You can use backd8 with the mouse or only with the keyboard.'
      Shortcuts = @(
        @{ Keys = 'F1';                 Does = 'Open this help.' }
        @{ Keys = 'Alt + underlined letter'; Does = 'Press that button, or go to that box.' }
        @{ Keys = 'Alt + B';            Does = 'Go back one page.' }
        @{ Keys = 'Alt + N';            Does = 'Go to the next page.' }
        @{ Keys = 'Enter';              Does = 'Press the highlighted button.' }
        @{ Keys = 'Esc';                Does = 'Close a message, or ask to leave backd8.' }
        @{ Keys = 'Tab / Shift + Tab';  Does = 'Move to the next or the previous box.' }
        @{ Keys = 'Space';              Does = 'Tick or untick the selected file.' }
        @{ Keys = 'Ctrl + A';           Does = 'Tick all the files in the list.' }
        @{ Keys = 'F5';                 Does = 'Check your project again.' }
        @{ Keys = 'Ctrl + C';           Does = 'Copy the selected text, or the details of a problem.' }
      )
      Footer = 'Your files are only changed when you press a button that says so.'
    }
  }
}
