# Lefthook Python

Opt-in staged Python feedback. `lefthook.yml` runs `ruff check` and `ruff format
--check` against staged Python files while Ruff discovers the root `ruff.toml`.
The distribution manifest materializes it at `.lefthook/python.yml` and requires
`ruff`, so the complete staged-check contract moves as one reviewed unit. The
consumer root `lefthook.yml` opts in by extending that fragment and sets
`min_version: "2.0.5"` and `assert_lefthook_installed: true` (see
[lefthook-base](../lefthook-base/README.md#remote-form)). The fragment sets
`glob_matcher: doublestar` itself, so its `**/` glob also matches files at the
repository root. Pyright stays in CI because type analysis needs whole-project
context.
