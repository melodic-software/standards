#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'sweep: %s\n' "$*" >&2
  exit 2
}

config=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || die '--config needs a file'
      config="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[[ -n "$config" ]] || die 'usage: sweep.sh --config FILE DIR...'
[[ -f "$config" ]] || die "config not found: $config"
[[ $# -gt 0 ]] || die 'no checkout directories given'

# The Primary location carries the offending `uses:` value; rows are 0-based.
# shellcheck disable=SC2016 # $dir is a jq variable, bound by --arg
findings='.[] | select(.ident == "unpinned-uses") | .locations[]
  | select(.symbolic.kind == "Primary")
  | "\(.symbolic.key.Local.verbatim_path | ltrimstr($dir + "/")):\(.concrete.location.start_point.row + 1): \(.concrete.feature)"'

err="$(mktemp)"
trap 'rm -f -- "$err"' EXIT

status=0
for dir in "$@"; do
  dir="${dir%/}"
  repo="${dir##*/}"
  [[ -d "$dir" ]] || {
    printf 'sweep: not a directory: %s\n' "$dir" >&2
    status=2
    continue
  }
  if [[ -z "$(find "$dir" -path "$dir/.git" -prune -o -type f \( \
    -path "$dir/.github/workflows/*.yml" -o -path "$dir/.github/workflows/*.yaml" \
    -o -name action.yml -o -name action.yaml \) -print -quit)" ]]; then
    printf 'NO-INPUTS: %s\n' "$repo"
    continue
  fi
  rc=0
  out="$(zizmor --offline --no-progress --color=never --format=json --no-ignores \
    --collect=workflows,actions --config "$config" -- "$dir" 2>"$err")" || rc=$?
  case "$rc" in
    0 | 11 | 12 | 13 | 14) ;;
    *)
      printf 'sweep: zizmor exited %s on %s\n' "$rc" "$repo" >&2
      cat "$err" >&2
      status=2
      continue
      ;;
  esac
  lines="$(jq -r --arg dir "$dir" "$findings" <<<"$out")" || {
    printf 'sweep: unreadable zizmor output for %s\n' "$repo" >&2
    status=2
    continue
  }
  if [[ -n "$lines" ]]; then
    while IFS= read -r line; do printf 'UNPINNED: %s: %s\n' "$repo" "$line"; done <<<"$lines"
    [[ $status -eq 2 ]] || status=1
  else
    printf 'CLEAN: %s\n' "$repo"
  fi
done
exit "$status"
