#!/usr/bin/env bash
# Tests how the base markdownlint lane resolves its executable: it must run the
# consumer's own node_modules/.bin/markdownlint-cli2. When that binary is absent
# it runs npm ci and lints; if the install fails or leaves no binary, it must
# hard-fail with a remediation rather than silently running whatever
# markdownlint-cli2 happens to sit on PATH (an arbitrary global version lints
# against the wrong rules while reporting success). Recording shims stand in for
# both binaries and npm, so no real markdownlint engine or install is needed and
# only the lefthook engine gates the suite.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

base="$root/components/lefthook-base/lefthook.yml"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
make_repo "$work"

# A consumer repo: adopt the managed fragment under the tool-native .lefthook
# slice and compose it from a root config via extends.
mkdir -p "$work/.lefthook"
cp "$base" "$work/.lefthook/base.yml"
cat >"$work/lefthook.yml" <<'YAML'
extends:
  - .lefthook/base.yml
YAML

local_log="$work/local.log"
global_log="$work/global.log"

# Two recording shims: the repo-local binary the lane must resolve, and a
# same-named binary first on PATH standing in for a global install. Each logs
# its argv, so "was it invoked, and with the staged file" is an artifact on disk
# rather than an inference from exit codes. Both exit 0 — a non-zero exit would
# make an accidental global invocation indistinguishable from the intended
# missing-dependency failure.
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

# A recording npm shim, so no real install or network runs. npm.mode selects
# its behavior: "fail" exits 1, "install" restores the local binary, "empty"
# exits 0 without creating anything.
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

# Case 1: with the local binary installed, the lane runs it — not the one on PATH.
rc=0
lefthook run pre-commit --command markdownlint >/dev/null 2>&1 || rc=$?
assert_exit 'installed local binary passes the lane' 0 "$rc"
assert_file_exists 'the lane invoked node_modules/.bin/markdownlint-cli2' "$local_log"
assert_contains 'the staged file reached the local binary' "$(cat "$local_log" 2>/dev/null)" 'doc.md'
assert_file_absent 'the PATH binary stayed unused while the local one exists' "$global_log"
assert_file_absent 'an installed local binary triggers no npm ci' "$npm_log"

# Case 2: uninstall the local binary; npm ci installs it. The lane installs on
# demand, then lints with the local binary, not the one on PATH.
rm -rf "$work/node_modules" "$local_log"
printf 'install\n' >"$work/npm.mode"
rc=0
lefthook run pre-commit --command markdownlint >/dev/null 2>&1 || rc=$?
assert_exit 'a missing local binary is installed and the lane passes' 0 "$rc"
assert_contains 'the lane ran a quiet npm ci' "$(cat "$npm_log" 2>/dev/null)" 'ci --no-audit --no-fund'
assert_contains 'the staged file reached the installed local binary' "$(cat "$local_log" 2>/dev/null)" 'doc.md'
assert_file_absent 'the PATH binary stayed unused after the install' "$global_log"

# Case 3: npm ci fails (no network, no lockfile). The lane must not fall through
# to PATH, and the missing dependency must surface as an actionable failure.
rm -rf "$work/node_modules" "$npm_log"
printf 'fail\n' >"$work/npm.mode"
out="$(lefthook run pre-commit --command markdownlint 2>&1)"
assert_nonzero 'a failed install fails the lane' "$?"
assert_file_exists 'the lane attempted npm ci' "$npm_log"
assert_file_absent 'the PATH binary is not a silent fallback' "$global_log"
assert_contains 'the failure names the unresolved local path' "$out" 'not found at node_modules/.bin/markdownlint-cli2'
assert_contains 'the failure carries the install remediation' "$out" 'npm ci'

# Case 4: npm ci succeeds but installs no markdownlint-cli2 (a lockfile that
# does not pin it). The lane re-checks and fails with the remediation.
rm -rf "$work/node_modules"
printf 'empty\n' >"$work/npm.mode"
out="$(lefthook run pre-commit --command markdownlint 2>&1)"
assert_nonzero 'an install without the binary fails the lane' "$?"
assert_file_absent 'the PATH binary is not a fallback after an empty install' "$global_log"
assert_contains 'the empty-install failure names the local path' "$out" 'not found at node_modules/.bin/markdownlint-cli2'

[[ $FAILED -eq 0 ]] || exit 1
