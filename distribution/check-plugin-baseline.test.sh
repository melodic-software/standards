#!/usr/bin/env bash
# Tests check-plugin-baseline.sh's offline --compare mode: identical settings
# match, a missing/extra enabledPlugins entry and a diverging marketplace
# source are each reported, and report lines carry the candidate label.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/distribution/check-plugin-baseline.sh"

bash -n "$script" 2>/dev/null
rc=$?
assert_exit 'check-plugin-baseline.sh parses (bash -n)' 0 "$rc"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/baseline.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "melodic-software/claude-code-plugins" }
    }
  },
  "enabledPlugins": {
    "alpha@melodic-software": true,
    "beta@melodic-software": true,
    "gamma@melodic-software": false
  }
}
JSON

cp "$tmp/baseline.json" "$tmp/same.json"
out="$(bash "$script" --compare "$tmp/baseline.json" "$tmp/same.json")"
rc=$?
assert_exit 'identical settings exit 0' 0 "$rc"
assert_contains 'identical settings report a match' "$out" 'matches baseline'

cat >"$tmp/drift.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "someone-else/claude-code-plugins" }
    },
    "third-party": {
      "source": { "source": "github", "repo": "vendor/marketplace" }
    }
  },
  "enabledPlugins": {
    "alpha@melodic-software": true,
    "gamma@melodic-software": true,
    "delta@third-party": true
  }
}
JSON

out="$(bash "$script" --compare "$tmp/baseline.json" "$tmp/drift.json")"
rc=$?
assert_exit 'diverging settings exit 1' 1 "$rc"
assert_contains 'a baseline-enabled plugin absent from the candidate is reported' \
  "$out" 'missing vs baseline: beta@melodic-software'
assert_contains 'a candidate-only enabled plugin is reported' \
  "$out" 'beyond baseline: delta@third-party'
assert_contains 'a baseline-disabled plugin enabled by the candidate is reported' \
  "$out" 'beyond baseline: gamma@melodic-software'
assert_contains 'a candidate-only marketplace is reported' \
  "$out" 'marketplace beyond baseline: third-party'
assert_contains 'a diverging marketplace source is reported' \
  "$out" 'marketplace source differs: melodic-software'
assert_contains 'report lines carry the candidate label' \
  "$out" 'drift.json:'

# An unparsable candidate must be a loud usage error, never an empty diff
# read as "matches baseline".
printf 'not json' >"$tmp/broken.json"
out="$(bash "$script" --compare "$tmp/baseline.json" "$tmp/broken.json" 2>&1)"
rc=$?
assert_exit 'malformed candidate exits 2' 2 "$rc"
assert_contains 'malformed candidate is named' "$out" 'not valid JSON'

[[ $FAILED -eq 0 ]] || exit 1
