# TypeScript review overlay

Stack-specific review bars for TypeScript and JavaScript. The mechanically-enforced posture — linting, formatting, import sorting, and type-checking — is owned by `modules/typescript/` (Biome and the compiler); this overlay covers only the reasoning-tier judgments those tools do not make. Severity labels are defined in [../README.md](../README.md).

## Correctness traps

- **Long-lived stdio servers and broken pipes** — when a parent process exits it closes the inherited output streams; a later write raises a broken-pipe error that, unhandled, can become a self-sustaining error storm pinning a CPU core. A long-lived server attaches an error listener that swallows the broken-pipe family at startup.
- **Floating and misused promises** — an unhandled promise silently swallows async failures, and a promise used where a synchronous value is expected misbehaves. The type-aware lint rules in `modules/typescript/` catch these; review covers any path the type information cannot reach.
- **Index-access safety** — array and index-signature access can return undefined under the strict compiler flags; narrow or guard rather than asserting non-null to silence it.

## Boundaries and validation

- **Validate at the boundary** — external input (tool parameters, API responses, configuration) is parsed and validated with a runtime schema at the entry point, not trusted from a type annotation alone.
- **No stray stdout in a transport server** — a server using standard streams as its transport must not write logs to stdout; diagnostics go to stderr. (Biome's no-console rule enforces this where configured.)

## Testing

- **Tests for package logic** — a logic change in a package has a co-located test or an updated package test. A protocol or transport boundary (parameter validation, lifecycle, framing) gets integration coverage when its behavior changes. The framework and placement follow `modules/typescript/`.
