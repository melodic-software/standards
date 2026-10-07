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
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

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

# Fleet plugin list: derived at cache build from the marketplace catalog. An
# entry set true, or with no defaultEnabled at all, is enabled; false or any
# non-boolean value leaves it out. The output is settings-shaped and
# registers the marketplace its entries name, which is what both
# install_plugins_from here and the repo bootstrap read. Sourced via
# MELODIC_SETUP_LIBONLY so the apt/dotnet/nvm tracks do not run.
# Do not `shellcheck source=` this: LIBONLY returns immediately, and following
# it marks the test bodies below unreachable (SC2317).
# shellcheck disable=SC1090,SC1091
MELODIC_SETUP_LIBONLY=1 source "$script"
cat_tmp="$(mktemp -d -p "$TEST_TMPDIR")"
cat >"$cat_tmp/catalog.json" <<'JSON'
{
  "name": "melodic-software",
  "plugins": [
    { "name": "on-explicit", "defaultEnabled": true },
    { "name": "off", "defaultEnabled": false },
    { "name": "off-string", "defaultEnabled": "false" },
    { "name": "on-default" }
  ]
}
JSON
fleet_list_from_catalog "$cat_tmp/catalog.json" "$cat_tmp/fleet.json"
rc=$?
assert_exit 'fleet list derives from a catalog' 0 "$rc"
assert_eq 'fleet list enables only entries with defaultEnabled absent or true' \
  '{"on-default@melodic-software":true,"on-explicit@melodic-software":true}' \
  "$(jq -cS '.enabledPlugins' "$cat_tmp/fleet.json")"
assert_eq 'fleet list registers the marketplace its entries name' \
  'melodic-software melodic-software/claude-code-plugins' \
  "$(jq -r '.extraKnownMarketplaces | to_entries[] | "\(.key) \(.value.source.repo)"' "$cat_tmp/fleet.json")"
printf '%s' '{"plugins":[{"name":"off","defaultEnabled":false}]}' >"$cat_tmp/alloff.json"
fleet_list_from_catalog "$cat_tmp/alloff.json" "$cat_tmp/alloff-fleet.json"
rc=$?
assert_exit 'an all-off catalog still yields a fleet list for repo opt-ins' 0 "$rc"
assert_eq 'an all-off catalog enables no plugins' '{}' \
  "$(jq -c '.enabledPlugins' "$cat_tmp/alloff-fleet.json")"
printf '%s' '{"plugins":[]}' >"$cat_tmp/empty.json"
fleet_list_from_catalog "$cat_tmp/empty.json" "$cat_tmp/none.json"
rc=$?
assert_nonzero 'a catalog with no entries yields no fleet list' "$rc"
assert_eq 'a refused derivation leaves no fleet list file' 'absent' \
  "$([[ -e "$cat_tmp/none.json" ]] && echo present || echo absent)"
printf '%s' '{"plugins": ' >"$cat_tmp/broken.json"
fleet_list_from_catalog "$cat_tmp/broken.json" "$cat_tmp/none.json"
rc=$?
assert_nonzero 'an unparsable catalog yields no fleet list' "$rc"
rm -rf "$cat_tmp"

assert_eq 'setup.sh derives the fleet list from the published catalog' \
  'https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/.claude-plugin/marketplace.json' \
  "$(sed -n "s/^FLEET_CATALOG_URL='\(.*\)'\$/\1/p" "$script")"
fleet_path="$(sed -n "s/^FLEET_PLUGINS='\(.*\)'\$/\1/p" "$script")"
if [[ -n "$fleet_path" ]]; then
  pass 'setup.sh declares the snapshot path for the fleet list'
else
  fail 'setup.sh declares the snapshot path for the fleet list' "no FLEET_PLUGINS='...' assignment found"
fi
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_contains 'setup.sh falls back when the snapshot path for the fleet list is unwritable' \
  "$(cat "$script")" 'fleet_list_from_catalog "$catalog_file" "$FLEET_PLUGINS_FALLBACK"'
assert_contains 'README documents the fleet list snapshot path' \
  "$(cat "$readme")" "$fleet_path"
assert_contains 'README documents the catalog the fleet list derives from' \
  "$(cat "$readme")" '.claude-plugin/marketplace.json'

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
# relies on when it reads the fleet list and then the repo overlay.
# Membership is in-process (no grep -qxF per entry).
plug_tmp="$(mktemp -d -p "$TEST_TMPDIR")"
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

perm_tmp="$(mktemp -d -p "$TEST_TMPDIR")"
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

# Key Vault resolver: setup.sh fetches this component's vault-exec from its
# published path, so the file in this directory is the one source. It installs
# only a file carrying the marker and never replaces a vault-exec that lacks it.
vault_exec_rel='components/cloud-environment/vault-exec'
vault_exec_src="$root/$vault_exec_rel"
assert_eq 'setup.sh fetches vault-exec from its published path' \
  "https://raw.githubusercontent.com/melodic-software/standards/main/$vault_exec_rel" \
  "$(sed -n "s/^VAULT_EXEC_URL='\(.*\)'\$/\1/p" "$script")"
vault_marker="$(sed -n "s/^VAULT_EXEC_MARKER='\(.*\)'\$/\1/p" "$script")"
grep -qxF "$vault_marker" "$vault_exec_src"
rc=$?
assert_exit 'vault-exec carries the marker setup.sh installs by' 0 "$rc"
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_contains 'setup.sh installs vault-exec under the user home' \
  "$(cat "$script")" 'vault_exec_dest="$HOME/.local/bin/vault-exec"'
# shellcheck disable=SC2088 # the ~ is literal README text
assert_contains 'README documents the vault-exec install path' \
  "$(cat "$readme")" '~/.local/bin/vault-exec'

ve_tmp="$(mktemp -d -p "$TEST_TMPDIR")"
ve_dest="$ve_tmp/home/.local/bin/vault-exec"
install_vault_exec "$vault_exec_src" "$ve_dest"
rc=$?
assert_exit 'vault-exec installs into a missing ~/.local/bin' 0 "$rc"
cmp -s "$vault_exec_src" "$ve_dest"
rc=$?
assert_exit 'the installed vault-exec is the component file' 0 "$rc"
if [[ -n "$(find "$ve_dest" -perm 0755 2>/dev/null)" ]]; then
  pass 'the installed vault-exec has mode 0755'
else
  fail 'the installed vault-exec has mode 0755' "$(ls -l "$ve_dest")"
fi
printf '%s\n%s\n' '#!/bin/bash' "$vault_marker" >"$ve_dest"
install_vault_exec "$vault_exec_src" "$ve_dest"
rc=$?
assert_exit 'an older copy of ours is replaced' 0 "$rc"
cmp -s "$vault_exec_src" "$ve_dest"
rc=$?
assert_exit 'the replaced copy is the component file' 0 "$rc"
printf '%s\n' '#!/bin/bash' 'echo someone else' >"$ve_dest"
cp "$ve_dest" "$ve_tmp/foreign"
install_vault_exec "$vault_exec_src" "$ve_dest"
rc=$?
assert_nonzero 'a vault-exec without the marker is not replaced' "$rc"
cmp -s "$ve_dest" "$ve_tmp/foreign"
rc=$?
assert_exit 'the foreign vault-exec is left byte-identical' 0 "$rc"
printf '%s\n' '<html>not found</html>' >"$ve_tmp/fetched"
install_vault_exec "$ve_tmp/fetched" "$ve_tmp/fresh/vault-exec"
rc=$?
assert_nonzero 'a fetched file without the marker is refused' "$rc"
assert_file_absent 'a refused fetch installs nothing' "$ve_tmp/fresh/vault-exec"
rm -rf "$ve_tmp"

# Page uploader: installed like vault-exec, by its own marker, and a foreign
# pages-publish is kept with a WARN that names it.
pp_rel='components/cloud-environment/pages-publish'
pp_src="$root/$pp_rel"
assert_eq 'setup.sh fetches pages-publish from its published path' \
  "https://raw.githubusercontent.com/melodic-software/standards/main/$pp_rel" \
  "$(sed -n "s/^PAGES_PUBLISH_URL='\(.*\)'\$/\1/p" "$script")"
pp_marker="$(sed -n "s/^PAGES_PUBLISH_MARKER='\(.*\)'\$/\1/p" "$script")"
grep -qxF "$pp_marker" "$pp_src"
rc=$?
assert_exit 'pages-publish carries the marker setup.sh installs by' 0 "$rc"
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_contains 'setup.sh installs pages-publish under the user home' \
  "$(cat "$script")" 'pages_publish_dest="$HOME/.local/bin/pages-publish"'
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_contains 'setup.sh names a foreign pages-publish in its WARN' \
  "$(cat "$script")" 'WARN pages-publish: $pages_publish_dest is not ours; left untouched'

pp_tmp="$(mktemp -d -p "$TEST_TMPDIR")"
pp_dest="$pp_tmp/home/.local/bin/pages-publish"
install_pages_publish "$pp_src" "$pp_dest"
rc=$?
assert_exit 'pages-publish installs into a missing ~/.local/bin' 0 "$rc"
cmp -s "$pp_src" "$pp_dest"
rc=$?
assert_exit 'the installed pages-publish is the component file' 0 "$rc"
printf '%s\n' '#!/bin/bash' 'echo someone else' >"$pp_dest"
cp "$pp_dest" "$pp_tmp/foreign"
install_pages_publish "$pp_src" "$pp_dest"
rc=$?
assert_exit 'a pages-publish without the marker is refused as not ours (2)' 2 "$rc"
cmp -s "$pp_dest" "$pp_tmp/foreign"
rc=$?
assert_exit 'the foreign pages-publish is left byte-identical' 0 "$rc"
install_pages_publish "$vault_exec_src" "$pp_tmp/fresh/pages-publish"
rc=$?
assert_exit 'a fetched file with the wrong marker is refused (1)' 1 "$rc"
assert_file_absent 'a refused fetch installs no pages-publish' "$pp_tmp/fresh/pages-publish"

# Operator files: written after the repo bootstrap, whatever its outcome.
bootstrap_ln="$(grep -n -F 'bash .claude/cloud-bootstrap.sh' "$script" | head -n 1 | cut -d: -f1)"
# shellcheck disable=SC2016 # the $ is a literal in the grep needles
for call in 'write_rendered_views "${CLAUDE_CONFIG_DIR' 'write_pages_publish_config "$pages_publish_config"'; do
  call_ln="$(grep -n -F "$call" "$script" | head -n 1 | cut -d: -f1)"
  if [[ -n "$call_ln" && -n "$bootstrap_ln" && "$call_ln" -gt "$bootstrap_ln" ]]; then
    pass "setup.sh calls ${call%% *} after the repo bootstrap"
  else
    fail "setup.sh calls ${call%% *} after the repo bootstrap" \
      "bootstrap at line '${bootstrap_ln:-none}', call at line '${call_ln:-none}'"
  fi
done

LOG="$pp_tmp/setup.log"
printf 'medium: artifact\n' >"$pp_tmp/rendered-views.md"
RENDERED_VIEWS_MD='medium: hosted' write_rendered_views "$pp_tmp/rendered-views.md"
assert_eq 'RENDERED_VIEWS_MD replaces what a repo bootstrap wrote' 'medium: hosted' \
  "$(cat "$pp_tmp/rendered-views.md")"
(unset RENDERED_VIEWS_MD && write_rendered_views "$pp_tmp/unset/rendered-views.md")
assert_file_absent 'an unset RENDERED_VIEWS_MD writes nothing' "$pp_tmp/unset/rendered-views.md"

# The config path comes from the passwd database (a stub getent here), never HOME.
mkdir -p "$pp_tmp/bin"
cat >"$pp_tmp/bin/getent" <<'STUB'
#!/usr/bin/env bash
printf '%s:x:1000:1000::%s:/bin/bash\n' "$2" "$STUB_HOME"
STUB
chmod +x "$pp_tmp/bin/getent"
pp_path="$(PATH="$pp_tmp/bin:$PATH" STUB_HOME="$pp_tmp/pwhome" HOME="$pp_tmp/decoy" pages_publish_config_path)"
assert_eq 'the config path is under the passwd home, not HOME' \
  "$pp_tmp/pwhome/.config/pages-publish/config" "$pp_path"

pp_vars=(PAGES_PUBLISH_PUBLIC_ENDPOINT=https://public.example.test
  PAGES_PUBLISH_PRIVATE_ENDPOINT=https://private.example.test
  PAGES_PUBLISH_PUBLIC_TOKEN_SECRET=pub-token PAGES_PUBLISH_PRIVATE_TOKEN_SECRET=priv-token
  PAGES_PUBLISH_PRIVATE_ACCESS_ID_SECRET=priv-access-id
  PAGES_PUBLISH_PRIVATE_ACCESS_KEY_SECRET=priv-access-key)
(export "${pp_vars[@]}" && write_pages_publish_config "$pp_path")
rc=$?
assert_exit 'all six PAGES_PUBLISH_* variables write the config' 0 "$rc"
assert_eq 'the config holds the six keys' \
  'PRIVATE_ACCESS_ID_SECRET=priv-access-id
PRIVATE_ACCESS_KEY_SECRET=priv-access-key
PRIVATE_ENDPOINT=https://private.example.test
PRIVATE_TOKEN_SECRET=priv-token
PUBLIC_ENDPOINT=https://public.example.test
PUBLIC_TOKEN_SECRET=pub-token' "$(sort "$pp_path")"
assert_eq 'the config has mode 0600' 600 "$(stat -c '%a' "$pp_path")"

rm -f "$pp_path"
(export "${pp_vars[@]:0:4}" && write_pages_publish_config "$pp_path")
rc=$?
assert_nonzero 'a partial set is refused' "$rc"
assert_file_absent 'a partial set writes no config' "$pp_path"
assert_contains 'the WARN names the missing keys' "$(cat "$LOG")" \
  'missing: PAGES_PUBLISH_PRIVATE_ACCESS_ID_SECRET PAGES_PUBLISH_PRIVATE_ACCESS_KEY_SECRET'
(export "${pp_vars[@]}" && export PAGES_PUBLISH_PUBLIC_TOKEN_SECRET=$'x\nPUBLIC_ENDPOINT=https://evil.example.test' &&
  write_pages_publish_config "$pp_path")
assert_file_absent 'a value holding a line break writes no config' "$pp_path"
(write_pages_publish_config "$pp_path")
rc=$?
assert_exit 'no PAGES_PUBLISH_* variables is a quiet no-op' 0 "$rc"
assert_file_absent 'no PAGES_PUBLISH_* variables writes no config' "$pp_path"
rm -rf "$pp_tmp"

[[ $FAILED -eq 0 ]] || exit 1
