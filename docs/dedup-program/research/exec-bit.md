# Research — exec-bit

Cross-cutting repo-hygiene gate: every tracked file whose content starts with a
shebang (`#!` at byte 0) must have git index mode `100755`. Lifted from
`medley`'s always-on `exec-bit` job in `ci-status.yml` (which mirrors its
`.lefthook/pre-commit/exec-bit-check.sh`).

## Why it exists

A shebang script committed as `100644` loses its executable bit on a fresh
clone/checkout, so anything that `exec`s it (CI hooks, bootstrap scripts,
Claude Code cloud hooks) fails with `Permission denied`. The bug is not confined
to `.sh`: shebangs appear in `.py`, `.js`, `.ts`, `.rb`, etc., so detection is
content-based, not extension-based.

## Tool / pinning

**Pure shell + git — no external binary**, so nothing to version-pin or
checksum. Uses only `git grep`, `git ls-files`, `git cat-file`. Confirmed: the
lifted logic shells out to no third-party tool.

## Behavior (lift-and-shift, faithful to medley)

Two-pass, extension-agnostic detection over the git index:

1. `git grep --cached -z -lIE '^#!'` narrows to candidate blobs containing `#!`
   on any line. `-I` skips binaries; `-z` + `-c core.quotePath=false` keep
   non-ASCII / tab / newline filenames intact.
2. For each candidate, read the staged entry (`git ls-files --stage -z`), parse
   `<mode>`, and confirm the blob's first two bytes are literally `#!` (filters
   docs with embedded snippets and `#!` past line 1). A `100644` match fails the
   gate with a `::error file=...::` annotation and the `git update-index
   --chmod=+x` fix command.

Fail-closed: `git grep` exit `0`/`1` are match/no-match; anything else is fatal
and fails the gate rather than passing an incomplete scan (a `blob:none`
checkout can surface real object-read errors).

## Config

**Config-light** — no patterns, no ruleset, no `standards` module. The only
optional input is `paths` (pathspec scope, default `.` = whole repo), an
open-closed string default (D4).

## Build decision

Bundled script (`check-exec-bit.sh`) located via `$GITHUB_ACTION_PATH` (D7)
rather than a long inline `run:` block: the two-pass NUL-safe parsing is
intricate enough that a standalone, separately-testable script reads better than
an embedded heredoc.
