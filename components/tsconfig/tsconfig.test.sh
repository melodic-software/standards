#!/usr/bin/env bash
# Proves the synced TypeScript base enables the intended strict checks when a
# consumer extends it by relative path.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
good='components/tsconfig/fixtures/good/tsconfig.json'
bad='components/tsconfig/fixtures/bad/tsconfig.json'
# The destination distribution/sync-manifest.yml gives the `tsconfig` component.
synced_path='.github/standards/tsconfig/tsconfig.json'

command -v tsc >/dev/null 2>&1 || skip_suite 'tsc not installed'
command -v node >/dev/null 2>&1 || skip_suite 'node not installed'

consumer="$(mktemp -d)"
trap 'rm -rf "$consumer"' EXIT
mkdir -p "$consumer/$(dirname "$synced_path")" "$consumer/good" "$consumer/bad"
cp components/tsconfig/tsconfig.json "$consumer/$synced_path"
cp "components/tsconfig/fixtures/good/example.ts" "$consumer/good/example.ts"
cp "components/tsconfig/fixtures/bad/violations.ts" "$consumer/bad/violations.ts"

# write_extending_tsconfig <source> <destination> — copy <source>'s tsconfig,
# pointed at the synced base via a relative `extends`, to <destination>.
write_extending_tsconfig() {
  node -e '
    const fs = require("node:fs");
    const [source, destination, base] = process.argv.slice(1);
    const config = JSON.parse(fs.readFileSync(source, "utf8"));
    config.extends = base;
    fs.writeFileSync(destination, JSON.stringify(config, null, 2) + "\n");
  ' "$1" "$2" "../$synced_path"
}
write_extending_tsconfig "$good" "$consumer/good/tsconfig.json"
write_extending_tsconfig "$bad" "$consumer/bad/tsconfig.json"

tsc --noEmit -p "$consumer/good/tsconfig.json" >/dev/null 2>&1
assert_exit 'good fixture type-checks clean' 0 "$?"

out="$(tsc --noEmit -p "$consumer/bad/tsconfig.json" 2>&1)"
assert_nonzero 'bad fixture exits non-zero' "$?"
assert_contains 'bad fixture enforces strict (TS7006)' "$out" 'TS7006'
assert_contains 'bad fixture enforces noUncheckedIndexedAccess (TS2532)' "$out" 'TS2532'

[[ $FAILED -eq 0 ]] || exit 1
