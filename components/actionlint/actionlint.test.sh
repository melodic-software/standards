#!/usr/bin/env bash
# Tests the actionlint component: the root-canonical config lets the declared
# self-hosted fleet labels lint clean while an undeclared fleet-shaped label
# still fails. Skips cleanly when the engine is absent.
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
cp components/actionlint/fixtures/good/fleet-runner-labels.yml "$project/.github/workflows/"

fleet_message='label "melodic-ubuntu-24.04-x64" is unknown'
review_message='label "melodic-review-ubuntu-24.04-x64" is unknown'
undeclared_message='label "melodic-undeclared-ubuntu-24.04-x64" is unknown'

out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_exit 'fleet-label workflow lints clean with the config' 0 "$rc"
assert_silent 'configured run emits no findings' "$out"

cp components/actionlint/fixtures/bad/unknown-runner-label.yml "$project/.github/workflows/"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'an undeclared fleet-shaped label still fails with the config' "$rc"
assert_contains 'an undeclared fleet-shaped label is still rejected' "$out" "$undeclared_message"
assert_not_contains 'the declared fleet label stays admitted' "$out" "$fleet_message"

# Control: without the config both fleet labels must be rejected. When this
# case fails, the fleet label became built-in; drop it from the config instead
# of patching this test.
rm "$project/.github/actionlint.yaml" \
  "$project/.github/workflows/unknown-runner-label.yml"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'fleet-label workflow fails without the config (removal tripwire)' "$rc"
assert_contains 'control run reports the build fleet label' "$out" "$fleet_message"
assert_contains 'control run reports the review fleet label' "$out" "$review_message"

# `$/` same-release reference: the scoped ignore admits it, and only it.
cp "$config" "$project/.github/"
rm -f "$project"/.github/workflows/*.yml
cp components/actionlint/fixtures/good/dollar-local-ref.yml "$project/.github/workflows/"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_exit 'a $/ same-release reference lints clean with the config' 0 "$rc"
assert_silent 'the $/ run emits no findings' "$out"

cp components/actionlint/fixtures/bad/missing-ref.yml "$project/.github/workflows/"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'a ref-less owner/repo/path still fails with the config' "$rc"
assert_contains 'the ref-less reference is still rejected' "$out" 'specifying action "owner/repo/path"'
assert_not_contains 'the $/ reference stays admitted' "$out" 'specifying action "$/'

rm "$project/.github/workflows/missing-ref.yml"
cp components/actionlint/fixtures/bad/empty-dollar-ref.yml "$project/.github/workflows/"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'a bare $/ reference still fails with the config' "$rc"
assert_contains 'the bare $/ reference is still rejected' "$out" 'specifying action "$/"'
rm "$project/.github/workflows/empty-dollar-ref.yml"
cp components/actionlint/fixtures/bad/missing-ref.yml "$project/.github/workflows/"

# Control: without the config the $/ reference must be rejected. When this
# case fails, actionlint accepts `$/` natively; drop the ignore instead of
# patching this test.
rm "$project/.github/actionlint.yaml" \
  "$project/.github/workflows/missing-ref.yml"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'a $/ reference fails without the config (removal tripwire)' "$rc"
assert_contains 'control run reports the $/ reference' "$out" 'specifying action "$/.github/actions/typos"'

# `concurrency.queue`: the scoped ignore admits it, and only its exact message.
queue_message='unexpected key "queue" for "concurrency" section'
cp "$config" "$project/.github/"
rm -f "$project"/.github/workflows/*.yml
cp components/actionlint/fixtures/good/queue-concurrency.yml "$project/.github/workflows/"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_exit 'a concurrency.queue workflow lints clean with the config' 0 "$rc"
assert_silent 'the queue run emits no findings' "$out"

cp components/actionlint/fixtures/bad/unknown-key.yml "$project/.github/workflows/"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'an unrelated unexpected key still fails with the config' "$rc"
assert_contains 'the unrelated key is reported' "$out" 'unexpected key "unknown-key"'
assert_not_contains 'the queue suppression stays scoped to its exact message' "$out" "$queue_message"

# Control: without the config the queue key must be rejected. When this case
# fails, rhysd/actionlint#654 shipped in the pinned engine; drop the ignore
# instead of patching this test.
rm "$project/.github/actionlint.yaml" \
  "$project/.github/workflows/unknown-key.yml"
out="$(cd "$project" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'a concurrency.queue workflow fails without the config (removal tripwire)' "$rc"
assert_contains 'control run reports the queue message' "$out" "$queue_message"

[[ $FAILED -eq 0 ]] || exit 1
