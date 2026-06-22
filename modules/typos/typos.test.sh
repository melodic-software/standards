#!/usr/bin/env bash
# Tests the typos module: the spell-checker passes the good fixture and flags
# the bad fixture. The good fixture plants a real misspelling under each of the
# four blessed ignore directives (disable-line, ignore-next-line, the comment
# block, and the HTML-comment block), so a good->exit-0 result conjunctively
# proves every directive form still suppresses. Skips when the engine is absent.
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

# typos exits 0 when clean and 2 when typos are found; any other non-zero is an error.
typos --config "$config" fixtures/typos/good >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(typos --config "$config" fixtures/typos/bad 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture reports a correction' "$out" 'should be'

[[ $FAILED -eq 0 ]] || exit 1
