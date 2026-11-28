#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

base="$root/components/lefthook-base/lefthook.yml"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
make_repo "$work"

mkdir -p "$work/.lefthook"
cp "$base" "$work/.lefthook/base.yml"
cat >"$work/lefthook.yml" <<'YAML'
extends:
  - .lefthook/base.yml
YAML

local_log="$work/local.log"
global_log="$work/global.log"

global_bin="$work/global-bin"
mkdir -p "$global_bin" "$work/node_modules/.bin"
cat >"$global_bin/markdownlint-cli2" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$global_log"
SH
cat >"$work/node_modules/.bin/markdownlint-cli2" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$local_log"
SH
chmod +x "$global_bin/markdownlint-cli2" "$work/node_modules/.bin/markdownlint-cli2"
cp "$work/node_modules/.bin/markdownlint-cli2" "$work/local-shim"

npm_log="$work/npm.log"
cat >"$global_bin/npm" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$npm_log"
case "\$(cat "$work/npm.mode")" in
  fail) exit 1 ;;
  install) mkdir -p node_modules/.bin && cp "$work/local-shim" node_modules/.bin/markdownlint-cli2 ;;
esac
SH
chmod +x "$global_bin/npm"
export PATH="$global_bin:$PATH"

cd "$work" || exit 1

printf '# Title\n' >doc.md
git add doc.md

lefthook run pre-commit --command markdownlint >/dev/null 2>&1
assert_exit 'installed local binary passes the lane' 0 "$?"
assert_file_exists 'the lane invoked node_modules/.bin/markdownlint-cli2' "$local_log"
assert_contains 'the staged file reached the local binary' "$(cat "$local_log" 2>/dev/null)" 'doc.md'
assert_file_absent 'the PATH binary stayed unused while the local one exists' "$global_log"
assert_file_absent 'an installed local binary triggers no npm ci' "$npm_log"

rm -rf "$work/node_modules" "$local_log"
printf 'install\n' >"$work/npm.mode"
lefthook run pre-commit --command markdownlint >/dev/null 2>&1
assert_exit 'a missing local binary is installed and the lane passes' 0 "$?"
assert_contains 'the lane ran a quiet npm ci' "$(cat "$npm_log" 2>/dev/null)" 'ci --no-audit --no-fund'
assert_contains 'the staged file reached the installed local binary' "$(cat "$local_log" 2>/dev/null)" 'doc.md'
assert_file_absent 'the PATH binary stayed unused after the install' "$global_log"

rm -rf "$work/node_modules" "$npm_log"
printf 'fail\n' >"$work/npm.mode"
out="$(lefthook run pre-commit --command markdownlint 2>&1)"
assert_nonzero 'a failed install fails the lane' "$?"
assert_file_exists 'the lane attempted npm ci' "$npm_log"
assert_file_absent 'the PATH binary is not a silent fallback' "$global_log"
assert_contains 'the failure names the unresolved local path' "$out" 'not found at node_modules/.bin/markdownlint-cli2'
assert_contains 'the failure carries the install remediation' "$out" 'npm ci'

rm -rf "$work/node_modules"
printf 'empty\n' >"$work/npm.mode"
out="$(lefthook run pre-commit --command markdownlint 2>&1)"
assert_nonzero 'an install without the binary fails the lane' "$?"
assert_file_absent 'the PATH binary is not a fallback after an empty install' "$global_log"
assert_contains 'the empty-install failure names the local path' "$out" 'not found at node_modules/.bin/markdownlint-cli2'

rm -rf "$work/node_modules" "$local_log" "$npm_log"
printf 'install\n' >"$work/npm.mode"
fake_home="$work/fake-home"
no_npm_bin="$work/no-npm-bin"
mkdir -p "$fake_home/.config/shell" "$no_npm_bin"
for cmd in sh bash env git uname timeout mkdir cp cat printf node; do
  if cmd_path="$(mise which "$cmd" 2>/dev/null || command -v "$cmd" 2>/dev/null)"; then
    ln -s "$cmd_path" "$no_npm_bin/$cmd"
  fi
done
cat >"$fake_home/.config/shell/env.sh" <<SH
export PATH="$global_bin:\$PATH"
SH
lefthook_bin="$(mise which lefthook 2>/dev/null || command -v lefthook)"
HOME="$fake_home" PATH="$no_npm_bin" "$lefthook_bin" run pre-commit --command markdownlint >/dev/null 2>&1
assert_exit 'missing npm on PATH recovers via env.sh' 0 "$?"
assert_contains 'env.sh recovery ran quiet npm ci' "$(cat "$npm_log" 2>/dev/null)" 'ci --no-audit --no-fund'
assert_contains 'env.sh recovery ran installed local binary' "$(cat "$local_log" 2>/dev/null)" 'doc.md'

[[ $FAILED -eq 0 ]] || exit 1
