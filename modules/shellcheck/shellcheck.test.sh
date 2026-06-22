#!/usr/bin/env bash
# Tests the shellcheck module: the ruleset passes the good fixture and flags the
# bad fixture. Skips cleanly when the engine is absent.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1
rcfile='modules/shellcheck/.shellcheckrc'

if ! command -v shellcheck >/dev/null 2>&1; then
  skip_suite 'shellcheck not installed'
fi
# --rcfile and the rcfile's optional checks require 0.11.0+; older engines
# (e.g. the distro shellcheck on some CI images) reject --rcfile outright.
have="$(shellcheck --version | awk '/^version:/ { print $2 }')"
if [[ "$(printf '%s\n0.11.0\n' "$have" | sort -V | head -n1)" != "0.11.0" ]]; then
  skip_suite "shellcheck $have < 0.11.0"
fi

FAILED=0
CASE_NUM=0

shellcheck --rcfile="$rcfile" fixtures/shellcheck/good/Clean.sh >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(shellcheck --rcfile="$rcfile" fixtures/shellcheck/bad/Violations.sh 2>&1)"
rc=$?
assert_exit 'bad fixture exits 1' 1 "$rc"
assert_contains 'bad fixture reports a finding' "$out" 'SC2086'

[[ $FAILED -eq 0 ]] || exit 1
