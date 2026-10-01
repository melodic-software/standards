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

# This script installs from the fleet list alone. A repo's enabledPlugins block
# is a deltas overlay the repo's own bootstrap applies, so no call here may
# install from the checkout's settings file: reintroducing one would make the
# snapshot repo-specific again and resurrect the block as a whole-set install
# source.
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_not_contains 'setup.sh does not install from the checkout settings block' \
  "$(cat "$script")" 'install_plugins_from "$settings"'
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_not_contains 'setup.sh does not resolve the checkout settings block for install' \
  "$(cat "$script")" 'settings="$REPO_ROOT/.claude/settings.json"'

# Ordering contract: the fleet install must precede the repo bootstrap. The
# repo bootstrap applies the repo's deltas as an overlay on the fleet list and
# skips entirely when that list is absent, so a bootstrap that runs first bakes
# no deltas into the snapshot and the repo's own plugins go live only on the
# next resume.
# shellcheck disable=SC2016 # the $ is a literal in the grep needle
fleet_install_ln="$(grep -n -F 'install_plugins_from "$fleet_file" fleet' "$script" | head -n 1 | cut -d: -f1)"
repo_bootstrap_ln="$(grep -n -F 'bash .claude/cloud-bootstrap.sh' "$script" | head -n 1 | cut -d: -f1)"
if [[ -n "$fleet_install_ln" && -n "$repo_bootstrap_ln" && "$fleet_install_ln" -lt "$repo_bootstrap_ln" ]]; then
  pass 'fleet plugin install runs before the repo bootstrap'
else
  fail 'fleet plugin install runs before the repo bootstrap' \
    "fleet install at line '${fleet_install_ln:-none}', repo bootstrap at line '${repo_bootstrap_ln:-none}'"
fi

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

# Permission floor (standards#653): setup.sh fetches the claude-permissions
# floor this repository publishes and unions it into the user settings file.
# The union must reproduce the source exactly, keep everything already in the
# file, and leave the file byte-identical whenever it refuses.
floor_rel='components/claude-permissions/claude-permissions.json'
floor_src="$root/$floor_rel"
assert_file_exists 'the claude-permissions floor exists in this repository' "$floor_src"
assert_eq 'setup.sh fetches the permission floor from its published path' \
  "https://raw.githubusercontent.com/melodic-software/standards/main/$floor_rel" \
  "$(sed -n "s/^CLAUDE_PERMISSIONS_URL='\(.*\)'\$/\1/p" "$script")"
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_contains 'setup.sh composes the fetched floor into the user settings file' \
  "$(cat "$script")" 'compose_permissions_floor "$floor_file" "$user_settings"'

perm_tmp="$(mktemp -d)"
fresh="$perm_tmp/fresh/.claude/settings.json"
compose_permissions_floor "$floor_src" "$fresh"
rc=$?
assert_exit 'composer creates a missing settings file from the real floor' 0 "$rc"
assert_eq 'composed allow is exactly the source allow minus withdraw' \
  "$(jq -c '.claudePermissions | (.allow | unique) - (.withdraw // [])' "$floor_src")" \
  "$(jq -c '.permissions.allow' "$fresh")"
assert_eq 'composed deny is exactly the source deny' \
  "$(jq -c '.claudePermissions.deny | unique' "$floor_src")" \
  "$(jq -c '.permissions.deny' "$fresh")"

cat >"$perm_tmp/floor.json" <<'JSON'
{ "claudePermissions": { "schemaVersion": 1,
  "allow": ["Bash(git add *)", "Bash(gh pr create *)"],
  "deny": ["Bash(git push --force *)", "Read(**/.env)"],
  "withdraw": ["Bash(retired *)"] } }
JSON
existing="$perm_tmp/existing.json"
cat >"$existing" <<'JSON'
{ "enabledPlugins": { "alpha@stub-market": true },
  "permissions": { "allow": ["Bash(local *)", "Bash(retired *)", "Bash(git add *)"],
    "ask": ["Bash(ask *)"], "deny": ["Bash(local-deny *)"], "defaultMode": "auto" },
  "env": { "KEEP": "1" } }
JSON
chmod 0640 "$existing"
mode_settable="$(find "$existing" -perm 0640 2>/dev/null)"
compose_permissions_floor "$perm_tmp/floor.json" "$existing"
rc=$?
assert_exit 'composer merges into an existing settings file' 0 "$rc"
assert_eq 'composer keeps every non-permission key' \
  '{"enabledPlugins":{"alpha@stub-market":true},"env":{"KEEP":"1"}}' \
  "$(jq -c 'del(.permissions)' "$existing")"
assert_eq 'composer keeps ask and defaultMode untouched' \
  '{"ask":["Bash(ask *)"],"defaultMode":"auto"}' \
  "$(jq -c '.permissions | del(.allow, .deny)' "$existing")"
assert_eq 'composed allow is the union minus the withdraw tombstones' \
  '["Bash(gh pr create *)","Bash(git add *)","Bash(local *)"]' \
  "$(jq -c '.permissions.allow' "$existing")"
assert_eq 'composed deny keeps local rows and adds the floor' \
  '["Bash(git push --force *)","Bash(local-deny *)","Read(**/.env)"]' \
  "$(jq -c '.permissions.deny' "$existing")"
if [[ -z "$mode_settable" ]]; then
  skip_case 'composer keeps the file mode (chmod has no effect on this filesystem)'
elif [[ -n "$(find "$existing" -perm 0640 2>/dev/null)" ]]; then
  pass 'composer keeps the file mode'
else
  fail 'composer keeps the file mode' "mode changed from 0640: $(ls -l "$existing")"
fi
cp "$existing" "$perm_tmp/first.json"
compose_permissions_floor "$perm_tmp/floor.json" "$existing"
cmp -s "$existing" "$perm_tmp/first.json"
rc=$?
assert_exit 'composing twice is byte-identical (idempotent)' 0 "$rc"

# Refusals: each must return non-zero and leave the settings file as it was.
refused="$perm_tmp/refused.json"
check_refusal() {
  local label="$1" floor="$2" content="$3" rc
  printf '%s' "$content" >"$refused"
  cp "$refused" "$perm_tmp/before.json"
  compose_permissions_floor "$floor" "$refused" 2>/dev/null
  rc=$?
  assert_nonzero "composer refuses $label" "$rc"
  cmp -s "$refused" "$perm_tmp/before.json"
  rc=$?
  assert_exit "composer leaves the file byte-identical when it refuses $label" 0 "$rc"
}
check_refusal 'a settings file that is not valid JSON' "$perm_tmp/floor.json" '{"permissions": '
check_refusal 'a settings file that is not an object' "$perm_tmp/floor.json" '["x"]'
check_refusal 'a settings file holding two documents' "$perm_tmp/floor.json" '{} {}'
check_refusal 'a non-array permissions.allow' "$perm_tmp/floor.json" '{"permissions":{"allow":"x"}}'
jq '.claudePermissions.schemaVersion = 2' "$perm_tmp/floor.json" >"$perm_tmp/v2.json"
check_refusal 'a floor with an unknown schemaVersion' "$perm_tmp/v2.json" '{}'
jq 'del(.claudePermissions.deny)' "$perm_tmp/floor.json" >"$perm_tmp/nodeny.json"
check_refusal 'a floor without deny' "$perm_tmp/nodeny.json" '{}'
jq '.claudePermissions.allow += [7]' "$perm_tmp/floor.json" >"$perm_tmp/nonstring.json"
check_refusal 'a floor with a non-string rule' "$perm_tmp/nonstring.json" '{}'
jq '.claudePermissions.withdraw = "Bash(retired *)"' "$perm_tmp/floor.json" >"$perm_tmp/strwithdraw.json"
check_refusal 'a floor whose withdraw is not an array' "$perm_tmp/strwithdraw.json" '{}'
# A permissive first document ahead of a valid one: the merge must never use a
# document other than the one it validated.
{
  printf '%s\n' '{"claudePermissions":{"schemaVersion":1,"allow":["Bash(rm -rf *)"],"deny":[]}}'
  cat "$perm_tmp/floor.json"
} >"$perm_tmp/twodoc.json"
check_refusal 'a floor file holding two documents' "$perm_tmp/twodoc.json" '{}'
assert_eq 'refusals leave no temp file behind' '' \
  "$(find "$perm_tmp" -name '*.compose.*' 2>/dev/null)"
rm -rf "$perm_tmp"

[[ $FAILED -eq 0 ]] || exit 1
