#!/usr/bin/env bash
# Tests the Lefthook TypeScript adapter's biome lane end-to-end: it passes a clean
# staged file, fails one with a real finding, and passes a commit whose staged files
# are all ignored by the consumer's Biome config (Biome would otherwise exit
# non-zero with "No files were processed"). Skips cleanly when lefthook or the
# repo's pinned Biome (node_modules) is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

fragment="$root/components/lefthook-typescript/lefthook.yml"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'
[[ -x "$root/node_modules/.bin/biome" ]] || skip_suite 'biome not installed (run npm ci)'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
make_repo "$work"
ln -s "$root/node_modules" "$work/node_modules"

mkdir -p "$work/.lefthook"
cp "$fragment" "$work/.lefthook/typescript.yml"
cat >"$work/lefthook.yml" <<'YAML'
extends:
  - .lefthook/typescript.yml
YAML
cat >"$work/biome.json" <<'JSON'
{
  "root": true,
  "files": { "includes": ["**", "!**/ignored.json"] }
}
JSON

cd "$work" || exit 1

mkdir src
printf 'export const a = 1;\n' >src/clean.ts
printf 'debugger;\n' >src/bad.ts
printf '{"a":   1}\n' >src/ignored.json

# Case 1: a clean staged file passes.
git add src/clean.ts
lefthook run pre-commit --command biome >/dev/null 2>&1
assert_exit 'clean staged file passes the biome lane' 0 "$?"
git rm --cached -q src/clean.ts

# Case 2: a real lint finding still fails the lane.
git add src/bad.ts
lefthook run pre-commit --command biome >/dev/null 2>&1
assert_nonzero 'staged file with a lint finding fails the biome lane' "$?"
git rm --cached -q src/bad.ts

# Case 3: a commit staging only Biome-ignored files passes.
git add src/ignored.json
lefthook run pre-commit --command biome >/dev/null 2>&1
assert_exit 'commit staging only biome-ignored files passes the lane' 0 "$?"

[[ $FAILED -eq 0 ]] || exit 1
