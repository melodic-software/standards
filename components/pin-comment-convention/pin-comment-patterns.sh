# shellcheck shell=bash
# Pin-comment convention detection policy — dual-form trailing-comment shape
# for `uses:` references to melodic-software/ci-workflows reusable workflows
# and composite actions, pinned by 40-character commit SHA.
#
# Library, NOT executable. Pure function: no env reads, no file I/O, no exit
# calls. `scan-workflow-files.sh` in this component owns file enumeration and
# exit-code mapping for this repository's own workflows; a ci-workflows-side
# driver (deferred — no consumer yet) would own full-tree execution for other
# repositories the way the comment-hygiene composite action does today.
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
# POSIX ERE only (bash =~ delegates to the platform regex library) for
# cross-platform parity between Linux CI and Git Bash.

# pcc::_record_violation <lineno> <kind> <detail>
#
# Emit one "lineno:kind:detail" line and increment the caller's `violations`
# local via bash dynamic scoping; private to pcc::scan_text.
pcc::_record_violation() {
  printf '%s:%s:%s\n' "$1" "$2" "$3"
  violations=$((violations + 1))
}

# pcc::scan_text <content>
#
# Scan <content> for `uses:` lines that pin a melodic-software/ci-workflows
# reusable workflow or composite action by 40-character commit SHA, and flag
# a trailing comment that is missing or does not match one of the two
# documented forms. A `uses:` line pinning any other action or workflow is
# out of scope and never flagged.
#
# Output (stdout): "lineno:kind:detail" per violation, lineno relative to
# <content>. kind is one of: missing-comment, invalid-form.
# Exit: 0 = clean, 1 = one or more violations.
pcc::scan_text() {
  local content="$1"
  local lineno line violations=0
  # The optional leading/trailing bracket expression accepts a plain,
  # single-, or double-quoted YAML scalar (`uses: 'owner/repo@sha'` and
  # `uses: "owner/repo@sha"` are both legal YAML for the same ref) — the two
  # quote characters need not match each other, since this scans for the
  # pin-comment shape, not YAML validity.
  local uses_re='uses:[[:space:]]*['\''"]?melodic-software/ci-workflows/\.github/(workflows|actions)/[^@[:space:]]+@[0-9a-f]{40}['\''"]?[[:space:]]*(#(.*))?$'
  local tag_re='^#[[:space:]]v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$'
  local fallback_re='^#[[:space:]][0-9a-f]{7,40}[[:space:]][0-9]{4}-[0-9]{2}-[0-9]{2}([[:space:]]+.+)?[[:space:]]*$'

  while IFS= read -r entry; do
    lineno="${entry%%:*}"
    line="${entry#*:}"

    [[ "$line" =~ $uses_re ]] || continue

    if [[ -z "${BASH_REMATCH[2]:-}" ]]; then
      pcc::_record_violation "$lineno" missing-comment "$line"
      continue
    fi

    local comment="#${BASH_REMATCH[3]}"
    if [[ "$comment" =~ $tag_re || "$comment" =~ $fallback_re ]]; then
      continue
    fi
    pcc::_record_violation "$lineno" invalid-form "$comment"
  done < <(awk '{ print NR ":" $0 }' <<<"$content")

  if [[ $violations -gt 0 ]]; then
    return 1
  fi
  return 0
}
