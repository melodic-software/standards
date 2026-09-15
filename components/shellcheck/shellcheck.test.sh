#!/usr/bin/env bash
# Tests the ShellCheck component: the root-canonical ruleset passes the good fixture and flags the
# bad fixture. Skips cleanly when the engine is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
rcfile='.shellcheckrc'

if ! command -v shellcheck >/dev/null 2>&1; then
  skip_suite 'shellcheck not installed'
fi
# 0.11.0 is the rcfile's floor (useless-use-of-cat became an optional check
# there); engines below 0.10.0 lack --rcfile entirely.
require_min_version shellcheck "$(shellcheck --version | awk '/^version:/ { print $2 }')" 0.11.0

shellcheck --rcfile="$rcfile" components/shellcheck/fixtures/good/Clean.sh >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(shellcheck --rcfile="$rcfile" components/shellcheck/fixtures/bad/Violations.sh 2>&1)"
rc=$?
assert_exit 'bad fixture exits 1' 1 "$rc"
assert_contains 'bad fixture reports a default finding' "$out" 'SC2086'
# SC2292 (require-double-brackets) is an rcfile-only optional check, so asserting
# it proves the .shellcheckrc was actually loaded — not just that ShellCheck ran.
assert_contains 'bad fixture reports an rcfile-enabled finding' "$out" 'SC2292'

[[ $FAILED -eq 0 ]] || exit 1
