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

# --- catalog coverage (--compare-catalog) -----------------------------------
# The blind spot the per-repo comparison cannot see: when the baseline itself
# trails the marketplace, every repo still reports "matches baseline" while
# none of them declares the newer plugins.
cat >"$tmp/catalog.json" <<'JSON'
{
  "plugins": [
    { "name": "alpha", "source": "./plugins/alpha" },
    { "name": "beta", "source": "./plugins/beta" },
    { "name": "gamma", "source": "./plugins/gamma" },
    { "name": "newcomer", "source": "./plugins/newcomer" }
  ]
}
JSON

out="$(bash "$script" --compare-catalog "$tmp/catalog.json" "$tmp/baseline.json" melodic-software)"
rc=$?
assert_exit 'a baseline trailing the catalog exits 1' 1 "$rc"
assert_contains 'a catalog plugin the baseline never enables is reported' \
  "$out" 'in catalog, not declared: newcomer@melodic-software'
assert_contains 'a catalog plugin the baseline disables is reported' \
  "$out" 'in catalog, not declared: gamma@melodic-software'
assert_not_contains 'an enabled plugin present in the catalog is not reported' \
  "$out" 'alpha@melodic-software'
assert_contains 'catalog report lines carry the settings label' \
  "$out" 'baseline.json:'

# Entries for another marketplace are out of this catalog's scope: reporting
# them would make every third-party plugin look retired.
cat >"$tmp/covering.json" <<'JSON'
{
  "enabledPlugins": {
    "alpha@melodic-software": true,
    "beta@melodic-software": true,
    "gamma@melodic-software": true,
    "newcomer@melodic-software": true,
    "delta@third-party": true
  }
}
JSON

out="$(bash "$script" --compare-catalog "$tmp/catalog.json" "$tmp/covering.json" melodic-software)"
rc=$?
assert_exit 'full catalog coverage exits 0' 0 "$rc"
assert_contains 'full coverage reports a match' "$out" 'covers the catalog'
assert_not_contains 'another marketplace is out of scope' "$out" 'delta@third-party'

# A plugin dropped from the catalog leaves a declaration installing nothing.
cat >"$tmp/retired.json" <<'JSON'
{
  "enabledPlugins": {
    "alpha@melodic-software": true,
    "beta@melodic-software": true,
    "gamma@melodic-software": true,
    "newcomer@melodic-software": true,
    "removed@melodic-software": true
  }
}
JSON

out="$(bash "$script" --compare-catalog "$tmp/catalog.json" "$tmp/retired.json" melodic-software)"
rc=$?
assert_exit 'a declaration the catalog dropped exits 1' 1 "$rc"
assert_contains 'a plugin no longer in the catalog is reported' \
  "$out" 'declared, not in catalog: removed@melodic-software'

# A marketplace name is interpolated text, not a pattern: a regex
# metacharacter in it must strip as a literal suffix.
cat >"$tmp/dotted.json" <<'JSON'
{
  "enabledPlugins": {
    "alpha@my.market": true
  }
}
JSON

cat >"$tmp/dotted-catalog.json" <<'JSON'
{ "plugins": [ { "name": "alpha", "source": "./plugins/alpha" } ] }
JSON

out="$(bash "$script" --compare-catalog "$tmp/dotted-catalog.json" "$tmp/dotted.json" 'my.market')"
rc=$?
assert_exit 'a marketplace name with a regex metacharacter exits 0' 0 "$rc"
assert_contains 'the metacharacter name matches literally' "$out" 'covers the catalog'

# An unreadable catalog must be a loud usage error, never an empty diff read
# as "covers the catalog".
out="$(bash "$script" --compare-catalog "$tmp/broken.json" "$tmp/baseline.json" melodic-software 2>&1)"
rc=$?
assert_exit 'malformed catalog exits 2' 2 "$rc"
assert_contains 'malformed catalog is named' "$out" 'not valid JSON'

[[ $FAILED -eq 0 ]] || exit 1
