#!/usr/bin/env bash
# Proves the packaged TypeScript base enables the intended strict checks.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
good='components/tsconfig/fixtures/good/tsconfig.json'
bad='components/tsconfig/fixtures/bad/tsconfig.json'

command -v tsc >/dev/null 2>&1 || skip_suite 'tsc not installed'
command -v npm >/dev/null 2>&1 || skip_suite 'npm not installed'
command -v node >/dev/null 2>&1 || skip_suite 'node not installed'

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
pack_json="$(npm pack ./components/tsconfig --json --ignore-scripts --pack-destination "$workspace")"
filename="$(node -p 'JSON.parse(process.argv[1])[0].filename' "$pack_json")"
consumer="$workspace/consumer"
mkdir -p "$consumer/good" "$consumer/bad"
printf '{"name":"tsconfig-consumer","private":true}\n' >"$consumer/package.json"
npm install --prefix "$consumer" --ignore-scripts --no-audit --no-fund --package-lock=false \
  --legacy-peer-deps "$workspace/$filename" >/dev/null 2>&1
assert_exit 'packed tsconfig installs in an isolated consumer' 0 "$?"
assert_file_exists 'installed package contains tsconfig.json' \
  "$consumer/node_modules/@melodic-software/tsconfig/tsconfig.json"

cp "components/tsconfig/fixtures/good/example.ts" "$consumer/good/example.ts"
cp "components/tsconfig/fixtures/bad/violations.ts" "$consumer/bad/violations.ts"
node -e '
  const fs = require("node:fs");
  const [source, destination] = process.argv.slice(1);
  const config = JSON.parse(fs.readFileSync(source, "utf8"));
  config.extends = "@melodic-software/tsconfig/tsconfig.json";
  fs.writeFileSync(destination, JSON.stringify(config, null, 2) + "\n");
' "$good" "$consumer/good/tsconfig.json"
node -e '
  const fs = require("node:fs");
  const [source, destination] = process.argv.slice(1);
  const config = JSON.parse(fs.readFileSync(source, "utf8"));
  config.extends = "@melodic-software/tsconfig/tsconfig.json";
  fs.writeFileSync(destination, JSON.stringify(config, null, 2) + "\n");
' "$bad" "$consumer/bad/tsconfig.json"

good="$consumer/good/tsconfig.json"
bad="$consumer/bad/tsconfig.json"
tsc --noEmit -p "$good" >/dev/null 2>&1
assert_exit 'good fixture type-checks clean' 0 "$?"

out="$(tsc --noEmit -p "$bad" 2>&1)"
assert_nonzero 'bad fixture exits non-zero' "$?"
assert_contains 'bad fixture enforces strict (TS7006)' "$out" 'TS7006'
assert_contains 'bad fixture enforces noUncheckedIndexedAccess (TS2532)' "$out" 'TS2532'

[[ $FAILED -eq 0 ]] || exit 1
