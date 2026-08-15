#!/usr/bin/env bash
# SessionStart: install the plugin catalog this repo enables.
# Declaring a marketplace is gated on workspace trust and cloud sessions arrive
# untrusted, so the declaration alone can load nothing there. Hooks run untrusted.
# Idempotent and best effort: a failed plugin costs its skills, not the session.
#
# The hook entry runs `bash <this script>`, so the interpreter is whatever `bash`
# resolves to rather than the shebang's. Stock macOS still ships bash 3.2, which
# has no `mapfile`, and errors on an empty "${array[@]}" under `set -u` before
# 4.4. Both are avoided here: newline-delimited strings, no arrays.
set -euo pipefail

repo_root="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd -- "$repo_root"

command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

marketplace="melodic-software"
source_repo="melodic-software/claude-code-plugins"

if ! claude plugin marketplace list --json 2>/dev/null |
  jq -e --arg n "$marketplace" 'any(.[]; .name == $n)' >/dev/null; then
  claude plugin marketplace add "$source_repo" --scope user >/dev/null || {
    echo "install-plugins: could not add the $marketplace marketplace" >&2
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
    echo "install-plugins: install failed: $id" >&2
  fi
done <<EOF
$wanted
EOF

echo "install-plugins: $enabled enabled, $installed newly installed" >&2

# Skill discovery runs before SessionStart hooks finish, so anything installed
# above would otherwise wait for the next session. Ask for the re-scan. Stdout
# on this event is parsed as hook output, so the summary above goes to stderr.
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true}}'
