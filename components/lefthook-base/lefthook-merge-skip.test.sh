#!/usr/bin/env bash
# Pins WHERE the merge/rebase skip lives, which is a security property and not a
# style one. The skip must sit on each hygiene command, never on the pre-commit
# hook: lefthook's `extends` merges every fragment plus the consumer's own root
# file into ONE hook, so a hook-level skip short-circuits the whole thing —
# gitleaks and any repository-owned security lane included — and the consumer
# has nothing in its own file to suggest that happened.
#
# The observable is a recording shim per lane. Each lane writes a marker when it
# runs, so "did this lane execute during a merge commit" is an artifact on disk.
# Merge state is forced by writing .git/MERGE_HEAD rather than by constructing a
# real conflict: lefthook reads that file to decide, and a synthetic conflict
# would add fixture surface without changing what is under test.
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

# A consumer that extends base AND declares its own security lane, which is the
# shape the bypass actually harmed: the guard is repo-owned, so nothing in the
# consumer's file mentions a skip, yet a hook-level skip in base would disable it.
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

# --- Ordinary commit: every lane runs (the baseline the merge case is read against)
lefthook run pre-commit >/dev/null 2>&1
assert_file_exists 'baseline: gitleaks runs on an ordinary commit' "$work/gitleaks.log"
assert_file_exists 'baseline: typos runs on an ordinary commit' "$work/typos.log"
assert_file_exists 'baseline: the consumer guard runs on an ordinary commit' "$work/consumer-guard-shim.log"

rm -f "$work"/*.log

# --- Merge commit: security lanes MUST still run, hygiene lanes must not.
git rev-parse HEAD >"$work/.git/MERGE_HEAD"
lefthook run pre-commit >/dev/null 2>&1

assert_file_exists 'gitleaks still runs during a merge commit' "$work/gitleaks.log"
assert_file_exists 'a consumer-owned security lane still runs during a merge commit' \
  "$work/consumer-guard-shim.log"
assert_file_absent 'typos opts out of a merge commit' "$work/typos.log"
assert_file_absent 'editorconfig opts out of a merge commit' "$work/editorconfig-checker.log"

# --- The structural assertion: no hook-level skip may reappear in the fragment.
# A per-command skip is indented under `commands:`; a hook-level one sits at the
# hook's own indent. Only the latter has the fleet-wide blast radius.
assert_eq 'the fragment declares no hook-level skip' '0'   "$(grep -c '^  skip:' "$base" || true)"

# --- Every lane in every fragment accounts for merge/rebase explicitly.
# Codex caught the first version of this change updating only two of the five
# adapters, which silently switched ShellCheck, Biome and dotnet-format on for
# merge commits. With the blanket skip gone, "I forgot one" is no longer a
# no-op, so the invariant is asserted over the whole component set rather than
# over the files this change happened to touch. One lane per `run:`, one opt-out
# per `skip:`; the ONLY lane allowed to lack one is gitleaks, which is the
# entire point of the fix.
for fragment in "$root"/components/lefthook-*/lefthook.yml; do
  lanes="$(grep -c '^ *run:' "$fragment" || true)"
  skips="$(grep -c '^ *skip:' "$fragment" || true)"
  expected="$lanes"
  # base carries gitleaks, the one deliberate exemption.
  if [[ "$fragment" == *"/lefthook-base/"* ]]; then
    expected="$((lanes - 1))"
  fi
  assert_eq "every lane in $(basename "$(dirname "$fragment")") declares merge/rebase intent" \
    "$expected" "$skips"
done

[[ $FAILED -eq 0 ]] || exit 1
