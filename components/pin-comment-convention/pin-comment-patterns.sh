# shellcheck shell=bash
# Pin-comment convention detection policy — dual-form trailing-comment shape
# for `uses:` references to melodic-software/ci-workflows reusable workflows
# and composite actions, pinned by 40-character commit SHA.
#
# Requires Mike Farah's yq v4 on PATH (this repo's established YAML tool —
# see distribution/sync-manifest.sh). `scan-workflow-files.sh` in this
# component owns file enumeration and exit-code mapping for this
# repository's own workflows; a ci-workflows-side driver (deferred — no
# consumer yet) would own full-tree execution for other repositories the
# way the comment-hygiene composite action does today.
#
# Policy: a `uses:` reference to a melodic-software/ci-workflows reusable
# workflow or composite action pinned by 40-character commit SHA must carry a
# trailing comment in exactly one of two forms:
#   1. `# vX.Y.Z`                      — primary form: the release tag the
#                                        pinned SHA corresponds to (full
#                                        SemVer only).
#   2. `# <short-sha> <date>[ <note>]` — fallback form for pinning a commit
#                                        with no corresponding tag;
#                                        <short-sha> is 7-40 lowercase hex
#                                        digits, <date> is ISO 8601
#                                        (YYYY-MM-DD), <note> is optional
#                                        free text.
# No comment, or any other shape (a stray version fragment, prose, the
# fields in the wrong order), is flagged.
#
# This policy checks FORM only. Whether a fallback comment's short SHA
# actually prefixes the pinned 40-character commit is a correctness question
# the runner-policy component's `pin-provenance-drift` check already owns —
# see components/runner-policy/README.md ("pin-provenance-drift"). The two
# checks are complementary: a comment can pass this form check and still fail
# runner-policy's prefix match; a comment that fails this form check never
# reaches runner-policy's prefix match because it does not read as a
# short-SHA-plus-date claim in the first place.
#
# Extraction goes through yq's YAML tree, not a per-line text regex: `explode`
# resolves anchors and aliases to their referenced scalar value before the
# walk, so a plain, quoted, anchored, or aliased `uses:` value is scanned the
# same way. The walk is scoped to the two positions GitHub Actions actually
# executes a `uses:` value from — `jobs.<id>.uses` (a reusable-workflow call)
# and `jobs.<id>.steps[*].uses` (an action call) — not an untargeted `..`
# walk of the whole document, so a same-named "uses" key that is only data
# (a `strategy.matrix.include` entry, a step's `with:` input) is never a
# candidate. Text that merely looks like a `uses:` pin inside a `run:` block
# body or a YAML `#` comment is never a `uses:` node in the parsed tree
# either, so it is never a candidate — a line-oriented regex cannot make
# either distinction reliably.
#
# The pinned 40-character SHA in the `uses:...@<sha>` value is matched
# case-insensitively: it is a git object ID, the same object regardless of
# hex letter case, and the runner-policy provenance scanner already treats
# it that way. The fallback comment's *own* short-SHA stays lowercase-only —
# that is an authored documentation string, not a resolved git object, and
# the two-form policy fixes its canonical spelling deliberately (see
# `pcc::_check_comment`). A release tag (`# vX.Y.Z`) likewise stays
# lowercase-`v`-only: unlike a SHA, a tag's case is part of its identity as
# a git ref, and every tag this repo has ever cut is lowercase `v` — an
# uppercase `V` comment would name a tag that does not exist, not a
# differently-spelled version of one that does.

# pcc::_record_violation <lineno> <kind> <detail>
#
# Emit one "lineno:kind:detail" line and increment the caller's `violations`
# local via bash dynamic scoping; private to pcc::scan_text.
pcc::_record_violation() {
  printf '%s:%s:%s\n' "$1" "$2" "$3"
  violations=$((violations + 1))
}

# pcc::_check_comment <raw_comment>
#
# <raw_comment> is yq's `line_comment` value for a `uses:` scalar node. yq
# strips exactly one leading "# " (hash + one space) when present, but
# leaves the hash in place when no space follows it — so "# v1" arrives here
# as "v1" while "#v1" arrives unchanged as "#v1". A leading "#" therefore
# means "no space followed the original #" in the source, which is already a
# format violation regardless of what follows; a comment with two or more
# original spaces arrives with residual leading whitespace instead (yq strips
# only one), which the patterns below tolerate rather than reject — the exact
# leading space count was never a deliberate policy dimension.
#
# Exit: 0 = one of the two documented forms, 1 = anything else, including an
# empty <raw_comment> (no comment at all).
pcc::_check_comment() {
  local raw="$1"
  [[ -n "$raw" ]] || return 1
  [[ "$raw" == \#* ]] && return 1
  [[ "$raw" =~ ^[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$ ]] && return 0
  [[ "$raw" =~ ^[[:space:]]*[0-9a-f]{7,40}[[:space:]][0-9]{4}-[0-9]{2}-[0-9]{2}([[:space:]]+.+)?[[:space:]]*$ ]] && return 0
  return 1
}

# pcc::scan_text <content>
#
# Scan the YAML document <content> for every `uses:` scalar node whose value
# pins a melodic-software/ci-workflows reusable workflow or composite action
# by 40-character commit SHA, and flag a trailing comment that is missing or
# does not match one of the two documented forms. A `uses:` node pinning any
# other action or workflow is out of scope and never flagged.
#
# Output (stdout): "lineno:kind:detail" per violation, lineno relative to
# <content> (0 for a document-level parse failure). kind is one of:
# missing-comment, invalid-form, yaml-parse-error.
# Exit: 0 = clean, 1 = one or more violations (including a parse failure).
pcc::scan_text() {
  local content="$1"
  local lineno comment value violations=0
  local value_re='^melodic-software/ci-workflows/\.github/(workflows|actions)/[^@[:space:]]+@[0-9a-fA-F]{40}$'
  local records

  if ! records="$(yq eval --yaml-fix-merge-anchor-to-spec=true -r '
      explode(.) | .jobs[]
      | (
          (select(has("uses")) | .uses),
          (select(has("steps")) | .steps[] | select(has("uses")) | .uses)
        )
      | (line | tostring) + "\t" + line_comment + "\t" + .
    ' - <<<"$content" 2>&1)"; then
    pcc::_record_violation 0 yaml-parse-error "$records"
    return 1
  fi

  # Field extraction is parameter expansion, not `IFS=$'\t' read -r a b c`:
  # bash's `read` treats tab as "IFS whitespace" regardless of what IFS is
  # set to, so it coalesces the two adjacent tabs an empty comment field
  # produces and silently shifts every later field left — parameter
  # expansion has no such collapsing behavior.
  local rec rest
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    lineno="${rec%%$'\t'*}"
    rest="${rec#*$'\t'}"
    comment="${rest%%$'\t'*}"
    value="${rest#*$'\t'}"

    [[ -n "$value" ]] || continue
    [[ "$value" =~ $value_re ]] || continue
    pcc::_check_comment "$comment" && continue

    if [[ -z "$comment" ]]; then
      pcc::_record_violation "$lineno" missing-comment "$value"
      continue
    fi
    if [[ "$comment" == \#* ]]; then
      pcc::_record_violation "$lineno" invalid-form "$comment"
    else
      pcc::_record_violation "$lineno" invalid-form "# ${comment}"
    fi
  done <<<"$records"

  if [[ $violations -gt 0 ]]; then
    return 1
  fi
  return 0
}
