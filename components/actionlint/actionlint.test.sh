#!/usr/bin/env bash
# Tests the actionlint component: the root-canonical config lets the GA
# concurrency.queue key and the declared self-hosted fleet labels lint clean
# without hiding unrelated findings. Skips cleanly when the engine is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='.github/actionlint.yaml'

if ! command -v actionlint >/dev/null 2>&1; then
  skip_suite 'actionlint not installed'
fi
# The `paths` config key shipped in actionlint 1.7.4; older engines reject it.
require_min_version actionlint "$(actionlint -version | head -n 1)" 1.7.4

# actionlint resolves the config and workflows from the project root, so the
# fixtures run inside a scratch repo mirroring a consumer checkout.
project="$(mktemp -d)"
trap 'rm -rf -- "$project"' EXIT
make_repo "$project"
mkdir -p "$project/.github/workflows"
cp "$config" "$project/.github/"
cp components/actionlint/fixtures/good/queue-concurrency.yml "$project/.github/workflows/"
cp components/actionlint/fixtures/good/fleet-runner-labels.yml "$project/.github/workflows/"

queue_message='unexpected key "queue" for "concurrency" section'
fleet_message='label "melodic-ubuntu-24.04-x64" is unknown'
review_message='label "melodic-review-ubuntu-24.04-x64" is unknown'
undeclared_message='label "melodic-undeclared-ubuntu-24.04-x64" is unknown'

out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_exit 'queue and fleet-label workflows lint clean with the config' 0 "$rc"
assert_silent 'suppressed run emits no findings' "$out"

cp components/actionlint/fixtures/bad/unknown-key.yml "$project/.github/workflows/"
cp components/actionlint/fixtures/bad/unknown-runner-label.yml "$project/.github/workflows/"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'unrelated violation still fails with the config' "$rc"
assert_contains 'unrelated violation is reported' "$out" 'unexpected key "unknown-key"'
assert_not_contains 'suppression stays scoped to its exact message' "$out" "$queue_message"
assert_contains 'an undeclared fleet-shaped label is still rejected' "$out" "$undeclared_message"
assert_not_contains 'the declared fleet label stays admitted' "$out" "$fleet_message"

# Control: without the config the queue key and both fleet labels must be
# rejected. When this case fails, either the upstream fix shipped in the pinned
# engine or the fleet label became built-in; fire the removal trigger recorded
# in the config instead of patching this test.
rm "$project/.github/actionlint.yaml" \
  "$project/.github/workflows/unknown-key.yml" \
  "$project/.github/workflows/unknown-runner-label.yml"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'queue and fleet-label workflows fail without the config (removal tripwire)' "$rc"
assert_contains 'control run reports the suppressed message' "$out" "$queue_message"
assert_contains 'control run reports the build fleet label' "$out" "$fleet_message"
assert_contains 'control run reports the review fleet label' "$out" "$review_message"

[[ $FAILED -eq 0 ]] || exit 1
