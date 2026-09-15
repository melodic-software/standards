#!/usr/bin/env bash
# Repo extension to the synced cloud bootstrap (.claude/cloud-bootstrap.sh) —
# the enrich seam: committed here, never synced, run by the canonical script
# after its generic toolchain stage. Same contract as the caller: cloud-only
# caller, idempotent, best effort, bash-3.2-safe (no arrays, no mapfile),
# always exits 0.
#
# This repository's extension installs each component project's own lockfile:
# the root package.json declares no workspaces, so the canonical script's root
# `npm ci` does not reach the component projects and their modules (ajv and
# friends) would be missing — exactly what ci.yml works around with its own
# `npm ci --prefix` steps.
set -uo pipefail

warn() { printf 'cloud-bootstrap.local: %s\n' "$*" >&2; }

# npm_ci_at <dir> — install <dir>'s own lockfile when it is newer than the
# installed tree there.
npm_ci_at() {
  dir="$1"
  [[ -f "$dir/package-lock.json" ]] || return 0
  if [[ ! -f "$dir/node_modules/.package-lock.json" ]] ||
    [[ "$dir/package-lock.json" -nt "$dir/node_modules/.package-lock.json" ]]; then
    npm ci --no-audit --no-fund --prefix "$dir" >/dev/null 2>&1 ||
      warn "npm ci failed in $dir"
  fi
}

for component_lock in components/*/package-lock.json distribution/package-lock.json; do
  if [[ -f "$component_lock" ]]; then
    npm_ci_at "${component_lock%/package-lock.json}"
  fi
done

exit 0
