# Simpler code over more code

When a unit of work can be written cleanly in fewer lines without sacrificing correctness, readability, test coverage, observability, or convention conformance, the smaller form is the default. Lines are liability: more to read, test, debug, refactor, and rename when conventions shift. This is a reasoning-only judgment — "simpler" is about intent and shape, not a character count a tool can enforce.

## Named failure modes to avoid

These are canonical smells, not invented ones:

- **Speculative generality** — hooks, parameters, and special cases for a "we might need this someday" requirement that never materializes. The tell: the only callers of a function or class are its own tests. ([Fowler, *Refactoring*](https://refactoring.guru/smells/speculative-generality))
- **The wrong abstraction** — an abstraction extracted before three concrete uses agree on its shape. Duplication is cheaper than the wrong abstraction; prefer inline duplication until the right shape emerges, then extract. ([Sandi Metz, *The Wrong Abstraction*, 2016](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction))
- **YAGNI violation** — configurability, plugin points, or interfaces for requirements that do not exist yet.

## Constraints — never traded away for line count

Reducing code must not cost any of:

- **Clarity** — no single-letter names, no clever one-liners that hide intent, no suppressed type information.
- **Test coverage** — every behavior still has a test.
- **Error handling at boundaries** — resilience at system edges is not optional.
- **Established conventions** — dependency direction, naming, and layering hold.
- **Observability** — structured logs, traces, and metrics survive the cut.

## Reading the reduction

A reduction is **right** when it removes copy-paste duplication after three uses agree on shape, collapses boilerplate into a helper, replaces a branch ladder with a lookup, uses a built-in framework primitive instead of a hand-rolled one, or deletes speculative parameters and code that only tests reference.

A reduction is **wrong** when it suppresses an analyzer rule, drops a test, disables a lint, hides intent behind cleverness, or forces one abstraction onto two cases that are not actually the same.

When in doubt, prefer the form that makes the next change cheaper.
