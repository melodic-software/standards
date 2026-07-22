# Issue-tracker playbook

How the organization uses its issue tracker: the naming grammar for labels, the free-text convention for issue titles, which axes are expressed as labels versus native GitHub mechanisms, the closing-keyword and comment conventions that connect issues to the pull requests that resolve them, and the governance process that keeps the taxonomy from drifting. This is a reasoning-only convention — it owns *usage and process*, the judgments a person or agent makes while triaging. It does not own the label definitions or the repository topology; those are deployed as infrastructure-as-code, and this playbook points at them rather than restating them.

## Definitions live in infrastructure-as-code

The deployed label set — every axis's members, their exact spelling, and their colors — is owned by each account's own infrastructure-as-code program, not by this playbook. That program is the single source of truth for *which labels exist*; this playbook is the single source of truth for *how they are used*. It names no members and lists no values — to see the live set, read the relevant infrastructure-as-code program or query the repository with `gh label list --limit 100` (the default limit is 30, which can silently omit labels once a taxonomy grows past it). Restating the set here would create a second, drifting copy of a fact that already has an owner (see [`../engineering/reference-dont-duplicate.md`](../engineering/reference-dont-duplicate.md)).

Which repositories are governed at all — and by which account's program — is itself infrastructure-as-code, not prose in this playbook. For the organization, `github-iac`'s `GovernedRepositories.cs` is the single registry: it drives repository creation and decides, per repository, whether it's label-managed, CI-required, and so on. This doc does not restate that topology or name specific repositories; read the registry to find out what's actually governed and how.

## Naming grammar

Labels follow one grammar across every axis, so a reader parses any label without a legend:

- **Prefix, colon, space, value.** A label opens with its axis prefix, then a colon and a single space, then the value (`<axis>: <value>`). The separator is always colon-then-space — never a bare colon, never a slash.
- **Long-form values.** An issue label names the *kind of work* as a full-word noun or state, not a commit-style abbreviation. Commit types describe an action recorded in the commit history and belong to the commit layer, where they drive changelogs and versioning; a single issue attracts many commits of different types, so borrowing that vocabulary onto the issue confuses the two layers.
- **One color family per axis.** Every value on an axis shares a color family, so the axis is legible at a glance in a crowded label list. The colors are part of the definition and are set in infrastructure-as-code.
- **Small, curated set.** Each axis stays deliberately small. A value earns its place by being triaged on; a value nobody filters by is noise. Values are added deliberately, through governance, not reactively.

## Issue titles

The naming grammar above governs labels only. Issue titles are free text: there is no enforced prefix vocabulary, and titles do not carry a conventional-commit-style tag such as `[CC]` or `feat:`. This is a deliberate choice, not a gap — the type, status, and area axes already have a governed home as Issue Types and labels, so a title prefix would duplicate an axis that already exists elsewhere and drift out of sync with it. Write a title that describes the issue.

## The type axis

On organization repositories the type axis is **native GitHub Issue Types**, not labels. Issue Types are an organization-level, single-select field — an issue carries **at most one** type, never two — and GitHub positions them as the successor to a type-prefixed label. They are the governance mechanism for this axis; there is no parallel type label alongside them. GitHub does not require every issue to carry a type — search exposes a positive `type:"Bug"`-style qualifier per enabled type but no `no:type` negation to find the untyped remainder directly (querying `no:type` silently returns the unfiltered total, not a filtered one), so finding what's missing means comparing per-type counts against the total or reading an issue's `type` field, which is `null` when unset. An issue created via a form or API call that skips the field can silently fall outside the taxonomy this way.

**Issue creation always sets the type.** CLI and agent-driven issue creation passes `--type` with one of the org's enabled native types (`gh issue create --type Task|Bug|Feature`); the web UI's issue form already surfaces the Types field, so that path can't skip it. A scheduled sweep is the backstop for whatever still slips through — see `github-iac`'s untyped-issue sweep.

Personal accounts have no native Issue Types, so their repositories retain a labelled type axis under the same naming grammar. This is a deliberate per-account divergence, not drift; each account's own infrastructure-as-code program is the record of which mechanism its repositories use (see "Definitions live in infrastructure-as-code" above).

## The status axis

Prefer a native mechanism over a status label wherever GitHub offers one, because the native mechanism carries behavior the label can only imitate:

- **Blocking is a dependency edge, not a label.** Model "this cannot proceed until that is done" as a native blocked-by relationship between issues. The edge resolves itself when the blocker closes; a label has to be cleared by hand and silently goes stale.
- **Claiming is an assignee plus a lease, not a label — but this mechanism is deferred.** The intended model is a worker taking an issue setting themselves as its assignee under a time-boxed lease, so ownership and its freshness live in the native field where a second worker can trust them, rather than in a label anyone can leave behind. It stays undeployed today because a single-maintainer org has nothing for it to arbitrate: activate it if the org adopts required reviewers or otherwise grows enough maintainers that assignment contention becomes real. Until then, the optional 🔒 marker below is the lightweight interim signal.
- **The remaining status labels are the human-gate signals.** What stays a label is the small set of states that mean *a human must act before work can continue* — an issue waiting on information, waiting on a decision, or cleared and ready to start. These have no native equivalent, so they remain labels under the naming grammar; their exact spelling is defined in infrastructure-as-code.

## Closing pull requests

A pull request that resolves an issue uses GitHub's native closing keywords — `Closes`, `Fixes`, or `Resolves`, followed by the issue number — as the default house style. The keyword is what wires the automatic link and auto-close on merge; a plain-text reference like "see #123" does neither. Every pull request fleet-wide additionally carries a manual `## Related` section alongside the native keyword (or the literal `No linked issue` when nothing closes) — the practice applies org- and account-wide, not only where a CI gate can check it. This began as `provisioning`'s stricter convention (decisions log #58/#59); the shared `pr-issue-linkage` gate mechanically enforces it on every requires-ci repository, and repositories without CI follow the same convention unenforced.

## Optional conventions

The following are documented patterns, not requirements — use them where they add signal, skip them where they don't:

- **🤖 marks a bot-authored comment.** A trailing 🤖 on a comment tells a human reader at a glance that an agent, not a person, wrote it.
- **Cite the evidence when closing on it.** A pull request or comment that closes an issue because of external evidence (a log, a run, an upstream release) links or quotes that evidence rather than asserting the conclusion bare.
- **🔒 marks a claimed issue.** Until the assignee-plus-lease mechanism above is activated, a worker who wants to signal "I'm on this" adds a 🔒 to the title or opens with it in a comment. It is advisory, not enforced — nothing clears it automatically, so treat a stale 🔒 with the same skepticism as any other unmaintained signal.

## Governance: infrastructure-as-code is the sole writer

The taxonomy drifts the moment two parties can write it, so the recurrence fix is a single writer:

- **New or changed labels go through a `github-iac` Pulumi pull request**, in whichever account's program governs the target repository. Never create a label ad-hoc with `gh label create`: the deployed set is authoritative and reconciles on the next apply, so an out-of-band label is pruned and the effort is lost.
- **Per-repository divergence is additive and reviewed.** A repository that needs its own labels contributes them as an additive extension to the union the program computes for it (`ExtraLabels`), or — rarely — opts out of managed labels entirely (`ManagedLabels: false`). Either path is an explicit, reviewed pull request, never a silent hand-edit: the baseline stays closed to modification and open to extension.
- **`pulumi import` recovers a mistake.** If a label reached a repository out-of-band before anyone noticed, import it into the program's state and codify it, so the next preview is clean rather than destructive.
- **CODEOWNERS adoption is deferred, but it would not be inert.** A CODEOWNERS file has two independent effects: GitHub auto-requests review from matching owners on any pull request that touches their paths, and — separately, only if a repository's branch protection opts in — it can require that a code owner approve before merge. The first effect fires regardless of the second. With `required_approving_review_count` held at 0 org-wide (a deliberate single-maintainer choice, not unset drift), the enforcement half is off, but adding a CODEOWNERS file today would still auto-request review on every matching pull request. Adoption stays deferred because a single-maintainer org has no second owner for that auto-request to route to, not because the file would do nothing. Revisit once the org has enough maintainers for auto-routed review requests, or required code-owner approval, to add real signal.

## Related

- [`../engineering/reference-dont-duplicate.md`](../engineering/reference-dont-duplicate.md) — why this playbook cites the label set instead of restating it.
- [`../engineering/naming.md`](../engineering/naming.md) — the general naming discipline the label grammar specializes.
