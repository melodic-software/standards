#!/usr/bin/env bash
# Tests the pin-comment-convention component: the policy library flags every
# non-conforming trailing comment on a ci-workflows SHA pin and passes the
# clean good fixture, while staying silent on pins to other actions and on
# uses:-shaped text that is not actually a uses: node.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

command -v yq >/dev/null 2>&1 || skip_suite 'Mike Farah yq v4 is not installed'
[[ "$(yq --version 2>/dev/null)" =~ version[[:space:]]+v?4\. ]] ||
  skip_suite 'Mike Farah yq v4 is required'

# shellcheck source=components/pin-comment-convention/pin-comment-patterns.sh
source components/pin-comment-convention/pin-comment-patterns.sh

good="$(<components/pin-comment-convention/fixtures/good/workflow.yml)"
pcc::scan_text "$good" >/dev/null
assert_exit 'good fixture has no violations' 0 "$?"

bad="$(<components/pin-comment-convention/fixtures/bad/workflow.yml)"
out="$(pcc::scan_text "$bad")"
assert_exit 'bad fixture is flagged' 1 "$?"
assert_row_count 'every non-conforming pin is flagged' "$out" 6 '^[0-9]+:'
assert_contains 'flags a pin with no comment' "$out" 'missing-comment'
assert_contains 'flags a prose comment' "$out" 'invalid-form:# latest stable'
assert_contains 'flags a partial-semver comment' "$out" 'invalid-form:# v1.2'
assert_contains 'flags a reversed fallback (date before short-sha)' "$out" 'invalid-form:# 2026-07-18 90f1c54'
assert_row_count 'an anchored pin and its alias are each flagged' "$out" 2 'invalid-form:# not-a-form'

# Every `pcc::scan_text` case below wraps its `uses:` line in the position
# GitHub Actions actually executes it from — `jobs.<id>.uses` — rather than a
# bare root-level `uses:` scalar, which is not a real workflow shape and
# (since the scan is scoped to jobs.*.uses / jobs.*.steps[*].uses, not an
# untargeted document walk) would never be scanned in the first place.

# Primary form: full SemVer tag.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46 # v0.7.0' >/dev/null
assert_exit 'full semver tag form is clean' 0 "$?"

# Fallback form: short SHA + ISO date, with and without a trailing note.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 90f1c54 2026-07-18' >/dev/null
assert_exit 'short-sha + date fallback form is clean' 0 "$?"
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 90f1c54 2026-07-18 pre-tag pin' >/dev/null
assert_exit 'short-sha + date + note fallback form is clean' 0 "$?"

# The fallback form's <short-sha> is provenance-checked against the same
# line's pinned SHA, not just shape-checked: it must be a (case-insensitive)
# prefix of the actual pin. A short-sha that does not prefix the pin is
# flagged even though the comment otherwise has the right shape.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 1234567 2026-07-18' >/dev/null
assert_exit 'a fallback short-sha that does not prefix the pin is flagged' 1 "$?"

# An all-digit short-sha is a real, if less common, git prefix and is
# accepted the same as a mixed digit/letter one — only the prefix
# relationship to the pin matters, not the token's own composition.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@1234567abcdef1234567890abcdef1234567890 # 1234567 2026-07-18' >/dev/null
assert_exit 'an all-digit short-sha that genuinely prefixes the pin is clean' 0 "$?"

# A short-sha under 7 characters never reaches the prefix check: it fails
# the documented shape first, the same way it always has.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 90f1c 2026-07-18' >/dev/null
assert_exit 'a short-sha under 7 characters is invalid-form' 1 "$?"

# Non-ci-workflows references are out of policy scope regardless of comment.
pcc::scan_text 'jobs:
  a:
    uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0' >/dev/null
assert_exit 'a pin to an unrelated action is not scanned' 0 "$?"

# A composite-action reference (no .yml suffix) is scanned the same as a
# reusable workflow reference.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/actions/comment-hygiene@f2d5e06757201f2fce187096a2c6fa805836c3d2' >/dev/null
assert_exit 'a composite-action pin with no comment is flagged' 1 "$?"

# A quoted YAML scalar `uses:` value is scanned the same as a plain one — a
# single- or double-quoted ref must not silently escape the check.
pcc::scan_text "jobs:
  a:
    uses: 'melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46' # v0.7.0" >/dev/null
assert_exit 'single-quoted ref with a valid comment is clean' 0 "$?"
pcc::scan_text "jobs:
  a:
    uses: 'melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46' # latest stable" >/dev/null
assert_exit 'single-quoted ref with an invalid comment is flagged' 1 "$?"
pcc::scan_text 'jobs:
  a:
    uses: "melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f" # 90f1c54 2026-07-18' >/dev/null
assert_exit 'double-quoted ref with a valid comment is clean' 0 "$?"
pcc::scan_text 'jobs:
  a:
    uses: "melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f"' >/dev/null
assert_exit 'double-quoted ref with no comment is flagged' 1 "$?"

# A YAML document without a jobs: key at all (the driver's file glob can
# plausibly reach a non-workflow file) is clean, not a parse failure — an
# absent or malformed jobs: value yields no candidates rather than erroring.
pcc::scan_text 'name: not-a-workflow
foo: bar' >/dev/null
assert_exit 'a document with no jobs: key is clean, not an error' 0 "$?"

# The fallback short-SHA is lowercase hex only; an uppercase short-SHA does
# not read as the documented fallback shape and is flagged as invalid-form.
# This is the fallback comment's OWN short-SHA (an authored documentation
# string, fixed lowercase by policy) — contrast with the PINNED SHA case
# below, a resolved git object ID that is genuinely case-insensitive.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@90f1c54935203fa31b5b3d1f41531228be2c2b7f # 90F1C54 2026-07-18' >/dev/null
assert_exit 'uppercase short-sha in fallback is invalid-form' 1 "$?"

# The PINNED 40-character SHA (the git object ID after @) is matched
# case-insensitively: it is the same commit regardless of hex letter case,
# matching how the runner-policy provenance scanner already treats it. An
# uppercase-hex pin is scanned the same as a lowercase one — clean with a
# valid comment, flagged with an invalid one — not silently skipped.
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@31A5B76C4A0B663023DC1C944E2BCFC01D6F6C46 # v0.7.0' >/dev/null
assert_exit 'uppercase pinned SHA with a valid comment is clean' 0 "$?"
pcc::scan_text 'jobs:
  a:
    uses: melodic-software/ci-workflows/.github/workflows/x.yml@31A5B76C4A0B663023DC1C944E2BCFC01D6F6C46 # latest stable' >/dev/null
assert_exit 'uppercase pinned SHA with an invalid comment is flagged' 1 "$?"

# A `strategy.matrix.include` entry (or any other data field) that happens to
# be named "uses" is not an executable position and must never be flagged —
# the scan is scoped to jobs.*.uses and jobs.*.steps[*].uses, not every
# same-named key anywhere in the document. `${{ matrix.uses }}` below is
# literal GitHub Actions expression text, not a bash expansion, so the
# single-quoted string is intentional.
# shellcheck disable=SC2016
matrix_decoy='jobs:
  a:
    strategy:
      matrix:
        include:
          - uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46
    steps:
      - run: echo "${{ matrix.uses }}"'
pcc::scan_text "$matrix_decoy" >/dev/null
assert_exit 'a strategy.matrix.include entry named uses is not scanned' 0 "$?"

# A step's `with:` input that happens to be named "uses" is not the step's
# own uses: key either, regardless of what the caller's own uses: is.
with_input_decoy='jobs:
  a:
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0
        with:
          uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46'
pcc::scan_text "$with_input_decoy" >/dev/null
assert_exit 'a with: input named uses is not scanned' 0 "$?"

# A whole aliased step — the anchor covers the entire step object including
# its trailing comment — resolves to the same content at both occurrences,
# matching the fleet's established anchor/alias precedent
# (ci-workflows#205) rather than a bare scalar-value alias (below).
anchored_valid='jobs:
  a:
    steps:
      - &s
        uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46 # v0.7.0
  b:
    steps:
      - *s'
pcc::scan_text "$anchored_valid" >/dev/null
assert_exit 'a whole-step anchor/alias with a valid comment is clean' 0 "$?"

anchored_invalid='jobs:
  a:
    steps:
      - &s
        uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46 # latest stable
  b:
    steps:
      - *s'
anchored_out="$(pcc::scan_text "$anchored_invalid")"
assert_exit 'a whole-step anchor/alias with an invalid comment is flagged' 1 "$?"
assert_row_count 'both the anchor and its alias are flagged' "$anchored_out" 2 '^[0-9]+:'

# A bare scalar-value alias on `uses:` itself shares only the string value,
# not the anchor line's trailing comment — the alias's own line still needs
# its own comment to satisfy the policy; the comment does not silently
# propagate along with the resolved value.
scalar_alias='jobs:
  a:
    uses: &v melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46 # v0.7.0
  b:
    uses: *v # v0.7.0'
pcc::scan_text "$scalar_alias" >/dev/null
assert_exit 'a scalar-value alias with its own matching comment is clean' 0 "$?"

scalar_alias_no_comment='jobs:
  a:
    uses: &v melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46 # v0.7.0
  b:
    uses: *v'
scalar_alias_out="$(pcc::scan_text "$scalar_alias_no_comment")"
assert_exit 'a scalar-value alias with no comment of its own is flagged' 1 "$?"
assert_contains 'the alias line is reported missing-comment, not silently inherited' "$scalar_alias_out" 'missing-comment'

# uses:-shaped text inside a run: block body is not a uses: node and must
# never be flagged, regardless of its own comment (or lack of one).
run_block_decoy='jobs:
  a:
    steps:
      - run: |
          echo "uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46"'
pcc::scan_text "$run_block_decoy" >/dev/null
assert_exit 'uses:-shaped text inside a run: block is not scanned' 0 "$?"

# uses:-shaped text inside a YAML comment is not a uses: node either.
yaml_comment_decoy='jobs:
  a:
    steps:
      - run: echo hi
      # uses: melodic-software/ci-workflows/.github/workflows/x.yml@31a5b76c4a0b663023dc1c944e2bcfc01d6f6c46'
pcc::scan_text "$yaml_comment_decoy" >/dev/null
assert_exit 'uses:-shaped text inside a YAML comment is not scanned' 0 "$?"

[[ $FAILED -eq 0 ]] || exit 1
