# Architecture decision records

This directory contains durable, repository-specific architecture decisions.
Create an ADR only when all three conditions hold:

- reversing the choice later would be costly;
- the choice would be surprising without its context; and
- real alternatives or competing forces shaped the outcome.

Issues, migration plans, rollout status, and implementation journals remain
ephemeral.

## Convention

- Keep ADRs flat at `docs/adr/NNNN-kebab-case-title.md` so their purpose and
  identity are visible from the path alone.
- Allocate the next four-digit repository-local number. Never reuse, renumber,
  or rename an accepted ADR.
- Use an active decision phrase for the H1; the filename already carries the
  identifier, so do not repeat `NNNN` in the heading.
- Use [`adr-template.md`](adr-template.md) and exactly one lifecycle status:
  `proposed`, `accepted`, or `superseded by [ADR-NNNN](NNNN-title.md)`.
- An ADR with `accepted` status is a historical record. Change the architecture
  with a new ADR that links to and supersedes it; do not rewrite the old decision.
- Use a repository-qualified URL for a cross-repository ADR reference. ADR
  numbering has meaning only within its owning repository.
- Add optional sections such as alternatives, evidence, or follow-up links only
  when they materially help a future reader understand the decision.
- Do not maintain a hand-written or generated index. Stable filenames and
  repository search are the discovery mechanism.

The convention itself is defined here for adoption by other repositories, but
each repository owns its own ADR contents and numbering namespace.
