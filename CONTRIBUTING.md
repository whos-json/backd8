# Contributing to backd8

Thanks for helping. backd8 is a small Windows PowerShell 5.1 + Git for Windows tool, so changes are easy to try.

## Ground rules
- **Never test against your real git config.** Every test sets `GIT_CONFIG_GLOBAL` and `BACKDATE_CONFIG` to temp files. If you try things by hand, do the same:

      $env:GIT_CONFIG_GLOBAL = "$env:TEMP\bd-test\gitconfig"
      $env:BACKDATE_CONFIG   = "$env:TEMP\bd-test\config.json"
      git config --global --list --show-origin   # must list only the temp file

- No network in tests. Pushes go to local bare repos or to `tests\fake-github.ps1`.
- Windows PowerShell 5.1 only (no `?:`, no `` `u{} ``). Remember: variable names are case-insensitive (`$E` and `$e` are the same variable), `R` is an alias of `Invoke-History`, and bare empty-string arguments are dropped when calling native commands.
- Test files that contain non-ASCII text (`uat.ps1`, `uat-repo.ps1`, `simulate.ps1`) must stay UTF-8 **with BOM**.
- The `hooks\` shims must keep LF line endings (`.gitattributes` enforces it).

## Layout
| File | Purpose |
|---|---|
| `lib.ps1` | config, install/uninstall, the post-commit hook logic |
| `repo.ps1` | list / reword / redate / undo commits, push |
| `github.ps1` | "can this PC push?" checks and sign-in guidance |
| `backdate.ps1` | CLI and hook entry point |
| `gui.ps1`, `BackD8.cs` | WinForms window and the launcher exe |

## Running the tests
    powershell -ExecutionPolicy Bypass -File tests\uat.ps1        # backdating, hook, GUI self-test
    powershell -ExecutionPolicy Bypass -File tests\uat-repo.ps1   # commit editing, push, GitHub checks
    powershell -ExecutionPolicy Bypass -File tests\simulate.ps1   # end-to-end story against a fake GitHub
    powershell -ExecutionPolicy Bypass -File tests\uat-workflow.ps1   # workflow state machine: proof + real repositories

All four must pass. `uat.ps1` briefly starts `BackD8.exe`, so a window may flash.

## Pull requests
- Add or extend a test for any behaviour you change; bug fixes should come with a test that failed before.
- Anything that rewrites history or pushes must keep its safety properties: backup ref before the move, compare-and-swap update, `--force-with-lease`, refusal when the remote holds commits you do not have.
- Rebuild the exe with `powershell -File build.ps1` only if `BackD8.cs` changed.
- Keep the README in step with the CLI (`backdate.ps1 help` is the source of truth).
