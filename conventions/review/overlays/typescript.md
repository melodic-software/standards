# TypeScript review overlay

Stack-specific review bars for TypeScript and JavaScript. The mechanically enforced posture is owned independently by the [`biome`](../../../components/biome/) and [`tsconfig`](../../../components/tsconfig/) components; this overlay covers only reasoning-tier judgments those tools do not make. Severity labels are defined in [../README.md](../README.md).

## Correctness traps

- **Long-lived stdio servers and broken pipes** — when a parent process exits it closes the inherited output streams; a later write raises a broken-pipe error that, unhandled, can become a self-sustaining error storm pinning a CPU core. A long-lived server attaches an error listener that swallows the broken-pipe family at startup.
- **Floating and misused promises** — an unhandled promise silently swallows async failures, and a promise used where a synchronous value is expected misbehaves. The Biome component's type-aware lint rules catch these; review covers paths the type information cannot reach.
- **Index-access safety** — array and index-signature access can return undefined under the strict compiler flags; narrow or guard rather than asserting non-null to silence it.

## Boundaries and validation

- **Validate at the boundary** — external input (tool parameters, API responses, configuration) is parsed and validated with a runtime schema at the entry point, not trusted from a type annotation alone.
- **No stray stdout in a transport server** — a server using standard streams as its transport must not write logs to stdout; diagnostics go to stderr. (Biome's no-console rule enforces this where configured.)

## Date and time

The shared [date-time criteria](../date-time.md) own the semantic and storage
contract. This overlay owns the JavaScript runtime representation.

- **Gate `Temporal` on the supported runtimes** — use `Temporal.Instant`,
  `Temporal.ZonedDateTime`, and the appropriate `Temporal.Plain*` type when
  their semantics match the contract. `Temporal` is a [Stage 4
  specification][6], but do not assume the global exists: MDN marks it as
  [limited availability and not Baseline][1]. When a target lacks it, add and
  import a project-reviewed polyfill explicitly. The proposal champions'
  [`@js-temporal/polyfill` README][2] says that package is not affiliated with
  TC39, does not install a global `Temporal`, supports Node.js 14 and later, and
  ships ES2020; test the target's runtime and bundle compatibility. Do not use
  legacy `Date` for named-zone or civil-time arithmetic.
- **Parse a declared wire format** — `Date` stores only an epoch-millisecond
  instant, not a time zone. Validate a standards-conforming string with an
  explicit offset before constructing it; reject non-standard or offset-less
  date-time input unless the boundary explicitly defines civil-time semantics.
  The [`Date` documentation][3] records the implementation-defined fallback
  formats and the historic UTC-versus-local parsing inconsistency.
- **Use a monotonic elapsed-time source** — use [`performance.now()`][4] in a
  browser and [`process.hrtime.bigint()`][5] in Node.js instead of subtracting
  `Date.now()` values. Browser behavior while the operating system sleeps still
  varies, so a suspend-inclusive deadline needs target-specific evidence.

## Testing

- **Tests for package logic** — a logic change in a package has a co-located test or an updated package test. A protocol or transport boundary (parameter validation, lifecycle, framing) gets integration coverage when its behavior changes. Framework and placement remain repository-specific.

[1]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Temporal
[2]: https://github.com/js-temporal/temporal-polyfill
[3]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date
[4]: https://developer.mozilla.org/en-US/docs/Web/API/Performance/now
[5]: https://nodejs.org/api/process.html#processhrtimebigint
[6]: https://tc39.es/proposal-temporal/
