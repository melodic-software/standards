# Code organization and module boundaries

How code is grouped, shared, and exposed determines how cheaply it can change. The aim is units that own one concern, expose a deliberate contract surface, and keep everything else private — so a change behind the surface never breaks a consumer. These are reasoning-only structural judgments.

## Share at the second consumer; never copy

- **One consumer** — co-locate the code with its consumer. No shared location.
- **Two or more consumers of the same logic** — extract it to the nearest shared location and have every consumer import from there. Never copy a script or function into a second place; import it.

Promote a co-located helper to a shared location *in the same change* that adds its second consumer. Until two real consumers exist, inline duplication is cheaper than a premature abstraction.

This governs verbatim reuse of identical logic; deciding the shape of a new abstraction follows the rule of three — see `simpler-code.md`.

## Name a shared unit for its capability, not its callers

A shared unit is named for what it does — `process-management`, not `webhook-helpers`. Banned names are the grab-bags: `utils`, `common`, `helpers`, `misc`. A name that would be a topic rather than a capability signals the wrong boundary. Each shared unit names a single owner; concern-specific logic stays in the concern's own unit, not in the shared tier.

## One-way dependency direction

Consumers depend on shared units; shared units depend on other shared units; a shared unit never depends back on a consumer. Promotion into the shared tier is justified by the *ownership* test — "who changes this when it changes?" no longer naming a single owner — not by consumer count. A multi-consumer, single-owner unit is a healthy deep module and stays put. Demoting a wrong abstraction back into its one real owner is low-ceremony and preferred over preserving it.

## The contract is behavior, not files

Every unit has a declared entry surface — the scripts, functions, or manifest entries that external consumers may target. Everything else is private: internal helpers, templates, schemas, and data files live behind the entry surface in private subdirectories. An external reference reaching past the surface into an internal schema or helper is the same anti-pattern as reading another component's private database.

Three classes of artifact follow from this:

1. **Unit-private** — lives inside its owner, reachable only from within.
2. **Unit-owned contract** — lives on the owner's declared entry surface.
3. **Shared capability** — lives in the shared tier, and only when no single unit is its natural owner.

Co-located tests are never contract, wherever they sit. Publishing a unit's internal *data* file as contract (a catalog read by CI, say) is legal but rare and deliberate — the default for data is private behind a facade.

## Breaking versus non-breaking change

- **Non-breaking (additive)** — a new entry point, a new optional flag, a new field. Ship freely.
- **Breaking** — renaming, removing, or changing the semantics of any contract surface. A breaking change carries its consumers: the same change updates every calling site and runs their tests.

There is no versioning of internal surfaces — no parallel old-and-new entry points, no `v2` alongside `v1`. Version control holds the history; the change replaces the surface rather than duplicating it. (Externally published contracts — packages, HTTP APIs — are the exception and follow expand-and-contract; see `../review/architecture.md`.)

## Orphans and deliberate duplication

A zero-consumer unit defaults to deletion — version control preserves it. Keeping an orphan requires a named justification recorded with it.

Duplication chosen for independent evolution is legal but always documented, never accidental: a comment or note at each copy names its counterpart and the reason. Undocumented duplication is a defect.

## Related

- When inline duplication beats a premature abstraction — see `simpler-code.md`.
- Naming shared units and their entry points — see `naming.md`.
