# Testing review criteria

Diff-time checks for test coverage, quality, and the honesty of a verification claim. Severity labels are defined in [README.md](README.md). Stack-specific placement, frameworks, and the test pyramid live in the overlays; the language-agnostic criteria are below.

## Coverage and level

- **New behavioral code missing tests**: business logic, validation, error handling, branching, and data transformation have tests that catch regressions. Ask: "if someone changes this, what test breaks?" Distinguish genuinely new behavior from a refactor or a config-only change with no runtime effect. **Critical.**
- **Test-level mismatch**: a unit test on code whose failures only surface across an infrastructure or UI boundary, or an end-to-end test on trivial pure logic. Ask: "what breaks in production that this test would not catch?" **Important.**
- **Refactor without characterization tests**: a change that restructures existing production code (extract, split, move responsibilities) with no automated test locking the current behavior of the paths it touches, added before the code moved. An approval or snapshot test suits stable output; a unit test suits logic that can be isolated. **Important**; **Suggestion** when pointing out an opportunity on stable code.
- **Bug fix without a regression test**: a change that fixes a reported defect carries at least one automated test, at the right level, that fails on the pre-fix behavior and passes after. Carve-outs: docs-only, comment-only, pure formatting, config with no code-path change. An exception (production-only hardware, a not-yet-captured race, an external system absent from CI) is justified explicitly in the change: "no time" is not a justification. **Important**, escalating to **Critical** when the defect class regressed before or the fix touches a high-risk path with no automated proof.

## Quality over volume

- **Test quality**: evaluate against the four properties of a good test: protection against regressions, resistance to refactoring, fast feedback, and maintainability ([Khorikov](https://www.manning.com/books/unit-testing)). A test that breaks on every refactor without catching a real regression is a liability.
- **No coverage percentage as a definition of done**: line and branch coverage are diagnostic, not a target. Flag a change or plan that optimizes for a coverage number without adding protective tests. **Suggestion.**
- **Test theater**: a test with no meaningful assertion, an always-green smoke test, constructor-only coverage, or an assertion that validates setup rather than behavior. Over-mocking on a high-risk path with no real-behavior assertion belongs here too. **Important.**
- **Resetting process-global state the test never changes**: a test that resets a static or process-wide singleton during setup or teardown without mutating it adds a race under parallel test execution and protects nothing. Reset only state the test changes, and isolate tests that must change it. **Important.**
- **Synthetic fixtures for external shapes**: a hand-written fixture standing in for an external system's payload, with no verified real sample behind it and no opt-in test against the live shape to catch drift. **Suggestion.**
- **Transitive coverage without rationale**: a new module left untested because "its consumers cover it", without meeting a defined bar for skipping its own tests. **Suggestion.**

## Verification honesty

When a change claims to be verified, the claim names which kind of proof supplied it:

- **Structural proof**: a script, schema validator, count, or forbidden-pattern scan proves an artifact's *shape*. It does not prove that the runtime behavior is correct or that a semantic judgment was actually made. Flag a structural pass presented as proof of behavior or quality. **Important.**
- **Behavioral proof**: an automated test with a behavioral assertion, cited by name and outcome, is sufficient for the runtime behavior it covers.
- **Unverified refactor equivalence**: a change that claims unchanged behavior (a helper extraction, a pipeline rewritten with builtins) is checked for every per-caller value the old code set, such as timeouts, retry counts, and wait windows, still reaching the new code, and for the edge inputs the old path handled (multi-line, empty, trailing whitespace). In bash, `read -ra arr <<<"$var"` keeps only the first line where a `tr | awk` pipeline kept them all. **Important** on a correctness path.

A gate that only asserts fields a tool could fill in without doing the work is structural; a behavioral or fidelity gap needs a behavioral test or a documented spot-check, not a green structural pass.
