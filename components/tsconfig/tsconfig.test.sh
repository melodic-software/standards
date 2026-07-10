#!/usr/bin/env bash
# Proves the packaged TypeScript base enables the intended strict checks.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
good='components/tsconfig/fixtures/good/tsconfig.json'
bad='components/tsconfig/fixtures/bad/tsconfig.json'

command -v tsc >/dev/null 2>&1 || skip_suite 'tsc not installed'

tsc --noEmit -p "$good" >/dev/null 2>&1
assert_exit 'good fixture type-checks clean' 0 "$?"

out="$(tsc --noEmit -p "$bad" 2>&1)"
assert_nonzero 'bad fixture exits non-zero' "$?"
assert_contains 'bad fixture enforces strict (TS7006)' "$out" 'TS7006'
assert_contains 'bad fixture enforces noUncheckedIndexedAccess (TS2532)' "$out" 'TS2532'

[[ $FAILED -eq 0 ]] || exit 1
