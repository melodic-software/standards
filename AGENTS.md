# standards

## Code Review Rules

Each line names a rule CI does not enforce; the linked file states it in full.

- Org-wide criteria: [`REVIEW.md`](REVIEW.md), the canonical source the standards sync distributes.
- Normative-doc changes reconcile every file that cites or assumes the rule before merge:
  [governance process](distribution/governance-process.md#cross-doc-reconciliation-before-a-normative-doc-change-merges).
- A new component brings its admission evidence:
  [component lifecycle](docs/component-lifecycle.md#admission-evidence).
- A new gate records its rollout in its admission change:
  [component lifecycle](docs/component-lifecycle.md#enforcement-rollout).
- Org policy lives here; agnostic audit tooling belongs in `claude-code-plugins`:
  [ownership boundaries](README.md#ownership-boundaries).
- Prose conventions reference an enforcing component instead of restating its rule:
  [conventions](conventions/README.md#how-this-is-consumed).
- No workflow here opens or maintains a GitHub issue; a scheduled check fails its run on drift:
  [CI posture](README.md#ci-posture).
