# fixtures

Sample inputs that prove each module's linter behaves: a *good* sample that must pass clean, and a *bad* sample that must produce the expected findings. Module tests run their linter against these and assert the outcome — this is how the standards are tested without any application or library code.

Layout (populated per module, starting in Phase 1):

```text
fixtures/
  markdown/   good/  bad/
  powershell/ good/  bad/
```

Bad fixtures are intentionally non-conforming. They are excluded from the repo's own self-lint so they don't fail CI as authored content.
