#!/usr/bin/env bash
# Tests the lychee component's offline checker: the good fixture's local links and
# anchors resolve on disk, and the bad fixture's broken references are flagged.
# Skips cleanly when the engine is absent or too old.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='lychee.toml'

if ! command -v lychee >/dev/null 2>&1; then
  skip_suite 'lychee not installed'
fi
# The include_fragments = "full" config key requires a recent lychee.
require_min_version lychee "$(lychee --version | awk '{ print $2 }')" 0.24.2

lychee --offline --config "$config" \
  components/lychee/fixtures/good/Clean.md components/lychee/fixtures/good/Target.md >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(lychee --offline --config "$config" components/lychee/fixtures/bad/Violations.md 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture flags the missing fragment' "$out" 'Cannot find fragment'
assert_contains 'bad fixture flags the missing file' "$out" 'does-not-exist.md'

[[ $FAILED -eq 0 ]] || exit 1
