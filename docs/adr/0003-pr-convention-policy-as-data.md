# Own PR convention policy as data

- Status: superseded by [ADR-0005](0005-retire-pr-convention-policy-distribution.md)
- Date: 2026-08-12

## Context

Fleet CI enforced PR title and body conventions only reactively through
`semantic-pr` and `pr-issue-linkage` reusables in `ci-workflows`. The rules —
allowed Conventional Commits types, required `## Related` section, closing
keyword or no-issue marker — were embedded in workflow JavaScript and duplicated
across consumers. Knowledge did not land at authoring time, and drift between
gates and `conventions/process/issue-tracker.md` required periodic reconciliation
(#247).

The path-detection component (#171 / #172) established the pattern: one
machine-readable policy file in `components/`, one validator script, materialized
per repository through the sync pipeline, with CI runners reduced to reading the
deployed policy.

## Decision

Add `components/pr-convention-policy/` as the standards-owned slice:

- `policy.json` records required body sections, closing-keyword rules, and
  allowed PR title types (including `security`).
- `pr-convention-policy.mjs` is the single validator; it is distributed through
  `distribution/sync-manifest.yml` to `.github/standards/pr-convention-policy/`.
- `ci-workflows` reusables and the source-control plugin mechanism are follow-on
  work in their respective repositories; they read the materialized policy
  rather than restating rules.

`pull_request_target` gates continue to execute only the base-ref copy of the
policy file.

## Consequences

Org PR conventions have one authoritative, testable source. Consumers gain the
policy through the existing sync path without a second inventory. The first
merge does not yet retarget `semantic-pr` or `pr-issue-linkage`; those thin-runner
conversions remain in `ci-workflows` (#173 program).
