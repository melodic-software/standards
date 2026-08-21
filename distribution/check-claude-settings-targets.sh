#!/usr/bin/env bash
# Assert every per-target Claude settings file carries the shared base
# marketplace and SessionStart bootstrap hook. enabledPlugins may diverge.
# Apply never merges; this is authoring-time conformance only.
#
# Usage:
#   distribution/check-claude-settings-targets.sh
#     Check every settings.json under components/claude-settings/targets/.
#   distribution/check-claude-settings-targets.sh --file <settings.json>
#     Check one candidate against the committed base (also what the test uses).
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
base="$root/components/claude-settings/base/settings.json"
targets_dir="$root/components/claude-settings/targets"

command -v jq >/dev/null 2>&1 || {
  echo 'check-claude-settings-targets: jq is required' >&2
  exit 2
}

[[ -f "$base" ]] || { echo "missing base settings: $base" >&2; exit 1; }

jq empty "$base" >/dev/null 2>&1 || {
  echo "check-claude-settings-targets: base is not valid JSON: $base" >&2
  exit 2
}

# check_one <file> <label>
# Always returns 0 so callers under set -e need no condition context
# (.shellcheckrc's SC2310). Signals through CHECK_RC: 0 conform, 1 missing
# shared keys, 2 unparsable JSON.
CHECK_RC=0
check_one() {
  local cand="$1" label="$2"
  CHECK_RC=0
  jq empty "$cand" >/dev/null 2>&1 || {
    echo "check-claude-settings-targets: $label is not valid JSON: $cand" >&2
    CHECK_RC=2
    return 0
  }
  jq -e --slurpfile b "$base" '
      (.extraKnownMarketplaces.["melodic-software"].source.repo
        == $b[0].extraKnownMarketplaces.["melodic-software"].source.repo)
      and ([.hooks.SessionStart[]?
            | select(
                ((.matcher // "") | test("startup"))
                and ((.matcher // "") | test("resume"))
                and ([.hooks[]?
                      | select(
                          .type == "command"
                          and ((.command // "")
                            | test("^bash[[:space:]]+\"\\$CLAUDE_PROJECT_DIR/\\.claude/cloud-bootstrap\\.sh\""))
                        )] | length > 0)
              )] | length > 0)
    ' "$cand" >/dev/null || {
    echo "$label: missing shared marketplace or SessionStart bootstrap hook" >&2
    CHECK_RC=1
    return 0
  }
  return 0
}

if [[ "${1:-}" == "--file" ]]; then
  [[ $# -eq 2 ]] || {
    echo 'usage: check-claude-settings-targets.sh --file <settings.json>' >&2
    exit 2
  }
  check_one "$2" "$(basename "$2")"
  exit "$CHECK_RC"
fi

[[ $# -eq 0 ]] || {
  echo 'usage: check-claude-settings-targets.sh [--file <settings.json>]' >&2
  exit 2
}

failed=0
while IFS= read -r cand; do
  label="${cand#"$targets_dir/"}"
  check_one "$cand" "$label"
  if [[ "$CHECK_RC" -ne 0 ]]; then
    failed=1
  fi
done < <(find "$targets_dir" -name settings.json -type f | sort)

exit "$failed"
