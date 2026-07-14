# Pyright

Strict, repository-agnostic Python type-checking defaults for
[Pyright](https://microsoft.github.io/pyright/).

`pyrightconfig.json` is the component's exported base. It owns type correctness
while Ruff owns lint, formatting, imports, and unused-symbol findings. The
distribution manifest materializes it below the consumer root at
`.github/standards/pyright/pyrightconfig.json`. A consumer-owned root
`pyrightconfig.json` uses Pyright's documented
[`extends`](https://github.com/microsoft/pyright/blob/main/docs/configuration.md#environment-options)
setting to inherit this policy and supplies only its repository scope and
interpreter environment: `include`, `exclude`, `executionEnvironments`,
`stubPath`, and `pythonVersion`.

The nested destination is intentional: Pyright resolves relative paths against
the configuration file that declares them and otherwise defaults project scope
to the config directory. Keeping scope in the consumer root prevents the shared
payload from guessing repository layout while preserving every strict
diagnostic. Run Pyright against the consumer root config, or use the `pyright`
action from `melodic-software/ci-workflows` with that config. When a repository
needs a different type-checking policy, it owns the whole component rather than
partially editing this upstream-owned payload.

`fixtures/` and `pyright.test.sh` prove that strict typing is active; they are
component contract tests and are not distributed to consumers.
