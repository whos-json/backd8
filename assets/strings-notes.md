# strings.en.psd1: notes for the UI

Load: `Import-PowerShellDataFile assets\strings.en.psd1` (UTF-8 with BOM). Check: `tests\strings-check.ps1`.

| Section | Use |
|---|---|
| `States.<State>` | `Title`, `Help` (black sidebar), `Heading`, `Instruction`, `Page` (which page layout), optional `Details` (technical, only behind Show details) |
| `Actions.<Id>` + `ActionOverrides['State/Id']` | `Label`, `Access` (Label with one `&`), `Tooltip`. Use the override when the key exists. |
| `Guards` | Why-disabled text. Find the entry whose `Match` regex matches the engine's `Why`; `Dynamic` entries (`Get-RemoteUrlProblem`, `Assert-GitDate`) are shown next to the field using `AddressProblems` / `Dates.Errors` |
| `ErrorClasses.<class>` | `Headline`, `Happened`, `Todo`; `Details` goes behind `TechInfo.Show`. `ErrorLabels` are the two caption words |
| `Dialogs.<Name>` | `Title`, `Heading`, `Body` (string or `@{One;Other}`), `Checkbox`, `Buttons` (`Role` accept / alt / cancel, `Requires`), `Default` = the safe button, `Uses` = placeholders |
| `Pages.<Page>.Controls` | field and button texts with `&` access keys. Back (B) and Next (N) are on every page. |
| `Progress.Steps` | `Running` / `Done` / `Failed` per step id |
| `Welcome`, `FirstRun`, `Success`, `Problem`, `EmptyStates`, `StatusBar`, `Dates`, `FileChecklist`, `Help.F1`, `Chrome`, `TechInfo`, `Messages` | as named |

Rules
- Plural: any text with `{count}` is `@{ One; Other }` (pick `One` when count is 1). Button labels may be pairs too.
- Placeholders: `{name}` is replaced by the UI. The allowed names are in `Placeholders`.
- Access key: insert nothing yourself, `Access` / Controls already contain the `&`. Keys are unique per page (and per state view, and on the problem box).
- Dialog `Danger`: the accept button is never the default. `Requires = 'Checkbox'` means the button stays disabled until the box is ticked.
- If both `Others` and `RemoteOnly` are above 0, show `DiscardRemote` (the stronger warning); `ReplaceRemoteOthers` is for foreign authors only.
- The status bar says "Up to date with GitHub" instead of "In sync": the glossary avoids "sync" in primary text.
- Shortcuts promised in `Help.F1`: F1, Alt+letter, Enter, Esc, Tab, Space, Ctrl+A (tick all files), F5 (check again), Ctrl+C. F5 and Ctrl+A need to be wired up.
- Words that never appear outside `Details*` keys: repository, push, pull, sync, fetch, commit (except once in `Welcome.Explain`), merge, rebase, remote, force, and the other words in the checker's list.
