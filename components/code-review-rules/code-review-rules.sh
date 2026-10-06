#!/usr/bin/env bash
# Checks that a repository's root AGENTS.md carries the `## Code Review Rules`
# section the convention in this directory's README.md defines: the heading,
# the inherited intro line verbatim, and exactly one org-wide REVIEW.md pointer
# whose target matches whether the repository has a root REVIEW.md.
#
# Usage:
#   code-review-rules.sh file  [--root DIR]
#   code-review-rules.sh fleet [--org OWNER] [--repos FILE] [--fixtures DIR]
#   code-review-rules.sh names <REPOSITORIES.json
#
# `file` checks DIR/AGENTS.md against DIR/REVIEW.md (default DIR: `.`).
# `fleet` checks the default branch of every repository named in FILE (one
# name per line), reading each repository's AGENTS.md and REVIEW.md through
# the GitHub contents API with the GH_TOKEN in the environment. Without
# --repos it checks the org's public, non-archived repositories without the
# `sandbox` topic, which any token can read. --fixtures DIR reads
# DIR/<repo>/AGENTS.md and DIR/<repo>/REVIEW.md instead of the API (tests
# only).
# `names` reads GitHub repository objects on stdin (a JSON array or a stream
# of objects) and prints the name of each one the fleet audits: not archived
# and without the `sandbox` topic. The scheduled workflow pipes its private
# installation listing through it, so both listings apply one filter.
#
# Exits 0 when every repository checked conforms, 1 when any does not (one
# `MISSING:` line per repository), 2 on a usage or query error.
set -euo pipefail

org='melodic-software'
root='.'
repos_file=''
fixtures=''

heading='## Code Review Rules'
intro='Each line names a rule CI does not enforce; the linked file states it in full.'
pointer_label='- Org-wide criteria:'
# shellcheck disable=SC2016 # literal Markdown backticks, not an expansion
pointer_prefix='- Org-wide criteria: [`REVIEW.md`]('
canonical_url='https://github.com/melodic-software/standards/blob/main/REVIEW.md'
# The repository objects the fleet audits: not archived, and not a disposable
# test bed carrying the `sandbox` topic (pr-pipeline-sandbox).
audited='select((.archived | not) and (any(.topics[]?; . == "sandbox") | not)) | .name'

usage() {
  sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

die() {
  printf 'code-review-rules: %s\n' "$*" >&2
  exit 2
}

command="${1:-}"
case "$command" in
  file | fleet) shift ;;
  names)
    jq -r "if type == \"array\" then .[] else . end | ${audited}"
    exit
    ;;
  -h | --help | help | '')
    usage
    exit 0
    ;;
  *) die "unknown command: $command" ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) root="${2:?--root needs a directory}"; shift 2 ;;
    --org) org="${2:?--org needs an owner}"; shift 2 ;;
    --repos) repos_file="${2:?--repos needs a path}"; shift 2 ;;
    --fixtures) fixtures="${2:?--fixtures needs a directory}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

# problems <agents-text> <has-review: true|false> — prints one reason per
# line for each way the text misses the convention; prints nothing when it
# conforms.
problems() {
  local text="$1" has_review="$2"
  local count section pointers expected unclosed
  # Fenced code is an example, never an operative line: drop it first. As in
  # CommonMark, a fence closes only on a bare run of its own character at
  # least as long as the opening run, and an unclosed fence runs to the end of
  # the document.
  # shellcheck disable=SC2016 # awk program text, not a shell expansion
  local fences='
    match($0, /^[[:space:]]*(```+|~~~+)/) {
      run = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", run)
      c = substr(run, 1, 1); n = length(run); rest = substr($0, RSTART + RLENGTH)
      if (!fenced) { fenced = 1; fc = c; fn = n; next }
      if (c == fc && n >= fn && rest ~ /^[[:space:]]*$/) { fenced = 0; next }
    }
    !fenced && !flag { print }
    END { if (flag && fenced) print "unclosed" }'
  unclosed="$(printf '%s\n' "$text" | awk -v flag=1 "$fences")"
  text="$(printf '%s\n' "$text" | awk -v flag=0 "$fences")"
  count="$(printf '%s\n' "$text" | grep -cxF -- "$heading" || true)"
  if [[ "$count" -eq 0 ]]; then
    if [[ -n "$unclosed" ]]; then
      echo "no '${heading}' heading outside code fences (a code fence is never closed)"
    else
      echo "no '${heading}' heading"
    fi
    return
  fi
  [[ "$count" -eq 1 ]] || echo "${count} '${heading}' headings, expected one"
  # The section runs from the heading to the next level-1 or level-2 heading.
  section="$(printf '%s\n' "$text" | awk -v h="$heading" '
    $0 == h { inside = 1; next }
    inside && /^##? / { exit }
    inside { print }')"
  printf '%s\n' "$section" | grep -qxF -- "$intro" || echo "the inherited intro line is missing"
  # Every line naming the org-wide criteria counts, linked or not and at any
  # indentation (an indented bullet is still a list item), so a stale second
  # pointer beside the correct one cannot pass.
  pointers="$(printf '%s\n' "$section" | awk -v p="$pointer_label" '{ s = $0; sub(/^[[:space:]]+/, "", s) } index(s, p) == 1')"
  if [[ -z "$pointers" ]]; then
    echo "the inherited REVIEW.md pointer line is missing"
    return
  fi
  count="$(printf '%s\n' "$pointers" | wc -l | tr -d ' ')"
  if [[ "$count" -ne 1 ]]; then
    echo "${count} org-wide criteria pointer lines, expected one"
    return
  fi
  # The inherited block is copied verbatim, so the one pointer is unindented.
  if [[ "$pointers" == [[:space:]]* ]]; then
    echo "the org-wide criteria pointer line must not be indented"
    return
  fi
  if [[ "$has_review" == true ]]; then expected='REVIEW.md'; else expected="$canonical_url"; fi
  [[ "$pointers" == "${pointer_prefix}${expected})"* ]] ||
    echo "the REVIEW.md pointer must link ${expected} (root REVIEW.md present: ${has_review})"
}

if [[ "$command" == file ]]; then
  [[ -d "$root" ]] || die "not a directory: $root"
  if [[ ! -f "$root/AGENTS.md" ]]; then
    printf 'MISSING: %s: no root AGENTS.md\n' "$root"
    exit 1
  fi
  has_review=false
  [[ -f "$root/REVIEW.md" ]] && has_review=true
  found="$(problems "$(cat "$root/AGENTS.md")" "$has_review")"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found" | sed "s|^|MISSING: ${root}/AGENTS.md: |"
    exit 1
  fi
  printf 'OK: %s/AGENTS.md carries the Code Review Rules section\n' "$root"
  exit 0
fi

# ---- fleet ---------------------------------------------------------------
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# fetch <repo> <path> — writes the file's content to $scratch/content and sets
# `exists` to true, or sets it to false when the file does not exist. Any
# other failure is a query error.
fetch() {
  local repo="$1" path="$2"
  exists=true
  if [[ -n "$fixtures" ]]; then
    if [[ -f "$fixtures/$repo/$path" ]]; then
      cp "$fixtures/$repo/$path" "$scratch/content"
    else
      exists=false
    fi
    return 0
  fi
  if gh api -H 'Accept: application/vnd.github.raw' "repos/${org}/${repo}/contents/${path}" \
    >"$scratch/content" 2>"$scratch/err"; then
    return 0
  fi
  if ! grep -q 'HTTP 404' "$scratch/err"; then
    cat "$scratch/err" >&2
    die "could not read ${org}/${repo}/${path}"
  fi
  exists=false
}

if [[ -n "$repos_file" ]]; then
  [[ -e "$repos_file" ]] || die "repository list not found: $repos_file"
  repos="$(sed '/^[[:space:]]*$/d' "$repos_file" | LC_ALL=C sort -u)"
else
  repos="$(gh api --paginate "orgs/${org}/repos?type=public&per_page=100" \
    --jq ".[] | ${audited}" | LC_ALL=C sort -u)" \
    || die "could not list public repositories of ${org}"
fi
[[ -n "$repos" ]] || die 'no repositories to check'

status=0
ok=''
for repo in $repos; do
  fetch "$repo" AGENTS.md
  if [[ "$exists" != true ]]; then
    printf 'MISSING: %s: no root AGENTS.md\n' "$repo"
    status=1
    continue
  fi
  agents="$(cat "$scratch/content")"
  fetch "$repo" REVIEW.md
  found="$(problems "$agents" "$exists")"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found" | sed "s|^|MISSING: ${repo}: |"
    status=1
  else
    ok="${ok}${ok:+ }${repo}"
  fi
done

[[ -z "$ok" ]] || printf 'OK: %s\n' "$ok"
exit "$status"
