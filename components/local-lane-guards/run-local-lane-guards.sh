#!/usr/bin/env bash
# Local-lane entrypoint for the bespoke CI guards that previously had no
# non-CI invocation path. Owns one dispatcher over four drivers so consumers
# invoke the standards-owned source (pointer-not-copy) instead of maintaining
# a per-repo copy. See README.md and docs/adr/0004-local-lane-guards-via-standards-component.md.
#
# Usage:
#   run-local-lane-guards.sh <guard>|all [env overrides via the environment]
#   run-local-lane-guards.sh --help
#
# Guards: comment-hygiene | exec-bit | machine-specific-paths | reference-integrity | all
#
# Exit: 0 clean, 1 findings, 2 usage/environment error. `all` stops at the first
# failing guard and propagates its exit code.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: run-local-lane-guards.sh <guard>|all

Standards-owned local lane for bespoke CI guards (pointer-not-copy).

Guards:
  comment-hygiene          Deferred-work markers / tracker provenance in comments
  exec-bit                 Shebang files must be git mode 100755
  machine-specific-paths   Reject absolute user-home / checkout roots
  reference-integrity      Resolve file.md "Anchor" prose citations
  all                      Run every guard above (fail-fast)

Environment (optional, same contracts as the ci-workflows composite actions):
  PATHS / EXTENSIONS / EXCLUDE / GLOBS / PATTERNS_FILE
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

guard="$1"
shift || true

case "$guard" in
  --help | -h)
    usage
    exit 0
    ;;
  comment-hygiene)
    exec bash "$HERE/scan-comment-hygiene.sh" "$@"
    ;;
  exec-bit)
    exec bash "$HERE/check-exec-bit.sh" "$@"
    ;;
  machine-specific-paths)
    exec bash "$HERE/check-machine-specific-paths.sh" "$@"
    ;;
  reference-integrity)
    exec bash "$HERE/check-heading-cites.sh" "$@"
    ;;
  all)
    for g in comment-hygiene exec-bit machine-specific-paths reference-integrity; do
      echo "==> local-lane-guards: $g" >&2
      rc=0
      bash "$HERE/run-local-lane-guards.sh" "$g" || rc=$?
      if [[ "$rc" -ne 0 ]]; then
        echo "local-lane-guards: $g failed (exit $rc)" >&2
        exit "$rc"
      fi
    done
    echo "local-lane-guards: all clean" >&2
    exit 0
    ;;
  *)
    echo "run-local-lane-guards.sh: unknown guard '$guard' (try --help)" >&2
    exit 2
    ;;
esac
