#!/usr/bin/env bash
# Pins who decides whether a lane sits out merge and rebase commits. The answer
# is the consumer, never a fragment, and both halves are load-bearing.
#
# A hook-level `skip` in a fragment short-circuits the whole merged pre-commit
# hook -- lefthook's `extends` folds every fragment and the consumer's root file
# into one hook, and the extended file's setting wins. That is how a
# `skip: [merge, rebase]` in the base fragment disabled gitleaks on merge
# commits, and with it any security lane the CONSUMER declared in its own file.
#
# Moving the skip onto the commands fixes that and breaks something else: the
# extended file still wins, so a `skip` on a lane defeats the consumer's
# documented `skip: true` override for that lane. So no fragment declares one at
# all, and a consumer that wants the opt-out writes it in its own root file.
#
# The observable is a recording shim per lane: each writes a marker when it
# runs, so "did this lane execute during a merge commit" is an artifact on disk.
# Merge state is forced by writing .git/MERGE_HEAD, which is what lefthook
# reads; a synthetic conflict would add fixture surface without changing what is
# under test.
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

# A consumer that extends base AND declares its own security lane -- the shape
# the hook-level skip actually harmed, since nothing in the consumer's file
# mentioned a skip yet its guard was disabled anyway.
cat >"$work/lefthook.yml" <<'YAML'
extends:
  - .lefthook/base.yml

pre-commit:
  commands:
    consumer-guard:
      run: consumer-guard-shim
YAML

bin="$work/bin"
mkdir -p "$bin" "$work/node_modules/.bin"
for lane in typos gitleaks editorconfig-checker consumer-guard-shim; do
  cat >"$bin/$lane" <<SH
#!/usr/bin/env bash
printf 'ran\n' >>"$work/$lane.log"
SH
  chmod +x "$bin/$lane"
done
export PATH="$bin:$PATH"

cd "$work" || exit 1
printf 'hello\n' >file.txt
git add file.txt

# --- Ordinary commit: the baseline the merge case is read against.
lefthook run pre-commit >/dev/null 2>&1
assert_file_exists 'baseline: gitleaks runs on an ordinary commit' "$work/gitleaks.log"
assert_file_exists 'baseline: the consumer guard runs on an ordinary commit' \
  "$work/consumer-guard-shim.log"

rm -f "$work"/*.log

# --- Merge commit: the regression this file exists for. Both security lanes
# must still run; before the fix neither did, and the hook reported
# "pre-commit (skip) hook setting" without executing anything at all.
git rev-parse HEAD >"$work/.git/MERGE_HEAD"
lefthook run pre-commit >/dev/null 2>&1

assert_file_exists 'gitleaks still runs during a merge commit' "$work/gitleaks.log"
assert_file_exists 'a consumer-owned security lane still runs during a merge commit' \
  "$work/consumer-guard-shim.log"
rm -f "$work/.git/MERGE_HEAD"

# --- The consumer keeps both decisions. It can opt a lane out of merge commits
# without the fragment's help, and (covered in full by lefthook-shellcheck's
# contract test) its `skip: true` override still works -- which a fragment-level
# skip on the same lane would have silently defeated.
cat >"$work/lefthook.yml" <<'YAML'
extends:
  - .lefthook/base.yml

pre-commit:
  commands:
    typos:
      skip:
        - merge
        - rebase
YAML
rm -f "$work"/*.log
git rev-parse HEAD >"$work/.git/MERGE_HEAD"
lefthook run pre-commit >/dev/null 2>&1
assert_file_absent 'a consumer can opt a lane out of merge commits itself' "$work/typos.log"
assert_file_exists 'and doing so leaves gitleaks running' "$work/gitleaks.log"
rm -f "$work/.git/MERGE_HEAD"

# --- The structural invariant: no fragment may declare a skip, at any level.
# Asserted over the whole component set rather than the files a given change
# touches, because the first cut of this fix updated two adapters and missed
# three. Comment text mentioning `skip:` does not match -- the pattern is
# anchored to the key.
for fragment in "$root"/components/lefthook-*/lefthook.yml; do
  assert_eq "$(basename "$(dirname "$fragment")") declares no skip; the consumer owns that call" \
    '0' "$(grep -c '^ *skip:' "$fragment" || true)"
done

[[ $FAILED -eq 0 ]] || exit 1
