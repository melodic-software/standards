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

lefthook run pre-commit >/dev/null 2>&1
assert_file_exists 'baseline: gitleaks runs on an ordinary commit' "$work/gitleaks.log"
assert_file_exists 'baseline: the consumer guard runs on an ordinary commit' \
  "$work/consumer-guard-shim.log"

rm -f "$work"/*.log

git rev-parse HEAD >"$work/.git/MERGE_HEAD"
lefthook run pre-commit >/dev/null 2>&1

assert_file_exists 'gitleaks still runs during a merge commit' "$work/gitleaks.log"
assert_file_exists 'a consumer-owned security lane still runs during a merge commit' \
  "$work/consumer-guard-shim.log"
rm -f "$work/.git/MERGE_HEAD"

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

for fragment in "$root"/components/lefthook-*/lefthook.yml "$root"/components/lefthook-*/lefthook-remote.yml; do
  assert_eq "${fragment#"$root"/} declares no skip; the consumer owns that call" \
    '0' "$(grep -c '^ *skip:' "$fragment" || true)"
done

[[ $FAILED -eq 0 ]] || exit 1
