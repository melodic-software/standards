#!/usr/bin/env bash
# Tests the Ruff component: the root-canonical config passes the good fixture
# and flags the bad fixture. Skips cleanly when Ruff is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

ruff_cfg='ruff.toml'
good='components/ruff/fixtures/good/example.py'
bad='components/ruff/fixtures/bad/violations.py'

command -v ruff >/dev/null 2>&1 || skip_suite 'ruff not installed'

ruff check --config "$ruff_cfg" "$good" >/dev/null 2>&1
assert_exit 'good fixture lints clean' 0 "$?"

ruff format --check --config "$ruff_cfg" "$good" >/dev/null 2>&1
assert_exit 'good fixture is already formatted' 0 "$?"

# Assert against the JSON `code` field, not the human output: Ruff's default
# text format can print rule names, while codes are stable interface identifiers.
out="$(ruff check --config "$ruff_cfg" --output-format json "$bad" 2>&1)"
assert_exit 'bad fixture exits 1' 1 "$?"
# banned-api is config-only, so TID251 proves the ruleset actually loaded.
assert_contains 'bad fixture reports banned-api (TID251)' "$out" 'TID251'
# DTZ is not in Ruff's defaults — asserting it proves the strict group is on.
assert_contains 'bad fixture reports naive datetime (DTZ005)' "$out" 'DTZ005'

[[ $FAILED -eq 0 ]] || exit 1
