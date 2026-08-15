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
#   - repo-agnostic: per-repo work lives in each repo's committed,
#     CLAUDE_CODE_REMOTE-guarded SessionStart hook, which this script bakes
#     into the snapshot as its final step when the checked-out repo has one.
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

SCRIPT_VERSION='2026-08-15.1'
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
# repo's SessionStart hook also installs its exact SDK repo-locally, so the
# env copy is a warm cache and the hook is the correctness guarantee.
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

# Track C: Node 24.18.0 — the fleet .node-version pin; the VM image ships
# Node 20/21/22 only, so this is always an install.
(
  export NVM_DIR="${NVM_DIR:-/opt/nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    set +u # nvm.sh reads unset vars; subshell-local, tracks A/B keep nounset
    # shellcheck disable=SC1091
    if . "$NVM_DIR/nvm.sh" &&
      nvm install 24.18.0 >>"$LOG" 2>&1 &&
      nvm alias default 24.18.0 >>"$LOG" 2>&1; then
      log 'node 24.18.0 installed'
    else
      log 'WARN node 24.18.0 install failed'
    fi
  else
    log 'WARN nvm not found; node pin unavailable'
  fi
) &

wait

# Bake the checked-out repo's own bootstrap into the cached snapshot (no-op
# for repos without the hook; hooks are idempotent, so any repo/cache pairing
# is safe — sessions re-run the hook at startup either way).
if [[ -f .claude/hooks/session-start.sh ]]; then
  if CLAUDE_CODE_REMOTE=true bash .claude/hooks/session-start.sh >>"$LOG" 2>&1; then
    log 'repo SessionStart hook baked'
  else
    log 'WARN repo SessionStart hook failed (see log; sessions re-run it)'
  fi
else
  # Logged rather than silent: a missing "baked" line would otherwise be
  # ambiguous between the expected no-op (repo has no hook) and the CWD not
  # being the repo checkout, which is a real problem.
  log 'no repo SessionStart hook at .claude/hooks/session-start.sh (no-op, or CWD is not the repo checkout)'
fi

log "done version=$SCRIPT_VERSION"
printf '%s %s\n' "$SCRIPT_VERSION" "$(date -u +%FT%TZ)" >"$STAMP" 2>/dev/null
exit 0
