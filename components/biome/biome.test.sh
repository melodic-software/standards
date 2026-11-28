#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

good='components/biome/fixtures/good/example.ts'
bad='components/biome/fixtures/bad/violations.ts'
synced_path='.github/standards/biome/biome.json'

command -v biome >/dev/null 2>&1 || skip_suite 'biome not installed'

consumer="$(mktemp -d)"
trap 'rm -rf "$consumer"' EXIT
mkdir -p "$consumer/$(dirname "$synced_path")"
cp components/biome/biome.json "$consumer/$synced_path"
cp "$good" "$consumer/good.ts"
cp "$bad" "$consumer/bad.ts"
printf '%s\n' \
  '{' \
  '  "root": true,' \
  "  \"extends\": [\"./$synced_path\"]" \
  '}' >"$consumer/biome.json"

biome ci --config-path="$consumer/biome.json" --error-on-warnings "$consumer/good.ts" >/dev/null 2>&1
assert_exit 'good fixture lints and formats clean' 0 "$?"

out="$(biome ci --config-path="$consumer/biome.json" --error-on-warnings "$consumer/bad.ts" 2>&1)"
assert_exit 'bad fixture exits 1' 1 "$?"
assert_contains 'bad fixture reports console use (noConsole)' "$out" 'noConsole'
assert_contains 'bad fixture reports floating promise (noFloatingPromises)' "$out" 'noFloatingPromises'

[[ $FAILED -eq 0 ]] || exit 1
