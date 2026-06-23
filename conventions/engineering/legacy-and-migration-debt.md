# Legacy and migration debt

Tracked source — code, comments, tests, and markdown — should describe **what exists now**. Version control already holds the renames, refactors, and removals. Prose that narrates the migration story, and code that keeps the old path alive "just in case", are two shapes of the same debt: they make the current form harder to see and the old form harder to delete. Both are reasoning-only findings — exposure and intent decide severity, which no tool can read.

## Two debt shapes

### Narration debt

Words that tell the migration story instead of naming the current form: *superseded*, *former*, *pre-rename*, *legacy layout*, *was renamed to*, *no longer read*, or identifiers like `LEGACY_*` / `SUPERSEDED_*` that encode history rather than behavior.

**Fix:** rewrite for the current path, name, or contract. An operator-facing hint that states a *current* required action ("unset the old variable; use the new one") is not narration debt — it describes what to do now, not what changed.

### Surface debt

Executable or documented dual paths: shims, silent fallbacks, rollback flags, dual entrypoints, deprecated symbols that still have callers, docs that still present a removed mode as supported.

**Fix:** delete the old path when exposure allows; otherwise document an intentional sunset (a decision record, a deprecation header, an operator runbook) per the exposure tiers below. A fail-loud guard that *rejects* the old input with a clear current-action message is not surface debt — it removes the path while helping the caller. External or domain terminology that happens to contain the word "legacy" is also not surface debt.

## Exposure classifier

Tag every finding with its exposure; that sets the default severity. When exposure is uncertain, treat it as a suggestion and confirm before removal — never assume a repo has no external consumers.

| Exposure | Signals | Default severity |
|---|---|---|
| **None** | never shipped from the main branch; internal-only; zero callers | Suggestion — cleanup opportunity |
| **Internal shipped** | shipped, in-repo consumers only, no published contract | Suggestion for existing debt; Important if the change *adds* a new shim |
| **External contract** | published package, versioned API, registry entry, operator runbook | Important if the dual path is undocumented; Suggestion if a sunset is documented |
| **Production obligation** | live consumers, migrations in flight, a committed sunset not yet reached | Important-to-Critical to remove without a plan |

A repo being pre-production today is a *current* fact, not a permanent exemption — exposure climbs as the product ships.

## Exceptions

- Decision-record status and amendment blocks; changelogs and release notes.
- Runtime operator hints stating a current required action.
- Intentional-sunset docs tied to an external contract (deprecation headers, removal dates, decision records).
- External or domain terminology that is not about this repo's own migration.

## Production-grade migrations are a separate discipline

Removing an old path safely in a live system uses expand-and-contract: add the new shape, migrate the data and callers, then drop the old shape only once nothing reads it. That sequencing — for schema migrations, API versioning, and the like — is a review concern in its own right; see `../review/architecture.md`.
