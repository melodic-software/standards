#!/usr/bin/env bash
# Tests the Biome component: the packaged ruleset passes the good fixture and
# flags the bad fixture. Skips cleanly when Biome is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

biome_cfg='components/biome/biome.json'
good='components/biome/fixtures/good/example.ts'
bad='components/biome/fixtures/bad/violations.ts'

command -v biome >/dev/null 2>&1 || skip_suite 'biome not installed'

# `biome ci` runs lint + format + import sorting in one read-only pass.
biome ci --config-path="$biome_cfg" --error-on-warnings "$good" >/dev/null 2>&1
assert_exit 'good fixture lints and formats clean' 0 "$?"

out="$(biome ci --config-path="$biome_cfg" --error-on-warnings "$bad" 2>&1)"
assert_exit 'bad fixture exits 1' 1 "$?"
# noConsole is not in Biome's recommended set, so it proves the strict config
# loaded (not just the defaults).
assert_contains 'bad fixture reports console use (noConsole)' "$out" 'noConsole'
# noFloatingPromises is a type-aware rule the strict config turns on; its
# firing proves the type-aware layer is active.
assert_contains 'bad fixture reports floating promise (noFloatingPromises)' "$out" 'noFloatingPromises'

[[ $FAILED -eq 0 ]] || exit 1
