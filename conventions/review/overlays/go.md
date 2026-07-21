# Go review overlay

Stack-specific review bars for Go. The mechanically enforced posture is owned
by the [`go-analysis`](../../../components/go-analysis/) component; this overlay
covers reasoning-tier judgments the official toolchain and the exact
golangci-lint analyzer set cannot fully decide. Severity labels are defined in
[../README.md](../README.md).

## Cancellation and concurrency

- **Context lifetime** — request-scoped work accepts `context.Context` as its
  first argument and propagates it; do not store it in a struct, pass `nil`, or
  replace a caller's context with `context.Background`. The rare compatibility
  exception must document the lifetime explicitly. The [`context` package][1]
  and Go team's [contexts-and-structs guidance][2] define this contract.
- **Goroutine ownership** — every started goroutine has an explicit completion
  or cancellation path that its owner can trigger and, when correctness depends
  on completion, await. An early-returning receiver must not leave an upstream
  sender blocked; follow the Go team's [pipeline cancellation guidance][3].
- **Channel ownership** — the sending owner closes a channel after its final send;
  receivers do not close shared inbound channels. Document who owns shutdown
  when multiple producers feed one channel.

## Errors and APIs

- **Error-chain contract** — wrapping with `%w` deliberately exposes the wrapped
  error as API; callers inspect chains with `errors.Is` or `errors.As`, not string
  matching or direct equality. Review whether exposing an underlying error would
  couple callers to an implementation detail. The standard [`errors` package][4]
  owns traversal behavior.
- **Typed-nil interfaces** — an error or other interface return must be genuinely
  `nil` on success, not an interface containing a nil pointer. Add a regression
  test at the interface boundary when a pointer-backed implementation can take
  the nil path.
- **Receiver semantics** — methods on one type use a consistent pointer-or-value
  receiver model. Mutation, synchronization fields, or identity require pointer
  semantics; a value receiver must represent an intentionally copyable value.
  The Go team's [review guidance][5] supplies the decision factors.

## Date and time

The shared [date-time criteria](../date-time.md) own the semantic and storage
contract. This overlay owns the Go representation.

- **Use `time.Time` and `time.Duration` by contract** — use `time.Time` for a
  resolved timestamp and `time.Duration` for a fixed elapsed interval. A
  floating date-only value uses an explicit domain type with no zone attachment;
  a future local schedule uses explicit local fields plus its IANA zone ID.
  Do not disguise either as a UTC instant. Normalize resolved instants to UTC at
  the persistence boundary, and compare them with `Time.Equal`, not `==`; `==`
  also compares location and monotonic-clock state. See the [`time` package][8].
- **Parse in an explicit location** — `time.Parse` interprets input without zone
  information as UTC; use `time.ParseInLocation` when the contract supplies a
  named location. Do not rely on `time.Local` or an abbreviation. Resolve an
  ambiguous or nonexistent local time before `time.Date`: its documented choice
  around an offset transition is not guaranteed. See [`ParseInLocation`][9] and
  [`time.Date`][10].
- **Make zone data a deployment dependency** — `time.LoadLocation` searches the
  configured path, the operating system, the Go installation, then embedded
  data. A final artifact that cannot rely on those sources imports
  `time/tzdata` or builds with `-tags timetzdata` (available since Go 1.15), and
  is rebuilt when that data changes. Test a required named zone in the final
  artifact; embedding adds binary size and belongs to the main program, not a
  library. See [`time.LoadLocation`][11] and [`time/tzdata`][12].
- **Keep monotonic measurements in process** — values from `time.Now` carry a
  monotonic reading, so use `Sub`, `Since`, or `Until` while both endpoints
  retain it. Serialization and parsing strip that reading and fall back to wall
  time; sleep behavior also varies by system, so persisted or suspend-inclusive
  deadlines need a different, explicit contract. See the package's [monotonic
  clock guidance][13].

## Resources and tests

- **Cleanup on every path** — close bodies, files, timers, tickers, and other
  acquired resources on all returns, and check cleanup errors when durability or
  protocol completion depends on them. Do not defer per-iteration cleanup in an
  unbounded loop; bound the lifetime with a helper or explicit close.
- **Concurrent behavior under load** — changes to goroutines, channels, locks,
  caches, or shared state include tests that exercise cancellation and failure,
  not only the happy path. The CI race lane observes only executed paths, as the
  official [race-detector guidance][6] cautions.
- **Fuzz regression lifecycle** — a discovered failure is minimized and kept as
  a committed fuzz seed. Pull requests execute committed seeds; active fuzzing
  runs for 30 seconds per target in the weekly and manually dispatched lane.
  Treat a timeout, crash, or infrastructure failure as a failed run, not an
  absence of findings. The Go toolchain's [fuzzing guidance][7] defines seed and
  failure-corpus behavior.
- **Analyzer suppressions** — a suppression is line-scoped, names every
  suppressed linter, and explains why the finding is intentionally accepted.
  Broad file/package exclusions and unexplained `//nolint` directives are
  Important review findings even when an editor has not run the analyzer.

[1]: https://pkg.go.dev/context
[2]: https://go.dev/blog/context-and-structs
[3]: https://go.dev/blog/pipelines
[4]: https://pkg.go.dev/errors
[5]: https://go.dev/wiki/CodeReviewComments#receiver-type
[6]: https://go.dev/doc/articles/race_detector
[7]: https://go.dev/doc/security/fuzz/
[8]: https://pkg.go.dev/time#Time
[9]: https://pkg.go.dev/time#ParseInLocation
[10]: https://pkg.go.dev/time#Date
[11]: https://pkg.go.dev/time#LoadLocation
[12]: https://pkg.go.dev/time/tzdata
[13]: https://pkg.go.dev/time#hdr-Monotonic_Clocks
