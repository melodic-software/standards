#!/usr/bin/env bash
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) )"

tests=()
if [[ $# -gt 0 ]]; then
  tests=("$@")
else
  while IFS= read -r f; do tests+=("$f"); done \
    < <(find "$root" -name '*.test.sh' -not -path '*/.git/*' -not -path '*/node_modules/*' | sort)
fi

total=0 passed=0 failed=0 skipped=0
for t in "${tests[@]+"${tests[@]}"}"; do
  total=$((total + 1))
  rel="${t#"$root"/}"
  if [[ ! -f "$t" ]]; then
    failed=$((failed + 1))
    printf 'FAIL  %s (not found)\n' "$rel"
    continue
  fi
  out="$(bash "$t" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]] || grep -q '^FAIL: ' <<<"$out"; then
    failed=$((failed + 1))
    printf 'FAIL  %s\n' "$rel"
    printf '%s\n' "$out" | sed 's/^/      | /'
  elif grep -q '^SKIP: ' <<<"$out" && ! grep -q '^PASS: ' <<<"$out"; then
    skipped=$((skipped + 1))
    printf 'SKIP  %s\n' "$rel"
  else
    passed=$((passed + 1))
    printf 'ok    %s\n' "$rel"
  fi
done

printf '\n%d files: %d passed, %d failed, %d skipped\n' "$total" "$passed" "$failed" "$skipped"
[[ $failed -eq 0 ]]
