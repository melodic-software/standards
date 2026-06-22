#!/usr/bin/env bash
# Tests the Markdown module: the GFM ruleset passes the good fixture and flags
# the bad fixture. Skips cleanly when markdownlint-cli2 is absent.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1
config='modules/markdown/.markdownlint-cli2.jsonc'

if [[ -x node_modules/.bin/markdownlint-cli2 ]]; then
  ml() { node_modules/.bin/markdownlint-cli2 "$@"; }
elif command -v markdownlint-cli2 >/dev/null 2>&1; then
  ml() { markdownlint-cli2 "$@"; }
else
  skip_suite 'markdownlint-cli2 not installed (run: npm ci)'
fi

FAILED=0
CASE_NUM=0

ml --config "$config" fixtures/markdown/good/Clean.md >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(ml --config "$config" fixtures/markdown/bad/Violations.md 2>&1)"
rc=$?
assert_exit 'bad fixture exits 1' 1 "$rc"
assert_contains 'bad fixture reports a rule' "$out" 'MD0'

[[ $FAILED -eq 0 ]] || exit 1
