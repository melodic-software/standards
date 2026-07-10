#!/usr/bin/env bash
# Tests the comment-hygiene component: the policy library flags the bad fixture's
# markers and tracker references, and passes the clean good fixture.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

# shellcheck source=components/comment-hygiene/comment-hygiene-patterns.sh
source components/comment-hygiene/comment-hygiene-patterns.sh

# Good fixture: ordinary comments only — no violations.
good="$(<components/comment-hygiene/fixtures/good/clean.sh)"
chp::scan_text "$good" >/dev/null
assert_exit 'good fixture has no violations' 0 "$?"

# Bad fixture: flagged, with markers and every widened tracker-reference kind.
bad="$(<components/comment-hygiene/fixtures/bad/violations.sh)"
out="$(chp::scan_text "$bad")"
assert_exit 'bad fixture is flagged' 1 "$?"
assert_contains 'reports a warning marker' "$out" 'warning-marker'
assert_contains 'reports a tracker reference' "$out" 'tracker-ref'
assert_contains 'flags cc-issue' "$out" 'cc-issue'
assert_contains 'flags a closing keyword with a number' "$out" 'closing-keyword'
assert_contains 'flags an issue/tracked reference' "$out" 'issue-reference'
assert_contains 'flags owner/repo#N' "$out" 'repo-issue'
assert_contains 'flags GH-N' "$out" 'gh-reference'
assert_contains 'flags PR #N' "$out" 'pr-reference'

# Comment styles beyond // and #: block, block-continuation, and HTML comments.
block="$(printf '%s\n' '/* fixes #5 */' ' * TODO: later' '<!-- tracked: #3 -->')"
block_out="$(chp::scan_text "$block")"
assert_exit 'block / continuation / html comments are scanned' 1 "$?"
assert_row_count 'every block-style line is flagged' "$block_out" 3 '^[0-9]+:'

# Matching is case-insensitive, and the scan restores the caller's nocasematch
# state instead of leaking it.
chp::scan_text '# todo: later' >/dev/null
assert_exit 'lowercase marker is flagged' 1 "$?"
shopt -q nocasematch
assert_exit 'nocasematch does not leak from the scan' 1 "$?"

# The one case-sensitive rule: XXX flags only in uppercase (lowercase collides
# with the CSS keyword xxx-large and placeholder text).
chp::scan_text '# XXX revisit this' >/dev/null
assert_exit 'uppercase XXX is flagged' 1 "$?"
chp::scan_text '# font-size: xxx-large is fine' >/dev/null
assert_exit 'lowercase xxx is not flagged' 0 "$?"

# False-positive guards: technical tokens that share the LETTERS-NUMBER shape
# and closing keywords without a # must stay clean.
clean_inline="$(printf '%s\n' \
  '// uses UTF-8 and SHA-256 per ISO-8601' \
  '// RFC-2119 keywords; the P-256 curve' \
  '// mitigates CVE-2025-30066' \
  '// fix 3 bugs and close the file handle without issue')"
chp::scan_text "$clean_inline" >/dev/null
assert_exit 'technical tokens and unanchored keywords are not flagged' 0 "$?"

# A dotted or hyphenated host with a numeric fragment must not be misread as
# owner/repo#N. This covers both scheme'd URLs (the host's '.'/'-' satisfied the
# rule's leading boundary) and bare domains at a space/start boundary (the host's
# dot previously slipped into the owner character class).
clean_url="$(printf '%s\n' \
  '// see https://example.com/page#2 for the rationale' \
  '# docs at https://host.example.org/guide#3' \
  '// see https://foo-example.com/page#2 for details' \
  '# ref https://my-cdn.example-host.net/asset#9' \
  '// see foo.com/bar#3 for the rationale' \
  '# example.com/page#2 explains the tradeoff' \
  '// sub.example.com/path#9 has the detail')"
chp::scan_text "$clean_url" >/dev/null
assert_exit 'dotted/hyphenated host (scheme or bare) with #fragment is not a repo-issue ref' 0 "$?"

# A genuine owner/repo#N — including an owner with a hyphen — is still flagged.
flagged_ref="$(printf '%s\n' '// tracked in owner-name/repo#7')"
chp::scan_text "$flagged_ref" >/dev/null
assert_exit 'hyphenated owner/repo#N is still flagged' 1 "$?"

# A GitHub Enterprise Managed User owner login carries an '_SHORTCODE' suffix, so
# an owner containing '_' must still be flagged as a repo-issue ref.
emu_ref="$(printf '%s\n' '// see mona-cat_octo/scratch#12')"
chp::scan_text "$emu_ref" >/dev/null
assert_exit 'EMU owner with underscore in owner/repo#N is still flagged' 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
