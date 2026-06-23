# Research — actionlint

GitHub Actions workflow linter. Upstream: <https://github.com/rhysd/actionlint>.

## Version

- Latest stable: **v1.7.12**, published 2026-03-30 (GitHub releases API,
  `repos/rhysd/actionlint/releases/latest`, verified 2026-06-23).
- `medley` already pins `1.7.12` in its inline lane, so the action default
  matches and adoption is behavior-preserving.

## Install asset + checksum

- Linux x64 asset: `actionlint_1.7.12_linux_amd64.tar.gz`; the binary is
  `actionlint` at the archive root (no subdir).
- SHA-256: `8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8`.
- Corroboration: matches the upstream-published `actionlint_1.7.12_checksums.txt`
  release asset and a locally computed hash of the download (both agree). The
  `taiki-e/install-action` manifest does not cover actionlint (it is not a
  cargo/Rust tool), so that cross-check is N/A.

## Invocation

`medley` runs (lift-and-shift target):

```sh
actionlint -color
```

- With **no path arguments, actionlint auto-discovers** all workflow files under
  `.github/workflows/*.{yml,yaml}` of the current repo. Explicit paths are an
  optional override.
- `-color` forces colored output (the documented CI idiom).
- Exit code is non-zero when problems are found (CI-failing).

### shellcheck / pyflakes integration

actionlint shells out to `shellcheck` (for `run:` bash/sh blocks) and `pyflakes`
(for `shell: python` blocks) **when those binaries are on `PATH`**, and silently
skips the integration otherwise. GitHub-hosted `ubuntu-latest` ships shellcheck,
so the workflow-embedded `run:` scripts in a caller repo are shellchecked by
default — a desirable extra lint, but it means a caller's workflow scripts must
be shellcheck-clean. Disable explicitly with empty overrides (`-shellcheck=`,
`-pyflakes=`) if ever needed.

## Config (backfill)

actionlint auto-loads an optional `.github/actionlint.yaml` (or `.yml`) for
self-hosted-runner labels, declared `config-variables`, and path-specific config;
`-config-file <PATH>` points elsewhere. **Config-light:** `medley` ships no such
file and the lifted lane needs none, so no `standards` module is required for
this tool. The action exposes an optional `config-file` input (default empty =
auto-discover) for callers that later add one.

## Relevant flags (exposed as optional inputs / behind defaults)

`-color`, `-config-file <PATH>`, `-shellcheck <PATH>` / `-pyflakes <PATH>`
(empty disables), `-ignore <REGEX>` (repeatable message filter),
`-format <GO-TEMPLATE>`.

## Why curl + sha256 (not download-actionlint.bash or a third-party action)

`medley` installs via the upstream `download-actionlint.bash` bootstrap. This
repo's established idiom for single-binary GitHub-release tools is curl +
checksum-pin (see `shellcheck`, `editorconfig`, `lychee-offline`): self-contained,
no nested action, the checksum an explicit input. actionlint is the same shape, so
the action follows that idiom.
