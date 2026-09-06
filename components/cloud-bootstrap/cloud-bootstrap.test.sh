#!/usr/bin/env bash
# Tests the cloud-bootstrap component: the canonical script parses, stays
# generic (no repo or marketplace identifiers — everything is data-driven from
# the consuming repo's own manifests), keeps its calling-contract landmarks
# (cloud-only guard, enrich seam, hook-output JSON), reads the same
# environment stamp the cloud-environment component writes, and this
# repository's own materialized copy is byte-identical to the component —
# standards is the manifest source, not a sync target, so this equality is
# what stands in for the synchronizer here.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/cloud-bootstrap/cloud-bootstrap.sh"
materialized="$root/.claude/cloud-bootstrap.sh"
readme="$root/components/cloud-bootstrap/README.md"
env_setup="$root/components/cloud-environment/setup.sh"

bash -n "$script" 2>/dev/null
rc=$?
assert_exit 'cloud-bootstrap.sh parses (bash -n)' 0 "$rc"

cmp -s "$script" "$materialized"
rc=$?
assert_exit 'repo .claude/cloud-bootstrap.sh is byte-identical to the component' 0 "$rc"

# Generic-by-construction: the canonical script must not name a marketplace,
# a repository, or a pinned tool version — those live in each repo's own
# manifests and settings, or in its cloud-bootstrap.local.sh extension.
if grep -qE 'claude-code-plugins|marketplace=|source_repo=' "$script"; then
  fail 'canonical script carries no hardcoded marketplace or repo identifiers' \
    "$(grep -nE 'claude-code-plugins|marketplace=|source_repo=' "$script" | head -n 3)"
else
  pass 'canonical script carries no hardcoded marketplace or repo identifiers'
fi

assert_contains 'cloud-only guard present (CLAUDE_CODE_REMOTE)' \
  "$(cat "$script")" 'CLAUDE_CODE_REMOTE'
assert_contains 'enrich seam runs .claude/cloud-bootstrap.local.sh' \
  "$(cat "$script")" '.claude/cloud-bootstrap.local.sh'
assert_contains 'SessionStart hook output JSON is emitted' \
  "$(cat "$script")" 'hookSpecificOutput'

# The catalog inventory line reads a machine-global marketplace listing to
# answer a repo-scoped question. Without narrowing it to what this repo
# declares, a machine carrying another repo's user-scoped marketplace reports
# that whole catalog as undeclared on every session.
assert_contains 'catalog inventory is scoped to declared marketplaces' \
  "$(cat "$script")" 'declared_mps'

# Cross-component lockstep: the environment stamp this script reports is the
# stamp path the cloud-environment component declares and writes.
stamp_path="$(sed -n "s/^STAMP='\(.*\)'\$/\1/p" "$env_setup")"
if [[ -n "$stamp_path" ]]; then
  pass 'cloud-environment setup.sh declares a stamp path'
else
  fail 'cloud-environment setup.sh declares a stamp path' \
    "no STAMP='...' assignment found"
fi
assert_contains 'bootstrap reads the stamp path cloud-environment writes' \
  "$(cat "$script")" "$stamp_path"
fallback_path="$(sed -n "s/^STAMP_FALLBACK='\(.*\)'\$/\1/p" "$env_setup")"
if [[ -n "$fallback_path" ]]; then
  pass 'cloud-environment setup.sh declares a fallback stamp path'
else
  fail 'cloud-environment setup.sh declares a fallback stamp path' \
    "no STAMP_FALLBACK='...' assignment found"
fi
assert_contains 'bootstrap reads the fallback stamp path cloud-environment writes' \
  "$(cat "$script")" "$fallback_path"

# Cross-component lockstep: the fleet plugin list this script installs from is
# the snapshot path (and /tmp fallback) the cloud-environment component writes
# at cache build, and the repo declaration stays as the fallback source.
fleet_path="$(sed -n "s/^FLEET_PLUGINS='\(.*\)'\$/\1/p" "$env_setup")"
if [[ -n "$fleet_path" ]]; then
  pass 'cloud-environment setup.sh declares a fleet list snapshot path'
else
  fail 'cloud-environment setup.sh declares a fleet list snapshot path' \
    "no FLEET_PLUGINS='...' assignment found"
fi
assert_contains 'bootstrap reads the fleet list path cloud-environment writes' \
  "$(cat "$script")" "$fleet_path"
fleet_fallback="$(sed -n "s/^FLEET_PLUGINS_FALLBACK='\(.*\)'\$/\1/p" "$env_setup")"
if [[ -n "$fleet_fallback" ]]; then
  pass 'cloud-environment setup.sh declares a fleet list fallback path'
else
  fail 'cloud-environment setup.sh declares a fleet list fallback path' \
    "no FLEET_PLUGINS_FALLBACK='...' assignment found"
fi
assert_contains 'bootstrap reads the fleet list fallback path cloud-environment writes' \
  "$(cat "$script")" "$fleet_fallback"
# shellcheck disable=SC2016 # the $ is a literal in the needle
assert_contains 'bootstrap keeps the repo enabledPlugins block as a source' \
  "$(cat "$script")" 'install_plugins_from "$settings"'

# Runtime behaviour of the catalog inventory with the repo settings file
# absent: the fleet list alone must still name the catalog gap. Driven with a
# stub `claude` on PATH, a fleet list at the /tmp fallback path, and a
# scratch repo with no .claude/settings.json.
inv_tmp="$(mktemp -d)"
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
case "\$1 \$2 \$3" in
  "plugin marketplace list") printf '[{"name":"stub-market","installLocation":"%s"}]\n' "$inv_tmp/mp" ;;
  "plugin list "*) printf '[{"id":"alpha@stub-market"},{"id":"beta@stub-market"}]\n' ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$inv_tmp/bin/claude"
# The fleet list path is the /opt constant when writable, else the /tmp
# fallback; the test uses whichever it can write, and cleans up after.
inv_fleet=''
for candidate in "$fleet_path" "$fleet_fallback"; do
  if [[ ! -e "$candidate" ]] && cp "$inv_tmp/fleet.json" "$candidate" 2>/dev/null; then
    inv_fleet="$candidate"
    break
  fi
done
if [[ -n "$inv_fleet" ]]; then
  inv_out="$(cd "$inv_tmp/repo" && git init -q . && PATH="$inv_tmp/bin:$PATH" \
    CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$inv_tmp/repo" bash "$script" 2>&1 >/dev/null)"
  rm -f "$inv_fleet"
  assert_contains 'fleet list installs are summarised when the repo settings file is absent' \
    "$inv_out" 'fleet list'
  assert_contains 'catalog gap is still named from the fleet list alone' \
    "$inv_out" 'stub-market carries plugins this repo does not declare: newcomer'
else
  fail 'catalog inventory without repo settings is exercised' \
    "neither $fleet_path nor $fleet_fallback was free and writable"
fi
rm -rf "$inv_tmp"

# README/script drift guards.
assert_contains 'README documents the materialized path' \
  "$(cat "$readme")" '.claude/cloud-bootstrap.sh'
assert_contains 'README documents the enrich seam filename' \
  "$(cat "$readme")" '.claude/cloud-bootstrap.local.sh'

[[ $FAILED -eq 0 ]] || exit 1
