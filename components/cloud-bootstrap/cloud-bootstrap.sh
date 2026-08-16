#!/usr/bin/env bash
# Canonical repo cloud bootstrap (SSOT). Materialized to each fleet repo's
# .claude/cloud-bootstrap.sh by distribution/sync-manifest.yml, so edits land
# here by pull request and fan out as reviewed sync PRs — never by patching a
# repo's materialized copy. Repo-specific work does not belong here: a repo
# enriches through its own .claude/cloud-bootstrap.local.sh (run below,
# never synced), or takes the component locally-owned in the manifest to
# customize the whole file.
#
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
# Idempotent and best effort: a failed step costs a tool or a plugin, never
# the session.
#
# Everything below is data-driven from the repo's own manifests — .node-version,
# package-lock.json, global.json, .claude/settings.json — so this file carries
# no repo names, no pinned versions, and no marketplace identifiers.
#
# Both callers run `bash <this script>`, so the interpreter is whatever `bash`
# resolves to rather than the shebang's. Stock macOS still ships bash 3.2, which
# has no `mapfile`, and errors on an empty "${array[@]}" under `set -u` before
# 4.4. Both are avoided here: newline-delimited strings, no arrays.
set -euo pipefail

[[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] || exit 0

repo_root="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
cd -- "$repo_root"

# Environment-snapshot inventory line: the shared environment's setup script
# writes its version + build time to this stamp as its last action. Logging it
# from every session makes "which snapshot is this account booting" visible
# without a per-account audit; a missing stamp means an unmanaged environment
# or an interrupted cache build.
if [[ -f /opt/melodic-env-setup.done ]]; then
  echo "cloud-bootstrap: env snapshot $(cat /opt/melodic-env-setup.done)" >&2
else
  echo "cloud-bootstrap: no env setup stamp (unmanaged environment or interrupted cache build)" >&2
fi

# --- Repo toolchain ---------------------------------------------------------
# Ahead of the plugin-CLI guards below on purpose: those `command -v` checks
# exit 0 when `claude` or `jq` is missing, and the toolchain must not be
# collateral damage of an unrelated CLI being absent. The cloud VM is a fresh
# Ubuntu image shipping Node 20/21/22 and no .NET, so without this a session
# builds and lints on the wrong toolchain — the failure a live cloud
# verification run confirmed across the fleet. The shared environment's setup
# script pre-installs a warm cache of common pins; this stage is the
# correctness guarantee and must not assume the cache installed anything.
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

  # npm dependencies from the root lockfile, skipped when already in sync.
  # Additional lockfile locations are a repo concern: install them from
  # .claude/cloud-bootstrap.local.sh.
  if [[ -f package-lock.json ]]; then
    if [[ ! -f node_modules/.package-lock.json ]] ||
      [[ package-lock.json -nt node_modules/.package-lock.json ]]; then
      npm ci --no-audit --no-fund >/dev/null 2>&1 ||
        toolchain_warn 'npm ci failed; node_modules is unavailable this session'
    fi
  fi

  # .NET SDK exactly as global.json pins, repo-local.
  if [[ -f global.json ]] && command -v jq >/dev/null 2>&1; then
    sdk="$(jq -r '.sdk.version // empty' global.json 2>/dev/null)"
    if [[ -n "$sdk" ]]; then
      # -F: the version is a literal, and its dots are not regex wildcards.
      if [[ ! -x .dotnet/dotnet ]] || ! .dotnet/dotnet --list-sdks 2>/dev/null | grep -qF "$sdk "; then
        installer=/tmp/dotnet-install.sh
        # The cloud egress proxy can return an error body with HTTP 200 from
        # dot.net, which `curl -f` cannot catch (-f only trips on >= 400), so a
        # real installer's shebang is checked before it is executed.
        # --proto/--proto-redir pin the redirect chain (dot.net -> aka.ms ->
        # builds.dotnet.microsoft.com) to HTTPS end to end.
        if curl -fsSL --proto '=https' --proto-redir '=https' \
          --retry 2 --retry-delay 3 https://dot.net/v1/dotnet-install.sh -o "$installer" 2>/dev/null &&
          [[ -s "$installer" ]] &&
          head -c 2 "$installer" 2>/dev/null | grep -q '^#!' &&
          bash "$installer" --version "$sdk" --install-dir .dotnet >/dev/null 2>&1; then
          :
        else
          toolchain_warn "dotnet $sdk install failed — check the environment's network allowlist (dot.net, aka.ms, builds.dotnet.microsoft.com, download.visualstudio.microsoft.com)"
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

  # Git history: base-ref diffs (several plugin suites use origin/main) break
  # on the shallow single-branch cloud clone — deepen it and make origin/main
  # resolve. The explicit destination refspec matters: in a single-branch
  # clone a bare `fetch origin main` only writes FETCH_HEAD and never creates
  # refs/remotes/origin/main. `main` is the fleet's default branch.
  git_dir="$(git rev-parse --git-dir 2>/dev/null)"
  if [[ -n "$git_dir" && -f "$git_dir/shallow" ]]; then
    git fetch --quiet --unshallow 2>/dev/null ||
      toolchain_warn 'could not unshallow; base-ref diffs may fail'
  fi
  git fetch --quiet origin "+main:refs/remotes/origin/main" 2>/dev/null ||
    toolchain_warn 'could not fetch origin/main'

  # --- Repo extension (enrich seam) -----------------------------------------
  # A repo appends its own setup — extra lockfiles, pinned hygiene binaries,
  # symlinks — in this committed, never-synced sibling. Same contract as this
  # file: idempotent, best effort, bash-3.2-safe. Deliberately inside this
  # subshell so it inherits the nvm-selected Node on PATH and the
  # warn-never-fatal posture, plus this script's environment
  # (CLAUDE_CODE_REMOTE, CLAUDE_PROJECT_DIR, CLAUDE_ENV_FILE when the
  # SessionStart hook is the caller). Its failure costs the extension, never
  # the session.
  if [[ -f .claude/cloud-bootstrap.local.sh ]]; then
    if bash .claude/cloud-bootstrap.local.sh >&2; then
      toolchain_warn 'local extension completed'
    else
      toolchain_warn 'WARN local extension failed'
    fi
  fi

  exit 0
)

# --- Plugins ----------------------------------------------------------------
# Data-driven from the repo's committed .claude/settings.json — every declared
# marketplace is registered and every enabledPlugins entry set to true is
# installed, whichever marketplace it names. A repo that declares nothing gets
# nothing. Explicit installs also sidestep the platform rule that adding a
# marketplace never auto-installs externally-sourced plugins.
command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

settings='.claude/settings.json'
[[ -f "$settings" ]] || exit 0

registered="$(claude plugin marketplace list --json 2>/dev/null |
  jq -r '.[].name' 2>/dev/null || true)"
declared=$(
  jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
    | [.key, (.value.source.repo // .value.source.path // .value.source.url // "")]
    | @tsv' "$settings" 2>/dev/null || true
)
while IFS=$'\t' read -r mp_name mp_target; do
  [[ -n "$mp_name" ]] || continue
  if [[ $'\n'"$registered"$'\n' == *$'\n'"$mp_name"$'\n'* ]]; then continue; fi
  if [[ -z "$mp_target" ]]; then
    echo "cloud-bootstrap: marketplace $mp_name declares no repo/path/url source; skipped" >&2
  elif claude plugin marketplace add "$mp_target" --scope user >/dev/null 2>&1; then
    echo "cloud-bootstrap: marketplace $mp_name registered ($mp_target)" >&2
  else
    echo "cloud-bootstrap: WARN marketplace add failed: $mp_name ($mp_target)" >&2
  fi
done <<EOF
$declared
EOF

wanted=$(
  jq -r '.enabledPlugins // {} | to_entries[]
    | select(.value == true) | .key' "$settings" 2>/dev/null || true
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
# that is why every summary above goes to stderr — and this line asks for a
# skills re-scan for whatever the harness can pick up mid-session (the plugin
# registry itself is only rebuilt at the next process start). From the
# pre-launch caller it lands harmlessly in the setup log.
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true}}'
