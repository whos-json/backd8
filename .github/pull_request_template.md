## What and why

## Checklist
- [ ] `tests\uat.ps1`, `tests\uat-repo.ps1` and `tests\simulate.ps1` pass (isolated: they never touch your real git config)
- [ ] New behaviour has a test; a bug fix has a test that failed before
- [ ] Anything that rewrites history or pushes keeps its safety properties (backup ref, compare-and-swap, `--force-with-lease`, foreign-commit check)
- [ ] README / `backdate.ps1 help` updated if the CLI changed
