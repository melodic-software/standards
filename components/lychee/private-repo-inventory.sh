#!/usr/bin/env bash
# Keeps lychee.toml's private-repo exclude inventory in lockstep with actual
# GitHub repository visibility, so the list is derived from a queryable fact
# instead of hand-maintained (standards#212, then #483: the same drift twice).
#
# The inventory is the repository alternation shared by the two
# `melodic-software/` exclude entries in lychee.toml (github.com and
# raw.githubusercontent.com). Both must carry the identical, sorted set.
#
# Usage:
#   private-repo-inventory.sh list     [--config FILE]
#   private-repo-inventory.sh check    [--config FILE] [--org OWNER]
#                                      [--public-list FILE]
#                                      [--installation-list FILE]
#                                      [--private-list FILE]
#   private-repo-inventory.sh generate [--config FILE] [--org OWNER]
#                                      [--private-list FILE] [--write]
#
# Inputs (each defaults to a live `gh` query when the file is omitted):
#   --public-list FILE        one public repository name per line
#                             (default: GET /orgs/OWNER/repos?type=public —
#                             readable with any token, including a public
#                             repository's GITHUB_TOKEN)
#   --installation-list FILE  `name<TAB>true|false` (private flag) per line for
#                             every repository an App installation can see
#                             (default: none; pass `--installation-list -`
#                             to read GET /installation/repositories through
#                             the GH_TOKEN in the environment, which must be an
#                             App installation token)
#   --private-list FILE       one private repository name per line — the
#                             complete truth (default for `generate`:
#                             `gh repo list OWNER --visibility private`, which
#                             needs a credential that can read the private
#                             repositories, i.e. a maintainer's `gh auth`)
#
# `check` exits 0 when the inventory agrees with every fact it was given, 1 on
# drift (printing the regenerated entries), 2 on a usage or query error. It
# never edits the file. `generate` prints the two regenerated exclude entries,
# or rewrites them in place with --write.
set -euo pipefail

org='melodic-software'
config='lychee.toml'
public_list=''
installation_list=''
private_list=''
write=false

usage() {
  sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

die() {
  printf 'private-repo-inventory: %s\n' "$*" >&2
  exit 2
}

command="${1:-}"
case "$command" in
  list | check | generate) shift ;;
  -h | --help | help | '')
    usage
    exit 0
    ;;
  *) die "unknown command: $command" ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) config="${2:?--config needs a path}"; shift 2 ;;
    --org) org="${2:?--org needs an owner}"; shift 2 ;;
    --public-list) public_list="${2:?--public-list needs a path}"; shift 2 ;;
    --installation-list) installation_list="${2:?--installation-list needs a path}"; shift 2 ;;
    --private-list) private_list="${2:?--private-list needs a path}"; shift 2 ;;
    --write) write=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -f "$config" ]] || die "config not found: $config"

# Regex-escape the org for the literal-TOML patterns (`.` is the only
# metacharacter a GitHub owner can carry).
org_re="${org//./\\.}"
github_prefix="'^https?://github\\.com/${org_re}/("
raw_prefix="'^https?://raw\\.githubusercontent\\.com/${org_re}/("

# extract_group <prefix> — the alternation body of the single exclude entry
# that starts with <prefix>; errors on zero or several matches.
extract_group() {
  local prefix="$1" matches
  matches="$(grep -F -- "$prefix" "$config" || true)"
  local count
  count="$(printf '%s' "$matches" | grep -c . || true)"
  [[ "$count" -eq 1 ]] || die "expected exactly one exclude entry starting with ${prefix}, found ${count}"
  local rest="${matches#*"$prefix"}"
  printf '%s' "${rest%%)*}"
}

# group_to_lines <alternation> — one repository name per line, regex unescaped.
group_to_lines() {
  printf '%s' "$1" | tr '|' '\n' | sed 's/\\\././g' | sed '/^$/d'
}

# lines_to_group — sorted, unique, regex-escaped alternation from stdin lines.
lines_to_group() {
  LC_ALL=C sort -u | sed '/^$/d' | sed 's/\./\\./g' | paste -sd '|' -
}

github_group="$(extract_group "$github_prefix")"
raw_group="$(extract_group "$raw_prefix")"

inventory_lines() {
  group_to_lines "$github_group"
}

if [[ "$command" == list ]]; then
  inventory_lines
  exit 0
fi

# read_list <path> — file lines with blank lines dropped.
read_list() {
  [[ -f "$1" ]] || die "list not found: $1"
  sed '/^[[:space:]]*$/d' "$1"
}

query_public() {
  gh api --paginate "orgs/${org}/repos?type=public&per_page=100" --jq '.[].name' \
    || die "could not list public repositories of ${org}"
}

query_installation() {
  gh api --paginate 'installation/repositories?per_page=100' \
    --jq '.repositories[] | "\(.name)\t\(.private)"' \
    || die 'could not list the App installation repositories (GH_TOKEN must be an installation token)'
}

query_private() {
  gh repo list "$org" --visibility private --limit 1000 --json name --jq '.[].name' \
    || die "could not list private repositories of ${org} (needs a credential that can read them)"
}

# render <alternation> — the two exclude entries as they belong in the file.
render() {
  printf "  %s%s)(\\\\.git)?([/#?]|\$)',\n" "$github_prefix" "$1"
  printf "  %s%s)/',\n" "$raw_prefix" "$1"
}

if [[ "$command" == generate ]]; then
  if [[ -n "$private_list" ]]; then
    private_lines="$(read_list "$private_list")"
  else
    private_lines="$(query_private)"
  fi
  [[ -n "$private_lines" ]] || die 'refusing to generate an empty inventory'
  new_group="$(printf '%s\n' "$private_lines" | lines_to_group)"
  if [[ "$write" != true ]]; then
    render "$new_group"
    exit 0
  fi
  tmp="$(mktemp)"
  # Passed through the environment rather than `-v`: awk applies escape
  # processing to -v values, which would turn every `\.` into a bare `.`.
  GP="$github_prefix" RP="$raw_prefix" NG="$new_group" awk '
    BEGIN { gp = ENVIRON["GP"]; rp = ENVIRON["RP"]; ng = ENVIRON["NG"] }
    function rewrite(prefix,   i, rest, j) {
      i = index($0, prefix)
      if (i == 0) { return 0 }
      rest = substr($0, i + length(prefix))
      j = index(rest, ")")
      $0 = substr($0, 1, i + length(prefix) - 1) ng substr(rest, j)
      return 1
    }
    { if (!rewrite(gp)) { rewrite(rp) }; print }
  ' "$config" >"$tmp"
  mv "$tmp" "$config"
  printf 'private-repo-inventory: rewrote %s (%s)\n' "$config" "$(printf '%s' "$new_group" | tr '|' ' ')"
  exit 0
fi

# ---- check ---------------------------------------------------------------
status=0
problem() {
  printf 'DRIFT: %s\n' "$*" >&2
  status=1
}

if [[ "$github_group" != "$raw_group" ]]; then
  problem "the github.com and raw.githubusercontent.com alternations differ: (${github_group}) vs (${raw_group})"
fi

expected_group="$(inventory_lines | lines_to_group)"
if [[ "$github_group" != "$expected_group" ]]; then
  problem "the alternation is not sorted and unique: (${github_group}) should read (${expected_group})"
fi

inventory="$(inventory_lines | LC_ALL=C sort -u)"
verified=''
missing=''
wrongly_excluded=''

# 1. Public list: any excluded repository that is public is a wrongly silenced
#    live link (the "repo went public" direction of drift).
if [[ -n "$public_list" ]]; then
  public="$(read_list "$public_list")"
else
  public="$(query_public)"
fi
if [[ -n "$public" ]]; then
  wrongly_excluded="$(LC_ALL=C comm -12 <(printf '%s\n' "$inventory") <(printf '%s\n' "$public" | LC_ALL=C sort -u))"
  for name in $wrongly_excluded; do
    problem "${name} is public but excluded as private"
  done
fi

# 2. Complete private truth (maintainer credential): exact set equality.
if [[ -n "$private_list" ]]; then
  private="$(read_list "$private_list" | LC_ALL=C sort -u)"
  missing="$(LC_ALL=C comm -13 <(printf '%s\n' "$inventory") <(printf '%s\n' "$private"))"
  extra="$(LC_ALL=C comm -23 <(printf '%s\n' "$inventory") <(printf '%s\n' "$private"))"
  for name in $missing; do
    problem "${name} is private but not excluded"
  done
  for name in $extra; do
    [[ " ${wrongly_excluded//$'\n'/ } " == *" ${name} "* ]] && continue
    problem "${name} is excluded but is not a private repository of ${org} (renamed, transferred, or deleted?)"
  done
  verified="$private"
fi

# 3. Partial private truth (an App installation's repository set, e.g. the
#    standards-sync App, which sees every sync target): each private member
#    must be excluded. Non-members stay unverified, and are reported as such.
if [[ -n "$installation_list" ]]; then
  if [[ "$installation_list" == - ]]; then
    installation="$(query_installation)"
  else
    installation="$(read_list "$installation_list")"
  fi
  inst_private="$(printf '%s\n' "$installation" | awk -F '\t' '$2 == "true" { print $1 }' | LC_ALL=C sort -u)"
  inst_public="$(printf '%s\n' "$installation" | awk -F '\t' '$2 == "false" { print $1 }' | LC_ALL=C sort -u)"
  for name in $(LC_ALL=C comm -13 <(printf '%s\n' "$inventory") <(printf '%s\n' "$inst_private")); do
    problem "${name} is private (per the App installation) but not excluded"
    missing="${missing}${missing:+$'\n'}${name}"
  done
  for name in $(LC_ALL=C comm -12 <(printf '%s\n' "$inventory") <(printf '%s\n' "$inst_public")); do
    [[ " ${wrongly_excluded//$'\n'/ } " == *" ${name} "* ]] && continue
    problem "${name} is public (per the App installation) but excluded as private"
    wrongly_excluded="${wrongly_excluded}${wrongly_excluded:+$'\n'}${name}"
  done
  verified="${verified}${verified:+$'\n'}${inst_private}"
fi

if [[ -z "$private_list" ]]; then
  unverified="$(LC_ALL=C comm -23 <(printf '%s\n' "$inventory") <(printf '%s\n' "$verified" | LC_ALL=C sort -u | sed '/^$/d'))"
  unverified="$(printf '%s\n' "$unverified" | LC_ALL=C comm -23 - <(printf '%s\n' "$wrongly_excluded" | LC_ALL=C sort -u | sed '/^$/d'))"
  if [[ -n "$unverified" ]]; then
    printf 'NOTE: not verifiable with the credentials given (assumed still private): %s\n' \
      "$(printf '%s' "$unverified" | tr '\n' ' ')"
  fi
fi

if [[ "$status" -ne 0 ]]; then
  regenerated="$(
    {
      printf '%s\n' "$inventory"
      printf '%s\n' "$missing"
    } | LC_ALL=C sort -u | sed '/^$/d' \
      | LC_ALL=C comm -23 - <(printf '%s\n' "$wrongly_excluded" | LC_ALL=C sort -u | sed '/^$/d') \
      | lines_to_group
  )"
  printf 'Regenerated exclude entries for %s:\n' "$config" >&2
  render "$regenerated" >&2
  exit 1
fi

printf 'OK: %s private-repo inventory (%s) agrees with every visibility fact checked\n' \
  "$config" "$(printf '%s' "$inventory" | tr '\n' ' ')"
