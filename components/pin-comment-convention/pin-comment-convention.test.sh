#!/usr/bin/env bash
# Tests the pin-comment-convention component: the policy library flags every
# non-conforming trailing comment on a ci-workflows SHA pin and passes the
# clean good fixture, while staying silent on pins to other actions.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

# shellcheck source=components/pin-comment-convention/pin-comment-patterns.sh
source components/pin-comment-convention/pin-comment-patterns.sh

good="$(<components/pin-comment-convention/fixtures/good/workflow.yml)"
pcc::scan_text "$good" >/dev/null
assert_exit 'good fixture has no violations' 0 "$?"

bad="$(<components/pin-comment-convention/fixtures/bad/workflow.yml)"
out="$(pcc::scan_text "$bad")"
assert_exit 'bad fixture is flagged' 1 "$?"
assert_row_count 'every non-conforming pin is flagged' "$out" 4 '^[0-9]+:'
assert_contains 'flags a pin with no comment' "$out" 'missing-comment'
assert_contains 'flags a prose comment' "$out" 'invalid-form:# latest stable'
assert_contains 'flags a partial-semver comment' "$out" 'invalid-form:# v1.2'
assert_contains 'flags a reversed fallback (date before short-sha)' "$out" 'invalid-form:# 2026-07-18 90f1c54'

# Primary form: full SemVer tag.
pcc::scan_text 'uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46 # v0.7.0' >/dev/null
assert_exit 'full semver tag form is clean' 0 "$?"

# Fallback form: short SHA + ISO date, with and without a trailing note.
pcc::scan_text 'uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 90f1c54 2026-07-18' >/dev/null
assert_exit 'short-sha + date fallback form is clean' 0 "$?"
pcc::scan_text 'uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 90f1c54 2026-07-18 pre-tag pin' >/dev/null
assert_exit 'short-sha + date + note fallback form is clean' 0 "$?"

# Non-ci-workflows references are out of policy scope regardless of comment.
pcc::scan_text 'uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0' >/dev/null
assert_exit 'a pin to an unrelated action is not scanned' 0 "$?"

# A composite-action reference (no .yml suffix) is scanned the same as a
# reusable workflow reference.
pcc::scan_text 'uses: melodic-software/ci-workflows/.github/actions/comment-hygiene@f2d5e06757201f2fce187096a2c6fa805836c3d2' >/dev/null
assert_exit 'a composite-action pin with no comment is flagged' 1 "$?"

# A quoted YAML scalar `uses:` value is scanned the same as a plain one — a
# single- or double-quoted ref must not silently escape the check.
pcc::scan_text "uses: 'melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46' # v0.7.0" >/dev/null
assert_exit 'single-quoted ref with a valid comment is clean' 0 "$?"
pcc::scan_text "uses: 'melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46' # latest stable" >/dev/null
assert_exit 'single-quoted ref with an invalid comment is flagged' 1 "$?"
pcc::scan_text 'uses: "melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f" # 90f1c54 2026-07-18' >/dev/null
assert_exit 'double-quoted ref with a valid comment is clean' 0 "$?"
pcc::scan_text 'uses: "melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f"' >/dev/null
assert_exit 'double-quoted ref with no comment is flagged' 1 "$?"

# The fallback short-SHA is lowercase hex only; an uppercase short-SHA does
# not read as the documented fallback shape and is flagged as invalid-form.
pcc::scan_text 'uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 90F1C54 2026-07-18' >/dev/null
assert_exit 'uppercase short-sha in fallback is invalid-form' 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
