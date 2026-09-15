#!/usr/bin/env bash
# Pin-comment-convention driver: scans the given workflow files for
# `uses: melodic-software/ci-workflows/...@<40-hex-sha>` references whose
# trailing comment does not match one of the two documented pin-comment forms
# (README.md in this directory). File enumeration, path handling, and
# exit-code mapping live here; the YAML-node extraction and comment-form
# check live in pin-comment-patterns.sh, which requires yq v4 on PATH.
#
# Spawn: one yq over every existing argument on the success path (the CI
# glob is 11 workflow files). Mike Farah yq 4.53.3 `eval` of several files
# stops at the first parse error and has no `try`/`catch`, so a failed batch
# falls back to per-file pcc::scan_text and still reports every file.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=components/pin-comment-convention/pin-comment-patterns.sh
source "$self_dir/pin-comment-patterns.sh"

if [[ $# -eq 0 ]]; then
  printf 'usage: %s <workflow-file>...\n' "$0" >&2
  exit 2
fi

existing=()
for file in "$@"; do
  [[ -f "$file" ]] || continue
  existing+=("$file")
done

failed=0

# emit_scan_rows <file> <scan_text_stdout> — re-prefix library rows with the
# path the driver already owns.
emit_scan_rows() {
  local file="$1" out="$2" row lineno rest kind detail
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    lineno="${row%%:*}"
    rest="${row#*:}"
    kind="${rest%%:*}"
    detail="${rest#*:}"
    printf '%s:%s: %s: %s\n' "$file" "$lineno" "$kind" "$detail" >&2
  done <<<"$out"
}

# scan_one_file <path> — isolation fallback: one pcc::scan_text per file.
scan_one_file() {
  local file="$1" content rc=0 out
  content="$(<"$file")"
  # pcc::scan_text's non-zero exit means "violations found," not failure; the
  # exit code is deliberately captured rather than left to propagate.
  # shellcheck disable=SC2310
  out="$(pcc::scan_text "$content")" || rc=$?
  if [[ $rc -ne 0 ]]; then
    failed=1
    emit_scan_rows "$file" "$out"
  fi
}

if [[ ${#existing[@]} -eq 0 ]]; then
  exit 0
fi

# A failed multi-file eval may have already printed the first files' records
# on stdout; discard that incomplete stream and isolate per file instead.
# SC2310: a non-zero yq is the fallback trigger, not a driver abort.
yq_rc=0
# shellcheck disable=SC2310
records="$(pcc::_extract_uses "${existing[@]}" 2>/dev/null)" || yq_rc=$?
if [[ "$yq_rc" -ne 0 ]]; then
  for file in "${existing[@]}"; do
    scan_one_file "$file"
  done
  exit "$failed"
fi

while IFS= read -r rec; do
  [[ -n "$rec" ]] || continue
  file="${rec%%$'\t'*}"
  rest="${rec#*$'\t'}"
  lineno="${rest%%$'\t'*}"
  rest="${rest#*$'\t'}"
  comment="${rest%%$'\t'*}"
  value="${rest#*$'\t'}"
  row=""
  rc=0
  # shellcheck disable=SC2310
  row="$(pcc::_classify_one "$lineno" "$comment" "$value")" || rc=$?
  if [[ $rc -ne 0 ]]; then
    failed=1
    rest="${row#*:}"
    kind="${rest%%:*}"
    detail="${rest#*:}"
    printf '%s:%s: %s: %s\n' "$file" "$lineno" "$kind" "$detail" >&2
  fi
done <<<"$records"

exit "$failed"
