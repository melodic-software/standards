# python module

Python static analysis: linting + formatting via [Ruff](https://docs.astral.sh/ruff/)
and type-checking via [Pyright](https://microsoft.github.io/pyright/).

Both configs lean strict — findings are hard failures, in line with a
warnings-as-errors posture — and the two tools are split so they never
double-report: Ruff owns lint concerns (including unused imports/variables,
which it can autofix), Pyright owns type correctness.

## Contents

- `ruff.toml` — the lint + format ruleset. Self-documents its rationale inline,
  including the opt-in groups a consumer can add and the extend semantics.
- `pyrightconfig.json` — the portable type-checking ruleset only. Pyright config
  is plain JSON with no comments, so the rationale lives here:
  - `typeCheckingMode: strict` is the base; the explicit `report*` keys escalate
    the high-value rules that strict still leaves at `none`
    (e.g. unnecessary `# type: ignore`, implicit override, uninitialized
    instance variables, import cycles, unreachable code) to `error`.
  - `reportUnusedImport` / `reportUnusedVariable` are set to `none` so Ruff is
    the single owner of unused-symbol findings.
  - It carries **no project-scope keys** — see adoption below.

Neither tool ships a runner here; the CI lanes that install pinned engines and
run them live in the `ci-workflows` repo (execution) as the `ruff` and `pyright`
composite actions. Pyright runs there with `--warnings` so even residual warnings
fail the build.

## Engine

- Ruff (any recent release; the repo dogfoods a pinned version in CI).
- Pyright (likewise pinned in CI).

`target-version` (Ruff) and `pythonVersion` (Pyright) are intentionally omitted:
each consuming repo's `requires-python` / active interpreter drives them, so the
base is correct for any Python floor.

## Adopt in a repo

1. **Ruff** — copy `ruff.toml` to the consuming repo's root (canonical home
   `modules/python/`). Extend it with `extend = "ruff.toml"` + `extend-select`;
   do not use `select`, which replaces the inherited list rather than adding to
   it. Reference the `ci-workflows` `ruff` and `pyright` actions from CI.
2. **Pyright** — copy `pyrightconfig.json` to the consuming repo's root, then add
   the project-scope keys the base omits:
   - `include` — the source roots to check, e.g. `["src", "tests", "tools"]`.
     Type-check tests too; excluding them is an anti-pattern.
   - `exclude` — only if needed; Pyright already excludes `**/node_modules`,
     `**/__pycache__`, and dotfiles by default.
   - `executionEnvironments` — one entry per sub-project with its own venv /
     import roots (`extraPaths` to its `site-packages`), and the right place to
     relax a rule for one directory rather than weakening the global standard.
   - `stubPath` — only if custom stubs live outside the default `./typings`.

## Test

`fixtures/python/{good,bad}` exercise both rulesets; `python.test.sh` asserts the
good fixture is clean and the bad fixture is flagged — proving the configs load
(not just that the tools ran) — via the shell harness
(`harness/shell/run-tests.sh`). The `bad` fixture is intentionally
non-conforming and is excluded from the repo's own self-lint.
