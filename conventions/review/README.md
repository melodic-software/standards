# Review criteria

Diff-time quality bars for reviewing a change — the checks a competent reviewer applies that automated tooling cannot fully decide. They are written to be read by a human reviewer or an agent performing a review; nothing here is executed by a tool walking the tree.

## Severity vocabulary

Every criterion resolves to one of three severities. They are the contract surface a review speaks in:

- **Critical** — a correctness, security, or data-integrity defect; merging it ships a bug.
- **Important** — a real problem that should be fixed before merge, or explicitly accepted with a recorded reason.
- **Suggestion** — an improvement worth making; not a merge blocker.

A criterion's default severity often shifts with context — the same smell is a Suggestion on a private helper and Critical on a public or security-bearing surface. Each file notes where that shift applies.

## Escalation tags

Severity states how bad a finding is. The `blocking` tag is a separate axis: it marks a specific finding as required-fix-before-merge on every consuming surface, overriding whatever severity the underlying criterion would otherwise carry in context. It exists because the synced `REVIEW.md` is short and universal by design — most of its lines are advisory (worth flagging, not worth hard-failing a build over), and `blocking` is how that thin file marks the minority that are not, so a hit is never quietly absorbed into a Nit or a Suggestion on any surface that reads it.

`blocking` is applied sparingly and only by a file's own author at authoring time — never inferred by a reviewer at review time. Recognizing that a *specific instance in a diff* matches a `blocking`-tagged criterion is unavoidably an LLM judgment call, the same kind of judgment every other criterion in this catalog already asks a reviewing agent to make. Treat that recognition as piloted, not as an assumed-reliable mechanism, until it has run against real diffs: a missed `blocking` match fails open (the finding still surfaces at its underlying severity, just without the hard-block), so the tag degrades gracefully rather than silently passing a build it should have stopped.

On a self-hosted or local review surface, an unresolved `blocking` finding maps to the same enforcement lever this organization's rulesets already use for review threads — the thread stays open and merge stays blocked until it is resolved. Managed Code Review's three-marker severity (Important / Nit / Pre-existing) has no `blocking` concept of its own; until managed exposes an equivalent, `blocking` is a self-hosted-only enforcement axis, and `REVIEW.md`'s crosswalk says so plainly rather than implying parity that doesn't exist.

## Agnostic criteria plus thin overlays

The criteria are language-agnostic by default. A stack overlay under `overlays/` adds only the bars specific to that stack that the agnostic file leaves out, and points to the corresponding components for everything the toolchain already enforces. When a change touches a stack, read its overlay alongside the agnostic criteria.

| Criteria | Covers |
|---|---|
| [code-quality.md](code-quality.md) | local design, parameter and model shape, style, authoring hygiene |
| [code-design.md](code-design.md) | cohesion, coupling, responsibility, abstraction fit, substitutability, pattern use |
| [architecture.md](architecture.md) | structural integrity, contract evolution, build-system coupling |
| [error-handling.md](error-handling.md) | result-modeling, exception boundaries, resilience, idempotency, atomicity of multi-step state changes |
| [concurrency.md](concurrency.md) | shared state, cancellation, async hazards, deadlocks |
| [messaging.md](messaging.md) | delivery integrity, ordering, message-contract evolution |
| [performance.md](performance.md) | queries, allocation, caching, pagination, streaming |
| [security.md](security.md) | secrets, injection, trust boundaries, supply chain |
| [multi-tenancy.md](multi-tenancy.md) | horizontal (cross-tenant) authorization, isolation, tenant lifecycle |
| [accessibility.md](accessibility.md) | WCAG-aligned review and evidence for user-facing experiences |
| [cross-platform.md](cross-platform.md) | OS, filesystem, encoding, and tooling portability |
| [date-time.md](date-time.md) | zone vs offset, future-local-time storage, tzdata currency, monotonic elapsed time, epoch ranges |
| [observability.md](observability.md) | tracing, metrics, logs, and correlation |
| [testing.md](testing.md) | coverage, test quality, verification honesty |
| [ai-generated-code.md](ai-generated-code.md) | the empirical failure modes of AI-authored changes |
| [ai-review-bot-composition.md](ai-review-bot-composition.md) | expected automated AI-reviewer composition per repository governance class |
| [mcp.md](mcp.md) | tools and MCP servers exposed to LLM agents |
| [reply-protocol.md](reply-protocol.md) | how a review-comment thread closes once its finding is addressed |
| [overlays/bash.md](overlays/bash.md) · [overlays/containers.md](overlays/containers.md) · [overlays/dotnet.md](overlays/dotnet.md) · [overlays/go.md](overlays/go.md) · [overlays/python.md](overlays/python.md) · [overlays/typescript.md](overlays/typescript.md) | per-stack review bars |

## Enforcement escalation

When review keeps catching the same issue, it may belong in a tool rather than in prose. Classify it by the enforceability tiers (`../engineering/enforceability-tiers.md`) and move it as far toward automation as its nature allows.
