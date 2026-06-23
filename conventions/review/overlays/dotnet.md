# .NET review overlay

Stack-specific review bars for .NET that the agnostic review criteria leave to an overlay. The mechanically-enforced posture (analyzers, code style, formatting, banned symbols) is owned by `modules/dotnet/` — this overlay covers only the reasoning-tier judgments a build cannot make. Severity labels are defined in [../README.md](../README.md).

## Code quality and shape

- **Parameter-count ceiling** — the analyzer breaks the build past its configured maximum (the `modules/dotnet/` posture). Review still owns the four-to-six range and the early parameter-object default below that floor.
- **Reflection where a source generator exists** — runtime reflection for serialization, P/Invoke, or assembly-scanning registration where a compile-time generator is available.
- **DI registration without an explicit service type** — registering a concrete instance such that the registered type is inferred; state the service type explicitly.
- **EF Core nullable pattern** — new entity reference properties use the null-forgiving initializer rather than a pragma suppression.

## Error handling and resilience

- **Result mapping at the boundary** — the API layer maps a result's failure to the appropriate status; domain code never handles a raw infrastructure exception type.
- **Resilience libraries** — outbound calls use the platform resilience handler (or an equivalent) for retry, backoff, and circuit breaking rather than hand-rolled loops.
- **Captive `HttpClient`** — a new client per request exhausts sockets; a captured long-lived client goes stale on DNS changes. Use the client factory or a static handler with a bounded connection lifetime, and never inject a short-lived typed client into a singleton.
- **Disposal** — synchronous and asynchronous disposal are not mixed; disposing an async-disposable through the synchronous path skips async cleanup. The mechanical cases are analyzer-caught; review owns the ownership judgment.
- **Time-ordered keys** — a server-generated key that doubles as a storage primary key prefers a time-ordered GUID over a random one to avoid fragmenting the index.

## Concurrency

- **Per-scope data context** — the data context is not thread-safe; a scoped lifetime is the correct pattern, and sharing one instance across concurrent operations is a defect.
- **Async-void** — acceptable only for an event handler; every other async method returns a task so exceptions and coordination propagate.
- **Library await configuration** — library code configures awaits to avoid capturing an unnecessary synchronization context.

## Performance

- **Two-tier cache coherence** — a hybrid in-process-over-distributed cache must keep its local and distributed lifetimes aligned, treat tag invalidation as logical (entries expire as misses, not evicted), and not wrap its built-in stampede protection in a redundant lock.
- **Large-object-heap pressure** — frequent large temporary buffers belong in a pooled allocator rather than fresh allocations.
- **Ordinal string comparison on hot paths** — culture-aware comparison is far slower; use ordinal comparison where culture is irrelevant, and a source-generated regex over a runtime-compiled one.

## Observability

- **Source and meter registration** — every new instrumentation source and meter name is registered with its provider in the shared service-defaults path, or its telemetry is silently dropped. Use the meter factory in DI rather than constructing a meter directly, and pick the instrument type that matches the measurement.

## Testing

- **Test-project placement** — integration tests as a child of a web-SDK project compile test files into the app; place them in a dedicated test project. Unit tests co-locate by responsibility; cross-cutting tests centralize.
- **Real instances for managed dependencies** — an in-memory provider or a mocked database for an application-owned store hides integration bugs; use a real instance (a container) for managed dependencies, and substitute only unmanaged, externally-visible ones.
- **Foundational library changes** — shared platform code requires thorough coverage; a bug there cascades. Critical when independently testable behavior is added without tests.
