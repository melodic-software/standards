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

## Date and time

The shared [date-time criteria](../date-time.md) own the semantic and storage
contract. This overlay owns the Python representation.

- **Aware `datetime` values represent instants** — use `date` for a date-only
  value, `time` for a time of day, `timedelta` for a duration, and an aware
  `datetime` for an instant. Create UTC with `datetime.now(timezone.utc)` (or
  `datetime.now(UTC)` on Python 3.11 and later), not `datetime.utcnow()`:
  `utcnow()` returns a naive value and is deprecated in Python 3.12. Never
  silently attach UTC to an unvalidated naive value. See the [`datetime`
  documentation][1].
- **Use `zoneinfo` with a declared data source** — on Python 3.9 and later,
  resolve IANA IDs with `ZoneInfo` and make the `fold` policy explicit for an
  ambiguous local input. The module is unavailable on WASI and does not bundle
  zone data; cross-platform projects that require named zones declare the
  first-party `tzdata` dependency instead of assuming the host supplies it.
  See the [`zoneinfo` documentation][2].
- **Measure with a monotonic clock** — use `time.monotonic()` or
  `time.monotonic_ns()` for elapsed time and in-process deadlines, not
  `datetime.now()` or `time.time()`. The reference point is deliberately
  undefined, so only differences within the process are meaningful. See the
  [`time` documentation][3].

## Testing

- **Tests for non-trivial package logic** — a package carrying real logic, a CLI boundary, or regression-prone parsing has tests for it; "covered by a consumer" is not a default. Framework and placement remain repository-specific.

[1]: https://docs.python.org/3/library/datetime.html
[2]: https://docs.python.org/3/library/zoneinfo.html
[3]: https://docs.python.org/3/library/time.html#time.monotonic
