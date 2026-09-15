#!/usr/bin/env bash
# Tests private-repo-inventory.sh offline: every visibility fact comes from a
# fixture file, so no test needs a GitHub credential or the network.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/lychee/private-repo-inventory.sh"
work="$(mktemp -d "$root/.lychee-inventory-fixture.XXXXXX")"
if [[ -z "$work" ]]; then
  printf 'ERROR: could not create a scratch directory under %s\n' "$root" >&2
  exit 1
fi
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# write_config <path> <github-alternation> <raw-alternation>
write_config() {
  cat >"$1" <<EOF
include_fragments = "full"
exclude = [
  '^https?://localhost',
  # PRIVATE GitHub repos.
  '^https?://github\\.com/melodic-software/($2)(\\.git)?([/#?]|\$)',
  '^https?://raw\\.githubusercontent\\.com/melodic-software/($3)/',
]
EOF
}

config="$work/lychee.toml"
write_config "$config" 'alpha|beta|gamma' 'alpha|beta|gamma'
printf '%s\n' public-one public-two >"$work/public.txt"
printf '%s\n' alpha beta gamma >"$work/private.txt"

# --- list ------------------------------------------------------------------
out="$(bash "$script" list --config "$config")"
assert_eq 'list prints one inventory entry per line' $'alpha\nbeta\ngamma' "$out"

# --- check: agreement ------------------------------------------------------
out="$(bash "$script" check --config "$config" --public-list "$work/public.txt" --private-list "$work/private.txt" 2>&1)"
assert_exit 'check passes when the inventory equals the private set' 0 $?
assert_contains 'check reports agreement' "$out" 'OK:'

out="$(bash "$script" check --config "$config" --public-list "$work/public.txt" 2>&1)"
assert_exit 'check passes on the public half alone' 0 $?
assert_contains 'public-only check names the entries it could not verify' "$out" 'not verifiable'

# --- check: a private repo missing from the inventory (the #212 / #483 class)
printf '%s\n' alpha beta gamma delta >"$work/private-plus.txt"
out="$(bash "$script" check --config "$config" --public-list "$work/public.txt" --private-list "$work/private-plus.txt" 2>&1)"
assert_exit 'check fails when a private repo is missing' 1 $?
assert_contains 'the missing repo is named' "$out" 'delta is private but not excluded'
assert_contains 'the regenerated github entry includes it, sorted' "$out" \
  "'^https?://github\\.com/melodic-software/(alpha|beta|delta|gamma)(\\.git)?([/#?]|\$)',"
assert_contains 'the regenerated raw entry includes it, sorted' "$out" \
  "'^https?://raw\\.githubusercontent\\.com/melodic-software/(alpha|beta|delta|gamma)/',"

# --- check: an excluded repo that went public ------------------------------
printf '%s\n' public-one beta >"$work/public-beta.txt"
out="$(bash "$script" check --config "$config" --public-list "$work/public-beta.txt" 2>&1)"
assert_exit 'check fails when an excluded repo is public' 1 $?
assert_contains 'the wrongly excluded repo is named' "$out" 'beta is public but excluded as private'
assert_contains 'the regenerated entry drops it' "$out" '/(alpha|gamma)(\.git)?'

# --- check: App installation list (partial truth) --------------------------
printf 'alpha\ttrue\nbeta\ttrue\ndelta\ttrue\npublic-one\tfalse\n' >"$work/installation.tsv"
out="$(bash "$script" check --config "$config" --public-list "$work/public.txt" --installation-list "$work/installation.tsv" 2>&1)"
assert_exit 'check fails when an installation-visible private repo is missing' 1 $?
assert_contains 'the installation-detected gap is named' "$out" 'delta is private (per the App installation) but not excluded'
assert_contains 'entries the installation cannot see stay reported as unverified' "$out" 'assumed still private): gamma'

printf 'alpha\ttrue\nbeta\ttrue\ngamma\ttrue\n' >"$work/installation-ok.tsv"
out="$(bash "$script" check --config "$config" --public-list "$work/public.txt" --installation-list "$work/installation-ok.tsv" 2>&1)"
assert_exit 'check passes when the installation confirms every entry' 0 $?
assert_not_contains 'nothing is left unverified' "$out" 'not verifiable'

# --- check: structural invariants ------------------------------------------
write_config "$work/unsorted.toml" 'gamma|alpha|beta' 'gamma|alpha|beta'
out="$(bash "$script" check --config "$work/unsorted.toml" --public-list "$work/public.txt" 2>&1)"
assert_exit 'check fails on an unsorted alternation' 1 $?
assert_contains 'the sorted form is shown' "$out" 'should read (alpha|beta|gamma)'

write_config "$work/mismatch.toml" 'alpha|beta|gamma' 'alpha|beta'
out="$(bash "$script" check --config "$work/mismatch.toml" --public-list "$work/public.txt" 2>&1)"
assert_exit 'check fails when the two alternations differ' 1 $?
assert_contains 'the mismatch is described' "$out" 'alternations differ'

write_config "$work/dotted.toml" 'alpha|my\.repo' 'alpha|my\.repo'
printf '%s\n' alpha my.repo >"$work/private-dotted.txt"
out="$(bash "$script" check --config "$work/dotted.toml" --public-list "$work/public.txt" --private-list "$work/private-dotted.txt" 2>&1)"
assert_exit 'a dotted repo name round-trips through regex escaping' 0 $?

# --- generate ----------------------------------------------------------------
out="$(bash "$script" generate --config "$config" --private-list "$work/private-plus.txt")"
assert_contains 'generate prints the github entry' "$out" \
  "'^https?://github\\.com/melodic-software/(alpha|beta|delta|gamma)(\\.git)?([/#?]|\$)',"
assert_contains 'generate prints the raw entry' "$out" \
  "'^https?://raw\\.githubusercontent\\.com/melodic-software/(alpha|beta|delta|gamma)/',"
assert_eq 'generate without --write leaves the config untouched' \
  "$(bash "$script" list --config "$config")" $'alpha\nbeta\ngamma'

bash "$script" generate --config "$config" --private-list "$work/private-plus.txt" --write >/dev/null
assert_exit 'generate --write succeeds' 0 $?
assert_eq 'generate --write rewrites both alternations' \
  $'alpha\nbeta\ndelta\ngamma' "$(bash "$script" list --config "$config")"
out="$(bash "$script" check --config "$config" --public-list "$work/public.txt" --private-list "$work/private-plus.txt" 2>&1)"
assert_exit 'the rewritten config passes check' 0 $?
assert_contains 'the untouched entries survive the rewrite' "$(<"$config")" "'^https?://localhost',"
assert_contains 'the comment survives the rewrite' "$(<"$config")" '# PRIVATE GitHub repos.'

: >"$work/empty.txt"
out="$(bash "$script" generate --config "$config" --private-list "$work/empty.txt" 2>&1)"
assert_exit 'generate refuses an empty private set' 2 $?
assert_contains 'the refusal is explicit' "$out" 'refusing to generate an empty inventory'

# --- usage errors ------------------------------------------------------------
out="$(bash "$script" check --config "$work/missing.toml" 2>&1)"
assert_exit 'a missing config is a usage error' 2 $?
out="$(bash "$script" frobnicate 2>&1)"
assert_exit 'an unknown command is a usage error' 2 $?

[[ $FAILED -eq 0 ]] || exit 1
