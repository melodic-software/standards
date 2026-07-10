# Lychee

Local link and Markdown-anchor validation with
[Lychee](https://github.com/lycheeverse/lychee). The exported payload is the
root-canonical [`lychee.toml`](../../lychee.toml).

The blocking `ci-workflows` action runs offline for deterministic local-file and
fragment checks. An online scheduled workflow may check external URLs
advisorially because network health is inherently transient.

Managed consumers do not edit the config. `fixtures/` and `lychee.test.sh`
prove valid links and missing file/fragment failures with Lychee 0.24.2+.
