# Security policy

## What backd8 touches
- Sets git's **global** `core.hooksPath` to this folder's `hooks\`. Every commit then runs `backdate.ps1` (started with `-ExecutionPolicy Bypass` for that process only). Anyone who can write to this folder can run code on every commit, so keep it in a location only you can write to.
- Rewrites commit history when you use `reword` / `redate`, and pushes (optionally with `--force-with-lease`) when you use `push`.
- Never stores, asks for, or logs passwords or tokens. Sign-in is delegated to git's credential helper (Git Credential Manager), the GitHub CLI or SSH. `user:token@` in remote URLs is masked as `***@` in all output.

## Reporting a vulnerability
Please open a **private** security advisory on GitHub (Security tab, "Report a vulnerability") instead of a public issue. Include the backd8 version/commit, steps to reproduce, and the impact. You should get a reply within a few days.

## Supported versions
Only the latest commit on the default branch is supported.
