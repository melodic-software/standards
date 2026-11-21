#!/usr/bin/env bash
# Tests the Markdownlint component: the GFM ruleset passes the good fixture and flags
# the bad fixture. Skips cleanly when markdownlint-cli2 is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='.markdownlint-cli2.jsonc'

if [[ -x "$root/node_modules/.bin/markdownlint-cli2" ]]; then
  ml() { "$root/node_modules/.bin/markdownlint-cli2" "$@"; }
elif command -v markdownlint-cli2 >/dev/null 2>&1; then
  ml() { markdownlint-cli2 "$@"; }
else
  skip_suite 'markdownlint-cli2 not installed (run: npm ci)'
fi

ml --config "$config" components/markdownlint/fixtures/good/Clean.md >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

# Stored with a .txt suffix so shared Markdown formatter hooks leave the
# deliberately malformed fixture untouched; materialized as .md below.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp components/markdownlint/fixtures/bad/Violations.md.txt "$tmp/Violations.md"

out="$(cd "$tmp" && ml --config "$root/$config" Violations.md 2>&1)"
rc=$?
assert_exit 'bad fixture exits 1' 1 "$rc"
# Assert specific configured style rules fired, not merely that some rule did,
# so the test proves the ruleset's intent rather than incidental output.
assert_contains 'bad fixture flags list-bullet style (MD004)' "$out" 'MD004'
assert_contains 'bad fixture flags emphasis style (MD049)' "$out" 'MD049'

[[ $FAILED -eq 0 ]] || exit 1
