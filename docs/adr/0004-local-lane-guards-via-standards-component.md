# Distribute local-lane guards via a standards component

- Status: superseded (partially) by [ADR-0006](0006-retire-local-lane-guards-distribution.md): driver distribution retired; the pattern-library components continue
- Date: 2026-08-12

## Context

Four bespoke guards gate CI through composite actions in
`melodic-software/ci-workflows` but had no local lane: `comment-hygiene`,
`exec-bit`, `machine-specific-paths`, and `reference-integrity`. Agents and operators
who need the same check before push either skipped it or copied driver logic
into a repo-local bin, drifting from the CI path (lint/static-analysis gap
brief item 7; tracked as ci-workflows#190).

Three distribution options were considered:

1. **Repo-local bin**: cheapest per repo, guarantees drift.
2. **Composite-action local runner only**: reuses the action entry for
   `act`/workflow-local runs, but does not solve true non-CI invocation and
   risks a second implementation beside the action-bundled scripts.
3. **Dedicated `standards` component** (bin/script, exact-file sync): single
   ownership, same delivery path as other shared lint/analyzer primitives,
   pointer-not-copy.

ADR-0001 already prefers native package/reference, then exact-file
synchronization by reviewed pull request, over ad-hoc copies. Pattern bodies
for comment hygiene and path detection already live in `standards`; only the
local **drivers** and a unified entrypoint were missing.

## Decision

Distribute the local-lane guards as the `local-lane-guards` component in this
repository (`components/local-lane-guards/`), synced to
`tools/shared/local-lane-guards/` via `distribution/sync-manifest.yml`.
Consumers invoke `run-local-lane-guards.sh`; they do not copy the drivers.

`ci-workflows` remains the owner of the GitHub Actions execution wrappers.
Follow-up work may re-point those wrappers at the synced drivers so CI and
local share one byte stream; until then, behavioral parity is required and
action-bundled copies must not grow a second policy.

## Consequences

Local and CI lanes can share one owned source without per-repo forks, and
adoption is an ordinary sync-manifest target edit. Landing the component does
not by itself rewrite consumers; target `managed` lists stay opt-in. Until
actions re-point, two driver copies can still drift; that gap is explicit
follow-up, not an invitation to edit downstream.
