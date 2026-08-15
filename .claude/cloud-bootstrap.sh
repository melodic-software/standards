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

# --- Repo toolchain ---------------------------------------------------------
# Ahead of the plugin-CLI guards below on purpose: those `command -v` checks
# exit 0 when `claude` or `jq` is missing, and the toolchain must not be
# collateral damage of an unrelated CLI being absent. The cloud VM ships Node
# 20/21/22 with no node_modules, so without this the component contract tests
# and lint gates run on the wrong Node against missing tooling — the failure a
# live cloud verification run confirmed across the fleet.
#
# Subshell with its own errexit posture: this file runs under `set -e`, and a
# failed optional install must cost a toolchain, never the session. The
# subshell ends in an explicit `exit 0` rather than being wrapped in
# `|| true` — wrapping would put every call inside it in an `||` context,
# which is what .shellcheckrc's check-set-e-suppressed (SC2310) exists to flag.
(
  set +e

  toolchain_warn() { printf 'cloud-bootstrap: %s\n' "$*" >&2; }

  # env_line <export-line> — append to the session env file once. Dedup-guarded
  # because SessionStart fires again on resume.
  env_line() {
    [[ -n "${CLAUDE_ENV_FILE:-}" ]] || return 0
    grep -qxF "$1" "$CLAUDE_ENV_FILE" 2>/dev/null || printf '%s\n' "$1" >>"$CLAUDE_ENV_FILE"
  }

  # Node from .node-version (VM nvm at /opt/nvm; image ships 20/21/22).
  if [[ -f .node-version ]]; then
    node_pin="$(tr -d '[:space:]' <.node-version)"
    if [[ "$(node --version 2>/dev/null)" != "v$node_pin" ]]; then
      export NVM_DIR="${NVM_DIR:-/opt/nvm}"
      if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        set +u # nvm.sh reads intentionally-unset variables
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh"
        if nvm install "$node_pin" >/dev/null 2>&1; then
          nvm alias default "$node_pin" >/dev/null 2>&1 ||
            toolchain_warn "Node $node_pin installed but could not be aliased default"
        else
          toolchain_warn "Node $node_pin install failed; continuing on $(node --version 2>/dev/null || echo 'no node')"
        fi
        set -u
      else
        toolchain_warn "nvm not found at $NVM_DIR; Node $node_pin unavailable"
      fi
    fi
    if node_bin="$(command -v node 2>/dev/null)"; then
      # shellcheck disable=SC2016
      env_line "export PATH=\"$(dirname -- "$node_bin"):$PWD/node_modules/.bin:\$PATH\""
    fi
  fi

  # npm_ci_at <dir> — install <dir>'s own lockfile when it is newer than the
  # installed tree there. Each path is a separate project: the root
  # package.json declares no workspaces, so a root `npm ci` does not reach the
  # component projects and their modules (ajv and friends) would be missing —
  # exactly what ci.yml works around with its own `npm ci --prefix` steps.
  npm_ci_at() {
    local dir="$1"
    [[ -f "$dir/package-lock.json" ]] || return 0
    if [[ ! -f "$dir/node_modules/.package-lock.json" ]] ||
      [[ "$dir/package-lock.json" -nt "$dir/node_modules/.package-lock.json" ]]; then
      npm ci --no-audit --no-fund --prefix "$dir" >/dev/null 2>&1 ||
        toolchain_warn "npm ci failed in $dir"
    fi
  }

  npm_ci_at .
  for component_lock in components/*/package-lock.json distribution/package-lock.json; do
    if [[ -f "$component_lock" ]]; then
      npm_ci_at "${component_lock%/package-lock.json}"
    fi
  done

  exit 0
)

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
