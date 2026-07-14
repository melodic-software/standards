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

# Production coverage contract: the runner policy is one atomic runtime
# component in each enrolled private consumer. Its dependency lockfile travels
# with the executable, and node-runtime makes the engine pin explicit.
actual_manifest="$root/distribution/sync-manifest.yml"
assert_eq 'runner-policy requires the shared Node runtime pin' 'node-runtime' \
  "$(yq -r '.components.runner-policy.requires | join(",")' "$actual_manifest")"
assert_eq 'runner-policy materializes exactly four runtime files' '4' \
  "$(yq -r '.components.runner-policy.files | length' "$actual_manifest")"

for mapping in \
  'components/runner-policy/runner-policy.mjs=.github/standards/runner-policy/runner-policy.mjs' \
  'components/runner-policy/policy.json=.github/standards/runner-policy/policy.json' \
  'components/runner-policy/package.json=.github/standards/runner-policy/package.json' \
  'components/runner-policy/package-lock.json=.github/standards/runner-policy/package-lock.json'; do
  source_path="${mapping%%=*}"
  destination_path="${mapping#*=}"
  assert_eq "runner-policy mapping is exact: $source_path" "$destination_path" \
    "$(SOURCE_PATH="$source_path" yq -r '.components.runner-policy.files[strenv(SOURCE_PATH)]' "$actual_manifest")"
done

runner_policy_source='components/runner-policy/runner-policy.mjs'
runner_policy_destination='.github/standards/runner-policy/runner-policy.mjs'
lefthook_dotnet_source='components/lefthook-dotnet/dotnet-format-staged.mjs'
lefthook_dotnet_destination='.lefthook/dotnet-format-staged.mjs'
assert_eq 'runner-policy production CLI source is executable in the Git index' '100755' \
  "$(git -C "$root" ls-files --stage -- "$runner_policy_source" | awk '{print $1}')"
assert_eq 'lefthook-dotnet production CLI source is executable in the Git index' '100755' \
  "$(git -C "$root" ls-files --stage -- "$lefthook_dotnet_source" | awk '{print $1}')"

# Exercise every production target that carries either CLI, not only the
# generic executable fixture. Linux is the deployment environment that records
# worktree modes in materialization PR indexes; source-index assertions remain
# platform-independent and fail before apply if either production mode regresses.
while IFS=$'\t' read -r production_slug includes_dotnet; do
  production_target="$tmp_root/production-${production_slug//\//-}"
  make_target "$production_target"
  out="$(
    "$engine" apply \
      --source-root "$root" \
      --manifest distribution/sync-manifest.yml \
      --target "$production_slug" \
      --target-root "$production_target" 2>&1
  )"; rc=$?
  assert_exit "$production_slug production mapping applies" 0 "$rc"
  assert_contains "$production_slug runner-policy apply reports executable mode" "$out" \
    "$runner_policy_source -> $runner_policy_destination (100755)"
  assert_file_exists "$production_slug runner-policy CLI reaches the target" \
    "$production_target/$runner_policy_destination"
  if [[ "$(uname -s)" == Linux* ]]; then
    assert_eq "$production_slug runner-policy target worktree mode is executable" 755 \
      "$(stat -c '%a' "$production_target/$runner_policy_destination")"
    git -C "$production_target" add -- "$runner_policy_destination"
    assert_eq "$production_slug runner-policy target index mode is executable" 100755 \
      "$(git -C "$production_target" ls-files --stage -- "$runner_policy_destination" | awk '{print $1}')"
  else
    skip_case "$production_slug runner-policy worktree mode requires a mode-preserving filesystem"
    skip_case "$production_slug runner-policy index mode requires a mode-preserving filesystem"
  fi

  if [[ "$includes_dotnet" == true ]]; then
    assert_contains "$production_slug lefthook-dotnet apply reports executable mode" "$out" \
      "$lefthook_dotnet_source -> $lefthook_dotnet_destination (100755)"
    assert_file_exists "$production_slug lefthook-dotnet CLI reaches the target" \
      "$production_target/$lefthook_dotnet_destination"
    if [[ "$(uname -s)" == Linux* ]]; then
      assert_eq "$production_slug lefthook-dotnet target worktree mode is executable" 755 \
        "$(stat -c '%a' "$production_target/$lefthook_dotnet_destination")"
      git -C "$production_target" add -- "$lefthook_dotnet_destination"
      assert_eq "$production_slug lefthook-dotnet target index mode is executable" 100755 \
        "$(git -C "$production_target" ls-files --stage -- "$lefthook_dotnet_destination" | awk '{print $1}')"
    else
      skip_case "$production_slug lefthook-dotnet worktree mode requires a mode-preserving filesystem"
      skip_case "$production_slug lefthook-dotnet index mode requires a mode-preserving filesystem"
    fi
  fi
done < <(
  yq -r \
    '.targets | to_entries[] |
     select(.value.managed | any_c(. == "runner-policy" or . == "lefthook-dotnet")) |
     [.key, (.value.managed | any_c(. == "lefthook-dotnet"))] | @tsv' \
    "$actual_manifest"
)

expected_runner_policy_targets='["melodic-software/claude-code-plugins","melodic-software/dotfiles","melodic-software/github-iac","melodic-software/medley","melodic-software/provisioning"]'
actual_runner_policy_targets="$(
  yq -o=json -I=0 \
    '[.targets | to_entries[] | select(.value.managed[]? == "runner-policy") | .key]' \
    "$actual_manifest"
)"
assert_eq 'runner-policy covers exactly the five enrolled private consumers' \
  "$expected_runner_policy_targets" "$actual_runner_policy_targets"
assert_eq 'source Dependabot covers the runner-policy dependency root exactly once' '1' \
  "$(
    yq -r \
      '[.updates[] | select(.package-ecosystem == "npm" and .directory == "/components/runner-policy")] | length' \
      "$root/.github/dependabot.yml"
  )"

assert_eq 'lefthook-dotnet distributes its argv-safe staged wrapper' \
  '.lefthook/dotnet-format-staged.mjs' \
  "$(
    yq -r \
      '.components.lefthook-dotnet.files."components/lefthook-dotnet/dotnet-format-staged.mjs"' \
      "$actual_manifest"
  )"
assert_eq 'lefthook-dotnet declares its direct Node runtime dependency' '1' \
  "$(
    yq -r \
      '[.components.lefthook-dotnet.requires[] | select(. == "node-runtime")] | length' \
      "$actual_manifest"
  )"

assert_eq 'lefthook-powershell materializes its complete isolated adapter' '3' \
  "$(yq -r '.components.lefthook-powershell.files | length' "$actual_manifest")"
for mapping in \
  'components/lefthook-powershell/psscriptanalyzer-staged.ps1=.lefthook/psscriptanalyzer-staged.ps1' \
  'components/lefthook-powershell/psscriptanalyzer-target.ps1=.lefthook/psscriptanalyzer-target.ps1'; do
  source_path="${mapping%%=*}"
  destination_path="${mapping#*=}"
  assert_eq "lefthook-powershell mapping is exact: $source_path" "$destination_path" \
    "$(SOURCE_PATH="$source_path" yq -r '.components.lefthook-powershell.files[strenv(SOURCE_PATH)]' "$actual_manifest")"
done

assert_eq 'Ruff materializes at its root-canonical discovery path' \
  'ruff.toml' \
  "$(yq -r '.components.ruff.files."ruff.toml"' "$actual_manifest")"
assert_eq 'Lefthook Python materializes as a composable fragment' \
  '.lefthook/python.yml' \
  "$(yq -r '.components.lefthook-python.files."components/lefthook-python/lefthook.yml"' "$actual_manifest")"
assert_eq 'Lefthook Python carries its complete direct dependencies' \
  'lefthook-base,ruff' \
  "$(yq -r '.components.lefthook-python.requires | join(",")' "$actual_manifest")"
assert_eq 'Pyright materializes as an inheritable base below the consumer root' \
  '.github/standards/pyright/pyrightconfig.json' \
  "$(yq -r '.components.pyright.files."components/pyright/pyrightconfig.json"' "$actual_manifest")"

for component in ruff lefthook-python pyright; do
  assert_eq "dotfiles enrolls the managed Python component exactly once: $component" '1' \
    "$(COMPONENT="$component" yq -r \
      '[.targets."melodic-software/dotfiles".managed[] | select(. == strenv(COMPONENT))] | length' \
      "$actual_manifest")"
done

[[ $FAILED -eq 0 ]] || exit 1
