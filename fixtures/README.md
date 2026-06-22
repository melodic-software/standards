# fixtures

Sample inputs that prove each module's linter behaves: a *good* sample that must pass clean, and a *bad* sample that must produce the expected findings. Module tests run their linter against these and assert the outcome — this is how the modules are tested without any application or library code.

Layout (one directory per module):

```text
fixtures/
  editorconfig/ good/  bad/
  gitleaks/     good/        # bad inputs are built at runtime, not committed
  lychee/       good/  bad/
  markdown/     good/  bad/
  powershell/   good/  bad/
  shellcheck/   good/  bad/
  typos/        good/  bad/
```

Bad fixtures are intentionally non-conforming. They are excluded from the repo's own self-lint so they don't fail CI as authored content.

gitleaks is the one exception to the good/bad pair: committing secret-shaped bytes would trip the repo's own scan and external secret scanners, so its bad inputs are constructed at runtime inside the module test rather than committed.
