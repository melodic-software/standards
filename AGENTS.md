# AGENTS.md

The [AGENTS.md convention](https://agents.md/) positions this file as the
agent-specific complement to `README.md`, not a restatement of it: `README.md`
is for humans — quick start, project description, ownership. This file is for
a coding agent working in this repository. For repository shape, ownership
boundaries, the component model, and validation commands, read
[`README.md`](README.md) first.

This file lives at the repository root only. Do not add a nested copy —
Codex concatenates every `AGENTS.md` it finds rather than having the nearest
one override, so a nested copy would compound instructions instead of
scoping them; use a nested `CLAUDE.md` or a `.claude/rules/` overlay for a
subtree-local instruction instead.

## Before changing anything here

- This repository dogfoods its own criteria: a change here is held to the
  bar [`conventions/engineering/`](conventions/engineering/) and
  [`conventions/review/`](conventions/review/) prescribe for every
  downstream consumer, not a lesser one.
- A change to a normative file — a rule another doc cites or assumes — needs
  the cross-doc reconciliation self-review step in
  [`distribution/governance-process.md`](distribution/governance-process.md)
  before it merges, not after.
- New or changed review criteria are authored fresh from primary sources and
  cite them; criteria are never ported from a downstream consumer's own
  copy, which would run the source-of-truth arrow backward.
- `.claude/` is untracked local session tooling. Never `git add -A` or
  `git add .` here — stage explicit paths only.

## Validating a change

Run the commands in [`README.md`'s Validation section](README.md#validation)
before opening a pull request. `lefthook` runs the fast pre-commit subset on
every commit; CI runs the complete suite.

## Pull requests

Titles are Conventional Commits, mechanically checked by the `pr-title`
required status. Merges are squash-only. An unresolved review-comment thread
blocks merge — see
[`conventions/review/reply-protocol.md`](conventions/review/reply-protocol.md)
for how a thread closes once its finding is addressed.
