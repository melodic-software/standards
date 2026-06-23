# Research — editorconfig-checker

Validates files against the repo-root `.editorconfig`. Upstream:
<https://github.com/editorconfig-checker/editorconfig-checker>.

## Version

- Latest stable: **v3.7.0**, published 2026-05-25 (GitHub releases API,
  `repos/editorconfig-checker/editorconfig-checker/releases/latest`, verified
  2026-06-23).
- `standards` pins **v3.6.1** in its inline lane (via
  `editorconfig-checker/action-editorconfig-checker`). The action defaults to the
  newer **v3.7.0**; behavior is preserved (3.x config schema is unchanged) and
  `standards` adopts the bump on cutover.

## Install asset + checksum

- Linux x64 asset: `ec-linux-amd64.tar.gz`; the binary is `bin/ec-linux-amd64`
  inside the archive (installed as `ec`).
- SHA-256: `9a0c3a5170bffa24f9e5f0def53d285777b6c5284a95367f40d399d0b76af552`.
- Corroboration: matches the upstream-published `checksums.txt` release asset and
  a locally computed hash of the download.

## Invocation

`standards` runs (lift-and-shift target):

```sh
editorconfig-checker -config modules/editorconfig/.editorconfig-checker.json \
  -exclude 'fixtures/[^/]+/bad/' .
```

- Command name is `editorconfig-checker` (alias `ec`); single-dash flags.
- `-config <PATH>` — ruleset file.
- `-exclude <REGEX>` — a **single regular expression** (not a glob, not
  space-split); combine multiple with `|`. Additive on top of the config's own
  `Exclude[]`. This differs from typos/shellcheck, whose excludes word-split.
- Checks git-tracked files by default; the trailing `.` scopes the run.
- Exit code is non-zero on violations (CI-failing).

## Output format (backfill)

`-format <FORMAT>` accepts `default | gcc | github-actions | codeclimate`
(README, v3.7.0). `github-actions` emits inline PR annotations. Exposed as an
optional `format` input, default empty = tool default (`default`).

## Why curl + sha256 (not action-editorconfig-checker)

Same rationale as the other single-binary tools in this repo (`shellcheck`,
`lychee-offline`): self-contained checksum-pinned install, no nested action.
