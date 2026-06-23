# Observability review criteria

Diff-time checks for telemetry a change adds — traces, metrics, and logs. Severity labels are defined in [README.md](README.md). The instrumentation APIs differ by stack and live in the overlays; the principles below are language-agnostic and follow [OpenTelemetry](https://opentelemetry.io/docs/concepts/) semantics.

## No black boxes

New apps, services, long-lived tool servers, and non-trivial scripts expose inspectable signal — structured logs, trace and metric hooks, or explicit progress output — scaled to the surface's complexity and lifetime. The polyglot minimum for any executable surface is a meaningful exit code, an actionable error message, and correlation context across a multi-step flow. A production-reachable surface needs more than print debugging.

## Tracing

- **Spans for domain-significant work** — wrap meaningful units (handlers, cross-module calls, external I/O), not every method. Set the right span kind rather than leaving the default. Over-spanning produces noise, not insight.
- **Stable, namespaced source names** — an instrumentation source uses a unique, dotted name from its component, created once and reused. The name is the registration key downstream and must stay stable across releases.
- **Registration is not optional and fails silently** — telemetry from an unregistered source or meter is dropped with no error. Every new source and meter name is wired into the provider, in the shared configuration path so every service inherits it. A typo yields zero telemetry, not a warning.
- **Do not re-instrument what a library already covers** — emitting a span for inbound HTTP, an outbound client call, or a database call that the platform already instruments double-counts timing. A domain span wraps the library span as a parent and adds business context.

## Trace context propagation

- **In-process flow is automatic — do not break it** — context flows across awaited calls; detached background work must capture and restore it or it loses its parent.
- **Cross-boundary work links rather than force-parents** — work dequeued from a queue, or a message being consumed, links to its originating context (captured at the producer) rather than parenting under an unrelated ambient span. Non-in-process boundaries serialize and reconstruct context.

## Metrics

- **Correct instrument type** — a monotonically increasing count uses a counter, an up-and-down value (queue depth, active requests) an up-down counter, a duration a histogram, a point-in-time reading a gauge. A counter used for a value that can decrease is a defect.
- **Bounded tag cardinality** — tags are low-cardinality (status, size, region), never unbounded (user identities, raw URLs, request identities) — those belong in logs and traces. A reused tag key means the same thing everywhere.

## Semantic conventions and correlation

- **Reuse semantic conventions before inventing keys** — use the stable standard attribute names for HTTP, database, and messaging rather than minting new ones, and isolate any attribute drawn from a still-evolving convention so a future rename is contained.
- **Namespace custom attributes** — app-specific tags use a reverse-domain or app-unique prefix; never an OpenTelemetry-reserved prefix or an existing standard namespace.
- **Log-trace correlation** — high-volume diagnostics go through the logging pipeline (which captures the active trace and span identities) while the relevant span is current, so logs and traces correlate. Log-level appropriateness and sensitive-data redaction are governed by the security and code-quality criteria.

## Sources

- [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/)
