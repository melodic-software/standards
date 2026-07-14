# Gitleaks

Secret scanning with [Gitleaks](https://github.com/gitleaks/gitleaks). The
exported payload is the root-canonical [`.gitleaks.toml`](../../.gitleaks.toml),
which inherits Gitleaks' maintained default ruleset and adds no repo-specific
allowlist.

Managed consumers do not edit the config. Use an inline `gitleaks:allow` pragma
for a reviewed one-line false positive or a repository-owned `.gitleaksignore`
fingerprint for an intentional finding. A broadly valid policy change goes
upstream; a genuinely different policy requires local component ownership.

## Execution contract

`ci-workflows` owns reusable Gitleaks installation and execution. Its scans
must fail closed when installation, configuration, scanning, or report parsing
fails, and must redact detected values from logs and reports. A consumer that
chooses repository-history coverage must fetch and scan the complete history;
a working-tree scan is not a substitute for that declared scope.

Keep Gitleaks as the single organization-default secret scanner. Upstream
[describes it as feature complete](https://github.com/gitleaks/gitleaks#readme),
with future releases focused on security fixes, so reassess it when any of the
following occurs:

- required security fixes stop arriving;
- the maintained default rules cannot cover a required secret class; or
- a maintained successor has compatible configuration, materially better
  detection, and enough operational evidence to satisfy the third-party review
  criteria.

Replace the default scanner through a reviewed migration; do not operate a
second permanent scanner for the same concern.

`gitleaks.test.sh` constructs secret-shaped input only at runtime, proving a
detection, output redaction, and the native pragma without committing a
token-like literal. `fixtures/` contains only a clean contract sample.
