# Engineering conventions

Agent-agnostic engineering standards that no linter can decide for you — the authoring lane of `../../conventions`, the catalog's reasoning-only tier. Each file owns one concern. Where a convention *can* be mechanically enforced, it belongs to a component under `../../components/`, not here; `enforceability-tiers.md` explains the split.

| Convention | Owns |
|---|---|
| [engineering-philosophy.md](engineering-philosophy.md) | the default posture: explicit, fail-fast, resilient, idempotent, simple, cross-platform, cosmetic findings as real work |
| [architecture-and-design.md](architecture-and-design.md) | dependency direction, vertical slices, composition, result-modeling, consistency boundaries, extension points, no-outage operational change |
| [domain-driven-design.md](domain-driven-design.md) | tactical patterns (entities, value objects, aggregates, repositories) and ubiquitous language |
| [naming.md](naming.md) | verbose behavior-naming, name-by-responsibility, disambiguating overloaded terms |
| [simpler-code.md](simpler-code.md) | the line-count-versus-clarity tradeoff and its named failure modes |
| [concise-prose.md](concise-prose.md) | removing prose overhead without losing meaning, force, or clarity |
| [code-organization.md](code-organization.md) | sharing at the second consumer, contract-versus-private surfaces, breaking-change discipline |
| [shareable-artifact-design.md](shareable-artifact-design.md) | consumer-agnostic behavior, externalized configuration, consumer tiers, explicit adoption for anything built to be shared |
| [documentation-existence.md](documentation-existence.md) | whether a tracked page may exist at all — the admission test upstream of the documentation family |
| [reference-dont-duplicate.md](reference-dont-duplicate.md) | one source of truth per fact; cite, never recap (in-repo) |
| [documentation-and-citations.md](documentation-and-citations.md) | citing upstream authorities; read-on-demand over snapshots |
| [deterministic-artifact-scaffolding.md](deterministic-artifact-scaffolding.md) | stable artifact structure in deterministic mechanisms; judgment-bearing slots stay human- or agent-owned |
| [deterministic-work-execution.md](deterministic-work-execution.md) | session-time tool execution for deterministic sub-work; judgment remains human- or agent-owned |
| [progressive-disclosure.md](progressive-disclosure.md) | layering information so a reader pays only for the depth they reach |
| [container-supply-chain.md](container-supply-chain.md) | Dockerfile, build-context, image-scanning, artifact-identity, and runtime assurance boundaries |
| [legacy-and-migration-debt.md](legacy-and-migration-debt.md) | describing the current form; the exposure classifier for old paths |
| [enforceability-tiers.md](enforceability-tiers.md) | deterministic vs detect-then-judge vs reasoning-only; why this directory exists |
