# Ruff

Strict linting and formatting policy for Python. The exported payload is the
root-canonical [`ruff.toml`](../../ruff.toml); it lives at the tool-mandated root
path exactly once, while this component owns its documentation and contract
tests.

Ruff owns lint, formatting, imports, modernization, security heuristics, and
unused-symbol findings. Pyright separately owns type correctness. The shared
policy omits `target-version`, allowing each repository's Python floor to drive
syntax modernization.

Managed consumers do not edit `ruff.toml`. A nested Python project may use
Ruff's native `extend` plus `extend-select` and
`extend-per-file-ignores` for additive policy. A repository requiring a
different root policy opts out and owns the whole component locally.

`fixtures/` and `ruff.test.sh` prove lint, format, banned-API, and timezone-aware
datetime rules. Fixtures and tests stay in this source slice and are not
distributed.
