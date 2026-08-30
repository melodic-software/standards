#!/usr/bin/env bash
# Tests the typos component: the spell-checker passes the good fixture and flags
# the bad fixture. The good fixture plants a real misspelling under each of the
# four blessed ignore directives (disable-line, ignore-next-line, the comment
# block, and the HTML-comment block), so a good->exit-0 result conjunctively
# proves every directive form still suppresses. Also pins the DUM scansion
# allowlist: uppercase passes; the case-sensitive lowercase token in
# fixtures/bad/ScansionLower.txt remains a finding. Skips when the engine is
# absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='_typos.toml'

if ! command -v typos >/dev/null 2>&1; then
  skip_suite 'typos not installed'
fi

# typos exits 0 when clean and 2 when typos are found; any other non-zero is an error.
typos --config "$config" components/typos/fixtures/good >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(typos --config "$config" components/typos/fixtures/bad 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture reports a correction' "$out" 'should be'

# DUM allowlist regression: uppercase passes; lowercase token stays rejected.
typos --config "$config" components/typos/fixtures/good/Scansion.txt >/dev/null 2>&1
rc=$?
assert_exit 'DUM scansion fixture exits 0' 0 "$rc"

lower_fixture='components/typos/fixtures/bad/ScansionLower.txt'
# Derive the case-sensitive token from the fixture so this file never embeds it.
lower_token="$(grep -v '^#' "$lower_fixture" | tr -d '[:space:]')"
lower_out="$(typos --config "$config" "$lower_fixture" 2>&1)"
rc=$?
assert_exit 'scansion lower fixture exits 2' 2 "$rc"
assert_contains 'scansion lower still corrected' "$lower_out" 'should be'
assert_contains 'scansion lower names the fixture token' "$lower_out" "$lower_token"

# Parent-config negative: without the allowlist entry, uppercase DUM must fail.
# --isolated prevents the repo-root _typos.toml (which still has DUM) from winning.
parent_config="$(mktemp)"
trap 'rm -f "$parent_config"' EXIT
sed '/Scansion vocalization/,/^DUM = "DUM"$/d' "$config" > "$parent_config"
typos --isolated --config "$parent_config" components/typos/fixtures/good/Scansion.txt >/dev/null 2>&1
rc=$?
assert_exit 'parent config rejects uppercase DUM' 2 "$rc"

[[ $FAILED -eq 0 ]] || exit 1
