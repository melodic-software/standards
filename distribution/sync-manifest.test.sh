#!/usr/bin/env bash
# Contract tests for the schema-v2 validator/materializer.
set -uo pipefail

root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"
engine="$root/distribution/sync-manifest.sh"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

command -v yq >/dev/null 2>&1 || skip_suite 'Mike Farah yq v4 is not installed'
[[ "$(yq --version 2>/dev/null)" =~ version[[:space:]]+v?4\. ]] ||
  skip_suite 'Mike Farah yq v4 is required'

valid_manifest() {
  cat <<'YAML'
version: 2

components:
  base:
    files:
      docs/adr/README.md: docs/adr/README.md
      policy.txt: .policy
      scripts/check.sh: tools/check.sh
  consumer:
    files:
      consumer.txt: consumer.txt
    requires:
      - base

targets:
  alpha/one:
    managed:
      - base
      - consumer
  beta/two:
    managed:
      - consumer
    locally-owned:
      - base
YAML
}

make_source() {
  local dir="$1" manifest="$2"
  make_repo "$dir"
  mkdir -p "$dir/docs/adr" "$dir/scripts"
  printf 'ADR guidance\n' >"$dir/docs/adr/README.md"
  printf 'policy\n' >"$dir/policy.txt"
  printf 'consumer\n' >"$dir/consumer.txt"
  printf '#!/usr/bin/env bash\nprintf check\n' >"$dir/scripts/check.sh"
  printf '%s\n' "$manifest" >"$dir/manifest.yml"
  git -C "$dir" add docs/adr/README.md policy.txt consumer.txt scripts/check.sh manifest.yml
  git -C "$dir" update-index --chmod=+x scripts/check.sh
  git -C "$dir" commit -m fixtures -q
}

make_target() {
  local dir="$1"
  make_repo "$dir"
}

run_engine() {
  local source="$1"
  shift
  "$engine" "$@" --source-root "$source" --manifest manifest.yml
}

manifest="$(valid_manifest)"
source_repo="$tmp_root/valid-source"
make_source "$source_repo" "$manifest"

out="$(run_engine "$source_repo" validate 2>&1)"; rc=$?
assert_exit 'valid multi-file manifest validates' 0 "$rc"
assert_contains 'validation reports catalog size' "$out" '2 components, 2 targets'

out="$(run_engine "$source_repo" matrix --targets ' beta/two , alpha/one ' 2>&1)"; rc=$?
assert_exit 'matrix accepts an exact whitespace-trimmed filter' 0 "$rc"
assert_eq 'matrix stays in manifest order' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one"},{"repo":"beta/two","repo_owner":"beta","repo_name":"two"}]}' \
  "$out"

out="$(run_engine "$source_repo" plan --targets beta/two 2>&1)"; rc=$?
assert_exit 'filtered plan succeeds' 0 "$rc"
assert_contains 'plan logs managed mapping' "$out" 'consumer.txt -> consumer.txt'
assert_contains 'plan identifies local ownership' "$out" 'locally-owned base (not modified)'
assert_not_contains 'plan excludes unselected target' "$out" 'alpha/one'

# Regression: target selection must not inherit the false status of the last
# manifest target when that target is outside the filter.
out="$(run_engine "$source_repo" matrix --targets alpha/one 2>&1)"; rc=$?
assert_exit 'filtered matrix succeeds when the last manifest target is omitted' 0 "$rc"
assert_eq 'filtered matrix contains only the requested earlier target' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one"}]}' \
  "$out"

out="$(run_engine "$source_repo" plan --targets alpha/one 2>&1)"; rc=$?
assert_exit 'filtered plan succeeds when the last manifest target is omitted' 0 "$rc"
assert_contains 'earlier-target plan includes the requested target' "$out" 'alpha/one'
assert_not_contains 'earlier-target plan excludes the last manifest target' "$out" 'beta/two'

out="$(run_engine "$source_repo" mappings --target beta/two 2>&1)"; rc=$?
assert_exit 'managed mapping renderer succeeds' 0 "$rc"
assert_contains 'mapping renderer includes managed component' "$out" '**consumer**'
assert_not_contains 'mapping renderer excludes locally-owned payload' "$out" '**base**'

target_repo="$tmp_root/target-beta"
make_target "$target_repo"
printf 'local policy\n' >"$target_repo/.policy"
git -C "$target_repo" add .policy
git -C "$target_repo" commit -m local -q
out="$(run_engine "$source_repo" apply --target beta/two --target-root "$target_repo" 2>&1)"; rc=$?
assert_exit 'apply accepts a dependency satisfied by locally-owned' 0 "$rc"
assert_eq 'managed file content copied' 'consumer' "$(tr -d '\r\n' <"$target_repo/consumer.txt")"
assert_eq 'locally-owned file remains untouched' 'local policy' "$(tr -d '\r\n' <"$target_repo/.policy")"
assert_file_absent 'locally-owned component support file is not copied' "$target_repo/tools/check.sh"

target_repo="$tmp_root/target-alpha"
make_target "$target_repo"
out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"; rc=$?
assert_exit 'multi-file component applies in one operation' 0 "$rc"
assert_file_exists 'root destination copied' "$target_repo/.policy"
assert_file_exists 'nested destination copied' "$target_repo/tools/check.sh"
assert_file_exists 'dependent component copied' "$target_repo/consumer.txt"
if [[ "$(uname -s)" == Linux* ]]; then
  assert_eq 'executable source mode reproduced' 755 "$(stat -c '%a' "$target_repo/tools/check.sh")"
  assert_eq 'regular source mode reproduced' 644 "$(stat -c '%a' "$target_repo/.policy")"
else
  skip_case 'worktree executable-bit assertion requires a mode-preserving filesystem'
fi

# Destination checks are a complete preflight: a later unsafe destination must
# stop the operation before an earlier valid mapping is copied.
target_repo="$tmp_root/target-preflight"
make_target "$target_repo"
printf 'untracked collision\n' >"$target_repo/consumer.txt"
out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"; rc=$?
assert_nonzero 'untracked destination is rejected' "$rc"
assert_contains 'untracked rejection is explicit' "$out" 'refusing to overwrite untracked destination'
assert_file_absent 'failed preflight writes none of the earlier files' "$target_repo/.policy"
assert_file_absent 'failed preflight creates no earlier nested file' "$target_repo/tools/check.sh"

for filter in 'unknown/repo' 'alpha/one,alpha/one' 'alpha/one,,beta/two' ',alpha/one'; do
  out="$(run_engine "$source_repo" matrix --targets "$filter" 2>&1)"; rc=$?
  assert_nonzero "invalid target filter fails: $filter" "$rc"
done

invalid_case() {
  local label="$1" bad_manifest="$2" needle="$3"
  local slug dir output status
  slug="${label//[^A-Za-z0-9]/-}"
  dir="$tmp_root/invalid-$slug"
  make_source "$dir" "$bad_manifest"
  output="$(run_engine "$dir" validate 2>&1)"; status=$?
  assert_nonzero "$label is rejected" "$status"
  assert_contains "$label has a useful diagnostic" "$output" "$needle"
}

bad="${manifest/version: 2/version: 1}"
invalid_case 'wrong version' "$bad" 'integer 2'

bad="$manifest"$'\n''unexpected: true'
invalid_case 'unknown root key' "$bad" 'unknown key'

bad="version: 2"$'\n'"version: 2"$'\n'"${manifest#*$'\n'}"
invalid_case 'duplicate YAML key' "$bad" 'duplicate mapping key'

bad="${manifest/policy.txt: .policy/policy\/..\/policy.txt: .policy}"
invalid_case 'unsafe traversal source' "$bad" 'unsafe source path'

bad="${manifest/consumer.txt: consumer.txt/consumer.txt: .policy}"
invalid_case 'destination ownership collision' "$bad" 'owned by both'

bad="${manifest/policy.txt: .policy/policy.txt: path}"
bad="${bad/consumer.txt: consumer.txt/consumer.txt: path\/child}"
invalid_case 'destination file before child collision' "$bad" 'file/directory conflict'

bad="${manifest/policy.txt: .policy/policy.txt: path\/child}"
bad="${bad/consumer.txt: consumer.txt/consumer.txt: path}"
invalid_case 'destination child before file collision' "$bad" 'file/directory conflict'

bad="${manifest/policy.txt: .policy/policy.txt: bad\"name}"
invalid_case 'destination outside portable path alphabet' "$bad" 'unsafe destination path'

bad="$(printf '%s\n' "$manifest" | sed 's|^  alpha/one:|  Alpha/one:|')"
invalid_case 'noncanonical uppercase target' "$bad" 'expected lowercase owner/repo'

# Remove every selected base entry while retaining consumer's dependency.
bad="$(printf '%s\n' "$manifest" |
  awk 'BEGIN { in_targets = 0 }
       /^targets:/ { in_targets = 1 }
       !(in_targets && $0 == "      - base") { print }')"
invalid_case 'missing target dependency' "$bad" "does not select required 'base'"

# Make base depend on consumer, completing a two-node cycle.
bad="$(printf '%s\n' "$manifest" |
  sed '/^  base:$/a\    requires:\n      - consumer')"
invalid_case 'dependency cycle' "$bad" 'dependency cycle'

# The source must be tracked even if a same-named worktree file exists.
source_repo="$tmp_root/untracked-source"
make_source "$source_repo" "$manifest"
git -C "$source_repo" rm --cached policy.txt -q
git -C "$source_repo" commit -m 'untrack policy' -q
out="$(run_engine "$source_repo" validate 2>&1)"; rc=$?
assert_nonzero 'untracked source is rejected' "$rc"
assert_contains 'untracked source diagnostic identifies tracked-file contract' \
  "$out" 'exactly one tracked stage-0 file'

source_repo="$tmp_root/dirty-source"
make_source "$source_repo" "$manifest"
printf 'unreviewed worktree bytes\n' >"$source_repo/policy.txt"
out="$(run_engine "$source_repo" validate 2>&1)"; rc=$?
assert_nonzero 'dirty tracked source is rejected' "$rc"
assert_contains 'dirty source diagnostic identifies index mismatch' \
  "$out" 'worktree bytes differ from the indexed object'

if ln -s policy.txt "$tmp_root/symlink-probe" 2>/dev/null; then
  rm "$tmp_root/symlink-probe"
  source_repo="$tmp_root/valid-source"
  target_repo="$tmp_root/target-symlink"
  make_target "$target_repo"
  mkdir -p "$target_repo/tools"
  ln -s ../escape "$target_repo/tools/check.sh"
  out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"; rc=$?
  assert_nonzero 'symlink destination is rejected' "$rc"
else
  skip_case 'symlink destination case unavailable on this platform'
fi

[[ $FAILED -eq 0 ]] || exit 1
