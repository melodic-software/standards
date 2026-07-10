# Lefthook Python

Opt-in staged Python feedback. `lefthook.yml` runs `ruff check` and `ruff format
--check` against staged Python files while Ruff discovers the root `ruff.toml`.
Compose it with `lefthook-base` for shared strict settings and root-aware glob
matching. Pyright stays in CI because type analysis needs whole-project context.
