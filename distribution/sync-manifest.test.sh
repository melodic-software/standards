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
[[ -f "$root/distribution/node_modules/ajv/package.json" ]] ||
  skip_suite 'distribution dependencies are not installed (run npm ci --prefix distribution)'

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
  local dir="$1" target="${2:-alpha/one}"
  make_repo "$dir"
  git -C "$dir" remote add origin "https://github.com/$target.git"
}

run_engine() {
  local source="$1"
  shift
  "$engine" "$@" --source-root "$source" --manifest manifest.yml
}

manifest="$(valid_manifest)"
source_repo="$tmp_root/valid-source"
make_source "$source_repo" "$manifest"

out="$({ printf '%s\n' "$manifest" | yq eval -o=json -I=0 '.' -; } |
  node "$root/distribution/validate-sync-manifest.mjs" 2>&1)"
rc=$?
assert_exit 'schema and Bash entrypoint agree that the fixture structure is valid' 0 "$rc"

out="$(run_engine "$source_repo" validate 2>&1)"
rc=$?
assert_exit 'valid multi-file manifest validates' 0 "$rc"
assert_contains 'validation reports catalog size' "$out" '2 components, 2 targets'

out="$(run_engine "$source_repo" matrix --targets ' beta/two , alpha/one ' 2>&1)"
rc=$?
assert_exit 'matrix accepts an exact whitespace-trimmed filter' 0 "$rc"
assert_eq 'matrix stays in manifest order' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one"},{"repo":"beta/two","repo_owner":"beta","repo_name":"two"}]}' \
  "$out"

out="$(run_engine "$source_repo" plan --targets beta/two 2>&1)"
rc=$?
assert_exit 'filtered plan succeeds' 0 "$rc"
assert_contains 'plan logs managed mapping' "$out" 'consumer.txt -> consumer.txt'
assert_contains 'plan identifies local ownership' "$out" 'locally-owned base (not modified)'
assert_not_contains 'plan excludes unselected target' "$out" 'alpha/one'

# Regression: target selection must not inherit the false status of the last
# manifest target when that target is outside the filter.
out="$(run_engine "$source_repo" matrix --targets alpha/one 2>&1)"
rc=$?
assert_exit 'filtered matrix succeeds when the last manifest target is omitted' 0 "$rc"
assert_eq 'filtered matrix contains only the requested earlier target' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one"}]}' \
  "$out"

out="$(run_engine "$source_repo" plan --targets alpha/one 2>&1)"
rc=$?
assert_exit 'filtered plan succeeds when the last manifest target is omitted' 0 "$rc"
assert_contains 'earlier-target plan includes the requested target' "$out" 'alpha/one'
assert_not_contains 'earlier-target plan excludes the last manifest target' "$out" 'beta/two'

out="$(run_engine "$source_repo" mappings --target beta/two 2>&1)"
rc=$?
assert_exit 'managed mapping renderer succeeds' 0 "$rc"
assert_contains 'mapping renderer includes managed component' "$out" '**consumer**'
assert_not_contains 'mapping renderer excludes locally-owned payload' "$out" '**base**'

target_repo="$tmp_root/target-beta"
make_target "$target_repo" beta/two
printf 'local policy\n' >"$target_repo/.policy"
git -C "$target_repo" add .policy
git -C "$target_repo" commit -m local -q
out="$(run_engine "$source_repo" apply --target beta/two --target-root "$target_repo" 2>&1)"
rc=$?
assert_exit 'apply accepts a dependency satisfied by locally-owned' 0 "$rc"
assert_eq 'managed file content copied' 'consumer' "$(tr -d '\r\n' <"$target_repo/consumer.txt")"
assert_eq 'locally-owned file remains untouched' 'local policy' "$(tr -d '\r\n' <"$target_repo/.policy")"
assert_file_absent 'locally-owned component support file is not copied' "$target_repo/tools/check.sh"

target_repo="$tmp_root/target-alpha"
make_target "$target_repo"
out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"
rc=$?
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
out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"
rc=$?
assert_nonzero 'untracked destination is rejected' "$rc"
assert_contains 'untracked rejection is explicit' "$out" 'refusing to overwrite untracked destination'
assert_file_absent 'failed preflight writes none of the earlier files' "$target_repo/.policy"
assert_file_absent 'failed preflight creates no earlier nested file' "$target_repo/tools/check.sh"

target_repo="$tmp_root/target-no-origin"
make_repo "$target_repo"
out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"
rc=$?
assert_nonzero 'target without origin is rejected' "$rc"
assert_contains 'missing origin diagnostic names identity evidence' "$out" 'no readable origin remote'
assert_file_absent 'missing origin writes no destination' "$target_repo/.policy"

target_repo="$tmp_root/target-wrong-origin"
make_target "$target_repo" beta/two
out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"
rc=$?
assert_nonzero 'mismatched target origin is rejected' "$rc"
assert_contains 'mismatched origin diagnostic names expected target' "$out" "expected 'alpha/one'"
assert_file_absent 'mismatched origin writes no destination' "$target_repo/.policy"

target_repo="$tmp_root/target-index-failure"
make_target "$target_repo"
mock_bin="$tmp_root/mock-git-bin"
mkdir -p "$mock_bin"
mock_git="$mock_bin/git"
cat >"$mock_git" <<'SH'
#!/usr/bin/env bash
has_ls_files=false
has_failed_root=false
for argument in "$@"; do
  [[ "$argument" == ls-files ]] && has_ls_files=true
  [[ "$argument" == "$FAIL_GIT_ROOT" ]] && has_failed_root=true
done
if [[ "$has_ls_files" == true && "$has_failed_root" == true ]]; then exit 78; fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$mock_git"
failed_git_root="$(cd -- "$target_repo" && pwd -P)"
real_git="$(command -v git)"
out="$(
  REAL_GIT="$real_git" FAIL_GIT_ROOT="$failed_git_root" PATH="$mock_bin:$PATH" \
    "$engine" apply --source-root "$source_repo" --manifest manifest.yml \
    --target alpha/one --target-root "$target_repo" 2>&1
)"
rc=$?
assert_nonzero 'target index inspection failure is rejected' "$rc"
assert_contains 'index failure diagnostic is explicit' "$out" 'could not inspect Git index path'
assert_file_absent 'index inspection failure writes no destination' "$target_repo/.policy"

# The merged distribution workflow installs only yq. Prove the production
# interpreter does not discover or invoke Node/Ajv after authoring validation.
runtime_bin="$tmp_root/yq-only-bin"
mkdir -p "$runtime_bin"
cat >"$runtime_bin/node" <<'SH'
#!/usr/bin/env bash
exit 99
SH
chmod +x "$runtime_bin/node"
runtime_engine_dir="$tmp_root/yq-only-runtime/distribution"
mkdir -p "$runtime_engine_dir"
cp "$engine" "$runtime_engine_dir/sync-manifest.sh"
runtime_engine="$runtime_engine_dir/sync-manifest.sh"
out="$(
  PATH="$runtime_bin:$PATH" "$runtime_engine" validate \
    --source-root "$source_repo" --manifest manifest.yml 2>&1
)"
validate_rc=$?
matrix_out="$(
  PATH="$runtime_bin:$PATH" "$runtime_engine" matrix \
    --source-root "$source_repo" --manifest manifest.yml --targets alpha/one 2>&1
)"
matrix_rc=$?
runtime_target="$tmp_root/yq-only-target"
make_target "$runtime_target"
apply_out="$(
  PATH="$runtime_bin:$PATH" "$runtime_engine" apply \
    --source-root "$source_repo" --manifest manifest.yml \
    --target alpha/one --target-root "$runtime_target" 2>&1
)"
apply_rc=$?
assert_exit 'yq-only production validate succeeds' 0 "$validate_rc"
assert_exit 'yq-only production matrix succeeds' 0 "$matrix_rc"
assert_eq 'yq-only matrix remains exact' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one"}]}' "$matrix_out"
assert_exit 'yq-only production apply succeeds' 0 "$apply_rc"
assert_file_exists 'yq-only production apply writes the managed destination' \
  "$runtime_target/.policy"
assert_not_contains 'yq-only production path never invokes the Node shim' "$out$apply_out" '99'

for filter in 'unknown/repo' 'alpha/one,alpha/one' 'alpha/one,,beta/two' ',alpha/one'; do
  out="$(run_engine "$source_repo" matrix --targets "$filter" 2>&1)"
  rc=$?
  assert_nonzero "invalid target filter fails: $filter" "$rc"
done

invalid_case() {
  local label="$1" bad_manifest="$2" needle="$3"
  local slug dir output status
  slug="${label//[^A-Za-z0-9]/-}"
  dir="$tmp_root/invalid-$slug"
  make_source "$dir" "$bad_manifest"
  output="$(run_engine "$dir" validate 2>&1)"
  status=$?
  assert_nonzero "$label is rejected" "$status"
  assert_contains "$label has a useful diagnostic" "$output" "$needle"
}

bad="${manifest/version: 2/version: 1}"
invalid_case 'wrong version' "$bad" 'manifest version must be the integer 2'

bad="$manifest"$'\n''unexpected: true'
invalid_case 'unknown root key' "$bad" "manifest root contains unknown key 'unexpected'"

bad="${manifest/files:/unknown: true$'\n'    files:}"
invalid_case 'unknown component key' "$bad" "component 'base' contains unknown key 'unknown'"

bad="${manifest/$'      - base\n      - consumer'/$'      - base\n      - base\n      - consumer'}"
invalid_case 'duplicate managed component' "$bad" "managed components contains duplicate 'base'"

bad="${manifest/$'    files:\n      consumer.txt: consumer.txt'/'    files: {}'}"
invalid_case 'empty component files' "$bad" "component 'consumer' files must be a non-empty mapping"

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

# An escaped NUL must fail both authoring-schema and production Bash validation,
# and apply must not reach target mutation.
bad_control="${manifest/policy.txt: .policy/policy.txt: \".policy\\u0000managed\\u0000consumer\"}"
invalid_case 'control-character mapping injection' "$bad_control" 'may not contain control characters'

control_error="$tmp_root/control-records.err"
{ printf '%s\n' "$bad_control" | yq eval -o=json -I=0 '.' -; } |
  node "$root/distribution/validate-sync-manifest.mjs" 2>"$control_error"
rc=$?
assert_nonzero 'control-character mapping fails authoring schema validation' "$rc"
assert_contains 'control-character mapping reports schema rejection' \
  "$(cat "$control_error")" 'must match pattern'

control_source="$tmp_root/control-source"
control_target="$tmp_root/control-target"
make_source "$control_source" "$bad_control"
make_target "$control_target"
out="$(run_engine "$control_source" apply --target alpha/one --target-root "$control_target" 2>&1)"
rc=$?
assert_nonzero 'control-character mapping fails before target apply' "$rc"
assert_file_absent 'control-character mapping writes no root destination' "$control_target/.policy"
assert_file_absent 'control-character mapping writes no consumer destination' \
  "$control_target/consumer.txt"

bad="$(printf '%s\n' "$manifest" | sed 's|^  alpha/one:|  Alpha/one:|')"
invalid_case 'noncanonical uppercase target' "$bad" "invalid target repository 'Alpha/one'"

# Remove alpha/one's selected base while retaining consumer's dependency. Keep
# beta/two's locally-owned base so the fixture remains schema-valid and reaches
# the dependency-graph validator.
bad="$(printf '%s\n' "$manifest" |
  awk 'BEGIN { in_alpha = 0 }
       /^  alpha\/one:$/ { in_alpha = 1 }
       /^  beta\/two:$/ { in_alpha = 0 }
       !(in_alpha && $0 == "      - base") { print }')"
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
out="$(run_engine "$source_repo" validate 2>&1)"
rc=$?
assert_nonzero 'untracked source is rejected' "$rc"
assert_contains 'untracked source diagnostic identifies tracked-file contract' \
  "$out" 'exactly one tracked stage-0 file'

source_repo="$tmp_root/dirty-source"
make_source "$source_repo" "$manifest"
printf 'unreviewed worktree bytes\n' >"$source_repo/policy.txt"
out="$(run_engine "$source_repo" validate 2>&1)"
rc=$?
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
  out="$(run_engine "$source_repo" apply --target alpha/one --target-root "$target_repo" 2>&1)"
  rc=$?
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
assert_eq 'runner-policy materializes exactly six runtime files' '6' \
  "$(yq -r '.components.runner-policy.files | length' "$actual_manifest")"

for mapping in \
  'components/runner-policy/runner-policy.mjs=.github/standards/runner-policy/runner-policy.mjs' \
  'components/runner-policy/policy.json=.github/standards/runner-policy/policy.json' \
  'components/runner-policy/policy.schema.json=.github/standards/runner-policy/policy.schema.json' \
  'components/runner-policy/repository-policy.schema.json=.github/standards/runner-policy/repository-policy.schema.json' \
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
  make_target "$production_target" "$production_slug"
  out="$(
    "$engine" apply \
      --source-root "$root" \
      --manifest distribution/sync-manifest.yml \
      --target "$production_slug" \
      --target-root "$production_target" 2>&1
  )"
  rc=$?
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

assert_eq 'Go analysis materializes at the root discovery path' \
  '.golangci.yml' \
  "$(yq -r '.components.go-analysis.files.".golangci.yml"' "$actual_manifest")"
assert_eq 'ci-runner enrolls the managed Go analyzer policy exactly once' '1' \
  "$(yq -r \
    '[.targets."melodic-software/ci-runner".managed[] | select(. == "go-analysis")] | length' \
    "$actual_manifest")"
assert_eq 'Go analysis covers exactly the ci-runner target' \
  '["melodic-software/ci-runner"]' \
  "$(yq -o=json -I=0 \
    '[.targets | to_entries[] | select(.value.managed[]? == "go-analysis") | .key]' \
    "$actual_manifest")"

expected_review_instructions_targets='["melodic-software/ci-workflows","melodic-software/claude-code-plugins","melodic-software/dotfiles","melodic-software/github-iac","melodic-software/provisioning"]'
actual_review_instructions_targets="$(
  yq -o=json -I=0 \
    '[.targets | to_entries[] | select(.value.managed[]? == "review-instructions") | .key]' \
    "$actual_manifest"
)"
assert_eq 'REVIEW.md reaches every enrolled ci-workflows-reviewable target, public and private alike' \
  "$expected_review_instructions_targets" "$actual_review_instructions_targets"

expected_agent_orientation_targets='["melodic-software/claude-code-plugins","melodic-software/dotfiles","melodic-software/github-iac","melodic-software/provisioning"]'
actual_agent_orientation_targets="$(
  yq -o=json -I=0 \
    '[.targets | to_entries[] | select(.value.managed[]? == "agent-orientation") | .key]' \
    "$actual_manifest"
)"
assert_eq 'AGENTS.md reaches exactly the four whole-file-managed private consumers (medley reconciles locally instead; ci-workflows is public and gets REVIEW.md only)' \
  "$expected_agent_orientation_targets" "$actual_agent_orientation_targets"

assert_eq 'ci-workflows does not whole-file-manage agent-orientation (public repo; AGENTS.md excluded)' '0' \
  "$(yq -r \
    '[.targets."melodic-software/ci-workflows".managed[] | select(. == "agent-orientation")] | length' \
    "$actual_manifest")"

for component in agent-orientation review-instructions; do
  assert_eq "medley locally-owns $component rather than whole-file-managing it" '1' \
    "$(COMPONENT="$component" yq -r \
      '[.targets."melodic-software/medley".locally-owned[] | select(. == strenv(COMPONENT))] | length' \
      "$actual_manifest")"
  assert_eq "medley's managed list does not also claim $component" '0' \
    "$(COMPONENT="$component" yq -r \
      '[.targets."melodic-software/medley".managed[] | select(. == strenv(COMPONENT))] | length' \
      "$actual_manifest")"
done

[[ $FAILED -eq 0 ]] || exit 1
