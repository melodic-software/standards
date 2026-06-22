# gitleaks module

Scans for committed secrets — API keys, tokens, private keys — with
[gitleaks](https://github.com/gitleaks/gitleaks).

## Contents

- `.gitleaks.toml` — the decoupled base config. It inherits the upstream default
  ruleset (`[extend] useDefault = true`) and adds **nothing** repo-specific.
  Adopters layer their own `[[allowlists]]` for false positives and vendored
  fixtures.

## Engine

[gitleaks](https://github.com/gitleaks/gitleaks) (`gitleaks`). Scan a working
tree with `gitleaks dir`, or git history with `gitleaks git`. Exits `0` when
clean, `1` when leaks are found.

## Ignoring intentional or false-positive findings

Three mechanisms, in order of preference — keep the shared config clean by
handling repo-specific findings per-repo:

- **Inline** — append `# gitleaks:allow` to a line gitleaks should ignore (its
  native pragma; no config change).
- **Repo-root `.gitleaksignore`** — list finding *fingerprints*
  (`<file>:<rule-id>:<line>`) for known/intentional findings, e.g. test
  fixtures. Regenerate with `gitleaks dir . -c <config> -f json --report-path -`.
- **Config `[[allowlists]]`** — only for genuinely repo-wide exemptions an
  adopter should inherit. Add to your own copy, not the shared base.

## Adopt in a repo

Reference the config without copying:

```bash
gitleaks dir . --config modules/gitleaks/.gitleaks.toml
```

or drop `.gitleaks.toml` at the consuming repo's root, where gitleaks
auto-discovers it. Extend it with repo-specific allowlists:

```toml
[extend]
useDefault = true

[[allowlists]]
description = "vendored sample data"
paths = ['''vendor/samples/.*''']
```

## Test

`gitleaks.test.sh` (on the shell harness) **constructs** real-shape tokens at
runtime from concatenated parts and scans them in a temp dir — proving the
scanner flags a secret, that `gitleaks:allow` silences one, and that the
committed `fixtures/gitleaks/good` clean fixture passes.

No secret-shaped bytes are committed: a secret-scanning repo cannot store
literal example secrets without tripping its own scan and every external secret
scanner (GitGuardian, GitHub secret scanning). Building the test inputs at run
time keeps the repo clean while still exercising real detections — so CI scans
the whole repo with nothing to exclude.
