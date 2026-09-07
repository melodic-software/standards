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
# build left no trace): every step logs a timestamped line to $LOG, the
# parallel tracks each write to their own temp log (concatenated under a
# track header after the wait barrier, so their output never interleaves),
# and the completion stamp is written only as the very last action.
# Verification starts at the stamp: a missing $STAMP (and no $STAMP_FALLBACK
# with a WARN in the log) means the build never finished — force a rebuild
# (any edit to the environment's script field does).
#
# Network prerequisite (claude-code-plugins#2654, Blocker 1 — verified live
# 2026-08-14): the .NET installer redirect chain (dot.net → aka.ms →
# builds.dotnet.microsoft.com / download.visualstudio.microsoft.com) is
# 403-blocked under Trusted network access. The environment must use Custom
# network access with "Also include default list of common package managers"
# checked plus those four hosts added. github.com is already on the default
# allowlist, so the pinned gh release asset needs no host of its own; the
# residual risk it carries is the GitHub proxy's repository scope, which can
# 403 release assets from repositories not attached to the session. That is
# why the gh step is best-effort and logs a WARN like every other step.
# shellcheck disable=SC2030,SC2031 # each parallel track deliberately
# reassigns LOG subshell-locally to its own temp log so track output never
# interleaves; the main shell's LOG is untouched by design.
set -u

SCRIPT_VERSION='2026-09-07.2'
STAMP='/opt/melodic-env-setup.done'
STAMP_FALLBACK='/tmp/melodic-env-setup.done'
# Fleet plugin list: the one standards-hosted, settings-shaped file every
# cloud snapshot installs at user scope (fleet-plugins.json beside this
# script). It arrives through the same raw.githubusercontent.com host this
# script does, and is written into the snapshot at FLEET_PLUGINS so each
# repo's session bootstrap can repair drift from it without a network round
# trip. It is the only install source at cache build; a repo's own
# enabledPlugins block carries deltas beyond the fleet, which the session
# bootstrap applies as an overlay on top of this list.
FLEET_PLUGINS_URL='https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/fleet-plugins.json'
FLEET_PLUGINS='/opt/melodic-fleet-plugins.json'
FLEET_PLUGINS_FALLBACK='/tmp/melodic-fleet-plugins.json'
LOG='/var/log/melodic-env-setup.log'
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$LOG"; }

# Plugin CLI listings are fetched once, lazily, on the first source that
# actually installs. `install_plugins_from` used to call `marketplace list`
# and `plugin list` itself (and spawn `grep -qxF` per entry): two CLI
# round-trips per source plus one grep per plugin. New registers and installs
# are recorded in-process, so a caller that installs from more than one source
# does not re-query. Same shape as cloud-bootstrap.sh, which reads two.
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

# install_plugins_from <settings-shaped json> <label>: register every
# declared marketplace and install every enabledPlugins entry set to true at
# user scope, skipping what is already present. Idempotence-check formats
# verified against claude CLI 2.1.241 (2026-08-23): `claude plugin list
# --json` ids are name@marketplace, exactly the enabledPlugins key shape, and
# `claude plugin marketplace list --json` names match extraKnownMarketplaces
# keys, so these exact membership checks are true already-installed checks,
# not format mismatches.
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

# Sourced by setup.test.sh for the plugin-list helpers only.
if [[ "${MELODIC_SETUP_LIBONLY:-}" == 1 ]]; then
  return 0
fi

if ! touch "$LOG" 2>/dev/null; then
  LOG='/tmp/melodic-env-setup.log'
fi

export DEBIAN_FRONTEND=noninteractive
rm -f "$STAMP" "$STAMP_FALLBACK" 2>/dev/null
log "start version=$SCRIPT_VERSION"

# Resolve the repo checkout root explicitly instead of trusting CWD: on a
# real cache build (SW2030, 2026-08-23, version 2026-08-15.3) the build's
# working directory was NOT the checkout, so the relative-path bootstrap and
# plugin steps silently no-opped. Primary: git from $PWD. Fallback: probe for
# a single git checkout under the container-user homes — the platform places
# it at /home/<container-user>/<repo> (observed live in remote sessions).
# Ambiguity or absence is a WARN, never a guess.
checkout_base='/home'
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO_ROOT=''
if [[ -n "$REPO_ROOT" && "$REPO_ROOT" != "$checkout_base"/* ]]; then
  # Sanity constraint: a git root outside the platform checkout area (a stray
  # dotfiles or tooling repo the build CWD happens to sit in) must not be
  # trusted — baking some other repo's bootstrap would recreate the silent
  # wrong-target failure this resolution exists to eliminate. Fall through to
  # the probe; skipping only costs warm cache (each repo's session bootstrap
  # stays the correctness guarantee), while a wrong bake is unrecoverable.
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

# Toolchain pins: prefer the resolved checkout's own manifests (global.json,
# .node-version) so the warm cache tracks each repo without manual sync;
# fall back to the fleet pins below when the repo declares none (or the root
# is unresolved). Each repo's cloud-bootstrap still installs its exact pins
# repo-locally — the env copy is a warm cache, the bootstrap the
# correctness guarantee.
DOTNET_FALLBACK_VERSIONS='10.0.302 10.0.400'
NODE_FALLBACK_VERSION='24.20.0'
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

# gh pin: a fleet pin with no in-repo manifest to read, so it is declared here
# and held in lockstep with the other two lanes by hand — the CI runner image
# (melodic-software/ci-runner, Dockerfile ARG GH_VERSION/GH_SHA256) and local
# dev machines (melodic-software/dotfiles, mise). All three must carry the same
# gh, or a script that passes on one lane fails on another. The hash is the
# sha256 of the exact release asset the install below names; bump version and
# hash together, and authenticate a new asset against the checksums cli/cli
# publishes for that release before recording its hash here.
GH_VERSION='2.98.0'
GH_SHA256='3b8ac6b30336802fc1a858d7c084e11cdf24ac1a761ca90b68022d7d729208de'
GH_TARBALL='/tmp/gh.tar.gz'

# Each parallel track writes to its own temp log (LOG is reassigned
# subshell-locally, so the log() calls and command output inside a track all
# land in its file); the tracks are concatenated into $LOG after the wait
# barrier so concurrent output never interleaves.
track_a_log="$(mktemp 2>/dev/null || echo "/tmp/melodic-env-track-a.$$")"
track_b_log="$(mktemp 2>/dev/null || echo "/tmp/melodic-env-track-b.$$")"
track_c_log="$(mktemp 2>/dev/null || echo "/tmp/melodic-env-track-c.$$")"

# Track A: gh CLI (pinned upstream release tarball) + PowerShell (apt;
# packages.microsoft.com is on the default allowlist).
(
  LOG="$track_a_log"
  # gh comes from its checksummed upstream release asset, at the version and
  # hash the CI runner image and local dev machines pin. Ubuntu's own archive
  # ships a years-stale gh (2.45.0 observed live in a cloud session, 53 minor
  # versions behind the other two lanes), and cli.github.com — the upstream
  # apt repo — is NOT on the default allowlist, so the release tarball is the
  # only install that keeps the three lanes at one version. Direct
  # /releases/download/ asset URLs do resolve from this build (the repo
  # bootstrap this script bakes in fetches its own hygiene binaries the same
  # way); a silent miss is caught by the verification checklist.
  # amd64 only, mirroring ci-runner's Dockerfile: the pin above is the hash of
  # that one asset, and substituting an unverified hash for another
  # architecture would defeat the check it exists to perform.
  gh_arch="$(uname -m)"
  if [[ "$gh_arch" != 'x86_64' ]]; then
    log "WARN gh install skipped: no pinned asset for $gh_arch (amd64 only)"
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

# Track B: .NET SDKs — the resolved repo's global.json pin when present,
# else the fleet fallback list above (rollForward: disable across the fleet,
# so exact versions matter).
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
    log 'WARN dotnet-install.sh fetch failed — check the Custom allowlist (see header)'
  fi
) &

# Track C: Node — the resolved repo's .node-version pin when present, else
# the fleet fallback above; the VM image ships Node 20/21/22 only, so this
# is always an install.
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

# Bake the checked-out repo's committed bootstrap (.claude/cloud-bootstrap.sh
# under the resolved repo root) into the cached snapshot. One name, no
# fallbacks: every fleet repo commits its generic repository setup —
# dependencies and plugin installs — there. Running it here is load-bearing
# for plugins: the session's plugin registry is built at process start and
# never re-read, so plugin installs must land at cache build, not
# mid-session.
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
  # Unambiguous no-op: the root WAS resolved, the repo just has no bootstrap.
  # The unresolved-root case logs its own distinct line above.
  log "repo root resolved to $REPO_ROOT, no bootstrap present (.claude/cloud-bootstrap.sh) — expected no-op"
fi

# Generic plugin install from one settings-shaped file (extraKnownMarketplaces
# + enabledPlugins): the fleet list at FLEET_PLUGINS_URL, which every snapshot
# installs whatever repo it was built for. No repo-specific logic — a repo's
# own enabledPlugins block declares deltas beyond the fleet and the session
# bootstrap applies them as an overlay, so the snapshot itself stays the same
# for every repo built against it. This must happen here, at cache build:
# Claude Code reads its plugin registry at process start and never re-reads
# it, so only snapshot-baked installs are loaded at a session's first turn.
# Github-source marketplaces' install/update semantics already handle
# versions — no snapshot-refresh logic here (the commit-drift refresh in
# claude-code-plugins' own hook is specific to its directory-source
# dogfooding).
if ! command -v claude >/dev/null 2>&1; then
  log 'plugins: claude CLI not on PATH; skipping'
elif ! command -v jq >/dev/null 2>&1; then
  log 'plugins: jq not available; skipping'
else
  # The fetched copy lands in the snapshot (FLEET_PLUGINS, or its /tmp
  # fallback with a WARN, mirroring the stamp) so the per-repo bootstrap's
  # drift repair reads the same list offline. A fetch failure costs this
  # build's plugin install, never the build: the next rebuild fetches again,
  # and a session on a snapshot without the list installs nothing rather than
  # guessing at a set.
  rm -f "$FLEET_PLUGINS" "$FLEET_PLUGINS_FALLBACK" 2>/dev/null
  if curl -fsSL --proto '=https' --retry 2 --retry-delay 3 \
    "$FLEET_PLUGINS_URL" -o "$FLEET_PLUGINS_FALLBACK" >>"$LOG" 2>&1 &&
    jq -e '(.enabledPlugins // {}) != {}' "$FLEET_PLUGINS_FALLBACK" >/dev/null 2>&1; then
    fleet_file="$FLEET_PLUGINS_FALLBACK"
    if cp "$FLEET_PLUGINS_FALLBACK" "$FLEET_PLUGINS" 2>/dev/null; then
      rm -f "$FLEET_PLUGINS_FALLBACK" 2>/dev/null
      fleet_file="$FLEET_PLUGINS"
    else
      log "WARN plugins (fleet): $FLEET_PLUGINS unwritable; list kept at $FLEET_PLUGINS_FALLBACK"
    fi
    log "plugins (fleet): list fetched to $fleet_file ($(jq -r '.enabledPlugins | length' "$fleet_file") entries)"
    install_plugins_from "$fleet_file" fleet
  else
    rm -f "$FLEET_PLUGINS_FALLBACK" 2>/dev/null
    log 'WARN plugins (fleet): list fetch failed or empty; no plugins install this build'
  fi
fi

# Temp-file hygiene: without this the fetched installers — and this script
# itself, which the environment bootstrap curls to /tmp — persist into the
# snapshot and show up in every live session. Runs after the repo bootstrap,
# which reuses /tmp/dotnet-install.sh. Unlinking the running script is safe:
# bash holds its open file descriptor.
rm -f /tmp/msprod.deb /tmp/dotnet-install.sh "$GH_TARBALL" \
  /tmp/melodic-env-setup.sh 2>/dev/null

log "done version=$SCRIPT_VERSION"
# Stamp write mirrors the $LOG fallback: /opt unwritable must not present as
# "build never finished" downstream — fall back to /tmp and WARN.
stamp_content="$SCRIPT_VERSION $(date -u +%FT%TZ)"
if ! printf '%s\n' "$stamp_content" >"$STAMP" 2>/dev/null; then
  log "WARN stamp: $STAMP unwritable; falling back to $STAMP_FALLBACK"
  if ! printf '%s\n' "$stamp_content" >"$STAMP_FALLBACK" 2>/dev/null; then
    log 'WARN stamp: fallback write failed too; verification will see a missing stamp'
  fi
fi
exit 0
