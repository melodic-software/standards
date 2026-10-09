# Org architecture pointer

Every non-archived Melodic Software repository, except a `sandbox`-topic test
bed and `melodic-software/architecture` itself, names that private repository
in its root `AGENTS.md` or `CLAUDE.md`, so an agent working there knows where
the cross-repo decisions, the glossary and the repo map live. Decided in the
org-wide pointer rollout of 2026-10-09.

## Shape

One fixed paragraph under a short `## Org architecture` heading (or appended
to an existing org-context section). The check does not match the paragraph
text, only the substring `melodic-software/architecture`, so a repository may
word the pointer for its own file.

## Check

[`org-architecture-pointer.sh`](org-architecture-pointer.sh) passes a
repository when its root `AGENTS.md` or its root `CLAUDE.md` contains the
substring, and fails it otherwise, with one `MISSING:` line per repository.

- `org-architecture-pointer.sh file` checks one checkout.
- `org-architecture-pointer.sh fleet` checks repositories through the GitHub
  contents API. The scheduled
  [`maintenance-audit-org-architecture-pointer`](../../.github/workflows/maintenance-audit-org-architecture-pointer.yml)
  workflow runs it over the org's public repositories with the workflow token
  and over the standards-sync App installation's private repositories with a
  read-only App token. A private repository outside the installation is
  visible to neither token.
- `org-architecture-pointer.sh names` is the one listing filter both listings
  apply: not archived, no `sandbox` topic, not `architecture`.

The contract test
[`org-architecture-pointer.test.sh`](org-architecture-pointer.test.sh) runs
offline over fixture repositories in `pr-require-checks.yml`.

Drift fails the scheduled run with one error annotation per nonconforming
repository and opens no issue, as `maintenance-audit-code-review-rules` does.
It gates no pull request.

## Ownership

- **Owner**: the `standards` maintainers.
- **Live consumer**: the scheduled `maintenance-audit-org-architecture-pointer`
  workflow, over the org's repositories.
- **Acceptance**: the audit run passes once every audited repository carries
  the pointer.
- **Delivery boundary**: a check, not a synchronized file. Each repository's
  `AGENTS.md` is repository-owned content, so the pointer is added once by a
  rollout pull request and held in place by the check.
- **Rollback**: delete the workflow, the component and its test step in
  `check-repo-hygiene`; the pointers already landed stay valid content.
