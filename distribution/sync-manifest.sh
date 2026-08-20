#!/usr/bin/env bash
# Stable CLI entrypoint for the standards distribution engine. The engine body
# lives in sync-manifest.mjs (standards-sync-audit Phase 6 cutover); this
# wrapper keeps every caller's `bash distribution/sync-manifest.sh ...`
# invocation byte-stable across the Bash-to-Node transition. The CLI surface,
# output bytes, and exit codes are the contract proven by
# sync-manifest.test.sh against the Node engine.
set -euo pipefail
exec node "$(dirname -- "$0")/sync-manifest.mjs" "$@"
