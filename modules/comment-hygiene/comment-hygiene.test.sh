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

# Bad fixture: flagged, with markers and every widened tracker-reference kind.
bad="$(cat fixtures/comment-hygiene/bad/violations.sh)"
out="$(chp::scan_text "$bad")"
assert_exit 'bad fixture is flagged' 1 "$?"
assert_contains 'reports a warning marker' "$out" 'warning-marker'
assert_contains 'reports a tracker reference' "$out" 'tracker-ref'
assert_contains 'flags cc-issue' "$out" 'cc-issue'
assert_contains 'flags a closing keyword with a number' "$out" 'closing-keyword'
assert_contains 'flags owner/repo#N' "$out" 'repo-issue'
assert_contains 'flags GH-N' "$out" 'gh-reference'

# Comment styles beyond // and #: block, block-continuation, and HTML comments.
block="$(printf '%s\n' '/* fixes #5 */' ' * TODO: later' '<!-- tracked: #3 -->')"
chp::scan_text "$block" >/dev/null
assert_exit 'block / continuation / html comments are scanned' 1 "$?"

# False-positive guards: technical tokens that share the LETTERS-NUMBER shape
# and closing keywords without a # must stay clean.
clean_inline="$(printf '%s\n' \
  '// uses UTF-8 and SHA-256 per ISO-8601' \
  '// RFC-2119 keywords; the P-256 curve' \
  '// mitigates CVE-2025-30066' \
  '// fix 3 bugs and close the file handle without issue')"
chp::scan_text "$clean_inline" >/dev/null
assert_exit 'technical tokens and unanchored keywords are not flagged' 0 "$?"

[[ $FAILED -eq 0 ]] || exit 1
