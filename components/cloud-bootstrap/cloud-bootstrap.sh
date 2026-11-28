#!/usr/bin/env bash
# Callers run `bash <this script>`; stock macOS bash 3.2 has no `mapfile` (bash 4.0), so no arrays.
# https://tiswww.case.edu/php/chet/bash/NEWS
set -euo pipefail

[[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] || exit 0

repo_root="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
cd -- "$repo_root"

if [[ -f /opt/melodic-env-setup.done ]]; then
  echo "cloud-bootstrap: env snapshot $(cat /opt/melodic-env-setup.done)" >&2
elif [[ -f /tmp/melodic-env-setup.done ]]; then
  echo "cloud-bootstrap: env snapshot $(cat /tmp/melodic-env-setup.done) (fallback stamp; /opt was unwritable at cache build)" >&2
else
  echo "cloud-bootstrap: no env setup stamp (unmanaged environment or interrupted cache build)" >&2
fi

(
  set +e

  toolchain_warn() { printf 'cloud-bootstrap: %s\n' "$*" >&2; }

  env_line() {
    [[ -n "${CLAUDE_ENV_FILE:-}" ]] || return 0
    grep -qxF "$1" "$CLAUDE_ENV_FILE" 2>/dev/null || printf '%s\n' "$1" >>"$CLAUDE_ENV_FILE"
  }

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

  if [[ -f package-lock.json ]]; then
    if [[ ! -f node_modules/.package-lock.json ]] ||
      [[ package-lock.json -nt node_modules/.package-lock.json ]]; then
      if npm ci --no-audit --no-fund >/dev/null 2>&1; then
        hooks_skipped=false
        case "${CI:-}" in
          '' | 0 | false) ;;
          *) case "${LEFTHOOK:-}" in '' | 0 | false) hooks_skipped=true ;; *) ;; esac ;;
        esac
        if [[ "$hooks_skipped" == false &&
          "$(npm config get ignore-scripts 2>/dev/null)" == true ]]; then
          npm run prepare --if-present >/dev/null 2>&1 ||
            toolchain_warn 'npm run prepare failed; git hooks are not installed'
        fi
      else
        toolchain_warn 'npm ci failed; node_modules is unavailable this session'
      fi
    fi
  fi

  if [[ -f global.json ]] && command -v jq >/dev/null 2>&1; then
    sdk="$(jq -r '.sdk.version // empty' global.json 2>/dev/null)"
    if [[ -n "$sdk" ]]; then
      if [[ ! -x .dotnet/dotnet ]] || ! .dotnet/dotnet --list-sdks 2>/dev/null | grep -qF "$sdk "; then
        installer=/tmp/dotnet-install.sh
        # A proxy error body can arrive as HTTP 200, which `curl -f` (>= 400 only) passes; check the shebang.
        # https://curl.se/docs/manpage.html#-f
        if curl -fsSL --proto '=https' --proto-redir '=https' \
          --retry 2 --retry-delay 3 https://dot.net/v1/dotnet-install.sh -o "$installer" 2>/dev/null &&
          [[ -s "$installer" ]] &&
          head -c 2 "$installer" 2>/dev/null | grep -q '^#!' &&
          bash "$installer" --version "$sdk" --install-dir .dotnet >/dev/null 2>&1; then
          :
        else
          toolchain_warn "dotnet $sdk install failed: check the environment's network allowlist (dot.net, aka.ms, builds.dotnet.microsoft.com, download.visualstudio.microsoft.com)"
        fi
        rm -f "$installer"
      fi
      if [[ -x .dotnet/dotnet ]]; then
        env_line "export DOTNET_ROOT=\"$PWD/.dotnet\""
        # shellcheck disable=SC2016
        env_line "export PATH=\"$PWD/.dotnet:\$PATH\""
      fi
    fi
  fi

  git_dir="$(git rev-parse --git-dir 2>/dev/null)"
  if [[ -n "$git_dir" && -f "$git_dir/shallow" ]]; then
    git fetch --quiet --unshallow 2>/dev/null ||
      toolchain_warn 'could not unshallow; base-ref diffs may fail'
  fi
  # A bare `fetch origin main` updates no remote-tracking ref in a single-branch clone; name the destination.
  # https://git-scm.com/docs/git-fetch#_configured_remote_tracking_branches
  git fetch --quiet origin "+main:refs/remotes/origin/main" 2>/dev/null ||
    toolchain_warn 'could not fetch origin/main'

  # Cloud sessions don't author commits as the connected account; set author only, remove once fixed upstream.
  # https://github.com/anthropics/claude-code/issues/104719
  gh_user="$(gh api user --jq 'select((.login // "") != "" and (.id // "" | tostring) != "")
    | [.login, (.id | tostring), (.name // "")] | @tsv' 2>/dev/null)" || gh_user=''
  IFS=$'\t' read -r gh_login gh_id gh_name <<<"$gh_user"
  if [[ -z "$gh_login" || -z "$gh_id" ]] ||
    ! git config --global author.name "${gh_name:-$gh_login}" ||
    ! git config --global author.email "$gh_id+$gh_login@users.noreply.github.com"; then
    git config --global --unset author.name 2>/dev/null || true
    git config --global --unset author.email 2>/dev/null || true
    toolchain_warn 'could not derive the git author from the connected GitHub account; author.* cleared'
  fi

  if [[ -f .claude/cloud-bootstrap.local.sh ]]; then
    if bash .claude/cloud-bootstrap.local.sh >&2; then
      toolchain_warn 'local extension completed'
    else
      toolchain_warn 'WARN local extension failed'
    fi
  fi

  exit 0
)

# SessionStart parses this script's stdout as hook output, so every summary goes to stderr.
# https://code.claude.com/docs/en/hooks
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true}}'

command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

settings='.claude/settings.json'
fleet_plugins="${CLOUD_BOOTSTRAP_FLEET_LIST:-/opt/melodic-fleet-plugins.json}"
if [[ ! -f "$fleet_plugins" ]]; then
  echo 'cloud-bootstrap: no fleet plugin list in this snapshot; plugin install skipped' >&2
  exit 0
elif ! jq -e 'type == "object" and ((.enabledPlugins // {}) | type == "object")' \
  "$fleet_plugins" >/dev/null 2>&1; then
  echo "cloud-bootstrap: fleet plugin list $fleet_plugins is not a settings-shaped object; plugin install skipped" >&2
  exit 0
fi

plugin_registered=''
plugin_have=''
plugin_mps=''
added_mp=0

mp_json=$(claude plugin marketplace list --json 2>/dev/null || true)
plugin_registered=$(printf '%s' "$mp_json" | jq -r '.[].name' 2>/dev/null || true)
plugin_mps=$(printf '%s' "$mp_json" | jq -r '.[] | select((.installLocation // "") != "")
    | [.name, .installLocation] | @tsv' 2>/dev/null || true)
plugin_have=$(claude plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)

install_plugins_from() {
  local file="$1" label="$2" declared wanted
  local mp_name mp_target id declared_count installed
  [[ -f "$file" ]] || return 0
  declared=$(
    jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
      | [.key, (.value.source.repo // .value.source.path // .value.source.url // "")]
      | @tsv' "$file" 2>/dev/null || true
  )
  while IFS=$'\t' read -r mp_name mp_target; do
    [[ -n "$mp_name" ]] || continue
    if [[ $'\n'"$plugin_registered"$'\n' == *$'\n'"$mp_name"$'\n'* ]]; then continue; fi
    if [[ -z "$mp_target" ]]; then
      echo "cloud-bootstrap: marketplace $mp_name declares no repo/path/url source; skipped" >&2
    elif claude plugin marketplace add "$mp_target" --scope user >/dev/null 2>&1; then
      echo "cloud-bootstrap: marketplace $mp_name registered ($mp_target)" >&2
      plugin_registered="${plugin_registered}${plugin_registered:+$'\n'}$mp_name"
      added_mp=1
    else
      echo "cloud-bootstrap: WARN marketplace add failed: $mp_name ($mp_target)" >&2
    fi
  done <<EOF
$declared
EOF

  wanted=$(
    jq -r '.enabledPlugins // {} | to_entries[]
      | select(.value == true) | .key' "$file" 2>/dev/null || true
  )

  declared_count=0
  installed=0
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    declared_count=$((declared_count + 1))
    if [[ $'\n'"$plugin_have"$'\n' == *$'\n'"$id"$'\n'* ]]; then continue; fi
    if claude plugin install "$id" --scope user -y >/dev/null 2>&1; then
      installed=$((installed + 1))
      plugin_have="${plugin_have}${plugin_have:+$'\n'}$id"
    else
      echo "cloud-bootstrap: install failed: $id" >&2
    fi
  done <<EOF
$wanted
EOF

  echo "cloud-bootstrap: $label: $declared_count declared, $installed newly installed" >&2
  return 0
}

install_plugins_from "$fleet_plugins" "fleet list $fleet_plugins"
install_plugins_from "$settings" "repo $settings"

repo_src="$settings"
[[ -f "$repo_src" ]] || repo_src="$fleet_plugins"
declared_from="$fleet_plugins"
if [[ "$added_mp" -eq 1 ]]; then
  plugin_mps=$(claude plugin marketplace list --json 2>/dev/null |
    jq -r '.[] | select((.installLocation // "") != "")
      | [.name, .installLocation] | @tsv' 2>/dev/null || true)
fi
declared_mps=$(jq -r '(.extraKnownMarketplaces // {}) | keys[]' "$repo_src" "$declared_from" 2>/dev/null | sort -u || true)
while IFS=$'\t' read -r mp_name mp_dir; do
  [[ -n "$mp_name" ]] || continue
  [[ $'\n'"$declared_mps"$'\n' == *$'\n'"$mp_name"$'\n'* ]] || continue
  catalog="$mp_dir/.claude-plugin/marketplace.json"
  [[ -f "$catalog" ]] || continue
  # Strip "@<marketplace>" by length: jq sub() always reads its argument as a regex.
  # https://jqlang.org/manual/#sub
  missing=$(jq -r --arg mp "$mp_name" --slurpfile s "$repo_src" --slurpfile f "$declared_from" '
    [.plugins[]?.name] as $names
    | [(($f[0].enabledPlugins // {}) + ($s[0].enabledPlugins // {}))
       | to_entries[] | select(.value == true) | .key
       | select(endswith("@" + $mp)) | .[:length - ($mp | length) - 1]] as $declared
    | ($names - $declared) | join(", ")' "$catalog" 2>/dev/null || true)
  if [[ -n "$missing" ]]; then
    echo "cloud-bootstrap: $mp_name carries plugins this repo does not declare: $missing" >&2
  fi
done <<EOF
$plugin_mps
EOF
