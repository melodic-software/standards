#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

ruff_cfg='ruff.toml'
good='components/ruff/fixtures/good/example.py'
bad_src='components/ruff/fixtures/bad/violations.py.txt'

command -v ruff >/dev/null 2>&1 || skip_suite 'ruff not installed'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$bad_src" "$tmp/violations.py"
bad="$tmp/violations.py"

ruff check --config "$ruff_cfg" "$good" >/dev/null 2>&1
assert_exit 'good fixture lints clean' 0 "$?"

ruff format --check --config "$ruff_cfg" "$good" >/dev/null 2>&1
assert_exit 'good fixture is already formatted' 0 "$?"

out="$(ruff check --config "$ruff_cfg" --output-format json "$bad" 2>&1)"
assert_exit 'bad fixture exits 1' 1 "$?"
assert_contains 'bad fixture reports banned-api (TID251)' "$out" 'TID251'
assert_contains 'bad fixture reports naive datetime (DTZ005)' "$out" 'DTZ005'

[[ $FAILED -eq 0 ]] || exit 1
