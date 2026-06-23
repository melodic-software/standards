#!/usr/bin/env bash
# Tests the lefthook module end-to-end: a consumer's root config that `extends`
# the shipped base.yml gets the base's lanes, a lane fires on a non-conforming
# staged file and passes a clean one, and a consumer can opt a lane out with
# `skip: true` from its own root config without editing the base. The shellcheck
# lane is the representative (single static binary, no node_modules resolution);
# the other base lanes are isolated out with `--command`. Skips cleanly when
# either tool (lefthook or the shellcheck engine) is absent.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
base="$root/modules/lefthook/base.yml"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'
command -v shellcheck >/dev/null 2>&1 || skip_suite 'shellcheck not installed'

FAILED=0
CASE_NUM=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
make_repo "$work"

# A consumer repo: vendor the base fragment at its canonical path and compose it
# from a root config via extends — the supported, decoupled adoption shape.
mkdir -p "$work/modules/lefthook"
cp "$base" "$work/modules/lefthook/base.yml"
cat >"$work/lefthook.yml" <<'YAML'
extends:
  - modules/lefthook/base.yml
YAML

cd "$work" || exit 1

# A clean script and a non-conforming one (unterminated `if` → ShellCheck SC1046,
# an error-severity finding that reliably exits non-zero across versions).
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

# Case 1: the base shellcheck lane, reached via extends, passes a clean staged file.
git add clean.sh
lefthook run pre-commit --command shellcheck >/dev/null 2>&1
assert_exit 'clean staged file passes the extended shellcheck lane' 0 $?
git rm --cached -q clean.sh

# Case 2: it fires on a non-conforming staged file.
git add bad.sh
out="$(lefthook run pre-commit --command shellcheck 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass 'non-conforming staged file fails the lane'
else
  fail 'non-conforming staged file fails the lane' "expected non-zero, got 0"
fi
assert_contains 'failure surfaces a ShellCheck code' "$out" 'SC1046'

# Case 3: a consumer disables the lane from its own root config (skip: true merges
# onto the inherited lane) — the bad file no longer blocks. Proves the open/closed
# opt-out without editing the base fragment.
cat >lefthook.yml <<'YAML'
extends:
  - modules/lefthook/base.yml
pre-commit:
  commands:
    shellcheck:
      skip: true
YAML
lefthook run pre-commit --command shellcheck >/dev/null 2>&1
assert_exit 'consumer skip:true opts the lane out' 0 $?

[[ $FAILED -eq 0 ]] || exit 1
