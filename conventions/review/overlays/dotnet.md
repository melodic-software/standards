# .NET review overlay

Stack-specific review bars for .NET that the agnostic review criteria leave to an overlay. The mechanically enforced posture (analyzers, code style, formatting, banned symbols) is owned by the [`.NET analysis`](../../../components/dotnet-analysis/) component; this overlay covers only reasoning-tier judgments a build cannot make. Severity labels are defined in [../README.md](../README.md).

## Code quality and shape

- **Parameter-count ceiling** — the `dotnet-analysis` component posture enforces none: no first-party CA rule covers method arity, and code-metrics rules stay opt-in even under `AnalysisMode=All`. Review owns the agnostic arity tiers in full, from the parameter-object default through seven-plus.
- **Reflection where a source generator exists** — runtime reflection for serialization, P/Invoke, or assembly-scanning registration where a compile-time generator is available.
- **DI registration without an explicit service type** — registering a concrete instance such that the registered type is inferred; state the service type explicitly.
- **EF Core nullable pattern** — new entity reference properties use the null-forgiving initializer rather than a pragma suppression.

## Error handling and resilience

- **Result mapping at the boundary** — the API layer maps a result's failure to the appropriate status.
- **Resilience libraries** — outbound calls use the platform resilience handler (or an equivalent) for retry, backoff, and circuit breaking rather than hand-rolled loops.
- **Captive `HttpClient`** — a new client per request exhausts sockets; a captured long-lived client goes stale on DNS changes. Use the client factory or a static handler with a bounded connection lifetime, and never inject a short-lived typed client into a singleton.
- **Disposal** — flag an async-disposable disposed through the synchronous path; it skips async cleanup.

## Concurrency

- **Per-scope data context** — the data context is the single-threaded unit of work the base per-request-state criterion targets; the .NET remediation is a scoped DI lifetime, never a singleton or an instance shared across parallel work.
- **Async-void** — `async void` is the fire-and-forget-shaped signature the base criterion restricts to the platform's event-handler case; everything else returns a `Task`.
- **Library await configuration** — the analyzer already forces every await to be configured (the `dotnet-analysis` component posture); review owns what it cannot decide: the configuration fits the context (library code avoids capturing the synchronization context), and the bar still holds in repos that deliberately relaxed the rule.

## Performance

- **Two-tier cache coherence** — a hybrid in-process-over-distributed cache treats tag invalidation as logical (entries expire as misses, not evicted) and must not wrap its built-in stampede protection in a redundant lock.
- **Large-object-heap pressure** — frequent large temporary buffers belong in a pooled allocator rather than fresh allocations.
- **Ordinal string comparison on hot paths** — culture-aware comparison is far slower; use ordinal comparison where culture is irrelevant, and a source-generated regex over a runtime-compiled one.
- **Time-ordered keys** — a server-generated key that doubles as a storage primary key prefers a time-ordered GUID over a random one to avoid fragmenting the index.

## Observability

- **Source and meter registration** — register every new instrumentation source and meter name in the shared service-defaults path, and use the meter factory in DI rather than constructing a meter directly.

## Testing

- **Test-project placement** — integration tests as a child of a web-SDK project compile test files into the app; place them in a dedicated test project. Unit tests co-locate by responsibility; cross-cutting tests centralize.
- **Real instances for managed dependencies** — an in-memory provider or a mocked database for an application-owned store hides integration bugs; use a real instance (a container) for managed dependencies, and substitute only unmanaged, externally-visible ones.
- **Foundational library changes** — shared platform code requires thorough coverage; a bug there cascades. Critical when independently testable behavior is added without tests.
