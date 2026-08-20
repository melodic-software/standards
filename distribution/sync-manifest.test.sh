#!/usr/bin/env bash
# Contract tests for the schema-v2 validator/materializer.
set -uo pipefail

root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"
# SYNC_ENGINE_PATH selects the engine under test (Phase 6 dual-gate): default
# is the Bash engine; the Node engine run sets it to distribution/sync-manifest.mjs.
# A relative value resolves against the repo root so the suite stays cwd-independent.
if [[ -n "${SYNC_ENGINE_PATH:-}" ]]; then
  if [[ "$SYNC_ENGINE_PATH" == /* || "$SYNC_ENGINE_PATH" =~ ^[A-Za-z]: ]]; then
    engine="$SYNC_ENGINE_PATH"
  else
    engine="$root/$SYNC_ENGINE_PATH"
  fi
else
  engine="$root/distribution/sync-manifest.sh"
fi
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

command -v yq >/dev/null 2>&1 || skip_suite 'Mike Farah yq v4 is not installed'
[[ "$(yq --version 2>/dev/null)" =~ version[[:space:]]+v?4\. ]] ||
  skip_suite 'Mike Farah yq v4 is required'
# A missing install is a configuration error, not a skippable environment:
# the Node deps are the production engine's own runtime, and skip_suite exits
# 0 — a silent skip would turn this whole production gate into a false green.
[[ -f "$root/distribution/node_modules/ajv/package.json" ]] || {
  echo 'ERROR: distribution dependencies are not installed (run npm ci --prefix distribution)' >&2
  exit 1
}

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

# Fixture-agreement contract (schema ∩ engine on fixtures).
# validate-sync-manifest.mjs checks an overlapping structural subset of the
# Bash engine's rules. Where both validators apply on a fixture manifest they
# must agree; the engine alone gates distribution/sync-manifest.yml in CI.
schema_rc_for_yaml() {
  local yaml="$1" stderr_file="${2:-/dev/null}"
  { printf '%s\n' "$yaml" | yq eval -o=json -I=0 '.' -; } |
    node "$root/distribution/validate-sync-manifest.mjs" 2>"$stderr_file"
}

invalid_case() {
  local label="$1" bad_manifest="$2" needle="$3"
  local agreement="${4:-structural}"
  local schema_needle="${5:-}"
  local slug dir output status schema_status schema_err
  slug="${label//[^A-Za-z0-9]/-}"
  dir="$tmp_root/invalid-$slug"
  make_source "$dir" "$bad_manifest"
  if [[ "$agreement" == structural ]]; then
    schema_err="$tmp_root/schema-err-$slug"
    schema_rc_for_yaml "$bad_manifest" "$schema_err"
    schema_status=$?
    assert_nonzero "fixture-agreement: $label rejected by schema" "$schema_status"
    if [[ -n "$schema_needle" ]]; then
      assert_contains "$label schema diagnostic" "$(<"$schema_err")" "$schema_needle"
    fi
  fi
  output="$(run_engine "$dir" validate 2>&1)"
  status=$?
  assert_nonzero "fixture-agreement: $label rejected by engine" "$status"
  assert_contains "$label has a useful diagnostic" "$output" "$needle"
}

valid_case() {
  local label="$1" good_manifest="$2"
  local slug dir
  slug="${label//[^A-Za-z0-9]/-}"
  dir="$tmp_root/valid-$slug"
  make_source "$dir" "$good_manifest"
  schema_rc_for_yaml "$good_manifest" >/dev/null
  assert_exit "fixture-agreement: $label accepted by schema" 0 "$?"
  run_engine "$dir" validate >/dev/null 2>&1
  assert_exit "fixture-agreement: $label accepted by engine" 0 "$?"
}

manifest="$(valid_manifest)"
source_repo="$tmp_root/valid-source"
make_source "$source_repo" "$manifest"

schema_rc_for_yaml "$manifest" >/dev/null
rc=$?
assert_exit 'fixture-agreement: canonical fixture accepted by schema' 0 "$rc"

out="$(run_engine "$source_repo" validate 2>&1)"
rc=$?
assert_exit 'fixture-agreement: canonical fixture accepted by engine' 0 "$rc"
assert_contains 'validation reports catalog size' "$out" '2 components, 2 targets'

out="$(run_engine "$source_repo" matrix --targets ' beta/two , alpha/one ' 2>&1)"
rc=$?
assert_exit 'matrix accepts an exact whitespace-trimmed filter' 0 "$rc"
assert_eq 'matrix stays in manifest order' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one","automerge":true},{"repo":"beta/two","repo_owner":"beta","repo_name":"two","automerge":true}]}' \
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
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one","automerge":true}]}' \
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

out="$(run_engine "$source_repo" dest-paths --target beta/two 2>&1)"
rc=$?
assert_exit 'dest-paths renderer succeeds' 0 "$rc"
assert_contains 'dest-paths includes managed destination' "$out" 'consumer.txt'
assert_not_contains 'dest-paths excludes Markdown chrome' "$out" '**'
assert_not_contains 'dest-paths excludes locally-owned destination' "$out" '.policy'

out="$(run_engine "$source_repo" dest-paths --target alpha/one 2>&1)"
rc=$?
assert_exit 'dest-paths multi-file target succeeds' 0 "$rc"
assert_eq 'dest-paths emits sorted unique destinations' \
  $'.policy\nconsumer.txt\ndocs/adr/README.md\ntools/check.sh' "$out"

out="$(run_engine "$source_repo" dest-paths --target unknown/repo 2>&1)"
rc=$?
assert_exit 'dest-paths unknown target is a successful no-op' 0 "$rc"
assert_eq 'dest-paths unknown target emits no paths' '' "$out"

# Full-output byte assertions for the renderers the sync PR bodies and logs
# consume verbatim (Phase 6 dual-gate hardening: needle checks alone would let
# an engine drift the arrow glyph, ordering, or field layout while staying
# green).
out="$(run_engine "$source_repo" mappings --target alpha/one 2>&1)"
rc=$?
assert_exit 'full mappings render succeeds' 0 "$rc"
# shellcheck disable=SC2016 # the backticks are literal Markdown output bytes
assert_eq 'mappings output is byte-exact' \
  '- **base**: `docs/adr/README.md` → `docs/adr/README.md` (mode `100644`)
- **base**: `policy.txt` → `.policy` (mode `100644`)
- **base**: `scripts/check.sh` → `tools/check.sh` (mode `100755`)
- **consumer**: `consumer.txt` → `consumer.txt` (mode `100644`)' \
  "$out"

out="$(run_engine "$source_repo" plan 2>&1)"
rc=$?
assert_exit 'full plan render succeeds' 0 "$rc"
assert_eq 'plan output is byte-exact' \
  'Distribution plan:
## alpha/one
  automerge: true
  managed base:
    100644 docs/adr/README.md -> docs/adr/README.md
    100644 policy.txt -> .policy
    100755 scripts/check.sh -> tools/check.sh
  managed consumer:
    100644 consumer.txt -> consumer.txt
## beta/two
  automerge: true
  managed consumer:
    100644 consumer.txt -> consumer.txt
  locally-owned base (not modified)' \
  "$out"

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
assert_eq 'apply output is byte-exact' \
  'synced docs/adr/README.md -> docs/adr/README.md (100644)
synced policy.txt -> .policy (100644)
synced scripts/check.sh -> tools/check.sh (100755)
synced consumer.txt -> consumer.txt (100644)' \
  "$out"
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

# The production workflows install yq for authoring-side checks only. Prove
# the production engine path — the exec wrapper plus the Node engine and its
# locked dependencies, relocated the way the reusables consume them — never
# discovers or invokes yq (Phase 6 decision 6-D: the inversion of the retired
# Bash-era no-Node control).
runtime_bin="$tmp_root/node-only-bin"
mkdir -p "$runtime_bin"
cat >"$runtime_bin/yq" <<'SH'
#!/usr/bin/env bash
exit 99
SH
chmod +x "$runtime_bin/yq"
runtime_engine_dir="$tmp_root/node-only-runtime/distribution"
mkdir -p "$runtime_engine_dir"
cp "$root/distribution/sync-manifest.sh" "$runtime_engine_dir/sync-manifest.sh"
cp "$root/distribution/sync-manifest.mjs" "$runtime_engine_dir/sync-manifest.mjs"
cp -R "$root/distribution/node_modules" "$runtime_engine_dir/node_modules"
runtime_engine="$runtime_engine_dir/sync-manifest.sh"
out="$(
  PATH="$runtime_bin:$PATH" bash "$runtime_engine" validate \
    --source-root "$source_repo" --manifest manifest.yml 2>&1
)"
validate_rc=$?
matrix_out="$(
  PATH="$runtime_bin:$PATH" bash "$runtime_engine" matrix \
    --source-root "$source_repo" --manifest manifest.yml --targets alpha/one 2>&1
)"
matrix_rc=$?
runtime_target="$tmp_root/node-only-target"
make_target "$runtime_target"
apply_out="$(
  PATH="$runtime_bin:$PATH" bash "$runtime_engine" apply \
    --source-root "$source_repo" --manifest manifest.yml \
    --target alpha/one --target-root "$runtime_target" 2>&1
)"
apply_rc=$?
assert_exit 'node-only production validate succeeds' 0 "$validate_rc"
assert_exit 'node-only production matrix succeeds' 0 "$matrix_rc"
assert_eq 'node-only matrix remains exact' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one","automerge":true}]}' "$matrix_out"
assert_exit 'node-only production apply succeeds' 0 "$apply_rc"
assert_file_exists 'node-only production apply writes the managed destination' \
  "$runtime_target/.policy"
assert_not_contains 'node-only production path never invokes the yq shim' "$out$matrix_out$apply_out" '99'

for filter in 'unknown/repo' 'alpha/one,alpha/one' 'alpha/one,,beta/two' ',alpha/one'; do
  out="$(run_engine "$source_repo" matrix --targets "$filter" 2>&1)"
  rc=$?
  assert_nonzero "invalid target filter fails: $filter" "$rc"
done

bad="${manifest/version: 2/version: 1}"
invalid_case 'wrong version' "$bad" 'manifest version must be the integer 2'

# An explicit core tag must win over the resolved value's shape: `!!float 2`
# resolves to numeric 2 in both engines but is tagged !!float, not !!int.
# The authoring schema sees only the converted JSON (an integer), hence
# engine-only.
bad="${manifest/version: 2/version: !!float 2}"
invalid_case 'explicitly tagged float version' "$bad" \
  'manifest version must be the integer 2' engine-only

bad="$manifest"$'\n''unexpected: true'
invalid_case 'unknown root key' "$bad" "manifest root contains unknown key 'unexpected'"

bad="${manifest/files:/unknown: true$'\n'    files:}"
invalid_case 'unknown component key' "$bad" "component 'base' contains unknown key 'unknown'"

bad="${manifest/$'      - base\n      - consumer'/$'      - base\n      - base\n      - consumer'}"
invalid_case 'duplicate managed component' "$bad" "managed components contains duplicate 'base'"

bad="${manifest/$'    files:\n      consumer.txt: consumer.txt'/'    files: {}'}"
invalid_case 'empty component files' "$bad" "component 'consumer' files must be a non-empty mapping"

bad="version: 2"$'\n'"version: 2"$'\n'"${manifest#*$'\n'}"
invalid_case 'duplicate YAML key' "$bad" 'duplicate mapping key' engine-only

bad="${manifest/policy.txt: .policy/policy\/..\/policy.txt: .policy}"
invalid_case 'unsafe traversal source' "$bad" 'unsafe source path' engine-only

bad="${manifest/consumer.txt: consumer.txt/consumer.txt: .policy}"
invalid_case 'destination ownership collision' "$bad" 'owned by both' engine-only

# One canonical source MAY back multiple components (per-destination fan-out);
# only destinations are single-owner.
shared="${manifest/consumer.txt: consumer.txt/policy.txt: consumer-policy.txt}"
valid_case 'shared source across components' "$shared"

bad="${manifest/policy.txt: .policy/policy.txt: path}"
bad="${bad/consumer.txt: consumer.txt/consumer.txt: path\/child}"
invalid_case 'destination file before child collision' "$bad" 'file/directory conflict' engine-only

bad="${manifest/policy.txt: .policy/policy.txt: path\/child}"
bad="${bad/consumer.txt: consumer.txt/consumer.txt: path}"
invalid_case 'destination child before file collision' "$bad" 'file/directory conflict' engine-only

bad="${manifest/policy.txt: .policy/policy.txt: bad\"name}"
invalid_case 'destination outside portable path alphabet' "$bad" 'unsafe destination path' engine-only

# An escaped NUL must fail both authoring-schema and production Bash validation,
# and apply must not reach target mutation.
bad_control="${manifest/policy.txt: .policy/policy.txt: \".policy\\u0000managed\\u0000consumer\"}"
invalid_case 'control-character mapping injection' "$bad_control" \
  'may not contain control characters' structural 'must match pattern'

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
invalid_case 'missing target dependency' "$bad" "does not select required 'base'" engine-only

# Make base depend on consumer, completing a two-node cycle.
bad="$(printf '%s\n' "$manifest" |
  sed '/^  base:$/a\    requires:\n      - consumer')"
invalid_case 'dependency cycle' "$bad" 'dependency cycle' engine-only

# Reachability is a whole-manifest property JSON Schema cannot express: a
# defined component no target selects (directly or through a selected
# component's dependency closure) is rejected by the engine alone.
bad="$(printf '%s\n' "$manifest" |
  sed '/^targets:$/i\  orphan:\n    files:\n      policy.txt: .orphan\n')"
invalid_case 'unreferenced component' "$bad" \
  "component 'orphan' is referenced by no target" engine-only

# Closure credit: 'extra-dep' is selected by no target, but 'helper' —
# locally-owned by beta/two — requires it, and a locally-owned selection
# credits its dependency closure (the per-target managed check deliberately
# does not reach locally-owned internals).
good="$(printf '%s\n' "$manifest" |
  sed '/^targets:$/i\  extra-dep:\n    files:\n      policy.txt: .extra-dep\n  helper:\n    files:\n      consumer.txt: .helper\n    requires:\n      - extra-dep\n' |
  sed '$a\      - helper')"
valid_case 'dependency-closure reachability' "$good"

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

manifest_symlink_source="$tmp_root/manifest-symlink-source"
make_source "$manifest_symlink_source" "$manifest"
mv "$manifest_symlink_source/manifest.yml" "$manifest_symlink_source/manifest.real.yml"
ln -s manifest.real.yml "$manifest_symlink_source/manifest.yml"
out="$(run_engine "$manifest_symlink_source" validate 2>&1)"
rc=$?
assert_nonzero 'manifest symlink is rejected before parsing' "$rc"
assert_contains 'manifest symlink diagnostic identifies worktree shape' \
  "$out" 'must exist as a non-symlink regular worktree file'

manifest_fifo_source="$tmp_root/manifest-fifo-source"
make_source "$manifest_fifo_source" "$manifest"
rm "$manifest_fifo_source/manifest.yml"
mkfifo "$manifest_fifo_source/manifest.yml"
out="$(run_engine "$manifest_fifo_source" validate 2>&1)"
rc=$?
assert_nonzero 'manifest FIFO is rejected before parsing' "$rc"
assert_contains 'manifest FIFO diagnostic identifies worktree shape' \
  "$out" 'must exist as a non-symlink regular worktree file'

# Batched index reads attribute exact recorded paths even when a shared
# directory prefix would also select descendants under ls-files pathspec rules.
nested_manifest="$(cat <<'YAML'
version: 2

components:
  base:
    files:
      pkg/dir-a/file-a.txt: out-a.txt
      pkg/dir-b/file-b.txt: out-b.txt
targets:
  alpha/one:
    managed:
      - base
YAML
)"
nested_source="$tmp_root/nested-prefix-source"
make_repo "$nested_source"
mkdir -p "$nested_source/pkg/dir-a" "$nested_source/pkg/dir-b"
printf 'a\n' >"$nested_source/pkg/dir-a/file-a.txt"
printf 'b\n' >"$nested_source/pkg/dir-b/file-b.txt"
printf '%s\n' "$nested_manifest" >"$nested_source/manifest.yml"
git -C "$nested_source" add pkg/dir-a/file-a.txt pkg/dir-b/file-b.txt manifest.yml
git -C "$nested_source" commit -m 'nested prefix fixture' -q
out="$(run_engine "$nested_source" validate 2>&1)"
rc=$?
assert_exit 'nested directory prefix sources validate under batched index reads' 0 "$rc"
assert_contains 'nested prefix validation reports catalog size' "$out" '1 components, 1 targets'
nested_target="$tmp_root/nested-prefix-target"
make_target "$nested_target"
out="$(run_engine "$nested_source" apply --target alpha/one --target-root "$nested_target" 2>&1)"
rc=$?
assert_exit 'nested prefix sources apply under batched destination index reads' 0 "$rc"
assert_file_exists 'nested prefix apply writes first destination' "$nested_target/out-a.txt"
assert_file_exists 'nested prefix apply writes second destination' "$nested_target/out-b.txt"

spawn_count_dir="$tmp_root/spawn-count"
mkdir -p "$spawn_count_dir/bin"
cat >"$spawn_count_dir/bin/git" <<'SH'
#!/usr/bin/env bash
REAL_GIT="${REAL_GIT:?}"
COUNT_DIR="${COUNT_DIR:?}"
for argument in "$@"; do
  case "$argument" in
  ls-files)
    echo $(( $(cat "$COUNT_DIR/ls-files" 2>/dev/null || echo 0) + 1 )) >"$COUNT_DIR/ls-files"
    ;;
  hash-object)
    echo $(( $(cat "$COUNT_DIR/hash-object" 2>/dev/null || echo 0) + 1 )) >"$COUNT_DIR/hash-object"
    ;;
  esac
done
exec "$REAL_GIT" "$@"
SH
chmod +x "$spawn_count_dir/bin/git"
: >"$spawn_count_dir/ls-files"
: >"$spawn_count_dir/hash-object"
real_git="$(command -v git)"
out="$(
  COUNT_DIR="$spawn_count_dir" REAL_GIT="$real_git" \
    PATH="$spawn_count_dir/bin:$PATH" \
    "$engine" validate --source-root "$root" \
    --manifest distribution/sync-manifest.yml 2>&1
)"
rc=$?
assert_exit 'production validate succeeds under spawn-counting git shim' 0 "$rc"
assert_eq 'production validate batches tracked-source ls-files calls' '1' \
  "$(cat "$spawn_count_dir/ls-files")"
assert_eq 'production validate batches tracked-source hash-object calls' '1' \
  "$(cat "$spawn_count_dir/hash-object")"
assert_contains 'production validate reports catalog size under spawn shim' "$out" 'components, 12 targets'

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
# component in each enrolled consumer. Its dependency lockfile travels
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
assert_eq 'runner-policy covers exactly the five enrolled consumers' \
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

# agent-orientation was retired by the standards sync audit (audit topic
# docs/topics/standards-sync-audit/, Phase 2): no component ships AGENTS.md
# anywhere anymore.
assert_eq 'no component named agent-orientation exists (retired)' '0' \
  "$(yq -r '[.components | keys[] | select(. == "agent-orientation")] | length' \
    "$actual_manifest")"

assert_eq 'medley locally-owns review-instructions rather than whole-file-managing it' '1' \
  "$(yq -r \
    '[.targets."melodic-software/medley".locally-owned[] | select(. == "review-instructions")] | length' \
    "$actual_manifest")"
assert_eq "medley's managed list does not also claim review-instructions" '0' \
  "$(yq -r \
    '[.targets."melodic-software/medley".managed[] | select(. == "review-instructions")] | length' \
    "$actual_manifest")"

# automerge is optional policy-as-data: absent means true (exercised by every
# prior matrix assertion above), an explicit value is emitted verbatim, and a
# non-boolean value is rejected by both the Bash validator and the authoring
# JSON Schema. A target-level unknown key is also re-verified here as a
# regression check on the generalized validate_record_keys optional-key set.
automerge_manifest="${manifest/'  alpha/one:'$'\n''    managed:'/'  alpha/one:'$'\n''    automerge: false'$'\n''    managed:'}"
automerge_dir="$tmp_root/automerge-source"
make_source "$automerge_dir" "$automerge_manifest"
schema_rc_for_yaml "$automerge_manifest" >/dev/null
assert_exit 'fixture-agreement: explicit automerge manifest accepted by schema' 0 "$?"
out="$(run_engine "$automerge_dir" matrix 2>&1)"
rc=$?
assert_exit 'manifest with an explicit automerge value validates' 0 "$rc"
assert_eq 'matrix emits the explicit false and the default-true for the other target' \
  '{"include":[{"repo":"alpha/one","repo_owner":"alpha","repo_name":"one","automerge":false},{"repo":"beta/two","repo_owner":"beta","repo_name":"two","automerge":true}]}' \
  "$out"

bad="${manifest/'  alpha/one:'$'\n''    managed:'/'  alpha/one:'$'\n''    automerge: yes-please'$'\n''    managed:'}"
invalid_case 'non-boolean automerge value' "$bad" \
  "target 'alpha/one' automerge must be a boolean" structural automerge

# Both engines must emit identical matrix bytes across the Phase 6 dual-gate
# window: yq's @tsv passes a capitalized boolean through verbatim (producing
# invalid matrix JSON) while a YAML-1.2 parser normalizes it, so the scalar is
# restricted to the two literal spellings. The authoring schema cannot see the
# raw scalar (yq normalizes it during the JSON conversion), hence engine-only.
bad="${manifest/'  alpha/one:'$'\n''    managed:'/'  alpha/one:'$'\n''    automerge: False'$'\n''    managed:'}"
invalid_case 'automerge boolean must be spelled true or false' "$bad" \
  "target 'alpha/one' automerge must be the literal true or false" engine-only

bad="${manifest/'  alpha/one:'$'\n''    managed:'/'  alpha/one:'$'\n''    unknown: true'$'\n''    managed:'}"
invalid_case 'unknown target key' "$bad" "target 'alpha/one' contains unknown key 'unknown'"

# Malformed-shape coverage for the consolidated structural pass. Validation reads
# the whole manifest in one yq pass per section, so a record whose shape cannot be
# descended into must still produce that record's own diagnostic rather than
# collapsing the pass itself. Every shape below is one that a naive single-pass
# expression evaluates as an error instead of a finding.
component_block='  consumer:'$'\n''    files:'$'\n''      consumer.txt: consumer.txt'$'\n''    requires:'$'\n''      - base'
requires_block='    requires:'$'\n''      - base'
target_block='  beta/two:'$'\n''    managed:'$'\n''      - consumer'$'\n''    locally-owned:'$'\n''      - base'

bad="${manifest/"$component_block"/'  consumer: "oops"'}"
invalid_case 'component is a scalar string' "$bad" "component 'consumer' must be a mapping"

bad="${manifest/"$component_block"/'  consumer:'$'\n''    - one'$'\n''    - two'}"
invalid_case 'component is a sequence' "$bad" "component 'consumer' must be a mapping"

bad="${manifest/"$component_block"/'  consumer: {}'}"
invalid_case 'component is an empty mapping' "$bad" "component 'consumer' is missing required key 'files'"

bad="${manifest/'    files:'$'\n''      consumer.txt: consumer.txt'/'    files: "oops"'}"
invalid_case 'component files is a scalar string' "$bad" \
  "component 'consumer' files must be a non-empty mapping"

bad="${manifest/'    files:'$'\n''      consumer.txt: consumer.txt'/'    files:'$'\n''      - a'$'\n''      - b'}"
invalid_case 'component files is a sequence' "$bad" \
  "component 'consumer' files must be a non-empty mapping"

bad="${manifest/consumer.txt: consumer.txt/consumer.txt: 42}"
invalid_case 'component file destination is not a string' "$bad" \
  "component 'consumer' file sources and destinations must be strings"

bad="${manifest/"$requires_block"/'    requires: "oops"'}"
invalid_case 'component requires is a scalar string' "$bad" \
  "component 'consumer' requires must be a non-empty sequence"

bad="${manifest/"$requires_block"/'    requires:'$'\n''      key: value'}"
invalid_case 'component requires is a mapping' "$bad" \
  "component 'consumer' requires must be a non-empty sequence"

bad="${manifest/"$requires_block"/'    requires:'$'\n''      - 42'}"
invalid_case 'component dependency is not a string' "$bad" \
  "component 'consumer' dependencies must be strings"

bad="${manifest/"$target_block"/'  beta/two: "oops"'}"
invalid_case 'target is a scalar string' "$bad" "target 'beta/two' must be a mapping"

bad="${manifest/"$target_block"/'  beta/two:'$'\n''    - one'}"
invalid_case 'target is a sequence' "$bad" "target 'beta/two' must be a mapping"

bad="${manifest/"$target_block"/'  beta/two: {}'}"
invalid_case 'target is an empty mapping' "$bad" \
  "target 'beta/two' is missing required key 'managed'"

bad="${manifest/'    managed:'$'\n''      - consumer'/'    managed: "oops"'}"
invalid_case 'target managed is a scalar string' "$bad" \
  "target 'beta/two' managed must be a non-empty sequence"

bad="${manifest/'    managed:'$'\n''      - consumer'/'    managed:'$'\n''      - 42'}"
invalid_case 'target managed entry is not a string' "$bad" \
  "target 'beta/two' managed entries must be strings"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    locally-owned: "oops"'}"
invalid_case 'target locally-owned is a scalar string' "$bad" \
  "target 'beta/two' locally-owned must be a non-empty sequence when present"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    locally-owned:'$'\n''      - 42'}"
invalid_case 'target locally-owned entry is not a string' "$bad" \
  "target 'beta/two' locally-owned entries must be strings"

# Regression: probing an absent optional key must not materialize it. yq creates
# a node for a traversed missing path, so a structural pass that reaches for
# `.requires` before reading a component's keys would report every component as
# carrying `requires` — and then reject the null it just created.
absent_optional_dir="$tmp_root/absent-optional-keys"
make_source "$absent_optional_dir" "$manifest"
out="$(run_engine "$absent_optional_dir" validate 2>&1)"
rc=$?
assert_exit 'component without requires validates' 0 "$rc"
assert_not_contains 'absent requires is never reported as an empty sequence' \
  "$out" 'requires must be a non-empty sequence'
assert_not_contains 'absent locally-owned is never reported as an empty sequence' \
  "$out" 'locally-owned must be a non-empty sequence'

# Empty-string paths. These frame the structural pass rather than the validator:
# `@tsv` renders an empty string as a genuinely empty column, and tab is an IFS
# *whitespace* character, so reading a row with `IFS=$'\t' read` would merge the
# empty column into its neighbour and reconstruct a path pair that the manifest
# never declared — turning a rejection into a silent acceptance that `apply`
# would then materialize.
bad="${manifest/policy.txt: .policy/policy.txt: \"\"}"
invalid_case 'file destination is the empty string' "$bad" \
  "component 'base' has unsafe destination path ''"

bad="${manifest/policy.txt: .policy/\"\": .policy}"
invalid_case 'file source is the empty string' "$bad" \
  "component 'base' has unsafe source path ''" structural 'must match pattern'

# Every remaining list a manifest can drive into `assert_sorted_unique`. Bash
# refuses an empty associative-array subscript rather than treating it as a key,
# so an unguarded empty element aborts the whole run with a bash internal error
# naming neither the record nor the offending list.
bad="${manifest/'components:'$'\n''  base:'/'components:'$'\n''  "":'$'\n''    files:'$'\n''      consumer.txt: consumer.txt'$'\n''  base:'}"
invalid_case 'component name is the empty string' "$bad" \
  'component names contains an empty element'

bad="${manifest/"$requires_block"/'    requires:'$'\n''      - ""'}"
invalid_case 'component dependency is the empty string' "$bad" \
  "component 'consumer' dependencies contains an empty element"

bad="${manifest/'targets:'$'\n''  alpha/one:'/'targets:'$'\n''  "":'$'\n''    managed:'$'\n''      - base'$'\n''  alpha/one:'}"
invalid_case 'target name is the empty string' "$bad" \
  'target names contains an empty element'

bad="${manifest/'    managed:'$'\n''      - consumer'/'    managed:'$'\n''      - ""'}"
invalid_case 'target managed entry is the empty string' "$bad" \
  "target 'beta/two' managed components contains an empty element"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    locally-owned:'$'\n''      - ""'}"
invalid_case 'target locally-owned entry is the empty string' "$bad" \
  "target 'beta/two' locally-owned components contains an empty element"

# A record's own key list is the one payload `@tsv` emits unescaped, so a key
# carrying a literal newline splits its row in two. Where the injected text
# continues with a recognized row kind, the forged second row satisfies the
# column-count check and reaches the `case`, which then writes an
# associative-array subscript Bash refuses. The YAML here is double-quoted so
# `\n` and `\t` become real control characters rather than two-character escapes.
bad="${manifest/"$requires_block"/'    "x\nctag\t\tboom": 1'}"
invalid_case 'component key forges a row with an empty record name' "$bad" \
  "component 'consumer' keys may not contain control characters"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    "y\nttag\t\tboom": 1'}"
invalid_case 'target key forges a row with an empty record name' "$bad" \
  "target 'beta/two' keys may not contain control characters"

# Naming a real record instead of an empty one does not crash — `record_count`
# rises above the separately-read name count and the fail-loud assertion catches
# it — but the key is still rejected, and rejected for the right reason.
bad="${manifest/"$requires_block"/'    "x\nctag\tconsumer\tboom": 1'}"
invalid_case 'component key forges a row naming a real record' "$bad" \
  "component 'consumer' keys may not contain control characters"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    "y\nttag\tbeta/two\tboom": 1'}"
invalid_case 'target key forges a row naming a real record' "$bad" \
  "target 'beta/two' keys may not contain control characters"

# A non-string key must be reported before the control-character test runs: `test`
# only matches strings and aborts the entire pass on anything else, which would
# lose the record name along with the diagnostic.
bad="${manifest/"$requires_block"/'    7: 1'}"
invalid_case 'component key is an integer' "$bad" \
  "component 'consumer' keys must be strings"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    true: 1'}"
invalid_case 'target key is a boolean' "$bad" \
  "target 'beta/two' keys must be strings"

bad="${manifest/"$requires_block"/'    1.5: 1'}"
invalid_case 'component key is a float' "$bad" \
  "component 'consumer' keys must be strings"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    null: 1'}"
invalid_case 'target key is null' "$bad" \
  "target 'beta/two' keys must be strings"

bad="${manifest/"$requires_block"/'    ? [a, b]'$'\n''    : 1'}"
invalid_case 'component key is a sequence' "$bad" \
  "component 'consumer' keys must be strings"

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    ? {p: q}'$'\n''    : 1'}"
invalid_case 'target key is a mapping' "$bad" \
  "target 'beta/two' keys must be strings"

bad="${manifest/"$requires_block"/'    <<: &defaults'$'\n''      extra: true'}"
invalid_case 'component merge key is not supported' "$bad" \
  "component 'consumer' merge keys are not supported" engine-only

bad="${manifest/'    locally-owned:'$'\n''      - base'/'    <<: &defaults'$'\n''      extra: true'}"
invalid_case 'target merge key is not supported' "$bad" \
  "target 'beta/two' merge keys are not supported" engine-only

# A bare newline with no forged continuation used to surface as a malformed-row
# internal error; it now reports the offending record like every other key.
bad="${manifest/"$requires_block"/'    "x\nplain": 1'}"
invalid_case 'component key with a bare newline' "$bad" \
  "component 'consumer' keys may not contain control characters"

node "$root/distribution/control-char-equivalence.mjs" ||
  { echo 'control-character equivalence test failed' >&2; exit 1; }

[[ $FAILED -eq 0 ]] || exit 1
