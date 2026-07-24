# AGENTS.md

The [AGENTS.md convention](https://agents.md/) positions this file as the
agent-specific complement to `README.md`, not a restatement of it: `README.md`
is for humans — quick start, project description, ownership. This file is for
a coding agent working in this repository. For repository shape, ownership
boundaries, the component model, and validation commands, read
[`README.md`](README.md) first.

This file lives at the repository root only. Do not add a nested copy of
it — its content (dogfooding, cross-doc reconciliation, PR conventions) is
repository-wide, not subtree-scoped, so a nested copy would duplicate
root-wide instructions rather than add anything new. For a genuine
subtree-local instruction, add a nested `AGENTS.md` in that subtree instead
(or `AGENTS.override.md` to fully replace rather than append): Codex
concatenates every `AGENTS.md` it finds root-down, joining them with blank
lines, and a file closer to the working directory is read later in that
combined prompt and can supersede the broader guidance above it —
`AGENTS.override.md` at a directory level replaces rather than appends.
Codex does not read a nested `CLAUDE.md` or a `.claude/rules/` overlay for
this purpose.

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
- `.claude/` is untracked local session tooling, with one exception:
  tracked repo-owned plugin configuration (`.claude/source-control.md`,
  whose loop-lane keys are ratified through reviewed PRs per the
  [loop-lane convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/loop-lane/README.md)).
  Never `git add -A` or `git add .` here — stage explicit paths only.

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
