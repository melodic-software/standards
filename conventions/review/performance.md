# Performance review criteria

Diff-time checks for patterns with measurable production impact — not micro-optimization. Severity labels are defined in [README.md](README.md). Stack-specific allocation, caching, and query mechanics live in the overlays; the language-agnostic patterns are below.

- **N+1 queries** — a query issued per item inside a loop where one batched query or a join would do. Each iteration is a separate round trip.
- **Chatty calls** — several sequential round trips to the same service or store for data a single batched call could fetch. Flag three or more sequential calls with similar parameters where a bulk alternative exists.
- **Unnecessary allocation on hot paths** — accumulating strings in a loop instead of a builder, materializing a collection only to iterate it once, repeated temporary buffers on a frequently hit path.
- **Caching without invalidation** — a cache with no invalidation strategy is a correctness bug, not an optimization. Conversely, flag repeated expensive computation or I/O for data that changes infrequently and has no cache.
- **Multi-tier cache coherence** — when an in-process cache layers over a distributed one, diverging their lifetimes lets a stale local read outlive a remote invalidation made on another node. Reason about both tiers.
- **Materialization timing** — filtering after fully materializing a set (rather than pushing the filter to the source), or returning a lazily-evaluated sequence backed by a resource that is disposed before the consumer iterates.
- **Streaming versus buffering large result sets** — buffering an entire large result set into memory where streaming it would bound memory. Never fully materialize a set only to chain one more transformation over it.
- **Pagination correctness and scalability** — an endpoint returning an unbounded collection, or pagination whose ordering is not fully unique. Offset pagination degrades on deep pages and can skip or duplicate rows under concurrent writes; keyset (seek) pagination is the scalable default for sequential navigation. Either way the ordering must include a unique tiebreaker, since stores apply no inherent order.
- **Async-over-sync and sync-over-async** — wrapping CPU-bound work in an async shell that just occupies a pool thread, or blocking synchronously on async work.
