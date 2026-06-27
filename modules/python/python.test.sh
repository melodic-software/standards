#!/usr/bin/env bash
# Tests the python module: the ruff and pyright configs pass the good fixture and
# flag the bad fixture. Each tool's cases skip cleanly when its engine is absent;
# the suite skips only when neither is installed.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

ruff_cfg='modules/python/ruff.toml'
pyright_proj='modules/python'
good='fixtures/python/good/example.py'
bad='fixtures/python/bad/violations.py'

have_ruff=0
have_pyright=0
command -v ruff >/dev/null 2>&1 && have_ruff=1
command -v pyright >/dev/null 2>&1 && have_pyright=1
if [[ $have_ruff -eq 0 && $have_pyright -eq 0 ]]; then
  skip_suite 'neither ruff nor pyright installed'
fi

if [[ $have_ruff -eq 1 ]]; then
  ruff check --config "$ruff_cfg" "$good" >/dev/null 2>&1
  assert_exit 'ruff: good fixture lints clean' 0 "$?"

  ruff format --check --config "$ruff_cfg" "$good" >/dev/null 2>&1
  assert_exit 'ruff: good fixture is already formatted' 0 "$?"

  # Assert against the JSON `code` field, not the human output: ruff's default
  # text format now prints rule NAMES (banned-api) rather than codes, but the
  # codes stay the canonical stable identifiers in the json interface.
  out="$(ruff check --config "$ruff_cfg" --output-format json "$bad" 2>&1)"
  assert_exit 'ruff: bad fixture exits 1' 1 "$?"
  # banned-api is config-only, so TID251 proves the ruleset actually loaded.
  assert_contains 'ruff: bad fixture reports banned-api (TID251)' "$out" 'TID251'
  # DTZ is not in ruff's defaults — asserting it proves the strict group is on.
  assert_contains 'ruff: bad fixture reports naive datetime (DTZ005)' "$out" 'DTZ005'
else
  skip_case 'ruff not installed'
fi

if [[ $have_pyright -eq 1 ]]; then
  pyright -p "$pyright_proj" "$good" >/dev/null 2>&1
  assert_exit 'pyright: good fixture type-checks clean' 0 "$?"

  out="$(pyright -p "$pyright_proj" "$bad" 2>&1)"
  assert_exit 'pyright: bad fixture exits 1' 1 "$?"
  assert_contains 'pyright: bad fixture reports a type error' "$out" 'reportAssignmentType'
  # Missing-parameter-type is an error only in strict mode — proves the config.
  assert_contains 'pyright: bad fixture enforces strict mode' "$out" 'reportMissingParameterType'
else
  skip_case 'pyright not installed'
fi

[[ $FAILED -eq 0 ]] || exit 1
