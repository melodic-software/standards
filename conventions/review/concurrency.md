# Concurrency review criteria

Diff-time checks for concurrent code — async handlers, background work, parallel processing, shared caches. Severity labels are defined in [README.md](README.md). Stack-specific primitives and idioms live in the overlays; the language-agnostic hazards are below.

- **Shared mutable state without synchronization** — static fields, singleton state, or shared collections mutated from more than one thread without a lock, a concurrent collection, or an atomic operation.
- **Cancellation propagation** — an async operation that accepts external input or performs I/O accepts and forwards a cancellation signal. Missing propagation lets work outlive its caller, orphaning requests and leaking connections.
- **Fire-and-forget without error handling** — a discarded async result silently swallows its failure. Background work routes through a mechanism that observes and logs exceptions.
- **Blocking on asynchronous work** — synchronously waiting on an async result inside an async context risks thread-pool starvation and, with some schedulers, deadlock.
- **Async signatures that hide failure** — an async method whose return type cannot surface an exception (a fire-and-forget-shaped signature) is acceptable only for the platform's event-handler case; everything else returns an awaitable.
- **Lock contention on hot paths** — a coarse lock around a whole method where finer-grained or lock-free alternatives would suffice.
- **Inconsistent lock ordering** — nested locks acquired in different orders across call sites are a classic deadlock.
- **Thread-unsafe collection access** — a non-thread-safe collection read and written across threads; use a concurrent collection or explicit synchronization.
- **Parallel iteration with shared-state side effects** — a parallel loop whose body captures and mutates shared state.
- **Per-request state shared across concurrent work** — a unit of work designed for single-threaded use (many data-access contexts, for instance) shared across concurrent operations. Scope it per operation.
- **Resource exhaustion and primitive disposal** — a throttling primitive whose permit is not released in a finally block, an unbounded wait with no timeout, or a concurrency primitive that owns resources and is never disposed.
