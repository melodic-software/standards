# Gitleaks

Secret scanning with [Gitleaks](https://github.com/gitleaks/gitleaks). The
exported payload is the root-canonical [`.gitleaks.toml`](../../.gitleaks.toml),
which inherits Gitleaks' maintained default ruleset and adds no repo-specific
allowlist.

Managed consumers do not edit the config. Use an inline `gitleaks:allow` pragma
for a reviewed one-line false positive or a repository-owned `.gitleaksignore`
fingerprint for an intentional finding. A broadly valid policy change goes
upstream; a genuinely different policy requires local component ownership.

`gitleaks.test.sh` constructs secret-shaped input only at runtime, proving a
detection and the native pragma without committing a token-like literal.
`fixtures/` contains only a clean contract sample.
