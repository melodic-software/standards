# Error-handling review criteria

Diff-time checks for how a change handles failure: result-modeling, exception boundaries, outbound resilience, and error context. Severity labels are defined in [README.md](README.md). The result-over-exceptions and timeout-first defaults are owned by `../engineering/architecture-and-design.md` and `../engineering/engineering-philosophy.md`; stack-specific resilience libraries and disposal rules live in the overlays.

- **Results at the domain boundary** — an anticipable domain or business failure returned as an explicit result, not signaled by a thrown exception. Flag a throw used for an expected failure condition in domain or application code.
- **Exception swallowing** — an empty catch, a catch that returns null, or a catch that logs without propagating or converting. Every caught exception is handled meaningfully, converted to a result error, or re-thrown.
- **Error context propagation** — errors carry enough context to diagnose without reproducing. Flag messages that drop the original cause, strip identifying data, or read "an error occurred".
- **Resilience on outbound calls** — calls to a network, database, queue, or external API have a retry policy with backoff where appropriate, and a circuit breaker where a down dependency could cascade.
- **Timeout-first** — every outbound call carries a timeout (and a cancellation signal where the platform offers one) from its first implementation. Flag a network or database call with no deadline.
- **Exception-type specificity** — catching the broadest exception type when a narrower one would do. Broad catches are acceptable only at an infrastructure boundary whose intent is explicitly "catch everything, log, continue".
- **Error mapping at layer boundaries** — infrastructure exceptions (storage, transport, file I/O) are caught at the infrastructure layer and converted to domain-meaningful result errors. Domain code does not handle a raw infrastructure exception type.
- **Validation versus domain errors** — input-validation failures are returned as structured validation results at the entry boundary, not as domain errors or exceptions.
- **Idempotency of retryable operations** — anything that can be retried must be safe to run more than once with the same effect as once. Per [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110#section-9.2.2), `GET`/`PUT`/`DELETE` are idempotent but `POST` is not — a create behind a retrying client needs an explicit client-supplied idempotency key, deduplicated server-side. At-least-once messaging guarantees duplicate delivery, so a consumer must dedupe (a natural key, a processed-message record, or an upsert). A multi-side-effect operation with no compensation is not idempotent.
- **Resource disposal and lifetime** — a resource with a disposal contract is released deterministically, synchronous and asynchronous disposal are not mixed up, and a short-lived client is not captured by a long-lived owner. The mechanical cases are often analyzer-caught; review owns the lifetime and ownership judgment.
- **Structured error codes** — errors surfaced to a consumer carry a machine-readable code alongside the human-readable message, so callers can branch programmatically.

## Sources

- [RFC 9110 §9.2 — safe and idempotent methods](https://www.rfc-editor.org/rfc/rfc9110#section-9.2.2)
