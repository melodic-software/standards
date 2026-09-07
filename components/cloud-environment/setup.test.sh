#!/usr/bin/env bash
# Tests the cloud-environment component: the canonical setup script parses,
# honors its ordering contract (the completion stamp is written only after the
# parallel install tracks finish), and the README documents the same bootstrap
# URL and stamp path the script implements — the drift a copy-paste consumer
# would actually hit.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/cloud-environment/setup.sh"
readme="$root/components/cloud-environment/README.md"

bash -n "$script" 2>/dev/null
rc=$?
assert_exit 'setup.sh parses (bash -n)' 0 "$rc"

tail -n 1 "$script" | grep -qx 'exit 0'
rc=$?
assert_exit 'setup.sh ends with exit 0 (cache-build contract)' 0 "$rc"

# Ordering contract: the stamp write must come after the `wait` barrier, so an
# interrupted build can never leave a stamp behind.
wait_ln="$(grep -n '^wait$' "$script" | head -n 1 | cut -d: -f1)"
stamp_ln="$(grep -n '>"[$]STAMP"' "$script" | head -n 1 | cut -d: -f1)"
if [[ -n "$wait_ln" && -n "$stamp_ln" && "$stamp_ln" -gt "$wait_ln" ]]; then
  pass 'completion stamp is written only after the wait barrier'
else
  fail 'completion stamp is written only after the wait barrier' \
    "wait at line '${wait_ln:-none}', stamp write at line '${stamp_ln:-none}'"
fi

# Pin lockstep: the script now reads pins from the resolved checkout's own
# manifests, but its FALLBACK Node pin (used when a repo declares none) must
# still match the fleet pin this repository itself carries in .node-version —
# the drift the README's update-lifecycle section otherwise leaves to manual
# diligence. (The .NET fallback list has no in-repo manifest to check against;
# it stays a documented manual obligation.)
node_pin_repo="$(tr -d '[:space:]' <"$root/.node-version")"
node_pin_script="$(sed -n "s/^NODE_FALLBACK_VERSION='\([0-9][0-9.]*\)'\$/\1/p" "$script" | head -n 1)"
if [[ -n "$node_pin_script" ]]; then
  pass "setup.sh declares a Node fallback pin (NODE_FALLBACK_VERSION='<version>')"
else
  fail "setup.sh declares a Node fallback pin (NODE_FALLBACK_VERSION='<version>')" \
    "no NODE_FALLBACK_VERSION='<version>' assignment found"
fi
assert_eq 'setup.sh Node fallback pin matches the repo .node-version' \
  "$node_pin_repo" "$node_pin_script"

# CWD-independence contract: the bootstrap and plugin steps must key off an
# explicitly resolved repo root, never a relative path from the build's CWD —
# the regression a real cache build hit (SW2030, 2026-08-23: CWD was not the
# checkout, so both steps silently no-opped).
grep -q 'git rev-parse --show-toplevel' "$script"
rc=$?
assert_exit 'setup.sh resolves the repo root explicitly (git rev-parse)' 0 "$rc"
# shellcheck disable=SC2016 # the $ is a literal in the grep pattern
grep -q '\$REPO_ROOT/\.claude/cloud-bootstrap\.sh' "$script"
rc=$?
assert_exit 'setup.sh addresses the repo bootstrap via REPO_ROOT, not CWD' 0 "$rc"

# Stamp fallback contract: a failed /opt stamp write must fall back (mirroring
# the LOG fallback) instead of silently presenting as an unfinished build.
# shellcheck disable=SC2016 # the $ is a literal in the grep pattern
grep -q '>"\$STAMP_FALLBACK"' "$script"
rc=$?
assert_exit 'setup.sh falls back when the primary stamp write fails' 0 "$rc"

# Fleet plugin list: the settings-shaped file every snapshot installs. It must
# parse, enable everything it names (a false entry is a per-repo delta, not a
# fleet decision), keep its keys in byte order so a single entry can be
# flipped without disturbing the rest, and declare every marketplace its
# entries name.
fleet="$root/components/cloud-environment/fleet-plugins.json"
assert_file_exists 'fleet-plugins.json exists beside setup.sh' "$fleet"
jq empty "$fleet" 2>/dev/null
rc=$?
assert_exit 'fleet-plugins.json parses' 0 "$rc"
assert_eq 'fleet-plugins.json enables every entry it names' \
  '0' "$(jq -r '[.enabledPlugins // {} | to_entries[] | select(.value != true)] | length' "$fleet")"
assert_eq 'fleet-plugins.json keys are in byte order' \
  "$(jq -r '.enabledPlugins | keys_unsorted[]' "$fleet" | LC_ALL=C sort)" \
  "$(jq -r '.enabledPlugins | keys_unsorted[]' "$fleet")"
assert_eq 'fleet-plugins.json declares every marketplace its entries name' \
  '' "$(jq -r '(.extraKnownMarketplaces // {} | keys) as $mps
    | [.enabledPlugins // {} | keys[] | split("@") | .[1:] | join("@")] | unique
    | map(select(IN($mps[]) | not)) | .[]' "$fleet")"

# Fetch lockstep: the URL setup.sh fetches must name the file this repository
# publishes, at the same host the README's bootstrap already relies on.
fleet_url="$(sed -n "s/^FLEET_PLUGINS_URL='\(.*\)'\$/\1/p" "$script")"
assert_eq 'setup.sh fetches the fleet list from its published path' \
  'https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/fleet-plugins.json' \
  "$fleet_url"
fleet_path="$(sed -n "s/^FLEET_PLUGINS='\(.*\)'\$/\1/p" "$script")"
if [[ -n "$fleet_path" ]]; then
  pass 'setup.sh declares the snapshot path for the fleet list'
else
  fail 'setup.sh declares the snapshot path for the fleet list' "no FLEET_PLUGINS='...' assignment found"
fi
# shellcheck disable=SC2016 # the $ is a literal in the grep pattern
grep -q '>"\$FLEET_PLUGINS_FALLBACK"\|-o "\$FLEET_PLUGINS_FALLBACK"' "$script"
rc=$?
assert_exit 'setup.sh falls back when the snapshot path for the fleet list is unwritable' 0 "$rc"
assert_contains 'README documents the fleet list snapshot path' \
  "$(cat "$readme")" "$fleet_path"
assert_contains 'README documents the fleet list file' \
  "$(cat "$readme")" 'fleet-plugins.json'

# README/script drift guards.
stamp_path="$(sed -n "s/^STAMP='\(.*\)'\$/\1/p" "$script")"
if [[ -n "$stamp_path" ]]; then
  pass 'setup.sh declares a stamp path'
else
  fail 'setup.sh declares a stamp path' "no STAMP='...' assignment found"
fi
assert_contains 'README documents the stamp path the script writes' \
  "$(cat "$readme")" "$stamp_path"

# gh install contract: the fleet runs one gh across three lanes (this script,
# the ci-runner image, dotfiles/mise). Ubuntu's archive gh is years stale, so
# an apt install here silently reopens that gap — guard the pinned,
# checksum-verified release asset instead.
grep -q 'apt-get install -y gh' "$script"
rc=$?
assert_exit 'setup.sh does not install gh from the Ubuntu archive' 1 "$rc"

gh_pin="$(sed -n "s/^GH_VERSION='\([0-9][0-9.]*\)'\$/\1/p" "$script" | head -n 1)"
if [[ -n "$gh_pin" ]]; then
  pass "setup.sh declares a gh pin (GH_VERSION='<version>')"
else
  fail "setup.sh declares a gh pin (GH_VERSION='<version>')" \
    "no GH_VERSION='<version>' assignment found"
fi

gh_sha="$(sed -n "s/^GH_SHA256='\([0-9a-f]\{64\}\)'\$/\1/p" "$script" | head -n 1)"
if [[ -n "$gh_sha" ]]; then
  pass 'setup.sh declares a 64-hex gh asset checksum (GH_SHA256)'
else
  fail 'setup.sh declares a 64-hex gh asset checksum (GH_SHA256)' \
    "no GH_SHA256='<64 hex chars>' assignment found"
fi

# shellcheck disable=SC2016 # the ${GH_VERSION} is literal text being searched for
assert_contains 'setup.sh fetches gh from the pinned upstream release asset' \
  "$(cat "$script")" 'https://github.com/cli/cli/releases/download/v${GH_VERSION}/'
assert_contains 'setup.sh verifies the gh asset before installing it' \
  "$(cat "$script")" 'sha256sum --check --strict'
assert_contains 'README documents the gh version the script installs' \
  "$(cat "$readme")" "$gh_pin"
assert_contains 'README bootstrap URL matches the component path' \
  "$(cat "$readme")" \
  'raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/setup.sh'

# The build installs from the fleet list alone. A repo's enabledPlugins block
# is a deltas overlay applied by the session bootstrap's drift repair, so no
# call here may install from the checkout's settings file: reintroducing one
# would make the snapshot repo-specific again and resurrect the block as a
# whole-set install source.
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_not_contains 'setup.sh does not install from the checkout settings block' \
  "$(cat "$script")" 'install_plugins_from "$settings"'
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_not_contains 'setup.sh does not resolve the checkout settings block for install' \
  "$(cat "$script")" 'settings="$REPO_ROOT/.claude/settings.json"'

# Spawn census for install_plugins_from: two sources must share one
# marketplace list and one plugin list, the memoization cloud-bootstrap.sh
# relies on when it reads the fleet list and then the repo overlay. Sourced
# via MELODIC_SETUP_LIBONLY so the apt/dotnet/nvm tracks do not run.
# Membership is in-process (no grep -qxF per entry).
plug_tmp="$(mktemp -d)"
# Do not `shellcheck source=` this: LIBONLY returns immediately, and following
# it marks the census body unreachable (SC2317).
# shellcheck disable=SC1090,SC1091
MELODIC_SETUP_LIBONLY=1 source "$script"
mkdir -p "$plug_tmp/bin" "$plug_tmp/counts"
cat >"$plug_tmp/bin/claude" <<STUB
#!/usr/bin/env bash
COUNT_DIR="${plug_tmp}/counts"
mkdir -p "\$COUNT_DIR"
case "\$1 \$2 \$3" in
  "plugin marketplace list")
    echo \$(( \$(cat "\$COUNT_DIR/marketplace-list" 2>/dev/null || echo 0) + 1 )) >"\$COUNT_DIR/marketplace-list"
    printf '[{"name":"stub-market"}]\n'
    ;;
  "plugin list "*)
    echo \$(( \$(cat "\$COUNT_DIR/plugin-list" 2>/dev/null || echo 0) + 1 )) >"\$COUNT_DIR/plugin-list"
    printf '[{"id":"alpha@stub-market"}]\n'
    ;;
  "plugin marketplace add")
    echo \$(( \$(cat "\$COUNT_DIR/marketplace-add" 2>/dev/null || echo 0) + 1 )) >"\$COUNT_DIR/marketplace-add"
    ;;
  "plugin install "*)
    echo \$(( \$(cat "\$COUNT_DIR/plugin-install" 2>/dev/null || echo 0) + 1 )) >"\$COUNT_DIR/plugin-install"
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$plug_tmp/bin/claude"
echo 0 >"$plug_tmp/counts/marketplace-list"
echo 0 >"$plug_tmp/counts/plugin-list"
echo 0 >"$plug_tmp/counts/marketplace-add"
echo 0 >"$plug_tmp/counts/plugin-install"
cat >"$plug_tmp/fleet.json" <<'JSON'
{
  "extraKnownMarketplaces": { "stub-market": { "source": { "source": "github", "repo": "example/stub" } } },
  "enabledPlugins": { "alpha@stub-market": true, "beta@stub-market": true }
}
JSON
cat >"$plug_tmp/repo.json" <<'JSON'
{
  "extraKnownMarketplaces": { "stub-market": { "source": { "source": "github", "repo": "example/stub" } } },
  "enabledPlugins": { "alpha@stub-market": true, "gamma@stub-market": true }
}
JSON
LOG="$plug_tmp/setup.log"
PATH="$plug_tmp/bin:$PATH"
install_plugins_from "$plug_tmp/fleet.json" fleet
install_plugins_from "$plug_tmp/repo.json" repo
assert_eq 'setup.sh lists marketplaces once across fleet+repo' '1' \
  "$(cat "$plug_tmp/counts/marketplace-list")"
assert_eq 'setup.sh lists plugins once across fleet+repo' '1' \
  "$(cat "$plug_tmp/counts/plugin-list")"
assert_eq 'already-registered marketplace is not added again' '0' \
  "$(cat "$plug_tmp/counts/marketplace-add")"
assert_eq 'missing plugins from either source are installed' '2' \
  "$(cat "$plug_tmp/counts/plugin-install")"
assert_contains 'warm fleet pass logs already-installed alpha' \
  "$(cat "$LOG")" 'plugins (fleet): alpha@stub-market already installed'
assert_contains 'repo pass installs gamma without a second plugin list' \
  "$(cat "$LOG")" 'plugins (repo): installed gamma@stub-market'
rm -rf "$plug_tmp"

[[ $FAILED -eq 0 ]] || exit 1
