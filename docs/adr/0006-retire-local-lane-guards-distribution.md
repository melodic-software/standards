# Retire local-lane-guards driver distribution

- Status: accepted
- Date: 2026-08-19
- Supersedes (partially): [ADR-0004](0004-local-lane-guards-via-standards-component.md)

## Context

ADR-0004 created `components/local-lane-guards/` — a dispatcher plus four
guard drivers, synced exact-file to `tools/shared/local-lane-guards/` — so
repositories could run the CI guards locally without forking driver logic.
The standards sync audit's guard-by-guard inventory (fleet-wide, live
origin/main) found that adoption never happened and never will in this
shape:

- The dispatcher (`run-local-lane-guards.sh`) and `coarse-prefilter.sh` are
  consumed by NOBODY: standards runs only the component's contract test in CI
  and gates itself via the ci-workflows actions; medley has its own lane
  wrappers; every other repository uses the CI actions with zero local lanes.
- The enforcement surface consolidated in the ci-workflows composite actions
  (whose bundled copies of the pattern/driver files are byte-identical or
  managed) and in repo-local wrappers, not in a synced local lane.
- The manifest definition sat with zero target references behind a named
  reachability exemption in `sync-manifest.sh` — dead weight the validator
  had to special-case.

## Decision

Stop distributing the drivers: the `local-lane-guards` manifest definition,
the validator's reachability exemption (and its conditional seed), and the
exemption's test fixture are removed. The component DIRECTORY stays as
producer-internal source plus contract test — the same treatment as the
Phase 3.1 trio — with its README and dispatcher header re-cut to stop
documenting a distribution path that no longer exists.

**This supersession is PARTIAL.** ADR-0004's driver-distribution decision
ends; the pattern-library distribution it built on CONTINUES — the
`comment-hygiene-tools` and `path-detection-tools` components remain managed
payloads (medley consumes both through repo-owned wrappers per its ADR-0019
pattern and its comment-hygiene ADR).

## Per-guard dispositions (recorded, not migrated)

The audit's per-guard inventory ends in deliberate states that were live but
unrecorded; this ADR is their durable record:

- **machine-specific-paths** — already at the target state in medley:
  ADR-0019's two-driver/one-SSOT pattern has the managed
  `path-detection-tools` body sourced by a medley-owned wrapper ("share
  bodies, NOT wrapping"). Migration complete by prior art; nothing to do.
- **exec-bit** — three INDEPENDENT, scope-differentiated implementations,
  not forks: canonical full-tree, medley staged/push-range, ccp
  new-index-entry (a different rule for its commit skill). Legitimate
  diversity of scope; deliberately not unified.
- **heading-cites (reference-integrity)** — medley's copy diverged at a
  non-canonical path (`tools/markdown-coupling/`); the ci-workflows action
  copy is byte-identical to canonical. Migration DEFERRED with a named
  revisit trigger: the next behavioral change to the canonical checker.

## Consequences

- The validator's reachability rule runs unexempted; the manifest carries 32
  components, all reachable from target selections.
- A future local-lane need re-enters through a fresh decision (likely the
  wrapper pattern medley proved), not by reviving this component's sync
  entry.
