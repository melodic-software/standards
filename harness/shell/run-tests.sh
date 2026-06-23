#!/usr/bin/env bash
# Discover and run *.test.sh files; report per-file status and a summary.
# Exit non-zero if any file fails. Runs the same locally and in CI.
#
# Usage:
#   harness/shell/run-tests.sh            # all *.test.sh in the repo
#   harness/shell/run-tests.sh path/a.test.sh path/b.test.sh
#
# A test file passes when it exits 0. A file that exits 0 with a `SKIP:` marker
# and no `PASS:` lines is counted as skipped (no coverage this run).
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd))"

tests=()
if [[ $# -gt 0 ]]; then
  tests=("$@")
else
  while IFS= read -r f; do tests+=("$f"); done \
    < <(find "$root" -name '*.test.sh' -not -path '*/.git/*' | sort)
fi

total=0 passed=0 failed=0 skipped=0
# "${tests[@]+...}" guards the empty-array expansion under `set -u` (on bash
# <= 4.3, including macOS's system bash 3.2, expanding an empty array otherwise
# aborts with "unbound variable").
for t in "${tests[@]+"${tests[@]}"}"; do
  [[ -f "$t" ]] || continue
  total=$((total + 1))
  rel="${t#"$root"/}"
  if out="$(bash "$t" 2>&1)"; then
    if grep -q '^SKIP: ' <<<"$out" && ! grep -q '^PASS: ' <<<"$out"; then
      skipped=$((skipped + 1))
      printf 'SKIP  %s\n' "$rel"
    else
      passed=$((passed + 1))
      printf 'ok    %s\n' "$rel"
    fi
  else
    failed=$((failed + 1))
    printf 'FAIL  %s\n' "$rel"
    printf '%s\n' "$out" | sed 's/^/      | /'
  fi
done

printf '\n%d files: %d passed, %d failed, %d skipped\n' "$total" "$passed" "$failed" "$skipped"
[[ $failed -eq 0 ]]
