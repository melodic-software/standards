#!/usr/bin/env bash
# Tests the zizmor component: with the root-canonical config, first-party and
# official-vendor refs on a branch or tag, a SHA-pinned third-party action and a
# 3-day Dependabot cooldown audit clean, a third-party tag still fails
# unpinned-uses, and a configless control run flags the first-party reusable,
# the vendor tags and the cooldown.
# Skips when zizmor is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='.github/zizmor.yml'
fixtures='components/zizmor/fixtures'

if ! command -v zizmor >/dev/null 2>&1; then
  skip_suite 'zizmor not installed'
fi
# Discovery from the repository root holds from 1.29.0; actions.lock and
# parallel: step support hold from 1.33.1.
version_output="$(zizmor --version)"
require_min_version zizmor "${version_output##* }" 1.33.1

# zizmor discovers .github/zizmor.yml from the Git root, so the fixtures run
# inside a scratch repo mirroring a consumer checkout.
project="$(mktemp -d)"
trap 'rm -rf -- "$project"' EXIT
make_repo "$project"
mkdir -p "$project/.github/workflows"
cp "$config" "$project/.github/"
cp "$fixtures/good/first-party-float.yml" "$fixtures/good/vendor-float.yml" "$project/.github/workflows/"
cp "$fixtures/good/dependabot.yml" "$project/.github/"

audit() { (cd "$project" && zizmor --offline --no-progress --color=never -- "$@" 2>&1); }

for input in . .github .github/workflows; do
  out="$(audit "$input")"
  rc=$?
  assert_exit "first-party and vendor refs and a 3-day cooldown audit clean (input $input)" 0 "$rc"
  assert_not_contains "no unpinned-uses finding (input $input)" "$out" 'unpinned-uses'
done

cp "$fixtures/bad/third-party-tag.yml" "$project/.github/workflows/"
out="$(audit .)"
rc=$?
assert_nonzero 'a third-party tag still fails with the config' "$rc"
assert_contains 'the third-party tag is rejected' "$out" 'third-party-tag.yml:'
assert_not_contains 'first-party refs stay admitted' "$out" 'first-party-float.yml:'
assert_not_contains 'vendor refs stay admitted' "$out" 'vendor-float.yml:'

# Locking the same third-party tag in actions.lock clears the unpinned-uses
# finding that just failed above, proving zizmor actually reads actions.lock;
# a parallel: step block also audits clean under the shipped config.
cat <<'EOF' >"$project/.github/workflows/parallel-steps.yml"
name: parallel-steps
on: push
permissions: {}
jobs:
  verify:
    runs-on: ubuntu-24.04
    steps:
      - parallel:
          - name: First check
            run: exit 0
          - name: Second check
            run: exit 0
EOF
cat <<'EOF' >"$project/.github/workflows/actions.lock"
version: 'v0.0.3'
workflows:
  '.github/workflows/third-party-tag.yml':
    - 'docker/setup-buildx-action@v3'
dependencies:
  'docker/setup-buildx-action@v3':
    ref: 'v3'
    commit: 'sha1-0123456789abcdef0123456789abcdef01234567'
    owner_id: 5429470
    repo_id: 295610011
EOF
out="$(audit .)"
rc=$?
assert_exit 'third-party tag locked in actions.lock and parallel steps audit clean' 0 "$rc"
assert_not_contains 'actions.lock clears unpinned-uses for the third-party tag' "$out" 'unpinned-uses'
rm "$project/.github/workflows/parallel-steps.yml" "$project/.github/workflows/actions.lock"

# Control: without the config zizmor's default hash-pins every ref and wants a
# 7-day cooldown. When this fails, the default changed; recheck the policy.
rm "$project/.github/zizmor.yml" "$project/.github/workflows/third-party-tag.yml"
out="$(audit .)"
rc=$?
assert_nonzero 'first-party @main refs fail without the config (removal tripwire)' "$rc"
assert_contains 'control run flags first-party refs' "$out" 'first-party-float.yml:'
assert_contains 'control run flags vendor tags' "$out" 'vendor-float.yml:'
assert_contains 'control run flags the 3-day cooldown' "$out" 'dependabot-cooldown'

[[ $FAILED -eq 0 ]] || exit 1
