# Engineering philosophy

The default posture for any code in a consuming repo: write like a senior engineer — industry-standard practice, biased toward simplicity, correctness, and maintainability. These are reasoning-only principles; no tool decides them for you. They set the priors the rest of this catalog refines.

## Correctness and resilience

- **Explicit over implicit.** Naming, behavior, and structure should be self-evident without external context. Names describe contents; parameters are named, not positional; fallback behavior is stated where it lives. State prohibitions directly rather than implying them.
- **Fail fast.** Surface invalid state at the entry point rather than deferring, swallowing, or hiding it. A failure that travels far from its cause is expensive to diagnose.
- **Timeout-first / resilient by default.** Every outbound call carries a timeout from its first implementation. Add retry with backoff and circuit breakers where a dependency can be slow or flaky. Resilience includes elapsed time: growth stays bounded, expiring material rotates automatically, and a restart recovers cleanly — the diff-time bars live in `../review/timebombs.md`.
- **Idempotency by default.** Anything that can be retried — command handlers, message consumers, endpoints behind a retrying client — must be safe to run more than once with the same effect as once. Use an explicit idempotency key where the operation is not naturally idempotent.
- **Cross-platform by default.** Code, scripts, and tracked artifacts behave identically on Windows, macOS, and Linux unless a concern is inherently OS-specific — in which case the OS dependency is declared, not assumed.

## Simplicity and design

- **Simpler code over more code.** The smallest form that trades nothing away is the default; lines are liability. The constraints and named failure modes are owned by `simpler-code.md`.
- **Do it right, not cheap.** Choose the best long-term design over an expedient hack. If the "right" approach would demand unwarranted complexity, find a different right design — never ship a documented wrong one.
- **One mechanism per concern.** Each operational concern has one authoritative owner. When a better mechanism exists, migrate to it fully rather than layering a second. Defense-in-depth is reserved for security boundaries.
- **Strongly-typed identities.** Model domain identities and constrained concepts as dedicated types, not bare primitives. Infrastructure, correlation, and configuration values stay primitive.

## Judgment and process

- **Reversibility-weighted rigor.** For easily reversible decisions, bias to action and revert if wrong. For hard-to-reverse decisions, widen options first, prefer the reversible path, and record the rationale in a decision record.
- **Research before deciding.** A change that feels "too simple to research" is a signal to verify, not to skip. Exhaust the obvious approaches before declaring a problem intractable.
- **Stress-test before presenting.** Attack your own design — edge cases, concurrency, state leaks — and reject proposals that duplicate a source of truth, over-build, or reinvent an existing mechanism.
- **Cosmetic findings are real work.** Cosmetic, stylistic, and formatting issues are addressed, not waved off as noise. They rank below substantive findings but are never dropped for being minor; fix them in passing where you already touch the code (the Boy Scout Rule).
- **Current state is evidence, never justification.** How code is structured, coupled, or "has always been done" describes what *is*; it does not argue for what *should be*. When a design or boundary's only support is descriptive — incumbency, precedent, existing coupling — re-derive it from first principles and challenge it.

## Cross-cutting design defaults

These show up repeatedly across consuming repos and are elaborated in their own conventions:

- Strict dependency direction and feature/vertical-slice organization — see `architecture-and-design.md`.
- Modeling expected failures as explicit results rather than exceptions — see `architecture-and-design.md`.
- Naming by responsibility — see `naming.md`.
- A single source of truth for every fact, cited rather than copied — see `reference-dont-duplicate.md`.
