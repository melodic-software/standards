# Gitleaks

Secret scanning with [Gitleaks](https://github.com/gitleaks/gitleaks). The
exported payload is the root-canonical [`.gitleaks.toml`](../../.gitleaks.toml),
which inherits Gitleaks' maintained default ruleset and adds one rule for
GitHub App installation tokens in the classic and stateless formats, but no
repo-specific allowlist.

Managed consumers do not edit the config. Use an inline `gitleaks:allow` pragma
for a reviewed one-line false positive or a repository-owned `.gitleaksignore`
fingerprint for an intentional finding. A broadly valid policy change goes
upstream; a genuinely different policy requires local component ownership, per
[Escape hatches](../../distribution/ESCAPE-HATCHES.md#opting-a-repository-out-of-a-managed-component).

## Defaults, extensions and overrides

The ci-workflows `gitleaks` composite and this repository's lefthook remote (`components/lefthook-base/lefthook-remote.yml`) read this file at run time. Gitleaks reads one config, so a repository's own file replaces this one whole; with none, the readers pass this file (`--config`).

| Mode | What the repository commits | Result |
| --- | --- | --- |
| Default | nothing | this file alone |
| Extension | per-finding suppressions: `gitleaks:allow` and `.gitleaksignore` | this file plus the suppressions |
| Complete override | its own root `.gitleaks.toml` (it may `[extend] useDefault = true` to keep Gitleaks' default rules) | that file alone; nothing here applies |

Gitleaks' `[extend] path` resolves relative to the directory Gitleaks runs in, not to the config file ([README](https://github.com/gitleaks/gitleaks/blob/master/README.md)), and this file sits at a different path under each reader, so a repository file cannot extend this one portably; a repository that needs this file's rules plus its own copies this file's one rule into its own config.

## Execution contract

`ci-workflows` owns reusable Gitleaks installation and execution. Its scans
must fail closed when installation, configuration, scanning, or report parsing
fails, and must redact detected values from logs and reports. A consumer that
chooses repository-history coverage must:

- check out with [`fetch-depth: 0`](https://github.com/actions/checkout#fetch-all-history-for-all-tags-and-branches);
- prove `git rev-parse --is-shallow-repository` returns `false`; and
- invoke `gitleaks git --log-opts="--all"`.

Git's [`--all` revision set](https://git-scm.com/docs/git-rev-list#Documentation/git-rev-list.txt---all)
covers `HEAD` and every ref under `refs/`. A remote ref that the origin does not
advertise or the checkout does not fetch into a local ref cannot be scanned, so
the workflow's fetch refspec must cover every remote ref in the declared scope.
A working-tree scan is not a substitute for repository-history coverage.

Keep Gitleaks as the single organization-default secret scanner. Upstream
[describes it as feature complete](https://github.com/gitleaks/gitleaks),
with future releases focused on security fixes, so reassess it when any of the
following occurs:

- required security fixes stop arriving;
- the maintained default rules cannot cover a required secret class; or
- a maintained successor has compatible configuration, materially better
  detection, and enough operational evidence to satisfy the third-party review
  criteria.

Third-party scanner and action review must apply
[GitHub's secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use):
verify the owner and source repository, audit source and the release or install
path, minimize permissions and secret/network exposure, and pin the reviewed
code to a full commit SHA and release artifacts to exact versions and verified
checksums. Review the applicable
[OpenSSF Scorecard checks](https://github.com/ossf/scorecard/blob/main/docs/checks.md)
as individual risk signals, including maintenance, code review, security policy,
known vulnerabilities, pinned dependencies, and signed releases; an aggregate
score never substitutes for that review and there is no approval threshold.
When provenance is available, verify the artifact, signature, builder identity,
and build parameters against documented expectations following
[SLSA's artifact-verification guidance](https://slsa.dev/spec/v1.2/verifying-artifacts).

Replace the default scanner through a reviewed migration; do not operate a
second permanent scanner for the same concern.

`gitleaks.test.sh` constructs secret-shaped input only at runtime, proving a
detection, output redaction, and the native pragma without committing a
token-like literal. `fixtures/` contains only a clean contract sample.
