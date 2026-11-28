#!/bin/bash
# shellcheck disable=SC2030,SC2031 # each parallel track deliberately
# reassigns LOG subshell-locally to its own temp log so track output never
# interleaves; the main shell's LOG is untouched by design.
# Always exit 0 and finish within ~5 minutes, or the environment is not cached:
# https://code.claude.com/docs/en/cloud-environments#script-requirements
set -u

SCRIPT_VERSION='2026-11-21.1'
STAMP='/opt/melodic-env-setup.done'
STAMP_FALLBACK='/tmp/melodic-env-setup.done'
FLEET_CATALOG_URL='https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/.claude-plugin/marketplace.json'
FLEET_PLUGINS='/opt/melodic-fleet-plugins.json'
FLEET_PLUGINS_FALLBACK='/tmp/melodic-fleet-plugins.json'
CLAUDE_PERMISSIONS_URL='https://raw.githubusercontent.com/melodic-software/standards/main/components/claude-permissions/claude-permissions.json'
VAULT_EXEC_URL='https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/vault-exec'
VAULT_EXEC_MARKER='# melodic-software/standards cloud-environment vault-exec'
PAGES_PUBLISH_URL='https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/pages-publish'
PAGES_PUBLISH_MARKER='# melodic-software/standards cloud-environment pages-publish'
RENDERED_VIEWS_SYNC_URL='https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/rendered-views-sync'
RENDERED_VIEWS_SYNC_MARKER='# melodic-software/standards cloud-environment rendered-views-sync'
LOG='/var/log/melodic-env-setup.log'
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$LOG"; }
fetch_to() { curl -fsSL --proto '=https' --retry 2 --retry-delay 3 "$1" -o "$2" >>"$LOG" 2>&1; }
scratch_file() { mktemp 2>/dev/null || echo "/tmp/melodic-$1.$$"; }

plugin_listings_ready=0
plugin_registered=''
plugin_have=''

ensure_plugin_listings() {
  [[ "$plugin_listings_ready" -eq 1 ]] && return 0
  plugin_registered="$(claude plugin marketplace list --json 2>/dev/null |
    jq -r '.[].name' 2>/dev/null || true)"
  plugin_have="$(claude plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)"
  plugin_listings_ready=1
}

install_plugins_from() {
  local file="$1" label="$2" mp_name mp_target plugin_id
  ensure_plugin_listings
  while IFS=$'\t' read -r mp_name mp_target; do
    [[ -n "$mp_name" ]] || continue
    if [[ $'\n'"$plugin_registered"$'\n' == *$'\n'"$mp_name"$'\n'* ]]; then
      log "plugins ($label): marketplace $mp_name already registered"
    elif [[ -z "$mp_target" ]]; then
      log "WARN plugins ($label): marketplace $mp_name declares no repo/path/url source; skipped"
    elif claude plugin marketplace add "$mp_target" >>"$LOG" 2>&1; then
      log "plugins ($label): marketplace $mp_name registered ($mp_target)"
      plugin_registered="${plugin_registered}${plugin_registered:+$'\n'}$mp_name"
    else
      log "WARN plugins ($label): marketplace add failed: $mp_name ($mp_target)"
    fi
  done < <(jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
    | [.key, (.value.source.repo // .value.source.path // .value.source.url // "")]
    | @tsv' "$file" 2>/dev/null)

  while IFS= read -r plugin_id; do
    [[ -n "$plugin_id" ]] || continue
    if [[ $'\n'"$plugin_have"$'\n' == *$'\n'"$plugin_id"$'\n'* ]]; then
      log "plugins ($label): $plugin_id already installed"
    elif claude plugin install "$plugin_id" --scope user -y >>"$LOG" 2>&1; then
      log "plugins ($label): installed $plugin_id"
      plugin_have="${plugin_have}${plugin_have:+$'\n'}$plugin_id"
    else
      log "WARN plugins ($label): install failed: $plugin_id"
    fi
  done < <(jq -r '(.enabledPlugins // {}) | to_entries[]
    | select(.value == true) | .key' "$file" 2>/dev/null)
}

fleet_list_from_catalog() {
  jq -e 'select((.plugins | length) > 0) | {
      extraKnownMarketplaces: {"melodic-software": {source: {source: "github",
        repo: "melodic-software/claude-code-plugins"}}},
      enabledPlugins: ([.plugins[]
        | select(.defaultEnabled == null or .defaultEnabled == true)
        | {key: "\(.name)@melodic-software", value: true}] | from_entries)
    }' "$1" >"$2" 2>/dev/null && return 0
  rm -f "$2" 2>/dev/null
  return 1
}

rewrite_settings() {
  local settings="$1" src="$1" tmp="$1.$2.$$"
  shift 2
  mkdir -p "${settings%/*}" || return 1
  if [[ -e "$settings" ]]; then
    cp -p "$settings" "$tmp" || {
      rm -f "$tmp"
      return 1
    }
  else
    src=/dev/null
  fi
  if jq -n "$@" "$src" >"$tmp" && [[ -s "$tmp" ]] && mv -f "$tmp" "$settings"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

compose_permissions_floor() {
  local floor="$1"
  jq -e '.claudePermissions | .schemaVersion == 1
    and (.allow | type == "array") and (.deny | type == "array" and length > 0)
    and ([.allow[], .deny[]] | all(type == "string" and length > 0))' \
    "$floor" >/dev/null || return 1
  # shellcheck disable=SC2016 # a jq program: $f and $p are jq variables
  rewrite_settings "$2" compose --slurpfile f "$floor" '($f | if length == 1 then .[0].claudePermissions
        else error("floor is not a single JSON document") end) as $p
      | if ($p | type) == "object" and $p.schemaVersion == 1
          and ($p.allow | type) == "array" and ($p.deny | type) == "array"
          and ($p.deny | length) > 0 and (($p.withdraw // []) | type) == "array"
          and ([$p.allow[], $p.deny[]] | all(type == "string" and length > 0))
        then . else error("floor is not schemaVersion 1 with string rows and a non-empty deny") end
      | [inputs] as $docs
      | if ($docs | length) == 0 then {}
        elif ($docs | length) == 1 and ($docs[0] | type) == "object" then $docs[0]
        else error("settings file is not a single JSON object") end
      | .permissions.allow = ((((.permissions.allow // []) + $p.allow) | unique) - ($p.withdraw // []))
      | .permissions.deny = (((.permissions.deny // []) + $p.deny) | unique)'
}

install_marked() {
  local marker="$1" src="$2" dest="$3" tmp="$3.install.$$"
  if ! bash -n "$src" 2>/dev/null || ! grep -qxF "$marker" "$src"; then
    return 1
  fi
  if [[ -e "$dest" ]] && ! grep -qxF "$marker" "$dest" 2>/dev/null; then
    return 2
  fi
  mkdir -p "${dest%/*}" || return 1
  if cp "$src" "$tmp" && chmod 0755 "$tmp" && mv -f "$tmp" "$dest"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}
install_vault_exec() { install_marked "$VAULT_EXEC_MARKER" "$@"; }
install_pages_publish() { install_marked "$PAGES_PUBLISH_MARKER" "$@"; }
install_rendered_views_sync() { install_marked "$RENDERED_VIEWS_SYNC_MARKER" "$@"; }

register_session_hook() {
  # shellcheck disable=SC2016 # a jq program: $docs and $cmd are jq variables
  rewrite_settings "$1" hook --arg cmd "$2" '[inputs] as $docs
      | if ($docs | length) == 0 then {}
        elif ($docs | length) == 1 and ($docs[0] | type) == "object" then $docs[0]
        else error("settings file is not a single JSON object") end
      | if (.hooks // {} | type) == "object" and (.hooks.SessionStart // [] | type) == "array"
        then . else error("hooks is not an object of arrays") end
      | .hooks.SessionStart = ([(.hooks.SessionStart // [])[]
          | if (.hooks | type) == "array"
            then .hooks |= map(select(.command != $cmd)) else . end
          | select(.hooks != [])]
        + [{matcher: "startup|resume",
            hooks: [{type: "command", command: $cmd, timeout: 30}]}])'
}

log_retired_inputs() {
  local var
  [[ -n "${RENDERED_VIEWS_MD+set}" ]] &&
    log 'WARN RENDERED_VIEWS_MD is set but ignored; the preference comes from Key Vault secret rendered-views-md through the rendered-views-sync hook'
  for var in PUBLIC_ENDPOINT PRIVATE_ENDPOINT PUBLIC_TOKEN_SECRET PRIVATE_TOKEN_SECRET PRIVATE_ACCESS_ID_SECRET PRIVATE_ACCESS_KEY_SECRET; do
    var="PAGES_PUBLISH_$var"
    [[ -n "${!var+set}" ]] &&
      log "WARN $var is set but ignored; pages-publish reads its config from Key Vault secret pages-publish-config"
  done
  return 0
}

if [[ "${MELODIC_SETUP_LIBONLY:-}" == 1 ]]; then
  return 0
fi

if ! touch "$LOG" 2>/dev/null; then
  LOG='/tmp/melodic-env-setup.log'
fi

export DEBIAN_FRONTEND=noninteractive
rm -f "$STAMP" "$STAMP_FALLBACK" 2>/dev/null
log "start version=$SCRIPT_VERSION"
log_retired_inputs

checkout_base='/home'
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO_ROOT=''
if [[ -n "$REPO_ROOT" && "$REPO_ROOT" != "$checkout_base"/* ]]; then
  log "repo root candidate $REPO_ROOT (git rev-parse, PWD=$PWD) is outside $checkout_base; distrusted, probing instead"
  REPO_ROOT=''
fi
if [[ -n "$REPO_ROOT" ]]; then
  log "repo root resolved to $REPO_ROOT (git rev-parse, PWD=$PWD)"
else
  candidates=()
  for d in "$checkout_base"/*/*/.git; do
    [[ -e "$d" ]] && candidates+=("${d%/.git}")
  done
  if [[ ${#candidates[@]} -eq 1 ]]; then
    REPO_ROOT="${candidates[0]}"
    log "repo root resolved to $REPO_ROOT (probed $checkout_base; PWD=$PWD is not a checkout)"
  elif [[ ${#candidates[@]} -eq 0 ]]; then
    log "WARN repo root unresolved: PWD=$PWD is not a checkout and $checkout_base holds none"
  else
    log "WARN repo root unresolved: multiple checkouts under $checkout_base (${candidates[*]}); PWD=$PWD"
  fi
fi

DOTNET_FALLBACK_VERSIONS='11.0.100'
NODE_FALLBACK_VERSION='24.21.0'
dotnet_versions="$DOTNET_FALLBACK_VERSIONS"
if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/global.json" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    log 'dotnet pin: jq unavailable to read repo global.json; using fleet fallback'
  else
    repo_sdk="$(jq -r '.sdk.version // empty' "$REPO_ROOT/global.json" 2>/dev/null)"
    if [[ -n "$repo_sdk" ]]; then
      dotnet_versions="$repo_sdk"
      log "dotnet pin $repo_sdk read from repo global.json"
    else
      log 'dotnet pin: repo global.json declares no sdk.version; using fleet fallback'
    fi
  fi
fi
node_version="$NODE_FALLBACK_VERSION"
if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/.node-version" ]]; then
  repo_node="$(tr -d '[:space:]' <"$REPO_ROOT/.node-version")"
  repo_node="${repo_node#v}"
  if [[ -n "$repo_node" ]]; then
    node_version="$repo_node"
    log "node pin $repo_node read from repo .node-version"
  else
    log 'node pin: repo .node-version is empty; using fleet fallback'
  fi
fi

GH_VERSION='2.98.0'
GH_SHA256='3b8ac6b30336802fc1a858d7c084e11cdf24ac1a761ca90b68022d7d729208de'
GH_TARBALL='/tmp/gh.tar.gz'
# shfmt publishes no checksums file: the hash is sha256sum of the linux_amd64 asset,
# matched against a second download: https://github.com/mvdan/sh/releases/tag/v3.14.1
SHFMT_VERSION='3.14.1'
SHFMT_SHA256='76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf'
SHFMT_ASSET='/tmp/shfmt'

track_a_log="$(scratch_file env-track-a)"
track_b_log="$(scratch_file env-track-b)"
track_c_log="$(scratch_file env-track-c)"

# PowerShell comes from packages.microsoft.com, on the default allowlist:
# https://code.claude.com/docs/en/cloud-environments#default-allowed-domains
(
  LOG="$track_a_log"
  arch="$(uname -m)"
  if [[ "$arch" != 'x86_64' ]]; then
    log "WARN gh install skipped: no pinned asset for $arch (amd64 only)"
  elif ! curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$GH_TARBALL" \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    >>"$LOG" 2>&1; then
    log "WARN gh $GH_VERSION download failed"
  elif ! printf '%s  %s\n' "$GH_SHA256" "$GH_TARBALL" |
    sha256sum --check --strict >>"$LOG" 2>&1; then
    log "WARN gh $GH_VERSION checksum mismatch; refusing to install"
  elif ! tar --extract --gzip --file="$GH_TARBALL" --directory=/usr/local/bin \
    --strip-components=2 "gh_${GH_VERSION}_linux_amd64/bin/gh" >>"$LOG" 2>&1; then
    log "WARN gh $GH_VERSION extract failed"
  elif ! chmod 0755 /usr/local/bin/gh 2>>"$LOG"; then
    log "WARN gh $GH_VERSION installed but chmod failed"
  else
    log "gh $GH_VERSION installed"
  fi
  rm -f "$GH_TARBALL" 2>/dev/null
  if [[ "$arch" != 'x86_64' ]]; then
    log "WARN shfmt install skipped: no pinned asset for $arch (amd64 only)"
  elif ! curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$SHFMT_ASSET" \
    "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64" \
    >>"$LOG" 2>&1; then
    log "WARN shfmt $SHFMT_VERSION download failed"
  elif ! printf '%s  %s\n' "$SHFMT_SHA256" "$SHFMT_ASSET" |
    sha256sum --check --strict >>"$LOG" 2>&1; then
    log "WARN shfmt $SHFMT_VERSION checksum mismatch; refusing to install"
  elif ! install -m 0755 "$SHFMT_ASSET" /usr/local/bin/shfmt 2>>"$LOG"; then
    log "WARN shfmt $SHFMT_VERSION install failed"
  else
    log "shfmt $SHFMT_VERSION installed"
  fi
  rm -f "$SHFMT_ASSET" 2>/dev/null
  ubuntu_ver="$(sed -n 's/^VERSION_ID="\{0,1\}\([0-9.]*\).*/\1/p' /etc/os-release)"
  if curl -fsSL "https://packages.microsoft.com/config/ubuntu/${ubuntu_ver}/packages-microsoft-prod.deb" \
    -o /tmp/msprod.deb >>"$LOG" 2>&1 &&
    dpkg -i /tmp/msprod.deb >>"$LOG" 2>&1 &&
    apt-get update -y >>"$LOG" 2>&1 &&
    apt-get install -y powershell >>"$LOG" 2>&1; then
    log 'powershell installed'
  else
    log 'WARN powershell install failed'
  fi
) &

(
  LOG="$track_b_log"
  if curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh >>"$LOG" 2>&1; then
    # shellcheck disable=SC2086 # dotnet_versions is a space-separated list
    for v in $dotnet_versions; do
      if bash /tmp/dotnet-install.sh --version "$v" --install-dir /opt/dotnet >>"$LOG" 2>&1; then
        log "dotnet $v installed"
      else
        log "WARN dotnet $v install failed"
      fi
    done
    if ! ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet 2>>"$LOG"; then
      log 'WARN dotnet symlink failed'
    fi
  else
    log 'WARN dotnet-install.sh fetch failed — check the Custom allowlist (see the cloud-environment README, Network prerequisite)'
  fi
) &

# The VM image ships Node 20/21/22 only, so this is always an install:
# https://code.claude.com/docs/en/cloud-environments#installed-tools
(
  LOG="$track_c_log"
  export NVM_DIR="${NVM_DIR:-/opt/nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    set +u # nvm.sh reads unset vars; subshell-local, tracks A/B keep nounset
    # shellcheck disable=SC1091
    if . "$NVM_DIR/nvm.sh" &&
      nvm install "$node_version" >>"$LOG" 2>&1 &&
      nvm alias default "$node_version" >>"$LOG" 2>&1; then
      log "node $node_version installed"
    else
      log "WARN node $node_version install failed"
    fi
  else
    log 'WARN nvm not found; node pin unavailable'
  fi
) &

wait

for track in "A gh + powershell|$track_a_log" \
  "B .NET SDKs|$track_b_log" "C node|$track_c_log"; do
  track_file="${track#*|}"
  printf -- '--- track %s ---\n' "${track%%|*}" >>"$LOG"
  cat "$track_file" >>"$LOG" 2>/dev/null
  rm -f "$track_file" 2>/dev/null
done

if ! command -v claude >/dev/null 2>&1; then
  log 'plugins: claude CLI not on PATH; skipping'
elif ! command -v jq >/dev/null 2>&1; then
  log 'plugins: jq not available; skipping'
else
  rm -f "$FLEET_PLUGINS" "$FLEET_PLUGINS_FALLBACK" 2>/dev/null
  catalog_file="$(scratch_file fleet-catalog)"
  if fetch_to "$FLEET_CATALOG_URL" "$catalog_file" &&
    fleet_list_from_catalog "$catalog_file" "$FLEET_PLUGINS_FALLBACK"; then
    fleet_file="$FLEET_PLUGINS_FALLBACK"
    if cp "$FLEET_PLUGINS_FALLBACK" "$FLEET_PLUGINS" 2>/dev/null; then
      rm -f "$FLEET_PLUGINS_FALLBACK" 2>/dev/null
      fleet_file="$FLEET_PLUGINS"
    else
      log "WARN plugins (fleet): $FLEET_PLUGINS unwritable; list kept at $FLEET_PLUGINS_FALLBACK"
    fi
    log "plugins (fleet): list derived from the catalog to $fleet_file ($(jq -r '.enabledPlugins | length' "$fleet_file") entries)"
    install_plugins_from "$fleet_file" fleet
  else
    log 'WARN plugins (fleet): catalog fetch failed or held no plugins; no plugins install this build'
  fi
  rm -f "$catalog_file" 2>/dev/null
fi

if [[ -z "$REPO_ROOT" ]]; then
  log 'repo bootstrap skipped: repo root unresolved (see WARN above); nothing baked'
elif [[ -f "$REPO_ROOT/.claude/cloud-bootstrap.sh" ]]; then
  if (cd "$REPO_ROOT" &&
    CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$REPO_ROOT" \
      bash .claude/cloud-bootstrap.sh) >>"$LOG" 2>&1; then
    log 'repo bootstrap .claude/cloud-bootstrap.sh baked'
  else
    log 'WARN repo bootstrap .claude/cloud-bootstrap.sh failed (see log)'
  fi
else
  log "repo root resolved to $REPO_ROOT, no bootstrap present (.claude/cloud-bootstrap.sh) — expected no-op"
fi

floor_file='/tmp/melodic-claude-permissions.json'
if ! command -v jq >/dev/null 2>&1; then
  log 'WARN permissions floor: jq not available; no floor composed'
elif [[ -z "${CLAUDE_CONFIG_DIR:-${HOME:-}}" ]]; then
  log 'WARN permissions floor: neither CLAUDE_CONFIG_DIR nor HOME is set; no floor composed'
else
  user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  if ! fetch_to "$CLAUDE_PERMISSIONS_URL" "$floor_file"; then
    log 'WARN permissions floor: fetch failed; no floor composed this build'
  elif compose_permissions_floor "$floor_file" "$user_settings" >>"$LOG" 2>&1; then
    log "permissions floor composed into $user_settings ($(jq -r \
      '"allow=\(.permissions.allow | length) deny=\(.permissions.deny | length)"' \
      "$user_settings" 2>/dev/null))"
  else
    log "WARN permissions floor: compose refused (invalid floor or settings, or a failed write); $user_settings unchanged"
  fi
fi
rm -f "$floor_file" 2>/dev/null

# Install only: setup script requests never get the agent proxy's secrets:
# https://code.claude.com/docs/en/cloud-environments#requests-that-never-get-the-credential
if [[ -z "${HOME:-}" ]]; then
  log 'WARN vault-exec: HOME is not set; not installed'
else
  vault_exec_dest="$HOME/.local/bin/vault-exec"
  vault_exec_file="$(scratch_file vault-exec)"
  if ! fetch_to "$VAULT_EXEC_URL" "$vault_exec_file"; then
    log 'WARN vault-exec: fetch failed; not installed this build'
  elif install_vault_exec "$vault_exec_file" "$vault_exec_dest" >>"$LOG" 2>&1; then
    log "vault-exec installed to $vault_exec_dest"
  else
    log "WARN vault-exec: install refused (fetched file invalid, $vault_exec_dest is not ours, or a failed write)"
  fi
  rm -f "$vault_exec_file" 2>/dev/null

  pages_publish_dest="$HOME/.local/bin/pages-publish"
  pages_publish_file="$(scratch_file pages-publish)"
  if ! fetch_to "$PAGES_PUBLISH_URL" "$pages_publish_file"; then
    log 'WARN pages-publish: fetch failed; not installed this build'
  else
    install_pages_publish "$pages_publish_file" "$pages_publish_dest" >>"$LOG" 2>&1
    case $? in
      0) log "pages-publish installed to $pages_publish_dest" ;;
      2) log "WARN pages-publish: $pages_publish_dest is not ours; left untouched" ;;
      *) log 'WARN pages-publish: install refused (fetched file invalid or a failed write)' ;;
    esac
  fi
  rm -f "$pages_publish_file" 2>/dev/null

  rv_sync_dest="$HOME/.local/bin/rendered-views-sync"
  rv_sync_file="$(scratch_file rendered-views-sync)"
  if ! fetch_to "$RENDERED_VIEWS_SYNC_URL" "$rv_sync_file"; then
    log 'WARN rendered-views-sync: fetch failed; not installed this build'
  elif ! install_rendered_views_sync "$rv_sync_file" "$rv_sync_dest" >>"$LOG" 2>&1; then
    log "WARN rendered-views-sync: install refused (fetched file invalid, $rv_sync_dest is not ours, or a failed write); no hook registered"
  elif ! command -v jq >/dev/null 2>&1; then
    log 'WARN rendered-views-sync: installed, but jq is not available; no hook registered'
  else
    user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    if register_session_hook "$user_settings" "$rv_sync_dest" >>"$LOG" 2>&1; then
      log "rendered-views-sync installed to $rv_sync_dest and registered as a SessionStart hook in $user_settings"
    else
      log "WARN rendered-views-sync: hook registration refused (invalid settings or a failed write); $user_settings unchanged"
    fi
  fi
  rm -f "$rv_sync_file" 2>/dev/null
fi

rm -f /tmp/msprod.deb /tmp/dotnet-install.sh "$GH_TARBALL" \
  /tmp/melodic-env-setup.sh 2>/dev/null

log "done version=$SCRIPT_VERSION"
stamp_content="$SCRIPT_VERSION $(date -u +%FT%TZ)"
if ! printf '%s\n' "$stamp_content" >"$STAMP" 2>/dev/null; then
  log "WARN stamp: $STAMP unwritable; falling back to $STAMP_FALLBACK"
  if ! printf '%s\n' "$stamp_content" >"$STAMP_FALLBACK" 2>/dev/null; then
    log 'WARN stamp: fallback write failed too; verification will see a missing stamp'
  fi
fi
exit 0
