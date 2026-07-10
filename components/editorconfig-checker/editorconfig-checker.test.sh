#!/usr/bin/env bash
# Tests the editorconfig-checker component: the checker passes the good fixture
# and flags the bad fixture against the repo-root .editorconfig. Skips cleanly
# when the engine is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='.editorconfig-checker.json'

# Binary name varies by install method: the official GitHub Action and most
# package managers install `editorconfig-checker` (with an `ec` alias); the
# winget package ships `ec-windows-amd64`.
if command -v editorconfig-checker >/dev/null 2>&1; then
  run_ec() { editorconfig-checker "$@"; }
elif command -v ec >/dev/null 2>&1; then
  run_ec() { command ec "$@"; }
elif command -v ec-windows-amd64 >/dev/null 2>&1; then
  run_ec() { ec-windows-amd64 "$@"; }
else
  skip_suite 'editorconfig-checker not installed'
fi

run_ec -config "$config" components/editorconfig-checker/fixtures/good >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(run_ec -config "$config" components/editorconfig-checker/fixtures/bad 2>&1)"
rc=$?
assert_exit 'bad fixture exits 1' 1 "$rc"
assert_contains 'bad fixture reports a finding' "$out" 'newline'

[[ $FAILED -eq 0 ]] || exit 1
