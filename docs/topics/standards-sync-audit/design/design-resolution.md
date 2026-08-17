# Design resolution — standards-sync-audit (Phase 0)

outcome: early-exit

## Phase 1 addendum (2026-08-17) — Tier B light design

Contract change: the watchdog reusable gains two `workflow_call` inputs —
`test-mode` (boolean, default false) and `test-synthetic-candidates` (number,
default 1, read only when test-mode) — threaded from the standards caller's
`workflow_dispatch` (which gains the same two inputs). Test-mode runs use a
divergent marker (`…:v1:test`) and title (`[Test] …`) across all five literal
sites, so test issues in medley are invisible to the production lookup and the
hourly cron cannot collide with a dispatched test. Synthetic candidates are
fabricated in the scan step (clearly labeled SYNTHETIC; no real repo probing),
driving the same downstream create/update/close/fail machinery unchanged. Job
and step names stay byte-identical (the standards caller's classifier matches
them as literal strings). Resolved threads: interview Q10 (locked shape),
explorer reports 2026-08-17 (reusable structure, five literal sites, App
token seam, classifier coupling, `.github` merge path).

## Phase 0 (original) — Tier C early-exit

Tier C: Phase 0 is hygiene + pins — manifest comment corrections, doc rewrites, ADR renumber, Dependabot entries, workflow caller re-pins, version-file bump. No new types, no contracts, no module boundaries, no package topology. Design decisions for later phases (engine Node port, watchdog test mode) were resolved in the interview ledger (`.work/standards-sync-audit/interview-checklist.md`, Q10/Q12) and will get their own design pass when those phases are planned.
