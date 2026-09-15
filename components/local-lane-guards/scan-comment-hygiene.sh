#!/usr/bin/env bash
# Full-tree comment-hygiene scan for local and CI drivers. A coarse `git grep`
# prefilter narrows to candidate comment lines; the selected policy library
# (default: the sibling comment-hygiene component, or PATTERNS_FILE) then
# authoritatively validates each hit. This two-pass shape keeps the scan fast
# on large trees — looping the library over every file would be O(files × lines).
#
# Emits "path:lineno:kind:detail" per violation.
# Exit: 0 = clean, 1 = violations, 2 = environment error.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Relative layout matches path-detection: in-source
# (components/local-lane-guards → ../comment-hygiene) and when synced beside
# comment-hygiene-tools (tools/shared/local-lane-guards → ../comment-hygiene).
PATTERNS_FILE="${PATTERNS_FILE:-$HERE/../comment-hygiene/comment-hygiene-patterns.sh}"
if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "comment-hygiene: patterns file not found: $PATTERNS_FILE" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$PATTERNS_FILE"

read -ra scan_globs <<<"${EXTENSIONS:-}"
read -ra excludes <<<"${EXCLUDE:-}"

# Coarse comment-marker prefilter, defined and documented in the sourced fragment
# (shared with the contract test, which enforces its superset contract against the
# policy library).
# shellcheck source=coarse-prefilter.sh
source "$HERE/coarse-prefilter.sh"
coarse_re="$(chp::coarse_re)"

# Run the prefilter into a tempfile so the git grep exit code can be read before
# consuming output:
#   0 = matches, 1 = no matches (clean), anything else = fatal. Fail CLOSED on a
#   fatal grep rather than passing an incomplete scan.
matches=$(mktemp)
errfile=$(mktemp)
trap 'rm -f "$matches" "$errfile"' EXIT
grep_rc=0
# Keep stderr out of $matches: it is parsed as path:lineno:content on the
# success path, so a non-fatal git warning merged in would become a spurious
# candidate. stderr is only needed for the fatal-error report below.
git grep -niE "$coarse_re" -- "${scan_globs[@]}" "${excludes[@]}" >"$matches" 2>"$errfile" || grep_rc=$?
if [[ "$grep_rc" -ne 0 && "$grep_rc" -ne 1 ]]; then
  echo "comment-hygiene: git grep failed (exit $grep_rc):" >&2
  cat "$errfile" >&2
  exit 2
fi

violations=0
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  rest="${match#*:}"
  lineno="${rest%%:*}"
  content="${rest#*:}"

  scan_rc=0
  scan_out="$(chp::scan_text "$content")" || scan_rc=$?
  if [[ "$scan_rc" -eq 0 ]]; then
    continue
  fi

  while IFS= read -r detail_line; do
    [[ -z "$detail_line" ]] && continue
    # The library prefixes its own (single-line) lineno; replace it with the
    # real git-grep file line number.
    detail="${detail_line#*:}"
    printf '%s:%s:%s\n' "$file" "$lineno" "$detail"
    violations=$((violations + 1))
  done <<<"$scan_out"
done <"$matches"

if [[ "$violations" -eq 0 ]]; then
  echo "comment-hygiene: clean" >&2
  exit 0
fi
echo "comment-hygiene: $violations violation(s)" >&2
exit 1
