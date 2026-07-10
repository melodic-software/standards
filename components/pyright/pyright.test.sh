#!/usr/bin/env bash
# Proves the Pyright component enables strict type checking.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='components/pyright/pyrightconfig.json'
good='components/pyright/fixtures/good/example.py'
bad='components/pyright/fixtures/bad/violations.py'

command -v pyright >/dev/null 2>&1 || skip_suite 'pyright not installed'

pyright -p "$config" "$good" >/dev/null 2>&1
assert_exit 'good fixture type-checks clean' 0 "$?"

out="$(pyright -p "$config" "$bad" 2>&1)"
assert_exit 'bad fixture exits 1' 1 "$?"
assert_contains 'bad fixture reports an assignment error' "$out" 'reportAssignmentType'
# Missing-parameter-type is an error only in strict mode, proving the config loaded.
assert_contains 'bad fixture enforces strict mode' "$out" 'reportMissingParameterType'

[[ $FAILED -eq 0 ]] || exit 1
