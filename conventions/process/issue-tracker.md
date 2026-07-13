# Issue-tracker playbook

How the organization uses its issue tracker: the naming grammar for labels, which axes are expressed as labels versus native GitHub mechanisms, and the governance process that keeps the taxonomy from drifting. This is a reasoning-only convention — it owns *usage and process*, the judgments a person or agent makes while triaging. It does not own the label definitions; those are deployed as infrastructure-as-code, and this playbook points at them rather than restating them.

## Definitions live in infrastructure-as-code

The deployed label set — every axis's members, their exact spelling, and their colors — is owned by [`melodic-software/github-iac`](https://github.com/melodic-software/github-iac) for organization repositories and by [`kyle-sexton/github-iac`](https://github.com/kyle-sexton/github-iac) for the personal account. That program is the single source of truth for *which labels exist*; this playbook is the single source of truth for *how they are used*. It names no members and lists no values — to see the live set, read the infrastructure-as-code program or query the repository with `gh label list`. Restating the set here would create a second, drifting copy of a fact that already has an owner (see [`../engineering/reference-dont-duplicate.md`](../engineering/reference-dont-duplicate.md)).

## Naming grammar

Labels follow one grammar across every axis, so a reader parses any label without a legend:

- **Prefix, colon, space, value.** A label opens with its axis prefix, then a colon and a single space, then the value (`<axis>: <value>`). The separator is always colon-then-space — never a bare colon, never a slash.
- **Long-form values.** An issue label names the *kind of work* as a full-word noun or state, not a commit-style abbreviation. Commit types describe an action recorded in the commit history and belong to the commit layer, where they drive changelogs and versioning; a single issue attracts many commits of different types, so borrowing that vocabulary onto the issue confuses the two layers.
- **One color family per axis.** Every value on an axis shares a color family, so the axis is legible at a glance in a crowded label list. The colors are part of the definition and are set in infrastructure-as-code.
- **Small, curated set.** Each axis stays deliberately small. A value earns its place by being triaged on; a value nobody filters by is noise. Values are added deliberately, through governance, not reactively.

## The type axis

On organization repositories the type axis is **native GitHub Issue Types**, not labels. Issue Types are an organization-level, single-select field — an issue carries exactly one type, enforced — and GitHub positions them as the successor to a type-prefixed label. They are the governance mechanism for this axis; there is no parallel type label alongside them.

Personal accounts have no native Issue Types, so their repositories retain a labelled type axis under the same naming grammar. This is a deliberate per-account divergence, not drift, and it is declared in [`kyle-sexton/github-iac`](https://github.com/kyle-sexton/github-iac).

## The status axis

Prefer a native mechanism over a status label wherever GitHub offers one, because the native mechanism carries behavior the label can only imitate:

- **Blocking is a dependency edge, not a label.** Model "this cannot proceed until that is done" as a native blocked-by relationship between issues. The edge resolves itself when the blocker closes; a label has to be cleared by hand and silently goes stale.
- **Claiming is an assignee plus a lease, not a label.** A worker taking an issue sets themselves as its assignee under a time-boxed lease. Ownership and its freshness then live in the native field, where a second worker can trust them, rather than in a label anyone can leave behind.
- **The remaining status labels are the human-gate signals.** What stays a label is the small set of states that mean *a human must act before work can continue* — an issue waiting on information, waiting on a decision, or cleared and ready to start. These have no native equivalent, so they remain labels under the naming grammar; their exact spelling is defined in infrastructure-as-code.

## Governance: infrastructure-as-code is the sole writer

The taxonomy drifts the moment two parties can write it, so the recurrence fix is a single writer:

- **New or changed labels go through a `github-iac` Pulumi pull request** — the [organization program](https://github.com/melodic-software/github-iac) for organization repositories, the [personal program](https://github.com/kyle-sexton/github-iac) for the personal account. Never create a label ad-hoc with `gh label create`: the deployed set is authoritative and reconciles on the next apply, so an out-of-band label is pruned and the effort is lost.
- **Per-repository divergence is additive and reviewed.** A repository that needs its own labels contributes them as an additive extension to the union the program computes for it (`ExtraLabels`), or — rarely — opts out of managed labels entirely (`ManagedLabels: false`). Either path is an explicit, reviewed pull request, never a silent hand-edit: the baseline stays closed to modification and open to extension.
- **`pulumi import` recovers a mistake.** If a label reached a repository out-of-band before anyone noticed, import it into the program's state and codify it, so the next preview is clean rather than destructive.

## Related

- [`../engineering/reference-dont-duplicate.md`](../engineering/reference-dont-duplicate.md) — why this playbook cites the label set instead of restating it.
- [`../engineering/naming.md`](../engineering/naming.md) — the general naming discipline the label grammar specializes.
