#!/usr/bin/env bash
# Tests the typos module: the spell-checker passes the good fixture (including
# an inline `spellchecker:disable-line` directive) and flags the bad fixture.
# Skips cleanly when the engine is absent.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1
config='modules/typos/_typos.toml'

if ! command -v typos >/dev/null 2>&1; then
  skip_suite 'typos not installed'
fi

FAILED=0
CASE_NUM=0

# typos exits 0 when clean, 2 when typos are found (1 is reserved for errors).
typos --config "$config" fixtures/typos/good >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(typos --config "$config" fixtures/typos/bad 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture reports a correction' "$out" 'should be'

[[ $FAILED -eq 0 ]] || exit 1
