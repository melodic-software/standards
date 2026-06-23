# Research — machine-specific-paths

Cross-cutting repo-hygiene gate: tracked files must not contain machine-specific
absolute paths — a developer's checkout root or user-home directory. Portable
placeholders (`C:\Users\<user>\`, `<repo-root>/`) are allowed. Lifted from
`medley`'s always-on `machine-specific-paths` job in `ci-status.yml`, which
calls `tools/verification/check-machine-specific-paths.sh` and sources the
`tools/shared/path-detection/hardcoded-path-patterns.sh` pattern bodies.

## Why it exists

A committed `C:\Users\<user>\…` or Linux `home/<user>/…` path breaks on every
other machine and leaks the author's environment. The check greps tracked files
for Windows / macOS / Linux user-home and repo-checkout-root shapes.

## Tool / pinning

**Pure shell + git — no external binary** to version-pin or checksum. Uses only
`git grep -E` (POSIX ERE; never `grep -P`, which macOS BSD grep lacks).

## Behavior (lift-and-shift, faithful to medley)

Five OS-path regex bodies are carried verbatim from medley's pattern library
into the action's bundled `check-machine-specific-paths.sh` — see that script
for the exact bodies and the per-OS rationale comments:

- Windows user-home and repo-checkout roots, each matching the separator as
  forward-slash, single-backslash, or JSON-escaped double-backslash, and
  accepting an 8.3 short-name segment (`~<digit>`).
- macOS and Linux user-home roots.

The negative character classes exclude `<`, so angle-bracket placeholders never
match. The macOS/Linux bodies get a `PATH_BOUNDARY` prefix (start-of-line /
whitespace / quote / `file://`) so a substring inside a longer word does not
false-match; the Windows bodies are self-anchored by the `[A-Za-z]:` drive
letter.

Each body is grepped independently; any match prints up to 20 hits and fails the
gate.

### What was NOT lifted (medley-internal)

medley's driver also carried a pre-push positional-arg mode (intersect a push
range with the allowlist) and a long repo-specific exclusion list. The push-
range mode is a medley pre-push concern, not a CI gate, and is dropped. The
repo-specific exclusions become the caller-supplied `exclude` input (D4) instead
of baked-in medley literals.

## Config

**Patterns are the check's definition, not a per-repo ruleset** — every repo
wants to reject a hardcoded `C:\Users\<user>\` root. So the bodies are baked-in
behavior-preserving defaults, **not** a `standards` config module. Per-repo
variation is exposed as two open-closed string inputs (D4):

- `extensions` — pathspec allowlist to scan (default: common code/config/docs
  extensions).
- `exclude` — additional `:(exclude)…` pathspecs appended to the scan.

This is the judgment flagged in the Phase 3 brief ("possibly
machine-specific-paths") resolved toward **config-light**: a future `standards`
module could supply the bodies via an input, but inventing one now would be
config the tool does not need.

> Dogfood note: because the bundled pattern script itself contains the literal
> regex bodies, the ci-workflows dogfood passes
> `exclude: ':(exclude).github/actions/machine-specific-paths/**'` to skip the
> action's own source — exactly how medley self-excludes its pattern files.

## Build decision

Bundled script via `$GITHUB_ACTION_PATH` (D7): the five-body scan with shared
boundary wrapping is too long for a readable inline `run:` block.
