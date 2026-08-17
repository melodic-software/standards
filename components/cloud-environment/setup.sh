#!/bin/bash
# Melodic shared cloud environment — canonical setup script (SSOT).
#
# Consumed by claude.ai/code environments through the three-line bootstrap
# documented in README.md: the environment's script field curls this file from
# raw.githubusercontent.com (on the default allowlist) and runs it, so edits
# land here by pull request instead of by hand-editing an account-scoped UI
# field. Contract:
#   - always exit 0 — a non-zero exit fails the environment cache build;
#   - stay well under the ~5-minute cache-build budget;
#   - repo-agnostic: per-repo work lives in each repo's committed
#     .claude/cloud-bootstrap.sh, which this script bakes into the snapshot
#     as its final step when the checked-out repo has one.
#
# Diagnosability (claude-code-plugins#2654, Blocker 2 — an interrupted cache
# build left no trace): every step logs a timestamped line to $LOG, and the
# completion stamp is written only as the very last action. Verification
# starts at the stamp: a missing $STAMP means the build never finished —
# force a rebuild (any edit to the environment's script field does).
#
# Network prerequisite (claude-code-plugins#2654, Blocker 1 — verified live
# 2026-08-14): the .NET installer redirect chain (dot.net → aka.ms →
# builds.dotnet.microsoft.com / download.visualstudio.microsoft.com) is
# 403-blocked under Trusted network access. The environment must use Custom
# network access with "Also include default list of common package managers"
# checked plus those four hosts added.
set -u

SCRIPT_VERSION='2026-08-15.3'
STAMP='/opt/melodic-env-setup.done'
LOG='/var/log/melodic-env-setup.log'
if ! touch "$LOG" 2>/dev/null; then
  LOG='/tmp/melodic-env-setup.log'
fi
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$LOG"; }

export DEBIAN_FRONTEND=noninteractive
rm -f "$STAMP" 2>/dev/null
log "start version=$SCRIPT_VERSION"

# Track A: apt tools — gh CLI + PowerShell (packages.microsoft.com is on the
# default allowlist).
(
  if apt-get update -y >>"$LOG" 2>&1; then
    log 'apt-get update ok'
  else
    log 'WARN apt-get update failed'
  fi
  # gh comes from Ubuntu's own archives: the official cloud-environments
  # worked example is exactly `apt update && apt install -y gh`, and
  # cli.github.com (the newer upstream apt repo) is NOT on the default
  # allowlist. A silent miss is caught by the verification checklist.
  if apt-get install -y gh >>"$LOG" 2>&1; then
    log 'gh installed'
  else
    log 'WARN gh install failed'
  fi
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

# Track B: .NET SDKs — the fleet's exact global.json pins (rollForward:
# disable). Update the version list when a repo's global.json bumps; each
# repo's cloud-bootstrap also installs its exact SDK repo-locally, so the
# env copy is a warm cache and the bootstrap is the correctness guarantee.
(
  if curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh >>"$LOG" 2>&1; then
    for v in 10.0.302 10.0.400; do
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
    log 'WARN dotnet-install.sh fetch failed — check the Custom allowlist (see header)'
  fi
) &

# Track C: Node 24.19.0 — the fleet .node-version pin; the VM image ships
# Node 20/21/22 only, so this is always an install.
(
  export NVM_DIR="${NVM_DIR:-/opt/nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    set +u # nvm.sh reads unset vars; subshell-local, tracks A/B keep nounset
    # shellcheck disable=SC1091
    if . "$NVM_DIR/nvm.sh" &&
      nvm install 24.19.0 >>"$LOG" 2>&1 &&
      nvm alias default 24.19.0 >>"$LOG" 2>&1; then
      log 'node 24.19.0 installed'
    else
      log 'WARN node 24.19.0 install failed'
    fi
  else
    log 'WARN nvm not found; node pin unavailable'
  fi
) &

wait

# Bake the checked-out repo's committed bootstrap (.claude/cloud-bootstrap.sh)
# into the cached snapshot. One name, no fallbacks: every fleet repo commits
# its generic repository setup — dependencies and plugin installs — there.
# Running it here is load-bearing for plugins: the session's plugin registry
# is built at process start and never re-read, so plugin installs must land
# at cache build, not mid-session.
if [[ -f .claude/cloud-bootstrap.sh ]]; then
  if CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$PWD" \
    bash .claude/cloud-bootstrap.sh >>"$LOG" 2>&1; then
    log 'repo bootstrap .claude/cloud-bootstrap.sh baked'
  else
    log 'WARN repo bootstrap .claude/cloud-bootstrap.sh failed (see log)'
  fi
else
  # Logged rather than silent: a missing "baked" line would otherwise be
  # ambiguous between the expected no-op (repo has no bootstrap) and the CWD
  # not being the repo checkout, which is a real problem.
  log 'no repo bootstrap at .claude/cloud-bootstrap.sh (no-op, or CWD is not the repo checkout)'
fi

# Generic plugin install — data-driven from the checkout's .claude/settings.json
# (extraKnownMarketplaces + enabledPlugins); no repo-specific logic, and a repo
# that declares nothing gets nothing. This must happen here, at cache build:
# Claude Code reads its plugin registry at process start and never re-reads it,
# so only snapshot-baked installs are loaded at a session's first turn.
# Consumer repos use github-source marketplaces, whose install/update semantics
# already handle versions — no snapshot-refresh logic here (the commit-drift
# refresh in claude-code-plugins' own hook is specific to its directory-source
# dogfooding).
settings='.claude/settings.json'
if ! command -v claude >/dev/null 2>&1; then
  log 'plugins: claude CLI not on PATH; skipping'
elif ! command -v jq >/dev/null 2>&1; then
  log 'plugins: jq not available; skipping'
elif [[ ! -f "$settings" ]]; then
  log 'plugins: no .claude/settings.json; skipping'
elif ! jq -e '(.extraKnownMarketplaces // {}) != {} or (.enabledPlugins // {}) != {}' \
  "$settings" >/dev/null 2>&1; then
  log 'plugins: settings declare no marketplaces or plugins; skipping'
else
  registered="$(claude plugin marketplace list --json 2>/dev/null |
    jq -r '.[].name' 2>/dev/null)"
  while IFS=$'\t' read -r mp_name mp_target; do
    [[ -n "$mp_name" ]] || continue
    if grep -qxF "$mp_name" <<<"$registered"; then
      log "plugins: marketplace $mp_name already registered"
    elif [[ -z "$mp_target" ]]; then
      log "WARN plugins: marketplace $mp_name declares no repo/path/url source; skipped"
    elif claude plugin marketplace add "$mp_target" >>"$LOG" 2>&1; then
      log "plugins: marketplace $mp_name registered ($mp_target)"
    else
      log "WARN plugins: marketplace add failed: $mp_name ($mp_target)"
    fi
  done < <(jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
    | [.key, (.value.source.repo // .value.source.path // .value.source.url // "")]
    | @tsv' "$settings" 2>/dev/null)

  installed="$(claude plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null)"
  while IFS= read -r plugin_id; do
    [[ -n "$plugin_id" ]] || continue
    if grep -qxF "$plugin_id" <<<"$installed"; then
      log "plugins: $plugin_id already installed"
    elif claude plugin install "$plugin_id" --scope user -y >>"$LOG" 2>&1; then
      log "plugins: installed $plugin_id"
    else
      log "WARN plugins: install failed: $plugin_id"
    fi
  done < <(jq -r '(.enabledPlugins // {}) | to_entries[]
    | select(.value == true) | .key' "$settings" 2>/dev/null)
fi

log "done version=$SCRIPT_VERSION"
printf '%s %s\n' "$SCRIPT_VERSION" "$(date -u +%FT%TZ)" >"$STAMP" 2>/dev/null
exit 0
