#!/usr/bin/env bash
# Report-only fleet drift check for the plugin catalog each repo declares.
#
# The baseline is this repository's own committed .claude/settings.json —
# standards dogfoods the fleet-standard catalog, so its enabledPlugins set and
# marketplace declarations are the reference. Each target repository's checked
# in .claude/settings.json is the per-repo source of truth (cloud sessions
# install exactly what it declares); this script only makes divergence from
# the baseline visible, it never edits anything. A repo may diverge on
# purpose — the signal is the diff existing, not the diff being wrong.
#
# Usage:
#   distribution/check-plugin-baseline.sh [owner/repo ...]
#     No arguments: checks every target listed in sync-manifest.yml, fetching
#     each repo's .claude/settings.json@HEAD via `gh api` (works for private
#     repositories with the caller's gh auth).
#   distribution/check-plugin-baseline.sh --compare <baseline.json> <candidate.json>
#     Offline single comparison between two settings files (also what the
#     test exercises).
#
# Exit status: 0 always in report mode (drift is a signal, not a failure);
# --compare exits 1 when the candidate diverges, so callers can script it.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
baseline="$root/.claude/settings.json"

# compare_settings <baseline.json> <candidate.json> <label>
# Prints the candidate's divergence from the baseline: enabledPlugins entries
# missing (in baseline, not candidate), extra (in candidate, not baseline),
# and marketplace declarations whose name or source differ. Always returns 0
# (so callers under set -e need no condition context — .shellcheckrc's SC2310);
# divergence is signalled through the DIVERGED global instead.
DIVERGED=0
compare_settings() {
  local base="$1" cand="$2" label="$3" diverged=0 line

  local missing extra
  # tr -d '\r' throughout: a Windows jq emits CRLF, and a carried CR corrupts
  # the reported names (and, in fleet mode, the repo slug handed to gh api).
  missing=$(jq -r --slurpfile b "$base" '
    ([$b[0].enabledPlugins // {} | to_entries[] | select(.value == true) | .key]
     - [.enabledPlugins // {} | to_entries[] | select(.value == true) | .key])[]' \
    "$cand" 2>/dev/null | tr -d '\r' || true)
  extra=$(jq -r --slurpfile b "$base" '
    ([.enabledPlugins // {} | to_entries[] | select(.value == true) | .key]
     - [$b[0].enabledPlugins // {} | to_entries[] | select(.value == true) | .key])[]' \
    "$cand" 2>/dev/null | tr -d '\r' || true)

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s: missing vs baseline: %s\n' "$label" "$line"
    diverged=1
  done <<EOF
$missing
EOF
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s: beyond baseline: %s\n' "$label" "$line"
    diverged=1
  done <<EOF
$extra
EOF

  local mp_diff
  mp_diff=$(jq -r --slurpfile b "$base" '
    (.extraKnownMarketplaces // {}) as $c
    | ($b[0].extraKnownMarketplaces // {}) as $bm
    | ( ($bm | keys) - ($c | keys) | map("marketplace missing vs baseline: " + .) )
      + ( ($c | keys) - ($bm | keys) | map("marketplace beyond baseline: " + .) )
      + ( [ ($bm | keys)[] as $k
            | select(($c[$k] != null) and ($c[$k].source != $bm[$k].source))
            | "marketplace source differs: " + $k ] )
    | .[]' "$cand" 2>/dev/null | tr -d '\r' || true)
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s: %s\n' "$label" "$line"
    diverged=1
  done <<EOF
$mp_diff
EOF

  if [[ "$diverged" -eq 0 ]]; then
    printf '%s: matches baseline\n' "$label"
  else
    DIVERGED=1
  fi
  return 0
}

# Both modes judge with jq; a missing jq or an unparsable settings file must
# be a loud usage error, never an empty diff read as "matches baseline".
command -v jq >/dev/null 2>&1 || {
  echo 'check-plugin-baseline: jq is required' >&2
  exit 2
}

# require_parses <file> <label> — refuse to compare what jq cannot read.
require_parses() {
  jq empty "$1" 2>/dev/null || {
    printf 'check-plugin-baseline: %s is not valid JSON: %s\n' "$2" "$1" >&2
    exit 2
  }
}

if [[ "${1:-}" == "--compare" ]]; then
  [[ $# -eq 3 ]] || {
    echo 'usage: check-plugin-baseline.sh --compare <baseline.json> <candidate.json>' >&2
    exit 2
  }
  require_parses "$2" 'baseline'
  require_parses "$3" 'candidate'
  compare_settings "$2" "$3" "$(basename "$3")"
  exit "$DIVERGED"
fi

command -v gh >/dev/null 2>&1 || {
  echo 'check-plugin-baseline: gh CLI is required for fleet mode' >&2
  exit 2
}

require_parses "$baseline" 'baseline'

repos="$*"
if [[ -z "$repos" ]]; then
  # Target enumeration belongs to the engine, not to a second YAML parser:
  # `matrix` is the same primitive the sync workflow consumes. The engine
  # rejects absolute paths, so run it from the repo root with relative ones.
  repos=$(cd "$root" && bash distribution/sync-manifest.sh matrix \
    --source-root . --manifest distribution/sync-manifest.yml |
    jq -r '.include[].repo' | tr -d '\r')
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for repo in $repos; do
  # The raw media type returns the file bytes directly — no base64 step, whose
  # decode flag differs between GNU (-d) and BSD/macOS (-D).
  if gh api -H 'Accept: application/vnd.github.raw+json' \
    "repos/$repo/contents/.claude/settings.json" >"$tmp/candidate.json" 2>/dev/null &&
    jq empty "$tmp/candidate.json" 2>/dev/null; then
    compare_settings "$baseline" "$tmp/candidate.json" "$repo"
  else
    printf '%s: no readable .claude/settings.json (repo declares nothing)\n' "$repo"
  fi
done

exit 0
