#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='_typos.toml'

if ! command -v typos >/dev/null 2>&1; then
  skip_suite 'typos not installed'
fi

typos --config "$config" components/typos/fixtures/good >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(typos --config "$config" components/typos/fixtures/bad 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture reports a correction' "$out" 'should be'

typos --config "$config" components/typos/fixtures/good/Scansion.txt >/dev/null 2>&1
rc=$?
assert_exit 'DUM scansion fixture exits 0' 0 "$rc"

lower_fixture='components/typos/fixtures/bad/ScansionLower.txt'
lower_token="$(grep -v '^#' "$lower_fixture" | tr -d '[:space:]')"
lower_out="$(typos --config "$config" "$lower_fixture" 2>&1)"
rc=$?
assert_exit 'scansion lower fixture exits 2' 2 "$rc"
assert_contains 'scansion lower still corrected' "$lower_out" 'should be'
assert_contains 'scansion lower names the fixture token' "$lower_out" "$lower_token"

parent_config="$(mktemp)"
trap 'rm -f "$parent_config"' EXIT
sed '/^DUM = "DUM"$/d' "$config" >"$parent_config"
typos --isolated --config "$parent_config" components/typos/fixtures/good/Scansion.txt >/dev/null 2>&1
rc=$?
assert_exit 'parent config rejects uppercase DUM' 2 "$rc"

british_fixture='components/typos/fixtures/bad/BritishVariants.txt'
british_out="$(typos --config "$config" "$british_fixture" 2>&1)"
rc=$?
assert_exit 'british variants fixture exits 2' 2 "$rc"
for british_token in $(grep -v '^#' "$british_fixture" | tr -d '\r'); do
  assert_contains "british variant $british_token still corrected" \
    "$british_out" "\`$british_token\` should be"
done

[[ $FAILED -eq 0 ]] || exit 1
