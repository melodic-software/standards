#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

fragment="$root/components/lefthook-shellcheck/lefthook.yml"
base="$root/components/lefthook-base/lefthook.yml"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'
command -v shellcheck >/dev/null 2>&1 || skip_suite 'shellcheck not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
make_repo "$work"

mkdir -p "$work/.lefthook"
cp "$base" "$work/.lefthook/base.yml"
cp "$fragment" "$work/.lefthook/shellcheck.yml"
cat >"$work/lefthook.yml" <<'YAML'
extends:
  - .lefthook/base.yml
  - .lefthook/shellcheck.yml
YAML

cd "$work" || exit 1

cat >clean.sh <<'SH'
#!/usr/bin/env bash
foo=bar
echo "$foo"
SH
cat >bad.sh <<'SH'
#!/usr/bin/env bash
if [ "$foo" = bar ]
then echo hi
SH

git add clean.sh
lefthook run pre-commit --command shellcheck >/dev/null 2>&1
assert_exit 'clean staged file passes the extended shellcheck lane' 0 "$?"
git rm --cached -q clean.sh

git add bad.sh
out="$(lefthook run pre-commit --command shellcheck 2>&1)"
assert_nonzero 'non-conforming staged file fails the lane' "$?"
assert_contains 'failure surfaces a ShellCheck code' "$out" 'SC1046'

cat >lefthook.yml <<'YAML'
extends:
  - .lefthook/base.yml
  - .lefthook/shellcheck.yml
pre-commit:
  commands:
    shellcheck:
      skip: true
YAML
out="$(lefthook run pre-commit --command shellcheck 2>&1)"
assert_contains 'consumer skip:true opts the lane out' "$out" 'shellcheck (skip)'
assert_not_contains 'skipped lane does not run ShellCheck' "$out" 'SC1046'

[[ $FAILED -eq 0 ]] || exit 1
