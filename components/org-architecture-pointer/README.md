# Org architecture pointer

Every non-archived Melodic Software repository, except a `sandbox`-topic test
bed and `melodic-software/architecture` itself, names that private repository
in its root `AGENTS.md` or `CLAUDE.md`, so an agent working there knows where
the cross-repo decisions, the glossary and the repo map live. Decided in the
org-wide pointer rollout of 2026-10-09.

## Shape

One fixed paragraph under a short `## Org architecture` heading (or appended
to an existing org-context section). The check does not match the paragraph
text, only the exact name `melodic-software/architecture` followed by a
character outside `[A-Za-z0-9._-]` or the end of the line (so
`melodic-software/architectures-of-others` does not match), so a repository may
word the pointer for its own file.

## Check

[`org-architecture-pointer.sh`](org-architecture-pointer.sh) passes a
repository when its root `AGENTS.md` or its root `CLAUDE.md` contains the
bounded name, and fails it otherwise, with one `MISSING:` line per repository.

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

## Admission evidence

Per [component lifecycle](../../docs/component-lifecycle.md#admission-evidence).

- **Alternatives and overlap**: GitHub has no facility that requires a named
  string in an instruction file. A repository ruleset cannot read file
  content, and a required workflow would run per pull request in every
  repository. `code-review-rules` checks a different section of the same file
  and shares no finding with this check. Composing the two would couple their
  failure modes, so this component copies its shape and shares no code.
- **Operational fit**: exercised against live `main` on 2026-10-09 after all
  18 pointer pull requests merged: `fleet` passed for every audited
  repository (output on the pull request). Signal quality: the only failure
  mode is a missing or misspelled name, and the boundary match rejects a longer
  repository name. Runtime: one contents-API read per file per repository, a
  few seconds. Privileges: `contents: read` and `metadata: read`, no write.
  Credentials: the workflow token for public repositories, a read-only
  standards-sync App token for private ones. Failure behavior: exit 1 lists
  the repositories missing the name; exit 2 on a query error fails the run
  without reporting drift.
- **Upstream health**: no third-party dependency; the script uses `bash`,
  `jq`, `gh` and `grep` from the runner image.
- **Legal and security fit**: first-party code under the repository's
  license; no new dependency, no network boundary beyond the GitHub API, and
  no credential beyond the existing standards-sync App.
- **Update path**: no dependency root to update; the workflow's actions are
  pinned and updated by the repository's updater.

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
