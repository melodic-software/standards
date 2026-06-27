#!/usr/bin/env bash
# Tests the typescript module: the biome and tsc configs pass the good fixture
# and flag the bad fixture. Each tool's cases skip cleanly when its engine is
# absent; the suite skips only when neither is installed.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

biome_cfg='modules/typescript/biome.json'
good='fixtures/typescript/good/example.ts'
bad='fixtures/typescript/bad/violations.ts'
good_proj='fixtures/typescript/good/tsconfig.json'
bad_proj='fixtures/typescript/bad/tsconfig.json'

have_biome=0
have_tsc=0
command -v biome >/dev/null 2>&1 && have_biome=1
command -v tsc >/dev/null 2>&1 && have_tsc=1
if [[ $have_biome -eq 0 && $have_tsc -eq 0 ]]; then
  skip_suite 'neither biome nor tsc installed'
fi

if [[ $have_biome -eq 1 ]]; then
  # `biome ci` runs lint + format + import sorting in one read-only pass.
  biome ci --config-path="$biome_cfg" --error-on-warnings "$good" >/dev/null 2>&1
  assert_exit 'biome: good fixture lints and formats clean' 0 "$?"

  out="$(biome ci --config-path="$biome_cfg" --error-on-warnings "$bad" 2>&1)"
  assert_exit 'biome: bad fixture exits 1' 1 "$?"
  # noConsole is not in Biome's recommended set, so it proves the strict config
  # loaded (not just the defaults).
  assert_contains 'biome: bad fixture reports console use (noConsole)' "$out" 'noConsole'
  # noFloatingPromises is a type-aware rule the strict config turns on; its
  # firing proves the type-aware layer is active.
  assert_contains 'biome: bad fixture reports floating promise (noFloatingPromises)' "$out" 'noFloatingPromises'
else
  skip_case 'biome not installed'
fi

if [[ $have_tsc -eq 1 ]]; then
  # tsc cannot mix --project with file args, so each fixture carries a tsconfig
  # that extends the ruleset base and supplies `include`.
  tsc --noEmit -p "$good_proj" >/dev/null 2>&1
  assert_exit 'tsc: good fixture type-checks clean' 0 "$?"

  out="$(tsc --noEmit -p "$bad_proj" 2>&1)"
  # tsc exits 1 or 2 depending on the diagnostic mix; assert non-zero.
  assert_nonzero 'tsc: bad fixture exits non-zero' "$?"
  # TS7006 (implicit-any parameter) is an error only under the strict family.
  assert_contains 'tsc: bad fixture enforces strict (TS7006)' "$out" 'TS7006'
  # TS2532 (object possibly undefined) comes from noUncheckedIndexedAccess,
  # which strict alone does not enable — proves the overlay loaded.
  assert_contains 'tsc: bad fixture enforces noUncheckedIndexedAccess (TS2532)' "$out" 'TS2532'
else
  skip_case 'tsc not installed'
fi

[[ $FAILED -eq 0 ]] || exit 1
