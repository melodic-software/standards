# Research — gitleaks

Secret scanner. Upstream: <https://github.com/gitleaks/gitleaks>.

## Version

- Latest stable: **v8.30.1**, published 2026-03-21 (GitHub releases API,
  `repos/gitleaks/gitleaks/releases/latest`, verified 2026-06-23).
- `standards` already pins `8.30.1` in its inline lane, so the action default
  matches and adoption is behavior-preserving.

## Install asset + checksum

- Linux x64 asset: `gitleaks_8.30.1_linux_x64.tar.gz`; the binary is `gitleaks`
  at the archive root.
- SHA-256: `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb`.
- Corroboration: matches the value `standards` independently recorded in its
  inline lane, plus a locally computed hash of the download.

## Invocation

`standards` runs (lift-and-shift target):

```sh
gitleaks dir . --config modules/gitleaks/.gitleaks.toml --no-banner
```

- `dir <PATH>` (aliases `files`, `directory`) — scan a directory/file on disk
  (filesystem scan, not git-history). Defaults to cwd if no path given.
- `--config/-c <PATH>` — ruleset file.
- `--no-banner` — suppress the ASCII banner (clean CI logs).
- Exit code defaults to `1` when leaks are found (CI-failing); `--exit-code`
  overrides.

## SARIF / PR annotations (backfill)

`--report-format <FMT>` accepts `json | csv | junit | sarif | template`;
`--report-path <PATH>` writes the report (written before the non-zero exit, so it
exists even when leaks are found). SARIF is the path to GitHub code-scanning and
PR annotations.

The **upload** (`github/codeql-action/upload-sarif`) is a job-level concern: it
needs `security-events: write` job permission and an `if: always()` step so the
report uploads even when the scan fails. A composite action cannot set job
permissions (architecture D1/D7), so the action's responsibility ends at emitting
the SARIF file via the optional `report-format` / `report-path` inputs; the
caller adds the upload step. Defaults are empty = no report file (matches
`standards`' current behavior).

## Why curl + sha256 (not gitleaks-action)

The official `gitleaks/gitleaks-action` requires an organization license, and
`taiki-e/install-action` has no gitleaks manifest. The checksum-pinned tarball
install is the same idiom this repo uses for `shellcheck` and `lychee-offline`,
and the one `standards` already uses inline.
