# Python review overlay

Stack-specific review bars for Python. The mechanically enforced posture is owned independently by the [`ruff`](../../../components/ruff/) and [`pyright`](../../../components/pyright/) components; this overlay covers only reasoning-tier judgments those tools do not make. Severity labels are defined in [../README.md](../README.md).

## Correctness traps

- **Unspecified text encoding** — opening or decoding a file without an explicit UTF-8 encoding falls back to the platform locale and silently corrupts non-ASCII text on some Windows installs. Always specify the encoding when reading text that may be non-ASCII. (Ruff's encoding rule backstops this; review catches what the rule misses.)
- **Cross-thread database connections** — a connection handed to another thread (for instance, work pushed off the event loop) must be opened to permit it, or it raises at use. Pair the change with a regression test that exercises the cross-thread path.

## Async

- **Structured concurrency** — prefer the structured task-group and timeout context managers over the older gather-and-wait forms; they give deterministic cancellation and exception grouping.
- **Blocking work off the event loop** — any synchronous operation long enough to stall the loop (model loading, heavy parsing, CPU-bound work) is dispatched to a worker thread, especially in a long-lived server that must stay responsive to concurrent requests.

## Modeling and errors

- **Immutability by default** — internal value objects and API models are frozen rather than mutable bags.
- **Explicit results for domain-heavy flows** — a domain-heavy service may model success and failure explicitly (an explicit result type) rather than control-flow exceptions, mirroring the result-modeling default; infrastructure failures stay exceptions.

## Testing

- **Tests for non-trivial package logic** — a package carrying real logic, a CLI boundary, or regression-prone parsing has tests for it; "covered by a consumer" is not a default. Framework and placement remain repository-specific.
