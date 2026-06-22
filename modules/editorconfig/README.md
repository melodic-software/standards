# editorconfig module

Validates that files obey the repo-root [`.editorconfig`](https://editorconfig.org/)
via [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker).

## Why the split

`.editorconfig` and `.gitattributes` are **copy-only**: editors and Git discover
them only by walking up the directory tree, so they cannot be referenced from a
module path the way a `--config` file can. They live canonically at the **repo
root** — those root files *are* the published standard. This module holds the
one piece that *is* referenceable: the checker's settings.

## Contents

- `.editorconfig-checker.json` — checker settings: which checks run and which
  paths are excluded. The end-of-line check is **disabled** here because
  `.gitattributes` is the single authority for line endings; indent-size and
  max-line-length are disabled as editor hints owned by per-language formatters.

## Engine

[editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker)
(`editorconfig-checker`, a.k.a. `ec`). It reads the rules from the nearest
`.editorconfig` and exits `0` when clean, non-zero on findings.

## Adopt in a repo

- **The rules** — copy the root `.editorconfig` (and `.gitattributes`) to the
  consuming repo's root, where every editor and `ec` auto-discover them.
- **The checker config** — reference it without copying:

  ```bash
  editorconfig-checker -config modules/editorconfig/.editorconfig-checker.json .
  ```

  or drop `.editorconfig-checker.json` at the consuming repo's root, where `ec`
  auto-discovers it.

`Exclude[]` is repo-agnostic (universal build/output dirs and lockfiles). Add
repo-specific excludes per run with `-exclude '<regex>'` — it combines additively
with the config list.

## Test

`fixtures/editorconfig/{good,bad}` exercise the checks; `editorconfig.test.sh`
runs them on the shell harness. CI additionally self-lints the whole repo.
