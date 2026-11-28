#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

stubs="$work/stubs"
mkdir -p "$stubs"
for tool in ruff pwsh npx; do
  cat >"$stubs/$tool" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG"
SH
  chmod +x "$stubs/$tool"
done

cases=(
  'python ruff-lint setup.py pkg/mod.py'
  'powershell psscriptanalyzer build.ps1 scripts/tool.ps1'
  'typescript biome eslint.config.mjs src/app.ts'
  'dotnet dotnet-format Program.cs src/Lib.cs'
)

for entry in "${cases[@]}"; do
  read -r adapter command root_file nested_file <<<"$entry"
  fragment="$root/components/lefthook-$adapter/lefthook.yml"
  assert_eq "$adapter fragment sets glob_matcher: doublestar" '1' \
    "$(grep -cx 'glob_matcher: doublestar' "$fragment")"

  repo="$work/$adapter"
  make_repo "$repo"
  mkdir -p "$repo/.lefthook" "$repo/${nested_file%/*}"
  cp "$fragment" "$repo/.lefthook/$adapter.yml"
  printf 'extends:\n  - .lefthook/%s.yml\n' "$adapter" >"$repo/lefthook.yml"
  : >"$repo/$root_file"
  : >"$repo/$nested_file"
  git -C "$repo" add -- "$root_file" "$nested_file"
  printf 'import { appendFileSync } from "node:fs";\nappendFileSync(process.env.STUB_LOG, process.argv.slice(2).join(" ") + "\\n");\n' \
    >"$repo/.lefthook/dotnet-format-staged.mjs"

  log="$work/$adapter.log"
  : >"$log"
  (cd "$repo" && STUB_LOG="$log" PATH="$stubs:$PATH" \
    lefthook run pre-commit --command "$command" >/dev/null 2>&1)
  assert_contains "$adapter lane receives a root-level $root_file" "$(cat "$log")" "$root_file"
  assert_contains "$adapter lane receives a nested $nested_file" "$(cat "$log")" "$nested_file"
done

[[ $FAILED -eq 0 ]] || exit 1
