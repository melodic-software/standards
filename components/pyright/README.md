# Pyright

Strict, repository-agnostic Python type-checking defaults for
[Pyright](https://microsoft.github.io/pyright/).

`pyrightconfig.json` is the component's exported payload. It owns type
correctness while Ruff owns lint, formatting, imports, and unused-symbol
findings. It deliberately omits repository scope and interpreter-floor keys:
consumers supply `include`, `exclude`, `executionEnvironments`, `stubPath`, and
`pythonVersion` for their own project.

Run Pyright with this config directly, or use the `pyright` action from
`melodic-software/ci-workflows` and pass the project-specific source paths.
When a repository needs a different committed Pyright policy, it owns the whole
config rather than partially editing this upstream-owned payload.

`fixtures/` and `pyright.test.sh` prove that strict typing is active; they are
component contract tests and are not distributed to consumers.
