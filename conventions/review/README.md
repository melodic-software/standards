# Review criteria

Diff-time quality bars for reviewing a change — the checks a competent reviewer applies that automated tooling cannot fully decide. They are written to be read by a human reviewer or an agent performing a review; nothing here is executed by a tool walking the tree.

## Severity vocabulary

Every criterion resolves to one of three severities. They are the contract surface a review speaks in:

- **Critical** — a correctness, security, or data-integrity defect; merging it ships a bug.
- **Important** — a real problem that should be fixed before merge, or explicitly accepted with a recorded reason.
- **Suggestion** — an improvement worth making; not a merge blocker.

A criterion's default severity often shifts with context — the same smell is a Suggestion on a private helper and Critical on a public or security-bearing surface. Each file notes where that shift applies.

## Agnostic criteria plus thin overlays

The criteria are language-agnostic by default. A stack overlay under `overlays/` adds only the bars specific to that stack that the agnostic file leaves out, and points to the corresponding components for everything the toolchain already enforces. When a change touches a stack, read its overlay alongside the agnostic criteria.

| Criteria | Covers |
|---|---|
| [code-quality.md](code-quality.md) | local design, parameter and model shape, style, authoring hygiene |
| [code-design.md](code-design.md) | cohesion, coupling, responsibility, abstraction fit, substitutability, pattern use |
| [architecture.md](architecture.md) | structural integrity, contract evolution, build-system coupling |
| [error-handling.md](error-handling.md) | result-modeling, exception boundaries, resilience, idempotency |
| [concurrency.md](concurrency.md) | shared state, cancellation, async hazards, deadlocks |
| [performance.md](performance.md) | queries, allocation, caching, pagination, streaming |
| [security.md](security.md) | secrets, injection, trust boundaries, supply chain |
| [accessibility.md](accessibility.md) | WCAG-aligned review and evidence for user-facing experiences |
| [cross-platform.md](cross-platform.md) | OS, filesystem, encoding, and tooling portability |
| [observability.md](observability.md) | tracing, metrics, logs, and correlation |
| [testing.md](testing.md) | coverage, test quality, verification honesty |
| [ai-generated-code.md](ai-generated-code.md) | the empirical failure modes of AI-authored changes |
| [ai-review-bot-composition.md](ai-review-bot-composition.md) | expected automated AI-reviewer composition per repository governance class |
| [mcp.md](mcp.md) | tools and MCP servers exposed to LLM agents |
| [reply-protocol.md](reply-protocol.md) | how a review-comment thread closes once its finding is addressed |
| [overlays/bash.md](overlays/bash.md) · [overlays/containers.md](overlays/containers.md) · [overlays/dotnet.md](overlays/dotnet.md) · [overlays/go.md](overlays/go.md) · [overlays/python.md](overlays/python.md) · [overlays/typescript.md](overlays/typescript.md) | per-stack review bars |

## Enforcement escalation

When review keeps catching the same issue, it may belong in a tool rather than in prose. Classify it by the enforceability tiers (`../engineering/enforceability-tiers.md`) and move it as far toward automation as its nature allows.
