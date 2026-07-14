# Lefthook Python

Opt-in staged Python feedback. `lefthook.yml` runs `ruff check` and `ruff format
--check` against staged Python files while Ruff discovers the root `ruff.toml`.
The distribution manifest materializes it at `.lefthook/python.yml` and requires
both `lefthook-base` and `ruff`, so the complete staged-check contract moves as
one reviewed unit. The consumer root `lefthook.yml` opts in by extending that
fragment. Pyright stays in CI because type analysis needs whole-project context.
