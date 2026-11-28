#!/usr/bin/env bash
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

mkdir -p "$tmp/jq-bin" "$tmp/jq-count"
cat >"$tmp/jq-bin/jq" <<'SH'
#!/usr/bin/env bash
COUNT_DIR="${COUNT_DIR:?}"
echo $(($(cat "$COUNT_DIR/jq" 2>/dev/null || echo 0) + 1)) >"$COUNT_DIR/jq"
exec "$REAL_JQ" "$@"
SH
chmod +x "$tmp/jq-bin/jq"
echo 0 >"$tmp/jq-count/jq"
# Resolve jq before the shim dir is prepended; `command -p` would search only the standard-utility PATH.
# https://pubs.opengroup.org/onlinepubs/9799919799/utilities/command.html
real_jq="$(command -v jq)"
if [[ -z "$real_jq" ]]; then
  fail 'real jq resolves for the spawn-census shim' 'jq not found on PATH'
  exit 1
fi
COUNT_DIR="$tmp/jq-count" REAL_JQ="$real_jq" PATH="$tmp/jq-bin:$PATH" \
  bash "$script" --file "$tmp/good.json" >/dev/null
assert_eq '--file batches candidate parse and policy into one jq pass plus the base check' '2' \
  "$(cat "$tmp/jq-count/jq")"

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

cat >"$tmp/echo-hook.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "melodic-software/claude-code-plugins" }
    }
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          { "type": "command", "command": "echo cloud-bootstrap.sh" }
        ]
      }
    ]
  }
}
JSON

out="$(bash "$script" --file "$tmp/echo-hook.json" 2>&1)"
rc=$?
assert_exit 'echo-only bootstrap mention exits 1' 1 "$rc"
assert_contains 'echo-only hook names the candidate' "$out" 'echo-hook.json'

cat >"$tmp/wrong-matcher.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "melodic-software/claude-code-plugins" }
    }
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/cloud-bootstrap.sh\"" }
        ]
      }
    ]
  }
}
JSON

out="$(bash "$script" --file "$tmp/wrong-matcher.json" 2>&1)"
rc=$?
assert_exit 'SessionStart matcher without startup/resume exits 1' 1 "$rc"

printf 'not json' >"$tmp/broken.json"
out="$(bash "$script" --file "$tmp/broken.json" 2>&1)"
rc=$?
assert_exit 'malformed candidate exits 2' 2 "$rc"
assert_contains 'malformed candidate is named' "$out" 'not valid JSON'

[[ $FAILED -eq 0 ]] || exit 1
