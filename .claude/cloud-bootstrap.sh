#!/usr/bin/env bash
# Cloud bootstrap: install the plugin catalog this repo enables.
# Two callers, both with CLAUDE_CODE_REMOTE=true:
#   1. The account environments' setup scripts, after clone and before the
#      session process launches. Claude Code builds its plugin/command/skill
#      registry at process start and never re-reads it, so this pre-launch
#      call is the only path that gets plugins loaded at turn one.
#   2. The SessionStart hook (startup|resume), as drift repair — the
#      environment cache can be ~7 days stale. Plugins it installs go live
#      at the next resume, not in the session that ran the hook.
# Outside cloud sessions this exits immediately: declaring a marketplace is
# gated on workspace trust, and on trusted local machines the marketplace and
# enabledPlugins declared in settings.json load on their own. Cloud sessions
# arrive untrusted, so there the declaration alone can load nothing.
# Idempotent and best effort: a failed plugin costs its skills, not the session.
#
# Both callers run `bash <this script>`, so the interpreter is whatever `bash`
# resolves to rather than the shebang's. Stock macOS still ships bash 3.2, which
# has no `mapfile`, and errors on an empty "${array[@]}" under `set -u` before
# 4.4. Both are avoided here: newline-delimited strings, no arrays.
set -euo pipefail

[[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] || exit 0

repo_root="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
cd -- "$repo_root"

command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

marketplace="melodic-software"
source_repo="melodic-software/claude-code-plugins"

if ! claude plugin marketplace list --json 2>/dev/null |
  jq -e --arg n "$marketplace" 'any(.[]; .name == $n)' >/dev/null; then
  claude plugin marketplace add "$source_repo" --scope user >/dev/null || {
    echo "cloud-bootstrap: could not add the $marketplace marketplace" >&2
    exit 0
  }
fi

wanted=$(
  jq -r --arg n "$marketplace" \
    '.enabledPlugins // {} | to_entries[]
     | select(.value == true and (.key | endswith("@" + $n))) | .key' \
    .claude/settings.json 2>/dev/null || true
)
have=$(claude plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)

enabled=0
installed=0
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  enabled=$((enabled + 1))
  if [[ $'\n'"$have"$'\n' == *$'\n'"$id"$'\n'* ]]; then continue; fi
  if claude plugin install "$id" --scope user -y >/dev/null 2>&1; then
    installed=$((installed + 1))
  else
    echo "cloud-bootstrap: install failed: $id" >&2
  fi
done <<EOF
$wanted
EOF

echo "cloud-bootstrap: $enabled enabled, $installed newly installed" >&2

# When the SessionStart hook is the caller, stdout is parsed as hook output —
# that is why the summary above goes to stderr — and this line asks for a
# skills re-scan for whatever the harness can pick up mid-session (the plugin
# registry itself is only rebuilt at the next process start). From the
# pre-launch caller it lands harmlessly in the setup log.
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true}}'
