#!/usr/bin/env bash
# SessionStart: install the plugin catalog this repo enables.
# Declaring a marketplace is gated on workspace trust and cloud sessions arrive
# untrusted, so the declaration alone can load nothing there. Hooks run untrusted.
# Idempotent and best effort: a failed plugin costs its skills, not the session.
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

mapfile -t wanted < <(
  jq -r --arg n "$marketplace" \
    '.enabledPlugins // {} | to_entries[]
     | select(.value == true and (.key | endswith("@" + $n))) | .key' \
    .claude/settings.json 2>/dev/null
)
mapfile -t have < <(claude plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null)

installed=0
for id in "${wanted[@]}"; do
  [[ -n "$id" ]] || continue
  if [[ " ${have[*]} " == *" $id "* ]]; then continue; fi
  if claude plugin install "$id" --scope user -y >/dev/null 2>&1; then
    installed=$((installed + 1))
  else
    echo "install-plugins: install failed: $id" >&2
  fi
done
echo "install-plugins: ${#wanted[@]} enabled, $installed newly installed"
