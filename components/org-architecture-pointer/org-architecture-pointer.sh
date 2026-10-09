#!/usr/bin/env bash
# Checks that a repository's root AGENTS.md or CLAUDE.md names the private
# org architecture repository, the substring `melodic-software/architecture`,
# so an agent working there is pointed at the org-wide decisions and glossary.
#
# Usage:
#   org-architecture-pointer.sh file  [--root DIR]
#   org-architecture-pointer.sh fleet [--org OWNER] [--repos FILE] [--fixtures DIR]
#   org-architecture-pointer.sh names <REPOSITORIES.json
#
# `file` checks DIR/AGENTS.md and DIR/CLAUDE.md (default DIR: `.`).
# `fleet` checks the default branch of every repository named in FILE (one
# name per line), reading each repository's AGENTS.md and CLAUDE.md through
# the GitHub contents API with the GH_TOKEN in the environment. Without
# --repos it checks the org's public, non-archived repositories the audit
# covers, which any token can read. --fixtures DIR reads
# DIR/<repo>/AGENTS.md and DIR/<repo>/CLAUDE.md instead of the API (tests
# only).
# `names` reads GitHub repository objects on stdin (a JSON array or a stream
# of objects) and prints the name of each one the fleet audits: not archived,
# without the `sandbox` topic, and not the architecture repository itself.
# The scheduled workflow pipes its private installation listing through it,
# so both listings apply one filter.
#
# Exits 0 when every repository checked conforms, 1 when any does not (one
# `MISSING:` line per repository), 2 on a usage or query error.
set -euo pipefail

org='melodic-software'
root='.'
repos_file=''
fixtures=''

needle='melodic-software/architecture'
# The name ends at a character that cannot continue a repository name.
pattern="${needle}($|[^A-Za-z0-9._-])"
# The repository objects the fleet audits: not archived, not a disposable
# test bed carrying the `sandbox` topic (pr-pipeline-sandbox), and not the
# architecture repository, which is the target of the pointer.
audited='select((.archived | not) and (any(.topics[]?; . == "sandbox") | not) and .name != "architecture") | .name'

usage() {
  sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

die() {
  printf 'org-architecture-pointer: %s\n' "$*" >&2
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

if [[ "$command" == file ]]; then
  [[ -d "$root" ]] || die "not a directory: $root"
  for f in AGENTS.md CLAUDE.md; do
    if [[ -f "$root/$f" ]] && grep -qE -- "$pattern" "$root/$f"; then
      printf 'OK: %s/%s names %s\n' "$root" "$f" "$needle"
      exit 0
    fi
  done
  printf 'MISSING: %s: neither AGENTS.md nor CLAUDE.md names %s\n' "$root" "$needle"
  exit 1
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
  found=false
  for f in AGENTS.md CLAUDE.md; do
    fetch "$repo" "$f"
    if [[ "$exists" == true ]] && grep -qE -- "$pattern" "$scratch/content"; then
      found=true
      break
    fi
  done
  if [[ "$found" == true ]]; then
    ok="${ok}${ok:+ }${repo}"
  else
    printf 'MISSING: %s: neither AGENTS.md nor CLAUDE.md names %s\n' "$repo" "$needle"
    status=1
  fi
done

[[ -z "$ok" ]] || printf 'OK: %s\n' "$ok"
exit "$status"
