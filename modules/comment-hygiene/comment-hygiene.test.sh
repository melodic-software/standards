#!/usr/bin/env bash
# Tests the comment-hygiene module: the policy library flags the bad fixture's
# markers and tracker references, and passes the clean good fixture.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1

# shellcheck source=modules/comment-hygiene/comment-hygiene-patterns.sh
source modules/comment-hygiene/comment-hygiene-patterns.sh

# Good fixture: ordinary comments only — no violations.
good="$(cat fixtures/comment-hygiene/good/clean.sh)"
chp::scan_text "$good" >/dev/null
assert_exit 'good fixture has no violations' 0 "$?"

# Bad fixture: flagged, with both a warning marker and a tracker reference.
bad="$(cat fixtures/comment-hygiene/bad/violations.sh)"
out="$(chp::scan_text "$bad")"
assert_exit 'bad fixture is flagged' 1 "$?"
assert_contains 'reports a warning marker' "$out" 'warning-marker'
assert_contains 'reports a tracker reference' "$out" 'tracker-ref'

[[ $FAILED -eq 0 ]] || exit 1
