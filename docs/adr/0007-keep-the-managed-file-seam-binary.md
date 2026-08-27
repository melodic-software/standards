# Keep the managed-file seam binary and derive facts at the source

- Status: accepted
- Date: 2026-08-27

## Context

A managed component is either fully synced or `locally-owned` in whole
(`distribution/sync-manifest.schema.json`). Standards#483 recorded a downstream
repository (`melodic-software/.github`, PR 46) fixing a real gap in its synced
`lychee.toml` — a private repository missing from the exclude inventory — and
the next exact-file sync (PR 47) reverting the fix three hours later with no
failing check, comment, or conflict. The issue asked whether the seam owes a
downstream repository an additive layer: (a) a per-component append file the
sync concatenates, (b) drift detection that flags a diverged managed file so a
revert is never silent, or (c) the binary seam plus (b) alone.

Evidence gathered for the decision:

- Every `locally-owned` entry in the manifest is a policy-level choice
  (`ruff` rule-set migrations, `actionlint` governance topology, `medley`'s
  wholesale local ownership), recorded with its own removal trigger. No target
  has taken a component locally-owned to hold one line.
- The only observed downstream edit of a managed file was the lychee
  inventory, and that edit existed because the inventory was a hand-maintained
  copy of a queryable fact (repository visibility). Deriving the fact at the
  source (`components/lychee/private-repo-inventory.sh`, the `lychee-fixtures`
  CI lane, and the scheduled `lychee-private-inventory` workflow) removes the
  reason for any downstream edit to that file.
- A guard that fails a consumer pull request hand-editing a managed file
  already exists as `melodic-software/ci-workflows`'s `managed-files-guard`
  composite action (ci-workflows#208, advisory-first), but only ci-workflows
  itself calls it.

## Decision

- No additive layer. A managed file stays byte-exact with its standards
  source; a consumer that needs different bytes changes the source or takes
  the component `locally-owned` in whole, with the reason recorded at its
  manifest key. Option (a) is rejected because no managed component has shown
  a downstream-only addition that is not better expressed as a source change,
  and an append seam would turn one source of truth into N partially-merged
  ones — the exact class of silent divergence the sync exists to prevent.
- Facts that a managed file inventories are derived from their queryable
  source, with a check that fails on disagreement, rather than hand-kept. The
  lychee private-repo inventory is the first instance; any future managed file
  that copies a queryable fact takes the same shape.
- The signal a downstream hand-edit gets is the `managed-files-guard` check on
  the consumer's pull request, not a comment from the sync. Rolling that guard
  out to every sync target is tracked separately (standards#496) because it is
  a fleet-wide workflow addition with its own soak; until it lands, the sync
  PR body's rule ("Do not hand-edit these managed files downstream; change
  their standards source instead") is the only signal, and this ADR records
  that gap as accepted rather than unnoticed.

## Consequences

- Downstream repositories cannot carry a one-line local addition to a managed
  file; the fix path is always a standards change, which fans out to every
  consumer on the next sync.
- The sync engine stays a pure overwrite with no merge logic, keeping its
  threat model (`distribution/THREAT-MODEL.md`) unchanged.
- A future proposal for an append layer must first show a downstream-only
  addition that cannot be a source change — the evidence this decision found
  absent.
