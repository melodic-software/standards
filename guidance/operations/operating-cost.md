# Operating cost

## Any stage

- Count as cost only what can bill; hard-capped usage that stops at a limit is capacity to spend freely.

## Design

- Adopt a scanner or service only when it adds no bill. When a tool is set up to use a paid service, the budgets are the user's to set, and a free-first tool that falls back to paid makes the fallback clear.
- Prefer storage for large files that expires and does not bill, deferring paid alternatives until they are needed.

## Design and plan

- Price every option and prefer free or cheap ones, but still present the best option with its projected cost.

## Design and operate

- Cap spend with hard budgets at the free or prepaid amount, with no overage or auto-refill, and keep automation away from billing settings. Where no hard cap exists, use noisy budget alerts with accurate projected spend and a regular billing summary. Keep all budget assignments in one visible place.
- Keep CI cost down with cheaper compute than hosted CI (a build server, self-hosted runners, containers), and avoid paid hosted minutes on private repositories.

## Plan and operate

- Know what a scheduled or repeated run costs in CI time and model usage before running it, and turn a useful capability off only on evidence that it burns too much.
