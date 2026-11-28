# Work item flow

## Design and operate

- Use native labels as workflow triggers and state, pairing a request label with a past-tense fact label, with names configurable downstream. Judge labels by semantic accuracy, low friction, signal clarity and whether agents can act on them alone. Remove an inaccurate label with a visible trail. Back event-driven automation with a cheap periodic sweep for stuck items.

## Plan

- Work agile: pick one item and iterate, deferring hardening until it is needed. Follow roughly interview, specs, work items, implementation, review, retro, without requiring that exact order. Fully integrate and close each unit of a large body before starting the next.
- Fix in the same change what the change introduced, except in an emergency, along with small problems in the lines it touches. File a nearby problem you cannot finish now as an issue assigned to yourself, after a duplicate check, rather than deferring it silently. A time-gated follow-up becomes one work item carrying its baselines, and related findings go into one consolidated or parent item.
- Order queues by value per unit of time, as team.work-planning says; use age, blockers, scope, size, status, priority and type to break ties and to cap how long an item waits.

## Plan and operate

- Run work as a capped continuous flow, with the cap sized from measured throughput and machine and rate limits, and drive open pull requests and issues toward zero. While draining, take the lowest-friction safe flow and add hardening back later as configuration.
- Anchor work to issues. Every new issue, bot-filed or human-filed, goes through the same intake triage (verify, dedupe, prioritize, size), and filing automation follows the repository's templates. Record blockers at admission and start an item only after its blockers merge. Tooling still accepts a pull request with no issue rather than force a round trip to create one.

## Operate

- Treat inefficiency as a defect: keep measuring and removing waste in time, tokens and calls without losing accuracy, in repeated data-driven rounds, with retrospectives held periodically and whenever metrics trend wrong.
- Close a work item only on stated evidence, never in bulk or to lower the count. Close deferrable low-risk and placeholder items rather than leave them open. Close a date-tied monitoring item once its measurement can be taken, with the result as evidence; keep one consolidated item while the check cannot run until a later date. Never auto-close stale pull requests on a timer; fix them.
