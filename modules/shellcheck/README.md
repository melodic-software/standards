# shellcheck module

Shell-script static analysis via [ShellCheck](https://www.shellcheck.net/).

## Contents

- `.shellcheckrc` — the ruleset: bash dialect, source resolution at lint time,
  and a selectively enabled set of optional checks (not `enable=all`, which the
  ShellCheck wiki warns against). Every enabled and notably-omitted check is
  justified inline.

ShellCheck is a single binary with no runner script; the CI lane that installs a
pinned binary and runs it lives in the `ci-workflows` repo (execution).

## Engine

Requires [ShellCheck](https://github.com/koalaman/shellcheck) 0.11.0+.

## Adopt in a repo

1. Copy `.shellcheckrc` into the consuming repo — canonical home
   `modules/shellcheck/`. ShellCheck also auto-discovers a `.shellcheckrc` from a
   script's directory upward, so a root-level copy works for editors and hooks.
2. Reference the `ci-workflows` shellcheck action from CI, pointing its `rcfile`
   input at the copied ruleset.

## Test

`fixtures/shellcheck/{good,bad}` exercise the ruleset; `shellcheck.test.sh`
asserts the good fixture is clean and the bad fixture is flagged, via the shell
harness (`harness/shell/run-tests.sh`). The `bad` fixture is intentionally
non-conforming and is excluded from the repo's own self-lint.
