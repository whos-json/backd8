<p align="center">
  <img src="docs/images/banner.png" alt="backd8 - rewrite your commit timeline" width="100%">
</p>

<p align="center">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white">
  <img alt="PowerShell 5.1" src="https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white">
  <img alt="Git for Windows" src="https://img.shields.io/badge/Git%20for%20Windows-required-F05032?logo=git&logoColor=white">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2dd4bf">
</p>

**backd8** is a small Windows tool that walks you through three things: pick a project folder, tidy the messages and dates of its commits, and publish it to GitHub. It looks and behaves like a Windows 98 Setup wizard: one question per page, `< Back`, `Next >`, `Cancel`, and a sidebar that always shows where you are.

> **Choose a folder -> edit the date and message of its commits -> publish to GitHub.**

<p align="center">
  <img src="docs/images/hero.png" alt="backd8 as a Windows 98 style setup wizard" width="760">
</p>

- **Choose any folder.** If it is not a git project yet, backd8 turns it into one and links it to your GitHub repository.
- **Save your work** with a message and a date you choose (now, or in the past).
- **Edit older commits**: change their messages and dates, with an automatic backup and one-click undo.
- **Publish to GitHub** from the same window. backd8 checks that this PC is signed in and guides you through signing in if it is not.
- Use the **window** (`BackD8.exe`) or the **command line** (`backdate`).

> [!WARNING]
> Editing commits rewrites history. Publishing the change replaces GitHub's version, and anyone who already pulled the old history must reset or re-clone. Faking commit dates can mislead collaborators; use it only where that is appropriate. The optional auto-backdating hook (see [Advanced](#advanced-auto-backdate-every-new-commit)) is off unless you install it.

## A tour of the wizard

Every page asks one thing and offers one recommended button. A button that cannot be used yet is greyed out, and its tooltip says why.

| | |
|---|---|
| **1. Choose your project.** Browse, paste a path or drop a folder on the window. Recent folders are remembered.<br><img src="docs/images/01-choose-folder.png" alt="Choose your project"> | **2. Save your changes.** Tick the files, describe what you changed, pick a date. Files that look like passwords or keys are flagged and can be left out in one click.<br><img src="docs/images/02-changes.png" alt="Save your changes"> |
| **3. Publish to GitHub.** One recommended button; the destination (`owner/repo`) is shown next to it.<br><img src="docs/images/03-ready-to-publish.png" alt="Ready to publish"> | **4. Change older commits.** Select a commit, change its message or date, or spread several over a period.<br><img src="docs/images/04-edit-history.png" alt="Edit history"> |
| **5. Pick the dates.** Presets, an exact date and time, or a spread across a period, with a preview.<br><img src="docs/images/05-dates.png" alt="Dates"> | **6. All done.** Everything is saved and published. Undo stays one click away.<br><img src="docs/images/06-published.png" alt="Published"> |
| **7. GitHub has a different version.** backd8 explains in plain words what would be replaced and asks before it does anything.<br><img src="docs/images/07-needs-replace.png" alt="Replace GitHub's version"> | **8. Sign in.** Your browser opens once; Windows remembers it.<br><img src="docs/images/08-sign-in.png" alt="Sign in"> |

The wizard is a view of a state machine, so it never leaves you stuck: whatever goes wrong, the page you land on explains it and offers a way forward (see [How the workflow is built](#how-the-workflow-is-built)).

## Requirements
- Windows with Windows PowerShell 5.1 (built into Windows 10/11)
- [Git for Windows](https://git-scm.com/download/win): `winget install --id Git.Git -e` (it also installs Git Credential Manager for GitHub sign-in)

## Quick start
**Window:** run `BackD8.exe` (a small launcher for `gui.ps1`, no console).
1. **Choose your folder.** A plain folder such as a C# project? backd8 offers *Turn this folder into a project*; paste your GitHub repository address (create an empty repository at <https://github.com/new> first).
2. **Save your changes.** Tick the changed files, describe what you changed, pick the date (default: now) and click *Next*. To fix older commits instead, choose *Change an older save point*.
3. **Publish.** If you are not signed in, the button says *Sign in to GitHub* (your browser opens once). If GitHub still has the old version of edited commits, backd8 explains and asks before replacing it.

**Command line:** use `backdate.cmd` in this folder (it starts PowerShell with `-ExecutionPolicy Bypass` for that one process, so it works even though Windows blocks scripts by default). Open a terminal here, or add this folder to your `PATH`. In cmd.exe you can then type just `backdate`; in PowerShell type `backdate.cmd` (PowerShell would pick the blocked `.ps1` first).

    backdate init    C:\Users\you\Projects\portfolio https://github.com/you/portfolio.git
    backdate changes C:\Users\you\Projects\portfolio
    backdate publish C:\Users\you\Projects\portfolio "first version" -Date 2024-03-01T14:30:00

`publish` = save all changes (with your message and date, or "Update N files" if you give none), then push. Use `commit` to skip the push. Commit with `-Staged` to commit only what you staged yourself.

### Editing older commits
    backdate commits C:\path\to\repo 20
    backdate reword  C:\path\to\repo HEAD~2 "clearer message"
    backdate redate  C:\path\to\repo a1b2c3d 2024-03-01T14:30:00
    backdate push    C:\path\to\repo -Force

`reword` and `redate` (or the window) rewrite the commit you pick **and every commit after it on the current branch**:
- Trees and authors are kept; only the message or date you changed differs. Untouched dates and messages are preserved byte for byte.
- Every later commit gets a new hash, because a hash covers its parents. Tags and other branches still point at the old commits (backd8 lists them).
- GPG/SSH signatures cannot survive a rewrite and are dropped on all rewritten commits. Git notes are carried over.
- Before moving the branch, backd8 saves the old tip as `refs/backd8/backup/<branch>/<timestamp>` (and the new tip as `refs/backd8/rewritten/...`, which `undo` uses to notice later commits). The newest 20 backups per branch are kept. `undo` restores the newest backup and refuses if you added commits since (use `-Force` to override; they stay in the reflog).
- Refused when HEAD is detached or a rebase/merge/cherry-pick is in progress. The branch update is compare-and-swap, so a concurrent change aborts the rewrite.

### Publishing safely
If the old commits were already published, GitHub has history your branch no longer contains, so a normal publish is refused with an explanation. `push -Force` ("Replace GitHub's version") first fetches, then uses `--force-with-lease` pinned to what it just saw, so it overwrites GitHub only if nobody published in between.

**Other people's commits are protected.** If GitHub holds commits that exist in none of your branches, tags or backups, or commits written by someone else (including a commit of theirs that you reworded), the replace is refused. Get them first with *Get the latest from GitHub*, or confirm with `-DiscardRemote` (the window asks a second time) if you really mean to delete them.

Save and publish also refuse to run in the middle of a rebase/merge, check that GitHub is reachable **before** saving anything, and flag files that look like secrets (`.env`, keys, `id_rsa`, ...) so you do not commit them by accident.

## Set up GitHub on a new PC
Publishing needs three things. `backdate github <folder>` (or the window's status line) checks them and prints the fix for whatever is missing:

1. **Git** installed: `winget install --id Git.Git -e`
2. **Your identity**: the wizard asks for your name and email; or `git config --global user.name "Your Name"` and `git config --global user.email "you@example.com"`. Use an email linked to your GitHub account (<https://github.com/settings/emails>), or GitHub will not count the commits on your profile.
3. **A GitHub sign-in and a remote.** Create an empty repository at <https://github.com/new>, then `backdate remote <folder> https://github.com/<you>/<repo>.git` (or paste it into the window).

**Sign in** with `github-login <folder>` or the **Sign in to GitHub** button. It does what the remote needs:
- HTTPS remote: a dry-run push, so Git Credential Manager opens your browser. Approve once; Windows remembers it.
- No credential helper but the GitHub CLI is installed: `gh auth login`.
- SSH remote: tests `ssh -T git@github.com` (create a key with `ssh-keygen -t ed25519` and add it at <https://github.com/settings/ssh/new>).

With several saved GitHub accounts, backd8 picks the one that owns the repository and remembers it per project (`backdate account <folder>` shows or changes it). Other problems get their own page: organisation SSO to authorise, an SSH host key problem, "repository not found", a temporary GitHub error, or no connection.

backd8 never asks for, stores or logs a password or token: git's credential helper does. Background checks set `GIT_TERMINAL_PROMPT=0` so nothing hangs, a push is stopped after 5 minutes, and `user:token@` in remote URLs is masked as `***@`.

## Advanced: auto-backdate every new commit
Optional and off by default. A global `post-commit` hook amends each new commit on this PC so it carries a date you chose, starting at a start date and moving forward 1-6 hours per commit (`backdate install`, `backdate set * 2024-03-01`, `backdate on`).

> [!WARNING]
> **While this is ON, every commit you make on this PC, in every repository, is rewritten with a fake date.** The hook is global (`core.hooksPath`). Turn it OFF (`backdate off`) or remove it (`backdate uninstall`) when you do not want that. You do not need it for the folder -> edit -> publish flow above.

`install` does not turn backdating on by itself (a previous ON setting is kept and reported). A repo with no entry uses the default start date and gets its own clock on its first commit. Once the clock catches up with real time, backdating stops for that repo. Start dates must be in the past. A commit is never dated before a backdated parent, so if a repo already has newer commits, the clock effectively starts after them (`set` tells you).

## CLI reference
`backdate <command> [args]` (`help` prints the same list; `backdate.cmd` runs `powershell -NoProfile -ExecutionPolicy Bypass -File backdate.ps1`)

| Command | Effect |
|---|---|
| `state <folder> [-Online]` | Where the project is in the workflow, what each step would do, and what is recommended next. `-Online` also looks at GitHub now. |
| `state-model` | Prove the workflow model (see below). |
| `init <folder> [github-url]` | Turn a plain folder into a git project (branch `main`) and optionally link it to GitHub. |
| `remote <folder> <github-url>` | Link (or re-link) the project to its GitHub repository. |
| `changes <folder>` | List files changed since the last commit (flags secret-looking files). |
| `commit <folder> <message> [-Staged] [-Date <date>] [-IncludeRisky]` | Commit all changes (or only staged ones) with your message and optional past date. `-MessageFile <file>` for multi-line messages. Files that look like secrets are refused unless you add `-IncludeRisky`. |
| `publish <folder> [message] [-Date <date>] [-Force]` | Commit all changes (if there are any), then push, in one step. After `reword`/`redate` use `push <folder> -Force`. |
| `commits <folder> [count]` | List recent commits (default 20): short hash, date, subject. |
| `reword <folder> <sha> <message>` | Change a commit message. `<sha>` can be a short/full sha, `HEAD~2`, a branch or a tag. |
| `redate <folder> <sha> <date>` | Change a commit's author and committer date. Date must be in the past. |
| `undo <folder> [-Force]` | Undo the most recent reword/redate on the current branch. |
| `push <folder> [-Force] [-DiscardRemote]` | Push the current branch to its remote (`origin` if none is configured). |
| `sync <folder>` | Get newer changes from GitHub (fast-forward, or merge when both sides changed; never rewrites your commits; on a conflict nothing is changed). |
| `ignore <folder> [dotnet\|node\|python\|java\|generic]` | Add a `.gitignore` so build and editor files are not committed. |
| `trust <folder>` | Say you trust a project whose hidden settings can run programs. |
| `account <folder> [name]` | Show, or choose, which saved GitHub account this project uses. |
| `github <folder>` | Check this PC can publish: git identity, remote, saved sign-in, dry-run push. Prints what to do if not. |
| `github-login <folder>` | Sign in to GitHub (see above). |
| `install [-Force]` / `uninstall` | (Advanced) Write or remove the auto-backdate hooks and the global `core.hooksPath`. |
| `on` / `off` / `status` / `list` | (Advanced) Switch auto-backdating, show its state and per-repo clocks. |
| `set <folder or *> <date>` / `remove <folder>` | (Advanced) Set or forget a start date. |
| `help` | Print usage. |

Dates: `2024-03-01` or `2024-03-01T14:30:00`, in your PC's local time. `01/03/2024` and `01.03.2024` are rejected as ambiguous, and times with a zone such as `+09:00` or `Z` are not accepted. The hook leaves alone commits that already carry a date older than one day (set by hand), merge commits, rebases, cherry-picks and partial commits (other changes still staged).

> **About dates on GitHub:** GitHub's contribution graph uses the author date, only for commits on the default branch, and only when the commit's email is linked to your account. It can take a while to update.

## How the workflow is built
The window and the `state` command are views of one deterministic finite state machine (`workflow.ps1`). Facts about the project (is it a git project, trusted, has changes, ahead/behind GitHub, signed in, ...) resolve to exactly one of 24 named states; each state offers a fixed list of actions, each guarded by prerequisites that explain themselves when not met. Every action re-checks its state before it runs and re-derives the state afterwards, and every error maps to a class with a recovery action, so a failure always lands somewhere with a way forward.

`backdate state-model` (and `tests\uat-workflow.ps1`) prove, over more than two thousand fact combinations, that the model is deterministic and total, has no dead ends, and that every state can reach "everything is saved and published". All wording shown in the window lives in `assets\strings.en.psd1` and is checked by `tests\strings-check.ps1` (plain words, one sentence per explanation, every button has a tooltip). The design rules are in [docs/DESIGN.md](docs/DESIGN.md).

## Known limits
- A repo-local `core.hooksPath` overrides the global one, so hook backdating does nothing there (`status` warns; reword/redate/push still work).
- Installed hooks forward to the repo's own `.git/hooks/<name>` so those keep working.
- Hooks call this folder's `backdate.ps1` on every commit. Run `uninstall` BEFORE moving or deleting the folder: a hooksPath pointing at a missing folder makes git ignore every repository's own hooks too (`status` warns about it). After a move, run `install` from the new location.
- A quoted path ending in a backslash (`"C:\repo\"`) is mangled by PowerShell argument parsing; omit the trailing `\`.
- When a sync finds the same file changed on both sides, backd8 changes nothing and tells you; combine them in a git tool.
- The hook and `BackD8.exe` start PowerShell with `-ExecutionPolicy Bypass` for that process only; your machine policy is not changed.
- Settings live in `config.json` and `ui.json` inside this folder (both git-ignored). Deleting the folder deletes the settings.
- If `BackD8.exe` shows nothing, run `powershell -STA -File gui.ps1` to see errors.

## Troubleshooting
- **"... cannot be loaded because running scripts is disabled on this system"**, or "not digitally signed": use `backdate.cmd` (and `BackD8.exe` for the window), which start PowerShell with `-ExecutionPolicy Bypass` for that one process. Files from a downloaded zip are also marked as blocked: right-click the zip > Properties > Unblock before extracting, or run `Get-ChildItem -Recurse | Unblock-File` in the folder.
- **The window does not appear:** run `powershell -STA -ExecutionPolicy Bypass -File gui.ps1` in a terminal to see the error. Crashes are also written to `%TEMP%\backd8-error.log`.
- **GitHub says you are not signed in although you are:** with several saved GitHub accounts, run `backdate account <folder>` to see which one the project uses.

## Uninstall / cleanup
    backdate uninstall

Then delete the folder. This does not change any commits already made. Leftover `refs/backd8/...` refs stay in the repos you edited (`git for-each-ref refs/backd8`).

## Fonts and art
backd8 bundles **no font files**: the window uses Tahoma, Arial and Lucida Console, the faces Windows itself shipped in the Windows 98 / 2000 era, drawn bi-level like the original wizard. They are used under the Windows licence. Details and the reasons for not shipping a pixel font are in [assets/fonts/FONTS.md](assets/fonts/FONTS.md). The wizard art (monitor, floppy disk, cloud, icons) in `assets\art` is original pixel art made for this project (`assets\make-art.ps1` redraws it).

## Development
`powershell -ExecutionPolicy Bypass -File build.ps1 [-Out <exe path>]` rebuilds `BackD8.exe` from `BackD8.cs` with the .NET Framework `csc.exe` that ships with Windows (no SDK). `powershell -ExecutionPolicy Bypass -File docs\make-assets.ps1` regenerates the logo and banner, and `docs\make-shots.ps1` re-renders the screenshots above from real demo projects (a local folder stands in for GitHub; no network).

Tests use temporary folders, a private git config (`GIT_CONFIG_GLOBAL`) and `BACKDATE_CONFIG`, so your real settings are untouched:

    powershell -ExecutionPolicy Bypass -File tests\uat.ps1            # backdating, hook, window self-tests
    powershell -ExecutionPolicy Bypass -File tests\uat-repo.ps1       # commit editing, publishing, GitHub checks (about 10 minutes)
    powershell -ExecutionPolicy Bypass -File tests\uat-workflow.ps1   # the workflow state machine: formal proof + every state with real repositories
    powershell -ExecutionPolicy Bypass -File tests\simulate.ps1       # end-to-end story against a fake GitHub
    powershell -ExecutionPolicy Bypass -File tests\strings-check.ps1  # every word in the window: wording, tooltips, coverage of every state

`uat.ps1` briefly starts the window (`BackD8.exe`), so one may flash on screen.

`tests\simulate.ps1` plays a full story against `tests\fake-github.ps1`, a real smart-HTTP git server that requires a login: new PC without identity, backdated commits, publishing refused until "signed in", edits, replacing GitHub's version, a second computer, undo, uninstall. No internet is used. Test files contain non-ASCII text and must stay UTF-8 with BOM. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License
[MIT](LICENSE)
