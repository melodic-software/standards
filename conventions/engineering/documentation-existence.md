# Documentation existence

Whether a tracked page may exist at all is decided before any other documentation convention applies. Code owns the behavior it expresses; a hand-written page restating that behavior is a second source of truth — when the two disagree, a reader (human or agent) cannot tell which is canonical, and every read of the page costs attention and tokens whether or not it is still true. Such a page drifts by construction: no discipline keeps prose aligned with code it merely describes. This is a reasoning-only judgment — whether code could express a given piece of content is a question of meaning, not format ([enforceability-tiers.md](enforceability-tiers.md)).

## The admission test

Could a reader with repository search derive this content from the code itself?

- **Yes** — the page may not exist. The code is the source of truth, and when it is hard to derive answers from, the fix is better organization, naming, and structure ([code-organization.md](code-organization.md), [naming.md](naming.md)), not a page explaining it.
- **No** — admit the page, then hold it to the rest of the family: one copy per fact ([reference-dont-duplicate.md](reference-dont-duplicate.md)), deference to upstream owners ([documentation-and-citations.md](documentation-and-citations.md)), layering ([progressive-disclosure.md](progressive-disclosure.md)), and wording ([concise-prose.md](concise-prose.md)).

## What earns existence

Content whose source of truth is the page itself — what code cannot express:

- **Decisions** — the alternatives considered and rejected, and the trade-off that picked the winner. Code shows only the winning form; a decision record is the sole home for the losing ones.
- **Domain language** — the glossary and ubiquitous language behind the names in the code; [domain-driven-design.md](domain-driven-design.md) owns this surface.
- **Navigation** — one thin index whose entries are pointers with just enough context to route a reader to the scenario-scoped file they need, never summaries of what those files say. [progressive-disclosure.md](progressive-disclosure.md) owns the layering shape; link validity is the deterministic edge a tool can own.
- **Policy and wiring** — the decisions, empirical findings, and operator recipes [documentation-and-citations.md](documentation-and-citations.md) names as what the repo records instead of upstream bodies.

## What is refused

Hand-written restatement of anything the code expresses: how-it-works narration, API and behavior descriptions, module-by-module walkthroughs, architecture recaps of what the structure already shows. Two exceptions are sanctioned elsewhere and stand:

- The **Expose** role in [reference-dont-duplicate.md](reference-dont-duplicate.md) — onboarding restatement with a pointer back to the source.
- **Automated derivation** — a page generated from code (an API reference from doc comments, schema docs from types) is a derived artifact, not a second source, admitted only while its regeneration is automated. A hand-maintained copy of generated output is refused.

## Failed admission is deleted, not updated

Drift inside an admitted page is a defect: fix the page. A page that fails the admission test is drift by construction, and updating it only re-arms the trap — the remediation is deletion, after relocating anything admissible to its owning category. This is the specific-case override of the general stale-descriptor rule ([../review/code-quality.md](../review/code-quality.md)): a behavior change that invalidates an admitted page's descriptors is completed by updating them; one that invalidates a page which fails admission is completed by deleting it. Apply the test opportunistically: when work touches a page, judge its existence before its accuracy.

## Sources

- Michael Nygard, ["Documenting Architecture Decisions"](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) (2011) — decision records exist to capture context, alternatives, and consequences that the resulting code cannot show.
- Matt Pocock, [on ADRs for agents](https://x.com/mattpocockuk/status/2060454199838544079) (X, 2026) — "the thinnest layer of docs that captures the stuff code can't"; well-organized code, not a layer of docs describing it, is what an agent should read.
