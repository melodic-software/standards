# Architecture review criteria

Diff-time checks for structural integrity, operational swap, contract evolution, and build-system coupling. Severity labels are defined in [README.md](README.md). The underlying design defaults are owned by `../engineering/architecture-and-design.md`; this file flags violations in a change.

## Structural integrity

- **Dependency direction** — a change that makes an inner layer reference an outer one, or the domain reference a framework, breaks the layering. Where an analyzer or architecture test can assert this, a violation should fail the build; review covers what the tool does not reach.
- **Aggregate boundaries** — external references to an aggregate go through the root's identity, not by navigating into its internals or exposing them as navigable properties.
- **Domain events as forward-compatible contracts** — events are designed serializable with a versionable shape so a later move to asynchronous messaging does not break them.
- **Operations return results, not raw types or thrown exceptions** for anticipable failures; see `../engineering/architecture-and-design.md`.
- **Module-to-module coupling** — shared internal types or direct reach into another module's internals instead of going through its published contract.
- **Incumbency as the only justification** — a boundary or design decision defended purely descriptively, with no normative argument; see [`../engineering/engineering-philosophy.md`](../engineering/engineering-philosophy.md#judgment-and-process).

## Operational swap

These bars flag diff-time violations of the [operational-change posture](../engineering/architecture-and-design.md#operational-change-without-an-outage).

- **Instance-local state accretion that breaks any-instance-can-die** — a change that starts holding session, workflow, or cache-as-truth state in process memory or on the instance's local filesystem, so an instance can no longer be killed and replaced without loss. Important.
- **Missing graceful shutdown or drain** — a new long-running process, worker, or listener with no termination-signal handling or drain on shutdown. Important.
- **Restart-only wiring where a reload path exists** — a change that wires a value so only a full process restart applies it, on a platform that offers a reload mechanism for exactly that kind of value. Suggestion; Important where operators change the value routinely (certificates, feature flags — whether a renewal is *triggered* automatically stays with `timebombs.md`; this bar owns only whether applying the new value needs a restart).

## Contract evolution

- **API versioning on public contracts** — additive changes (a new optional field, a new endpoint, a new enum member, added paging) are non-breaking and keep the version. Breaking changes (removing or renaming a field, changing its type, tightening validation, adding a required parameter, changing the URL or response shape) require a new version. Flag a breaking edit made in place to an already-shipped version. A versioned API should signal deprecation and carry a removal date ([RFC 8594 Sunset header](https://www.rfc-editor.org/rfc/rfc8594)).
- **Backward-compatible schema migrations** — a schema change is expand-and-contract: add the new shape, migrate the data, and drop the old shape only in a later release once nothing reads it. Apply the migration before deploying code that depends on it. Do not trust auto-scaffolded migrations blindly — a column rename often scaffolds as drop-then-add, which silently destroys data; review the generated migration and heed any data-loss warning. (Stack-specific migration mechanics live in the overlays.)
- **Recorded external state** — flag tracked content that copies externally-owned or derivable state instead of storing a stable key and resolving it at read time: a copied issue title or status, a hardcoded `file:line` cross-reference, another repo's file list reproduced inline, a hardcoded count of a derivable inventory. Acceptable only for an immutable point-in-time fact (a commit hash) or a cache that carries an explicit recheck trigger. See `../engineering/legacy-and-migration-debt.md` and `../engineering/documentation-and-citations.md`.

## Build-system coupling

- **Central, managed dependencies** — new dependencies go through the ecosystem's central dependency-management mechanism, not ad-hoc per-project additions. A project carrying a real dependency tree must declare it where the toolchain and CI can install it.
- **Monolithic append-only shared files** — a single file many contributors append to is a merge-conflict magnet. Prefer one file per entry in a directory, with metadata in frontmatter, aggregated at read time.
- **CI trigger and checkout coupling** — where a workflow's path triggers and its checkout or sparse-checkout scope must agree, a change to one without the other silently skips or breaks a build; flag the drift.
- **Removal of defensive exclusion entries** — deleting an entry from an ignore or exclusion list on a "dead code" rationale carries the burden of proof: the path is structurally impossible, no convention names it as a future target, and removal does not change intended behavior.

## Sources

- [Best practices for RESTful web API design](https://learn.microsoft.com/azure/architecture/best-practices/api-design) — breaking versus non-breaking changes
- [RFC 8594 — the Sunset HTTP header field](https://www.rfc-editor.org/rfc/rfc8594)
