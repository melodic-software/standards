# Delete the local-lane-guards drivers

- Status: accepted
- Date: 2026-11-22
- Supersedes (partially): [ADR-0006](0006-retire-local-lane-guards-distribution.md)

## Context

ADR-0006 stopped distributing `components/local-lane-guards/` but kept the
directory as producer-internal source plus contract test, on the premise that
the ci-workflows action copies of its drivers were byte-identical or managed.
That premise no longer holds. At standards `main` and ci-workflows `main` on
2026-11-22, every driver differs from its action copy:

| Driver here | ci-workflows action copy | Differing lines |
| --- | --- | --- |
| `check-exec-bit.sh` | `check-exec-bit/check-exec-bit.sh` | 141 |
| `check-heading-cites.sh` | `check-markdown-references/check-heading-cites.sh` | 50 |
| `check-machine-specific-paths.sh` | `check-machine-paths/check-machine-specific-paths.sh` | 162 |
| `coarse-prefilter.sh` | `check-comment-markers/coarse-prefilter.sh` | 19 |
| `scan-comment-hygiene.sh` | `check-comment-markers/scan-tree.sh` | 71 |

Only the pattern libraries are synced into the actions (`comment-hygiene-action`
and `path-detection-action` in `distribution/sync-manifest.yml`); the drivers
were never managed. A fresh adoption audit (every `melodic-software` clone and
the dotfiles source, at each default branch) found no caller of the
dispatcher or any driver here: the only reference outside this repository was
a ci-workflows README note pointing local use at this component. The
directory was a second implementation of each guard, maintained by hand,
consumed by nothing, and already drifted from the one CI runs.

## Decision

Delete `components/local-lane-guards/` (dispatcher, four drivers, the
comment-hygiene prefilter, README and contract test) and its CI step. The ci-workflows composite actions are the
only implementation of the four guards; local use runs an action's script
from a ci-workflows checkout.

The pattern libraries stay: `components/comment-hygiene/` and
`components/path-detection/` remain managed payloads with their own tests,
synced into the ci-workflows actions, the guardrails plugin and
`tools/shared/` targets. ADR-0006's retirement of the driver distribution
also stands.

ADR-0006's per-guard dispositions change in one place: the "canonical
checker" for heading-cites is now the ci-workflows
`check-markdown-references` action, and medley's revisit trigger refers to
it.

## Consequences

- One implementation per guard; no hand-kept parity between two repositories.
- Changing a guard's behavior is a ci-workflows change; changing a pattern
  body is still a standards change that reaches the actions through the sync.
- A future local-lane need re-enters through a fresh decision, as ADR-0006
  already required.
