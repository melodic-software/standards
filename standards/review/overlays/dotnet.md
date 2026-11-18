# .NET review overlay

Stack-specific review bars for .NET that the agnostic review criteria leave to an overlay. The mechanically enforced posture (analyzers, code style, formatting, banned symbols) is owned by the [`.NET analysis`](../../../components/dotnet-analysis/) component; this overlay covers only reasoning-tier judgments a build cannot make. Severity labels are defined in [../README.md](../README.md).

## Code quality and shape

- **Parameter-count ceiling**: the `dotnet-analysis` component posture enforces none. No first-party CA rule covers method arity, and code-metrics rules stay opt-in even under `AnalysisMode=All`. Review owns the agnostic arity tiers in full, from the parameter-object default through seven-plus.
- **Reflection where a source generator exists**: runtime reflection for serialization, P/Invoke, or assembly-scanning registration where a compile-time generator is available.
- **DI registration without an explicit service type**: registering a concrete instance such that the registered type is inferred; state the service type explicitly.
- **EF Core nullable pattern**: new entity reference properties use the null-forgiving initializer rather than a pragma suppression.

## Error handling and resilience

- **Result mapping at the boundary**: the API layer maps a result's failure to the appropriate status.
- **Resilience libraries**: outbound calls use the platform resilience handler (or an equivalent) for retry, backoff, and circuit breaking rather than hand-rolled loops.
- **Captive `HttpClient`**: a new client per request exhausts sockets; a captured long-lived client goes stale on DNS changes. Use the client factory or a static handler with a bounded connection lifetime, and never inject a short-lived typed client into a singleton.
- **Disposal**: flag an async-disposable disposed through the synchronous path; it skips async cleanup.

## Persistence (EF Core)

The agnostic atomicity and migration bars live in [error-handling.md](../error-handling.md#atomicity) and [architecture.md](../architecture.md#contract-evolution); these are the EF Core mechanics that decide whether they hold.

- **Multiple `SaveChanges` are not one transaction**: one `SaveChanges` applies its tracked changes in a single implicit transaction; several calls are not jointly atomic. Work that must commit together uses one call, or an explicit transaction whose `using` scope wraps the whole unit and which calls `Commit`; disposal without a commit rolls back silently [8].
- **Explicit transactions under a retrying execution strategy**: with a retrying strategy configured (`EnableRetryOnFailure` or a custom one), a bare `BeginTransaction` throws, and only when retries are enabled, so local testing misses it. The whole unit, the transaction, every `SaveChanges`, and the commit, runs inside `CreateExecutionStrategy().Execute(...)` so it replays as one block. A connection drop during commit leaves the outcome unknown and the strategy retries as if it rolled back; guard with client-generated keys or a `verifySucceeded` check [9].
- **Savepoints and MARS**: `SaveChanges` inside an open transaction sets a savepoint and rolls back to it on error, so already-applied work is not re-applied after a caught error. On SQL Server with MARS enabled no savepoint is created, and an error can leave the transaction in an unknown state [8].
- **Ambient transactions across `await`**: a `TransactionScope` around asynchronous calls passes `TransactionScopeAsyncFlowOption.Enabled`, or the work after the first `await` runs outside it. Distributed `System.Transactions` transactions are Windows-only (.NET 7 and later); coordinate across stores with an outbox instead [8].
- **Migration hygiene**: a property rename can scaffold as drop-then-add, destroying the column's data; replace it with a rename or a copy-then-drop. Commit the migration with the model change and guard it with a test on `HasPendingModelChanges()`; from EF Core 9, `Migrate()` throws on uncaptured model changes and when called inside an explicit transaction. Operations that cannot run in a transaction go in their own migration, or use `suppressTransaction: true` knowing it removes that statement's rollback [10], [11].

## Multi-tenancy

The agnostic bars live in [multi-tenancy.md](../multi-tenancy.md); these are the .NET mechanisms behind them.

- **Tenant query filters**: tenant-owned entities are scoped by a global query filter or an interceptor, so a default query cannot return another tenant's rows. `IgnoreQueryFilters()` appears only on a documented cross-tenant path (platform admin, migration, cross-tenant report), never on a default request path [12].
- **Tenant context lifetime**: the resolved tenant lives in a scoped service or an async-local context for the request or job, never in static or thread-static state, and downstream handlers receive it through DI or a parameter rather than reading an ambient value nothing established.
- **Claim names match the wire**: token and OpenID Connect handlers remap inbound claim types by default (the default inbound claim-type map, switched off per scheme with `MapInboundClaims = false`), so code reading `sub` or a custom tenant claim reads the name the token carries after mapping, consistently from issuer to consumer [13].

## Messaging (MassTransit)

The agnostic bars live in [messaging.md](../messaging.md); these apply where MassTransit is the bus [14].

- **Outbox relay running**: with the MassTransit outbox, the delivery service that relays outbox rows is registered and running, or messages persist and never publish; the inbox duplicate-detection window covers the realistic redelivery horizon.
- **Bounded fault path that keeps failures**: message retry, then scheduled redelivery, is bounded so a poison message reaches the `_error` queue rather than looping. `DiscardSkippedMessages()` silently drops unroutable messages instead of moving them to `_skipped`; flag it. Delayed redelivery relies only on what the deployed broker has installed (a delayed-exchange plugin is not assumed).
- **Contract shape**: message contracts are public types; interface contracts expose get-only properties. A new version is a new additive contract, not an edit to the shipped one.

## Concurrency

- **Per-scope data context**: the data context is the single-threaded unit of work the base per-request-state criterion targets; the .NET remediation is a scoped DI lifetime, never a singleton or an instance shared across parallel work.
- **Async-void**: `async void` is the fire-and-forget-shaped signature the base criterion restricts to the platform's event-handler case; everything else returns a `Task`.
- **Library await configuration**: the analyzer already forces every await to be configured (the `dotnet-analysis` component posture); review owns what it cannot decide: the configuration fits the context (library code avoids capturing the synchronization context), and the bar still holds in repos that deliberately relaxed the rule.

## Date and time

The shared [date-time criteria](../date-time.md) own the semantic and storage
contract. This overlay owns only the .NET and SQL Server representation.

- **Types match the contract**: represent an instant with `DateTimeOffset`,
  normalizing it to UTC when the shared storage contract requires that; use a
  UTC `DateTime` only behind an enforced `Kind.Utc` invariant. On targets that
  provide them, use `DateOnly` and `TimeOnly` for date-only and time-of-day
  values (`DateOnly` and `TimeOnly` are not available in .NET Framework). Use
  `TimeZoneInfo`, not the obsolete `TimeZone`, for zone conversion, and retain
  the IANA zone ID separately for future local intent: a `DateTimeOffset`
  carries an offset, not a time zone. Prove ID resolution on every target;
  Windows IANA lookup starts with .NET 6 and requires ICU rather than NLS or
  invariant globalization. See Microsoft's [type-selection guidance][1] and
  [`TimeZoneInfo` compatibility notes][6].
- **Inject the clock**: time-dependent services receive a `TimeProvider` and
  use its timestamp APIs for elapsed time so tests can control wall time and
  timers. It is built into .NET 8 and later; .NET 5–7, .NET Framework 4.6.2 and
  later, and .NET Standard 2.0 use the official compatibility package. See the
  [`TimeProvider` overview][2].
- **Modern SQL Server columns**: for SQL Server and Azure SQL, select `date`,
  `time`, `datetime2`, or `datetimeoffset` by contract; a new legacy `datetime`
  column is an Important finding because Microsoft says to avoid it for new
  work. Use `datetime2` when an offset need not round-trip and `datetimeoffset`
  only when the numeric offset is part of the contract; neither type stores a
  named time zone. Confirm the target before prescribing `datetimeoffset`:
  Microsoft Fabric Warehouse does not support that column type for persisted
  table storage [7]. See the [`datetime`][3], [`datetime2`][4], and
  [`datetimeoffset`][5] documentation.

## Performance

- **Two-tier cache coherence**: a hybrid in-process-over-distributed cache treats tag invalidation as logical (entries expire as misses, not evicted) and must not wrap its built-in stampede protection in a redundant lock.
- **`HybridCache` keys and tags**: keys are caller-supplied strings with no automatic namespacing, so two entity types sharing a key string collide silently; prefix keys by entity. The tag `"*"` is reserved and matches no prefix, so `RemoveByTagAsync("*")` flushes the whole cache [15].
- **Hot-path boxing**: a value type stored as `object`, through a non-generic interface or collection, or captured in a `params object[]`, on a frequently hit path (serialization, logging, collection operations) allocates on every call.
- **Large-object-heap pressure**: frequent large temporary buffers belong in a pooled allocator rather than fresh allocations.
- **Ordinal string comparison on hot paths**: culture-aware comparison is far slower; use ordinal comparison where culture is irrelevant, and a source-generated regex over a runtime-compiled one.
- **Time-ordered keys**: a server-generated key that doubles as a storage primary key prefers a time-ordered GUID over a random one to avoid fragmenting the index.

## Observability

- **Source and meter registration**: register every new instrumentation source and meter name in the shared service-defaults path, and use the meter factory in DI rather than constructing a meter directly.
- **Null-safe activities**: `StartActivity` returns `null` when no listener samples the source, so calls on the result are null-conditional (`activity?.SetTag(...)`), and the failure path calls `activity?.SetStatus(ActivityStatusCode.Error, ...)`.

## Accessibility (Blazor)

The agnostic bars live in [accessibility.md](../accessibility.md); these are Blazor rendering behaviors that decide whether they hold [16].

- **Attributes land on the intended element**: `aria-*` and `role` passed to an input component splat onto its rendered element, but `ValidationMessage` and `ValidationSummary` splat onto their own generated container, and Blazor does not associate a validation message with its input. Author the `aria-describedby` association and verify it on the rendered DOM.
- **Focus calls wait for interactivity**: `FocusAsync` and other JS-interop focus calls run after the component is interactive (`OnAfterRenderAsync`, or gated on `RendererInfo.IsInteractive`), never during prerender or static server rendering, where handlers and interop are not wired.
- **Nothing depends on prerendered interactivity**: prerender emits non-interactive HTML first, so interactivity-dependent UI is gated on `RendererInfo.IsInteractive`; a form under static server rendering validates only on the server round-trip, so its error messaging is verified without interactivity.

## Testing

- **Test-project placement**: integration tests as a child of a web-SDK project compile test files into the app; place them in a dedicated test project. Unit tests co-locate by responsibility; cross-cutting tests centralize.
- **Real instances for managed dependencies**: an in-memory provider or a mocked database for an application-owned store hides integration bugs; use a real instance (a container) for managed dependencies, and substitute only unmanaged, externally-visible ones.
- **Test host by scope**: proof that crosses services or relies on service discovery runs against the distributed application (Aspire's hosting test harness); a single service's API with its direct dependencies runs under `WebApplicationFactory`. Suggestion.
- **Analyzer tests in both directions**: a new or changed Roslyn analyzer ships tests that show the diagnostic firing on violating code and staying silent on compliant code.
- **Foundational library changes**: shared platform code requires thorough coverage; a bug there cascades. Critical when independently testable behavior is added without tests.

[1]: https://learn.microsoft.com/en-us/dotnet/standard/datetime/choosing-between-datetime
[2]: https://learn.microsoft.com/en-us/dotnet/standard/datetime/timeprovider-overview
[3]: https://learn.microsoft.com/en-us/sql/t-sql/data-types/datetime-transact-sql
[4]: https://learn.microsoft.com/en-us/sql/t-sql/data-types/datetime2-transact-sql
[5]: https://learn.microsoft.com/en-us/sql/t-sql/data-types/datetimeoffset-transact-sql
[6]: https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.findsystemtimezonebyid
[7]: https://learn.microsoft.com/en-us/fabric/data-warehouse/data-types#unsupported-data-types-for-tables
[8]: https://learn.microsoft.com/ef/core/saving/transactions
[9]: https://learn.microsoft.com/ef/core/miscellaneous/connection-resiliency
[10]: https://learn.microsoft.com/ef/core/managing-schemas/migrations/managing
[11]: https://learn.microsoft.com/ef/core/what-is-new/ef-core-9.0/breaking-changes
[12]: https://learn.microsoft.com/ef/core/querying/filters
[13]: https://learn.microsoft.com/aspnet/core/security/authentication/claims
[14]: https://masstransit.io/documentation
[15]: https://learn.microsoft.com/aspnet/core/performance/caching/hybrid
[16]: https://learn.microsoft.com/aspnet/core/blazor/
