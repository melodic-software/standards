#!/usr/bin/env bash
# Tests the Biome component: the packaged ruleset passes the good fixture and
# flags the bad fixture. Skips cleanly when Biome is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

good='components/biome/fixtures/good/example.ts'
bad='components/biome/fixtures/bad/violations.ts'

command -v biome >/dev/null 2>&1 || skip_suite 'biome not installed'
command -v npm >/dev/null 2>&1 || skip_suite 'npm not installed'
command -v node >/dev/null 2>&1 || skip_suite 'node not installed'

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
pack_json="$(npm pack ./components/biome --json --ignore-scripts --pack-destination "$workspace")"
filename="$(node -p 'JSON.parse(process.argv[1])[0].filename' "$pack_json")"
consumer="$workspace/consumer"
mkdir -p "$consumer"
printf '{"name":"biome-config-consumer","private":true}\n' >"$consumer/package.json"
npm install --prefix "$consumer" --ignore-scripts --no-audit --no-fund --package-lock=false \
  --legacy-peer-deps "$workspace/$filename" >/dev/null 2>&1
assert_exit 'packed Biome config installs in an isolated consumer' 0 "$?"
assert_file_exists 'installed package contains biome.json' \
  "$consumer/node_modules/@melodic-software/biome-config/biome.json"

cp "$good" "$consumer/good.ts"
cp "$bad" "$consumer/bad.ts"
printf '%s\n' \
  '{' \
  '  "root": true,' \
  '  "extends": ["@melodic-software/biome-config/biome"]' \
  '}' >"$consumer/biome.json"

# `biome ci` runs lint + format + import sorting in one read-only pass. Running
# from the isolated consumer proves package export and resolution, not only the
# source-tree configuration path.
biome ci --config-path="$consumer/biome.json" --error-on-warnings "$consumer/good.ts" >/dev/null 2>&1
assert_exit 'good fixture lints and formats clean' 0 "$?"

out="$(biome ci --config-path="$consumer/biome.json" --error-on-warnings "$consumer/bad.ts" 2>&1)"
assert_exit 'bad fixture exits 1' 1 "$?"
# noConsole is not in Biome's recommended set, so it proves the strict config
# loaded (not just the defaults).
assert_contains 'bad fixture reports console use (noConsole)' "$out" 'noConsole'
# noFloatingPromises is a type-aware rule the strict config turns on; its
# firing proves the type-aware layer is active.
assert_contains 'bad fixture reports floating promise (noFloatingPromises)' "$out" 'noFloatingPromises'

[[ $FAILED -eq 0 ]] || exit 1
