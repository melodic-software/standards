# Research — typos

Spell-checker for source code. Upstream: <https://github.com/crate-ci/typos>.

## Version

- Latest stable: **v1.47.2**, published 2026-06-04 (GitHub releases API,
  `repos/crate-ci/typos/releases/latest`, verified 2026-06-23).
- `standards` already pins typos `1.47.2` in its inline lane, so the action
  default matches and adoption is behavior-preserving.

## Install asset + checksum

- Linux x64 asset: `typos-v1.47.2-x86_64-unknown-linux-musl.tar.gz`; the binary
  is `./typos` at the archive root.
- SHA-256: `7aef58932fc123b4cf4b40d86468e89a3297d80169051d7cfd13a235e05fc426`.
- typos publishes **no** checksum sidecar or manifest with its releases.
  Corroboration: (1) computed locally from the downloaded asset, and (2) matches
  the independently-maintained `taiki-e/install-action` manifest
  (`manifests/typos.json`, `1.47.2 -> x86_64_linux_musl.hash`). Both agree, and
  GitHub release assets are immutable once published.

## Invocation

`standards` runs (lift-and-shift target):

```sh
typos --config modules/typos/_typos.toml --exclude 'fixtures/*/bad/' .
```

- `--config <PATH>` — ruleset file.
- `--exclude <GLOB>` — gitignore-syntax exclude, additive on top of the config's
  own `[files] extend-exclude` and typos' defaults. Repeatable.
- typos respects `.gitignore` and skips binary files by default.
- Exit code is non-zero when typos are found (CI-failing).

## Output format (backfill)

`--format <FORMAT>` accepts `silent | brief | long | json | sarif` (default
`long`), per the v1.47.2 source
(`crates/typos-cli/src/bin/typos-cli/args.rs`, `enum Format`). There is no
GitHub-annotation format; `sarif` is the path to code-scanning/PR annotations
(caller uploads the SARIF). Exposed as an optional `format` input, default empty
= tool default.

## Why curl + sha256 (not the crate-ci/typos action)

`standards` installs via `taiki-e/install-action`. This repo's established idiom
for single-binary GitHub-release tools is curl + checksum-pin (see the
`shellcheck` and `lychee-offline` actions). typos is the same shape, so the
action follows that idiom: self-contained, no nested third-party action, the
checksum an explicit input. The crate-ci/typos action is avoided because it
scans the whole tree and cannot pass `--exclude`.
