#!/usr/bin/env bash
# Tests the Biome component: a consumer that extends the synced ruleset by
# relative path passes the good fixture and flags the bad fixture. Skips cleanly
# when Biome is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

good='components/biome/fixtures/good/example.ts'
bad='components/biome/fixtures/bad/violations.ts'
# The destination distribution/sync-manifest.yml gives the `biome` component.
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

# `biome ci` runs lint + format + import sorting in one read-only pass. Running
# from the isolated consumer proves the relative-path extends a sync target
# uses, not only the source-tree configuration path.
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
