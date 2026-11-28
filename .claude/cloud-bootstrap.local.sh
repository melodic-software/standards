#!/usr/bin/env bash
set -uo pipefail

warn() { printf 'cloud-bootstrap.local: %s\n' "$*" >&2; }

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
