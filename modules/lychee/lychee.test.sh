#!/usr/bin/env bash
# Tests the lychee module's offline checker: the good fixture's local links and
# anchors resolve on disk, and the bad fixture's broken references are flagged.
# Skips cleanly when the engine is absent or too old.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1
config='modules/lychee/lychee.toml'

if ! command -v lychee >/dev/null 2>&1; then
  skip_suite 'lychee not installed'
fi
# The include_fragments = "full" config key requires a recent lychee.
have="$(lychee --version | awk '{ print $2 }')"
if [[ "$(printf '%s\n0.24.2\n' "$have" | sort -V | head -n1)" != "0.24.2" ]]; then
  skip_suite "lychee $have < 0.24.2"
fi

FAILED=0
CASE_NUM=0

lychee --offline --config "$config" \
  fixtures/lychee/good/Clean.md fixtures/lychee/good/Target.md >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(lychee --offline --config "$config" fixtures/lychee/bad/Violations.md 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture flags the missing fragment' "$out" 'Cannot find fragment'
assert_contains 'bad fixture flags the missing file' "$out" 'does-not-exist.md'

[[ $FAILED -eq 0 ]] || exit 1
