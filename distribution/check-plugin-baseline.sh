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
manifest="$root/distribution/sync-manifest.yml"

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
  missing=$(jq -r --slurpfile b "$base" '
    ([$b[0].enabledPlugins // {} | to_entries[] | select(.value == true) | .key]
     - [.enabledPlugins // {} | to_entries[] | select(.value == true) | .key])[]' \
    "$cand" 2>/dev/null || true)
  extra=$(jq -r --slurpfile b "$base" '
    ([.enabledPlugins // {} | to_entries[] | select(.value == true) | .key]
     - [$b[0].enabledPlugins // {} | to_entries[] | select(.value == true) | .key])[]' \
    "$cand" 2>/dev/null || true)

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
    | .[]' "$cand" 2>/dev/null || true)
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

if [[ "${1:-}" == "--compare" ]]; then
  [[ $# -eq 3 ]] || {
    echo 'usage: check-plugin-baseline.sh --compare <baseline.json> <candidate.json>' >&2
    exit 2
  }
  compare_settings "$2" "$3" "$(basename "$3")"
  exit "$DIVERGED"
fi

command -v gh >/dev/null 2>&1 || {
  echo 'check-plugin-baseline: gh CLI is required for fleet mode' >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  echo 'check-plugin-baseline: jq is required' >&2
  exit 2
}

repos="$*"
if [[ -z "$repos" ]]; then
  repos=$(sed -n '/^targets:/,$p' "$manifest" |
    sed -n 's/^  \([a-z.-]*\/[a-z.-]*\):$/\1/p')
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for repo in $repos; do
  if gh api "repos/$repo/contents/.claude/settings.json" \
    --jq '.content' 2>/dev/null | base64 -d >"$tmp/candidate.json" 2>/dev/null &&
    [[ -s "$tmp/candidate.json" ]]; then
    compare_settings "$baseline" "$tmp/candidate.json" "$repo"
  else
    printf '%s: no readable .claude/settings.json (repo declares nothing)\n' "$repo"
  fi
done

exit 0
