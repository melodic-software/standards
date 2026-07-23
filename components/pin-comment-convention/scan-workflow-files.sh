#!/usr/bin/env bash
# Pin-comment-convention driver: scans the given workflow files for
# `uses: melodic-software/ci-workflows/...@<40-hex-sha>` references whose
# trailing comment does not match one of the two documented pin-comment forms
# (README.md in this directory). File enumeration, path handling, and
# exit-code mapping live here; the YAML-node extraction and comment-form
# check live in pin-comment-patterns.sh, which requires yq v4 on PATH.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=components/pin-comment-convention/pin-comment-patterns.sh
source "$self_dir/pin-comment-patterns.sh"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <workflow-file>..." >&2
  exit 2
fi

failed=0
for file in "$@"; do
  [[ -f "$file" ]] || continue
  content="$(<"$file")"
  # pcc::scan_text's non-zero exit means "violations found," not failure; the
  # exit code is deliberately captured rather than left to propagate.
  rc=0
  # shellcheck disable=SC2310
  out="$(pcc::scan_text "$content")" || rc=$?
  if [[ $rc -ne 0 ]]; then
    failed=1
    while IFS= read -r row; do
      lineno="${row%%:*}"
      rest="${row#*:}"
      kind="${rest%%:*}"
      detail="${rest#*:}"
      printf '%s:%s: %s: %s\n' "$file" "$lineno" "$kind" "$detail" >&2
    done <<<"$out"
  fi
done

exit "$failed"
