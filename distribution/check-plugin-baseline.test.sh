#!/usr/bin/env bash
# Tests check-plugin-baseline.sh's four offline comparison modes and the exit
# code each one contracts for. Report lines carry the label of the file being
# judged in every mode.
#
#   --compare <baseline> <candidate>
#     0 identical settings; 1 a missing/extra enabledPlugins entry, a
#     candidate-only marketplace or a diverging marketplace source; 2 an
#     unparsable candidate, which must never read as an empty diff.
#   --compare-catalog <catalog> <settings> <marketplace>
#     0 the settings cover the catalog; 1 a catalog plugin the settings never
#     enable or a declaration the catalog dropped; 2 an unparsable catalog.
#     Another marketplace's entries are out of scope, and the marketplace name
#     is stripped as a literal suffix, not a pattern.
#   --compare-seed <seed> [baseline]
#     0 the seed carries every fleet entry; 1 a fleet plugin the seed opts out
#     of or names beyond the fleet list; 2 an unparsable seed, or one whose
#     shape require_seed_shape rejects — a missing, scalar or non-object
#     claudeSettings.seed.enabledPlugins, or an array root.
#   --compare-seed-strict <seed> [baseline]
#     The same comparison with one class raised: 3 when a fleet plugin is
#     absent from the seed. Opt-outs and seed-only entries stay 1, a matching
#     seed stays 0, a broken seed stays 2, and plain --compare-seed keeps
#     reporting the same gap as 1.
#
# Three non-mode checks ride along: the script parses under `bash -n`,
# --compare batches its structural jq into one pass plus two parse checks, and
# the fleet list the baseline points at exists and is what the script reads.
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

# Spawn census: --compare used to run three jq filters over the same pair
# (missing plugins, extra plugins, marketplace diffs). One tagged pass is
# enough. require_parses still calls jq empty once per file.
mkdir -p "$tmp/jq-bin" "$tmp/jq-count"
cat >"$tmp/jq-bin/jq" <<'SH'
#!/usr/bin/env bash
COUNT_DIR="${COUNT_DIR:?}"
echo $(($(cat "$COUNT_DIR/jq" 2>/dev/null || echo 0) + 1)) >"$COUNT_DIR/jq"
exec "$REAL_JQ" "$@"
SH
chmod +x "$tmp/jq-bin/jq"
: >"$tmp/jq-count/jq"
real_jq="$(command -v jq)"
COUNT_DIR="$tmp/jq-count" REAL_JQ="$real_jq" PATH="$tmp/jq-bin:$PATH" \
  bash "$script" --compare "$tmp/baseline.json" "$tmp/same.json" >/dev/null
assert_eq '--compare batches structural jq into one pass plus two parse checks' '3' \
  "$(cat "$tmp/jq-count/jq")"

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

# --- fleet baseline file -----------------------------------------------------
# Fleet mode's baseline is the cloud plugin list the cloud-environment
# component installs, not this repository's own settings; it must exist and
# parse, or every fleet run would be a usage error.
fleet="$root/components/cloud-environment/fleet-plugins.json"
assert_file_exists 'the fleet list the baseline points at exists' "$fleet"
grep -q 'components/cloud-environment/fleet-plugins.json' "$script"
rc=$?
assert_exit 'check-plugin-baseline.sh takes its baseline from the fleet list' 0 "$rc"

# --- dotfiles seed comparison (--compare-seed) ------------------------------
# The personal-machine seed and the cloud list are two files on purpose; this
# mode is what keeps them from drifting apart unnoticed. Only the fleet's own
# marketplaces are in scope, and a seed false is reported as an opt-out, not
# as a missing entry.
cat >"$tmp/seed.json" <<'JSON'
{
  "claudeSettings": {
    "seed": {
      "enabledPlugins": {
        "alpha@melodic-software": true,
        "beta@melodic-software": false,
        "delta@third-party": true,
        "epsilon@melodic-software": true,
        "zeta@melodic-software": false
      }
    }
  }
}
JSON
out="$(bash "$script" --compare-seed "$tmp/seed.json" "$tmp/baseline.json")"
rc=$?
assert_exit 'a diverging seed exits 1' 1 "$rc"
assert_contains 'a fleet plugin the seed opts out of is reported as an opt-out' \
  "$out" 'in fleet list, seed opts out: beta@melodic-software'
assert_contains 'a seed entry for a fleet marketplace the fleet lacks is reported' \
  "$out" 'in seed, not in fleet list: epsilon@melodic-software'
assert_not_contains 'a seed opt-out of a plugin outside the fleet list is not a gap' \
  "$out" 'zeta@melodic-software'
assert_not_contains 'a seed entry for another marketplace is out of scope' \
  "$out" 'delta@third-party'
assert_not_contains 'a fleet-disabled entry is not demanded of the seed' \
  "$out" 'gamma@melodic-software'
assert_contains 'seed report lines carry the seed label' "$out" 'seed.json:'

cat >"$tmp/seed-match.json" <<'JSON'
{
  "claudeSettings": {
    "seed": {
      "enabledPlugins": {
        "alpha@melodic-software": true,
        "beta@melodic-software": true,
        "delta@third-party": false
      }
    }
  }
}
JSON
out="$(bash "$script" --compare-seed "$tmp/seed-match.json" "$tmp/baseline.json")"
rc=$?
assert_exit 'a seed carrying every fleet entry exits 0' 0 "$rc"
assert_contains 'a matching seed reports a match' "$out" 'matches the fleet list'

out="$(bash "$script" --compare-seed "$tmp/broken.json" "$tmp/baseline.json" 2>&1)"
rc=$?
assert_exit 'malformed seed exits 2' 2 "$rc"
assert_contains 'malformed seed is named' "$out" 'not valid JSON'

# A seed that parses can still carry no usable plugin list. Reading one as an
# empty seed reports the whole fleet as missing; a structural jq error inside
# compare_seed is swallowed and reports a match. Both are wrong about a broken
# file, so the shape is checked before the comparison and exits 2 like any
# other unreadable input.
cat >"$tmp/seed-scalar.json" <<'JSON'
{ "claudeSettings": { "seed": { "enabledPlugins": "oops" } } }
JSON
out="$(bash "$script" --compare-seed "$tmp/seed-scalar.json" "$tmp/baseline.json" 2>&1)"
rc=$?
assert_exit 'a seed whose enabledPlugins is a scalar exits 2' 2 "$rc"
assert_contains 'a scalar enabledPlugins is named' \
  "$out" 'no claudeSettings.seed.enabledPlugins object'
assert_not_contains 'a scalar enabledPlugins never reports a match' \
  "$out" 'matches the fleet list'

cat >"$tmp/seed-no-key.json" <<'JSON'
{ "claudeSettings": { "seed": {} } }
JSON
out="$(bash "$script" --compare-seed "$tmp/seed-no-key.json" "$tmp/baseline.json" 2>&1)"
rc=$?
assert_exit 'a seed with no enabledPlugins key exits 2' 2 "$rc"

printf '[]' >"$tmp/seed-array.json"
out="$(bash "$script" --compare-seed "$tmp/seed-array.json" "$tmp/baseline.json" 2>&1)"
rc=$?
assert_exit 'a seed whose root is an array exits 2' 2 "$rc"
assert_not_contains 'an array root never reports a match' "$out" 'matches the fleet list'

# --- strict seed comparison (--compare-seed-strict) -------------------------
# The CI gate acts on exactly one divergence class — a fleet plugin the seed
# never names — and must not decide that by grepping this script's prose. The
# strict mode raises that class to exit 3; the message below is asserted in
# the same breath, so rewording it without moving the flag trips here first.
cat >"$tmp/seed-gap.json" <<'JSON'
{
  "claudeSettings": {
    "seed": {
      "enabledPlugins": {
        "alpha@melodic-software": true,
        "delta@third-party": true
      }
    }
  }
}
JSON
out="$(bash "$script" --compare-seed-strict "$tmp/seed-gap.json" "$tmp/baseline.json")"
rc=$?
assert_exit 'a seed missing a fleet plugin exits 3 under --compare-seed-strict' 3 "$rc"
assert_contains 'the missing fleet plugin is still reported in the log' \
  "$out" 'in fleet list, not in seed: beta@melodic-software'

# Existing callers of --compare-seed keep today's semantics: the same gap is
# ordinary divergence, exit 1.
out="$(bash "$script" --compare-seed "$tmp/seed-gap.json" "$tmp/baseline.json")"
rc=$?
assert_exit 'the same gap stays exit 1 under plain --compare-seed' 1 "$rc"

# Only that class raises the code: a seed carrying every fleet key but opting
# out of one still diverges (exit 1), and strict mode must not escalate it,
# because the real seed's steady state is exactly this shape.
out="$(bash "$script" --compare-seed-strict "$tmp/seed.json" "$tmp/baseline.json")"
rc=$?
assert_exit 'opt-outs and seed-only entries stay exit 1 under --compare-seed-strict' 1 "$rc"
assert_contains 'the opt-out is still reported' \
  "$out" 'in fleet list, seed opts out: beta@melodic-software'

out="$(bash "$script" --compare-seed-strict "$tmp/seed-match.json" "$tmp/baseline.json")"
rc=$?
assert_exit 'a matching seed exits 0 under --compare-seed-strict' 0 "$rc"

out="$(bash "$script" --compare-seed-strict "$tmp/seed-scalar.json" "$tmp/baseline.json" 2>&1)"
rc=$?
assert_exit 'a structurally broken seed exits 2 under --compare-seed-strict' 2 "$rc"

[[ $FAILED -eq 0 ]] || exit 1
