# MCP and agent-tool review criteria

Diff-time checks for tools and functions exposed to an LLM agent, including MCP servers. The model consumes these definitions directly — it routes on a tool's name and description, fills its input schema, and reads the output back into its context — so the authoring surface is a first-class contract. `security.md` owns secrets, trust boundaries, and vetting a third-party tool server for adoption; this file owns how a tool is defined. Severity labels are defined in [README.md](README.md).

## Tool interface

- **Vague or colliding name and description** — the model selects a tool from its name and description alone, so a generic description, a name that overlaps an existing tool in meaning, or an ambiguous parameter (`user` where `user_id` is meant) causes selection misfires. A tool description should read like onboarding a new hire. Important; Critical where the ambiguity lets the model pick a mutating or destructive tool by mistake ([writing effective tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents)).
- **Loose input or output schema** — an input schema that accepts a free-form string where a bounded enum or typed field belongs, omits `required`, or leaves the object open when it should be closed, widening the surface the model can hallucinate into; or a tool that returns structured data as untyped text with no declared output schema, so neither client nor model can validate the shape. Important; Suggestion on a trivial read-only helper. Parameter and model shape is owned by `code-quality.md`, applied here at the tool boundary ([MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)).
- **Redundant or overloaded tools** — a change adding a thin per-endpoint wrapper where a consolidated workflow tool fits, a new tool overlapping an existing one, or one tool doing two unrelated jobs. Too many or overlapping tools distract the agent from an efficient strategy. Suggestion; Important when the overlap is with a destructive tool ([writing effective tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents)).

## Output and errors

- **Unbounded output** — a tool that returns a verbose or unbounded payload (full records, a raw upstream API dump, opaque identifiers) straight into the context with no pagination, filtering, truncation, or default limit, and no concise-versus-detailed mode where output is large. Prefer human-readable identifiers, and make any truncation carry steering guidance rather than a silent cut. Important; Suggestion on a low-volume internal tool. Store-side pagination mechanics are owned by `performance.md`; this bar is context-window economy ([writing effective tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents)).
- **Errors the model cannot act on** — a tool that lets an exception escape as a transport or protocol error, or returns an opaque code or stack trace, instead of returning a recoverable error as tool-result content flagged as an error, with text that steers the next call. The protocol separates an execution error the model can self-correct from a protocol error it cannot. Important. Result-versus-exception at a boundary is owned by `error-handling.md` ([MCP tools — error handling](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)).

## Safety and trust

- **Unsignalled side effects** — a mutating, destructive, or external-world tool defined without behavior annotations, or with annotations that misdescribe it. The hints default toward caution (read-only is false, destructive is true, idempotent is false, open-world is true), so flag a read-only tool that omits the read-only hint (needless friction) and a mutating tool that leans on the defaults instead of explicit hints plus a human confirmation seam. Annotations are hints from a possibly-untrusted server, never an authorization control — real gating is server-side. Important; Critical for an irreversible action with no annotation and no confirmation ([tool annotations](https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)).
- **Treating tool output as instructions** — tool-result text and resource content are untrusted input, not commands. A server that reflects unvalidated upstream content back to the agent, or a design that folds returned text into the agent's instruction channel without delimiting it as data, is a prompt-injection surface. Critical. Trust boundaries are owned by `security.md`; injection as an AI-authored-code failure mode by `ai-generated-code.md` ([OWASP LLM01](https://genai.owasp.org/llmrisk/llm01-prompt-injection/)).
- **Embedded secrets or over-broad scope** — a tool definition embedding a credential; a tool or server granted broader scope than its task needs; token passthrough, where a server accepts a token not issued to it and forwards it downstream. Critical. Secrets are owned by `security.md`; this flags them at the tool-definition surface ([MCP security best practices](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices)).

## Reliability

- **Unsafe retry and colliding names** — a non-idempotent mutating tool with no idempotency key or server-side deduplication, where an agent will retry on a timeout (an idempotent hint claimed but unenforced is worse than none); and a tool name with no server or service prefix, which collides when several servers load together (`asana_search`, not a bare `search`). Important; the namespacing half is a Suggestion for a single-server target. Idempotency is owned by `error-handling.md` ([MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)).

## Boundaries

- **vs `security.md`** — security owns secrets, trust boundaries, injection generally, and vetting a third-party tool server for adoption. This file owns the tool-authoring surface: the definition, its schema, and what it returns.
- **vs `error-handling.md`** — error-handling owns result-versus-exception and the idempotency and retry posture. The error-as-content contract and agent-retry safety here are the MCP instances.
- **vs `ai-generated-code.md`** — that file owns prompt injection as a failure mode of AI-authored code. This owns the tool-output-is-untrusted framing at the tool boundary.
- **vs `performance.md`** — performance owns query and endpoint pagination mechanics. The output bar here is context-window economy.
- **vs `code-quality.md`** — code-quality owns parameter and model shape; the input-schema bar reuses that judgment at the tool boundary.

## Sources

- Anthropic Engineering — [writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- Model Context Protocol — [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [security best practices](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices), [tool annotations](https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)
- OWASP — [LLM01:2025 Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/), [Top 10 for LLM Applications 2025](https://owasp.org/www-project-top-10-for-large-language-model-applications/assets/PDF/OWASP-Top-10-for-LLMs-v2025.pdf)
