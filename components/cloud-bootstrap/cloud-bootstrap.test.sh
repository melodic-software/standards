#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

script="$root/components/cloud-bootstrap/cloud-bootstrap.sh"
materialized="$root/.claude/cloud-bootstrap.sh"
readme="$root/components/cloud-bootstrap/README.md"
env_setup="$root/components/cloud-environment/setup.sh"
script_text="$(cat "$script")"

GIT_CONFIG_GLOBAL="$(mktemp "$TEST_TMPDIR/gitconfig.XXXXXX")"
export GIT_CONFIG_GLOBAL

bash -n "$script" 2>/dev/null
rc=$?
assert_exit 'cloud-bootstrap.sh parses (bash -n)' 0 "$rc"

cmp -s "$script" "$materialized"
rc=$?
assert_exit 'repo .claude/cloud-bootstrap.sh is byte-identical to the component' 0 "$rc"

if grep -qE 'claude-code-plugins|marketplace=|source_repo=' "$script"; then
  fail 'canonical script carries no hardcoded marketplace or repo identifiers' \
    "$(grep -nE 'claude-code-plugins|marketplace=|source_repo=' "$script" | head -n 3)"
else
  pass 'canonical script carries no hardcoded marketplace or repo identifiers'
fi

assert_contains 'cloud-only guard present (CLAUDE_CODE_REMOTE)' \
  "$script_text" 'CLAUDE_CODE_REMOTE'
assert_contains 'enrich seam runs .claude/cloud-bootstrap.local.sh' \
  "$script_text" '.claude/cloud-bootstrap.local.sh'
assert_contains 'SessionStart hook output JSON is emitted' \
  "$script_text" 'hookSpecificOutput'

assert_contains 'catalog inventory is scoped to declared marketplaces' \
  "$script_text" 'declared_mps'

setup_decl() {
  decl="$(sed -n "s/^$1='\(.*\)'\$/\1/p" "$env_setup")"
  if [[ -n "$decl" ]]; then
    pass "$2"
  else
    fail "$2" "no $1='...' assignment found"
  fi
}

setup_decl STAMP 'cloud-environment setup.sh declares a stamp path'
assert_contains 'bootstrap reads the stamp path cloud-environment writes' \
  "$script_text" "$decl"
setup_decl STAMP_FALLBACK 'cloud-environment setup.sh declares a fallback stamp path'
assert_contains 'bootstrap reads the fallback stamp path cloud-environment writes' \
  "$script_text" "$decl"

setup_decl FLEET_PLUGINS 'cloud-environment setup.sh declares a fleet list snapshot path'
assert_contains 'bootstrap reads the fleet list path cloud-environment writes' \
  "$script_text" "$decl"
setup_decl FLEET_PLUGINS_FALLBACK 'cloud-environment setup.sh declares a fleet list fallback path'
assert_not_contains 'bootstrap does not read the world-writable fleet list fallback path' \
  "$script_text" "$decl"
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_contains 'bootstrap keeps the repo enabledPlugins block as the deltas overlay' \
  "$script_text" 'install_plugins_from "$settings"'

inv_tmp="$(mktemp -d "$TEST_TMPDIR/inv_tmp.XXXXXX")"
mkdir -p "$inv_tmp/bin" "$inv_tmp/mp/.claude-plugin" "$inv_tmp/repo"
cat >"$inv_tmp/mp/.claude-plugin/marketplace.json" <<'JSON'
{ "plugins": [ { "name": "alpha" }, { "name": "beta" }, { "name": "newcomer" } ] }
JSON
cat >"$inv_tmp/fleet.json" <<'JSON'
{
  "extraKnownMarketplaces": { "stub-market": { "source": { "source": "github", "repo": "example/stub" } } },
  "enabledPlugins": { "alpha@stub-market": true, "beta@stub-market": true }
}
JSON
cat >"$inv_tmp/bin/claude" <<STUB
#!/usr/bin/env bash
COUNT_DIR="${inv_tmp}/counts"
mkdir -p "\$COUNT_DIR"
bump() { echo \$(( \$(cat "\$COUNT_DIR/\$1" 2>/dev/null || echo 0) + 1 )) >"\$COUNT_DIR/\$1"; }
case "\$1 \$2 \$3" in
  "plugin marketplace list")
    bump marketplace-list
    printf '[{"name":"stub-market","installLocation":"%s"}]\n' "$inv_tmp/mp"
    ;;
  "plugin list "*)
    bump plugin-list
    printf '[{"id":"alpha@stub-market"},{"id":"beta@stub-market"}]\n'
    ;;
  "plugin install "*)
    bump plugin-install
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$inv_tmp/bin/claude"
run_inv() {
  (cd "$1" && PATH="$inv_tmp/bin:$PATH" CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$1" \
    CLOUD_BOOTSTRAP_FLEET_LIST="$2" bash "$script")
}
git init -q "$inv_tmp/repo"
inv_out="$(run_inv "$inv_tmp/repo" "$inv_tmp/fleet.json" 2>&1 >/dev/null)"
assert_contains 'fleet list installs are summarized when the repo settings file is absent' \
  "$inv_out" 'fleet list'
assert_contains 'catalog gap is still named from the fleet list alone' \
  "$inv_out" 'stub-market carries plugins this repo does not declare: newcomer'
assert_eq 'warm catalog inventory lists marketplaces once' '1' \
  "$(cat "$inv_tmp/counts/marketplace-list")"
assert_eq 'warm catalog inventory lists plugins once' '1' \
  "$(cat "$inv_tmp/counts/plugin-list")"

mkdir -p "$inv_tmp/degrade/.claude"
cat >"$inv_tmp/degrade/.claude/settings.json" <<'JSON'
{ "enabledPlugins": { "gamma@stub-market": true } }
JSON
git init -q "$inv_tmp/degrade"
degrade_case() {
  local label="$1" fleet="$2" expected="$3" out hook_out
  rm -f "$inv_tmp/counts/plugin-install"
  out="$(run_inv "$inv_tmp/degrade" "$fleet" 2>&1 >/dev/null)"
  hook_out="$(run_inv "$inv_tmp/degrade" "$fleet" 2>/dev/null)"
  assert_contains "$label still emits the SessionStart reloadSkills output" \
    "$hook_out" '"reloadSkills":true'
  assert_contains "$label is refused with a reason" "$out" "$expected"
  assert_contains "$label skips the plugin install" "$out" 'plugin install skipped'
  assert_not_contains "$label does not install from the repo declaration" \
    "$out" 'repo .claude/settings.json'
  assert_eq "$label installs nothing" '0' \
    "$(cat "$inv_tmp/counts/plugin-install" 2>/dev/null || echo 0)"
  assert_not_contains "$label does not summarize a fleet list source" \
    "$out" 'fleet list'
}
degrade_case 'an absent fleet list' "$inv_tmp/no-such-fleet.json" \
  'no fleet plugin list in this snapshot'
printf 'not json at all\n' >"$inv_tmp/malformed.json"
degrade_case 'an unparsable fleet list' "$inv_tmp/malformed.json" \
  'is not a settings-shaped object'
printf '%s\n' '{"enabledPlugins":["alpha@stub-market"]}' >"$inv_tmp/wrong-shape.json"
degrade_case 'a fleet list whose enabledPlugins is an array' "$inv_tmp/wrong-shape.json" \
  'is not a settings-shaped object'
printf '%s\n' '[]' >"$inv_tmp/bare-array.json"
degrade_case 'a fleet list that is a bare array' "$inv_tmp/bare-array.json" \
  'is not a settings-shaped object'

printf '%s\n' '{"extraKnownMarketplaces":{}}' >"$inv_tmp/no-enabled.json"
rm -f "$inv_tmp/counts/plugin-install"
empty_out="$(run_inv "$inv_tmp/degrade" "$inv_tmp/no-enabled.json" 2>&1 >/dev/null)"
assert_not_contains 'a fleet list with no enabledPlugins is not refused' \
  "$empty_out" 'is not a settings-shaped object'
assert_contains 'a fleet list with no enabledPlugins is summarized as a source' \
  "$empty_out" 'fleet list'
assert_contains 'a repo delta outside the fleet list is installed as an overlay' \
  "$empty_out" 'repo .claude/settings.json: 1 declared, 1 newly installed'
assert_eq 'the overlay install reaches the plugin CLI' '1' \
  "$(cat "$inv_tmp/counts/plugin-install" 2>/dev/null || echo 0)"
rm -rf "$inv_tmp"

author_tmp="$(mktemp -d "$TEST_TMPDIR/author_tmp.XXXXXX")"
mkdir -p "$author_tmp/bin" "$author_tmp/repo"
cat >"$author_tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ -n "${GH_STUB_USER:-}" ]] || exit 1
[[ "$1 $2 $3" == 'api user --jq' ]] || exit 1
printf '%s' "$GH_STUB_USER" | jq -r "$4"
STUB
chmod +x "$author_tmp/bin/gh"
git init -q "$author_tmp/repo"
author_case() {
  local cfg="$author_tmp/$1.gitconfig"
  if [[ -n "${4:-}" ]]; then
    GIT_CONFIG_GLOBAL="$cfg" git config --global author.name 'Stale Author'
    GIT_CONFIG_GLOBAL="$cfg" git config --global author.email 'stale@example.test'
  fi
  (cd "$author_tmp/repo" && PATH="$author_tmp/bin:$PATH" GIT_CONFIG_GLOBAL="$cfg" \
    GIT_CONFIG_NOSYSTEM=1 CLAUDE_CODE_REMOTE="$2" CLAUDE_PROJECT_DIR="$author_tmp/repo" \
    CLOUD_BOOTSTRAP_FLEET_LIST="$author_tmp/no-such-fleet.json" GH_STUB_USER="$3" \
    bash "$script" >/dev/null 2>&1)
  GIT_CONFIG_GLOBAL="$cfg" git config --global --list 2>/dev/null | sort
}
assert_eq 'the connected account sets author.* only' \
  "$(printf '%s\n' 'author.email=42+octo@users.noreply.github.com' 'author.name=Octo Cat')" \
  "$(author_case success true '{"login":"octo","id":42,"name":"Octo Cat"}')"
assert_eq 'an account with no display name falls back to the login' \
  "$(printf '%s\n' 'author.email=42+octo@users.noreply.github.com' 'author.name=octo')" \
  "$(author_case no-name true '{"login":"octo","id":42,"name":null}')"
assert_eq 'a failed gh call sets nothing' '' "$(author_case failure true '')"
assert_eq 'a failed gh call clears a stale author' '' "$(author_case stale true '' stale)"
assert_eq 'an empty login sets nothing' '' \
  "$(author_case no-login true '{"login":null,"id":42,"name":"Octo Cat"}')"
assert_eq 'an empty id sets nothing' '' \
  "$(author_case no-id true '{"login":"octo","id":null,"name":"Octo Cat"}')"
assert_eq 'a non-remote session sets nothing' '' \
  "$(author_case local false '{"login":"octo","id":42,"name":"Octo Cat"}')"
rm -rf "$author_tmp"

assert_contains 'README documents the materialized path' \
  "$(cat "$readme")" '.claude/cloud-bootstrap.sh'
assert_contains 'README documents the enrich seam filename' \
  "$(cat "$readme")" '.claude/cloud-bootstrap.local.sh'

[[ $FAILED -eq 0 ]] || exit 1
