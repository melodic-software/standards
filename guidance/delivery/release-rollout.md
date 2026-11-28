# Release rollout

## Design and operate

- Aim for trunk-based, true continuous delivery: small changes shipped continuously behind feature flags, scripted migrations, blue-green deploys, and recovery decided per product and failure (most changes revert, database migrations fail forward).
- Deploys, updates and data changes must not disrupt active users, wipe their state or force long-lived sessions to restart; introduce new infrastructure so it does not stall work in flight.

## Plan and operate

- Roll internal automation out to its full intended scope unless there is a reason to narrow it. Roll a migration across many hosts in coordinated stages, accepting temporary duplication until every host is updated.

## Review and operate

- For a shared source with many consumers: merge the change that ships it before any consumer adopts it, run an end-to-end check before each release, and point consumers at the published remote source, not a local checkout.
- Count a tool as set up only when its real distribution is installed and updated on the target; running it from a dev console does not count.

## Operate

- Before a state-changing step, explore read-only and preview the change (diff, what-if, dry run), apply it only after review, then read the state back to confirm exactly the expected changes applied, nothing more or less.
- Run production deploy workflows in a protected environment with an owner as required reviewer.
