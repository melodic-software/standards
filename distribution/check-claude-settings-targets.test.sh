#!/usr/bin/env bash
# Tests check-claude-settings-targets.sh: the committed github-iac target
# conforms, a candidate missing the marketplace or bootstrap hook fails, and
# an unparsable file is a loud usage error.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/distribution/check-claude-settings-targets.sh"

bash -n "$script" 2>/dev/null
rc=$?
assert_exit 'check-claude-settings-targets.sh parses (bash -n)' 0 "$rc"

out="$(bash "$script")"
rc=$?
assert_exit 'committed targets conform' 0 "$rc"

out="$(bash "$script" --file \
  "$root/components/claude-settings/targets/github-iac/settings.json")"
rc=$?
assert_exit 'github-iac target file conforms' 0 "$rc"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/good.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "melodic-software/claude-code-plugins" }
    }
  },
  "enabledPlugins": { "review@melodic-software": true },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/cloud-bootstrap.sh\"" }
        ]
      }
    ]
  }
}
JSON

out="$(bash "$script" --file "$tmp/good.json")"
rc=$?
assert_exit 'fixture with marketplace and bootstrap hook exits 0' 0 "$rc"

cat >"$tmp/no-hook.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "melodic-software/claude-code-plugins" }
    }
  },
  "enabledPlugins": { "review@melodic-software": true }
}
JSON

out="$(bash "$script" --file "$tmp/no-hook.json" 2>&1)"
rc=$?
assert_exit 'missing SessionStart hook exits 1' 1 "$rc"
assert_contains 'missing hook names the candidate' "$out" 'no-hook.json'

cat >"$tmp/wrong-mp.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "someone-else/claude-code-plugins" }
    }
  },
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash cloud-bootstrap.sh" } ] }
    ]
  }
}
JSON

out="$(bash "$script" --file "$tmp/wrong-mp.json" 2>&1)"
rc=$?
assert_exit 'diverging marketplace repo exits 1' 1 "$rc"
assert_contains 'diverging marketplace names the candidate' "$out" 'wrong-mp.json'

printf 'not json' >"$tmp/broken.json"
out="$(bash "$script" --file "$tmp/broken.json" 2>&1)"
rc=$?
assert_exit 'malformed candidate exits 2' 2 "$rc"
assert_contains 'malformed candidate is named' "$out" 'not valid JSON'

[[ $FAILED -eq 0 ]] || exit 1
