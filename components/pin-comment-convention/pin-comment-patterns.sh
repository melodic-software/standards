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
#                                        digits that must case-insensitively
#                                        PREFIX the same line's pinned
#                                        40-character SHA, <date> is ISO 8601
#                                        (YYYY-MM-DD), <note> is optional
#                                        free text.
# No comment, or any other shape (a stray version fragment, prose, the
# fields in the wrong order, a short-sha that does not prefix the pin it
# annotates), is flagged.
#
# The tag form checks FORM only — GitHub's tag data is not something a
# static scan can verify without a network call, so whether a `# vX.Y.Z`
# comment names the release the pinned SHA actually corresponds to is out of
# scope here. The fallback form is provenance-checked, not just
# format-checked: at this position, the token is an unambiguous SHA claim
# about the exact SHA on the same line, so there is no heuristic classifier
# to defer to the way runner-policy's `pin-provenance-drift` check needs one
# (its `isShaClaim` heuristic scans free-form comments across the whole
# repository, where a bare 7-character token could be almost anything). The
# two checks now overlap for a ci-workflows fallback comment specifically —
# this check is the authoritative one there, verified directly against the
# pin it annotates — and `pin-provenance-drift` remains the sole check for
# every other SHA-pin comment shape this convention does not govern. See
# components/runner-policy/README.md ("pin-provenance-drift").
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

# pcc::_check_comment <raw_comment> <pinned_sha>
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
# <pinned_sha> is the same node's 40-character pinned SHA (any case — see
# the case-insensitivity note above). For the fallback form, <short-sha>
# must case-insensitively PREFIX <pinned_sha>: an all-digit or
# all-a-through-f abbreviated SHA is a real, if less common, git prefix (one
# in roughly 25 real 7-character hex prefixes has no mixed-case letters) and
# is accepted the same as a mixed one — only the prefix relationship to the
# actual pin is checked, never the token's own letter/digit composition.
#
# Exit: 0 = one of the two documented forms (fallback additionally requires
# the prefix match), 1 = anything else, including an empty <raw_comment>.
pcc::_check_comment() {
  local raw="$1" pinned_sha="$2"
  [[ -n "$raw" ]] || return 1
  [[ "$raw" == \#* ]] && return 1
  [[ "$raw" =~ ^[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$ ]] && return 0
  if [[ "$raw" =~ ^[[:space:]]*([0-9a-f]{7,40})[[:space:]][0-9]{4}-[0-9]{2}-[0-9]{2}([[:space:]]+.+)?[[:space:]]*$ ]]; then
    local short="${BASH_REMATCH[1]}" pinned_lc="${pinned_sha,,}"
    [[ "$pinned_lc" == "$short"* ]] && return 0
  fi
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
  local rec rest pinned_sha
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    lineno="${rec%%$'\t'*}"
    rest="${rec#*$'\t'}"
    comment="${rest%%$'\t'*}"
    value="${rest#*$'\t'}"

    [[ -n "$value" ]] || continue
    [[ "$value" =~ $value_re ]] || continue
    # The path segment excludes '@' (value_re), so the last '@' unambiguously
    # separates the workflow/action path from the pinned SHA.
    pinned_sha="${value##*@}"
    pcc::_check_comment "$comment" "$pinned_sha" && continue

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
