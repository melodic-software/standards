#!/usr/bin/env bash
# Tests the lychee component's offline checker: the good fixture's local links and
# anchors resolve on disk, and the bad fixture's broken references are flagged.
# Skips cleanly when the engine is absent or too old.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='lychee.toml'

if ! command -v lychee >/dev/null 2>&1; then
  skip_suite 'lychee not installed'
fi
# The include_fragments = "full" config key requires a recent lychee.
require_min_version lychee "$(lychee --version | awk '{ print $2 }')" 0.24.2

path_fixture_root="$(mktemp -d "$root/.lychee-path-fixture.XXXXXX")"
trap 'rm -rf "$path_fixture_root"' EXIT
mkdir -p \
  "$path_fixture_root/components/lychee/fixtures" \
  "$path_fixture_root/components/lychee/fixtures-old" \
  "$path_fixture_root/notcomponents/lychee/fixtures" \
  "$path_fixture_root/components/lychee/nested/fixtures" \
  "$path_fixture_root/nested/components/lychee/fixtures"
printf '%s\n' '<https://www.rfc-editor.org/rfc/rfc3986?boundary=intended>' \
  >"$path_fixture_root/components/lychee/fixtures/PathBoundary.md"
printf '%s\n' '<https://www.rfc-editor.org/rfc/rfc3986?boundary=fixtures-old>' \
  >"$path_fixture_root/components/lychee/fixtures-old/PathBoundary.md"
printf '%s\n' '<https://www.rfc-editor.org/rfc/rfc3986?boundary=notcomponents>' \
  >"$path_fixture_root/notcomponents/lychee/fixtures/PathBoundary.md"
printf '%s\n' '<https://www.rfc-editor.org/rfc/rfc3986?boundary=nested-middle>' \
  >"$path_fixture_root/components/lychee/nested/fixtures/PathBoundary.md"
printf '%s\n' '<https://www.rfc-editor.org/rfc/rfc3986?boundary=nested-prefix>' \
  >"$path_fixture_root/nested/components/lychee/fixtures/PathBoundary.md"

fixture_path_rule='^(\./)?components[\\/][^\\/]+[\\/]fixtures([\\/]|$)'
path_dump="$(
  cd "$path_fixture_root" || exit 1
  for input in \
    components/lychee/fixtures/PathBoundary.md \
    components/lychee/fixtures-old/PathBoundary.md \
    notcomponents/lychee/fixtures/PathBoundary.md \
    components/lychee/nested/fixtures/PathBoundary.md \
    nested/components/lychee/fixtures/PathBoundary.md; do
    lychee --dump --exclude-path "$fixture_path_rule" -- "$input"
  done 2>&1
)"
rc=$?
assert_exit 'fixture path boundary dump needs no network and exits 0' 0 "$rc"
assert_not_contains 'component fixture path is excluded' \
  "$path_dump" 'https://www.rfc-editor.org/rfc/rfc3986?boundary=intended'
assert_contains 'fixtures-old sibling remains checked' \
  "$path_dump" 'https://www.rfc-editor.org/rfc/rfc3986?boundary=fixtures-old'
assert_contains 'notcomponents lookalike remains checked' \
  "$path_dump" 'https://www.rfc-editor.org/rfc/rfc3986?boundary=notcomponents'
assert_contains 'nested fixture lookalike remains checked' \
  "$path_dump" 'https://www.rfc-editor.org/rfc/rfc3986?boundary=nested-middle'
assert_contains 'nested components prefix remains checked' \
  "$path_dump" 'https://www.rfc-editor.org/rfc/rfc3986?boundary=nested-prefix'

private_org_rule="$(grep -F \
  "  '^https?://github\\.com/melodic-software/" "$config" || true)"
assert_eq 'private GitHub exclusion is one exact transferred-org inventory' \
  "  '^https?://github\\.com/melodic-software/(dotfiles|github-iac|itinerary-planner|knowledge-corpus|medley-archive|medley|melodic-main-archive|provisioning|songwriting)(\\.git)?([/#?]|$)'," \
  "$private_org_rule"
private_raw_rule="$(grep -F \
  "  '^https?://raw\\.githubusercontent\\.com/melodic-software/" "$config" || true)"
assert_eq 'private raw-content exclusion uses the same exact inventory' \
  "  '^https?://raw\\.githubusercontent\\.com/melodic-software/(dotfiles|github-iac|itinerary-planner|knowledge-corpus|medley-archive|medley|melodic-main-archive|provisioning|songwriting)/'," \
  "$private_raw_rule"
assert_eq 'obsolete personal-owner private exclusion is absent' '0' \
  "$(grep -cF 'github\.com/kyle-sexton/' "$config" || true)"

dump_out="$(lychee --dump --config "$config" \
  components/lychee/fixtures/good/Exclusions.md 2>&1)"
rc=$?
assert_exit 'URL exclusion boundary dump needs no network and exits 0' 0 "$rc"
for repo in dotfiles github-iac itinerary-planner knowledge-corpus medley \
  medley-archive melodic-main-archive provisioning songwriting; do
  assert_not_contains "private inventory excludes melodic-software/$repo" \
    "$dump_out" "https://github.com/melodic-software/$repo"
done
for repo in claude-code-plugins standards; do
  assert_contains "public melodic-software/$repo stays checked" \
    "$dump_out" "https://github.com/melodic-software/$repo"
done
assert_not_contains 'private raw-content URL is excluded' \
  "$dump_out" 'https://raw.githubusercontent.com/melodic-software/dotfiles/'
# medley-archive is a superstring of medley: proves the longer name is matched
# on its own and not shadowed by the shorter alternation arm.
assert_not_contains 'private raw-content URL is excluded for a prefixed name' \
  "$dump_out" 'https://raw.githubusercontent.com/melodic-software/medley-archive/'
assert_contains 'public raw-content URL stays checked' \
  "$dump_out" 'https://raw.githubusercontent.com/melodic-software/claude-code-plugins/'
assert_not_contains 'current Medium article is excluded' "$dump_out" \
  'https://medium.com/@ziobrando/the-rise-and-fall-of-the-dungeon-master-c2d511eed12f'
assert_not_contains 'Fortmatic postmortem is excluded' "$dump_out" \
  'https://medium.com/fortmatic/postmortem-service-disruption-from-expired-ssl-certificate-a993a59272a0'
assert_not_contains 'current Miro article is excluded' "$dump_out" \
  'https://help.miro.com/hc/en-us/articles/31624028247058'
assert_not_contains 'current IsDown page is excluded' "$dump_out" \
  'https://isdown.app/status/anthropic'
assert_not_contains 'current firecrawl-cli package page is excluded' "$dump_out" \
  'https://www.npmjs.com/package/firecrawl-cli'
assert_not_contains 'current Miro API package page is excluded' "$dump_out" \
  'https://www.npmjs.com/package/@mirohq/miro-api'
assert_not_contains 'current MySQL isolation manual page is excluded' "$dump_out" \
  'https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html'
assert_not_contains 'current W3C time-zone guidance is excluded' "$dump_out" \
  'https://www.w3.org/International/wiki/WorkingWithTimeZones'
assert_contains 'another Medium path remains checked' "$dump_out" 'https://medium.com/example'
assert_contains 'another Miro help path remains checked' "$dump_out" \
  'https://help.miro.com/hc/en-us/articles/example'
assert_contains 'another IsDown path remains checked' "$dump_out" 'https://isdown.app/status/example'
assert_contains 'another npm package remains checked' "$dump_out" 'https://www.npmjs.com/package/example'
assert_contains 'another MySQL manual path remains checked' "$dump_out" \
  'https://dev.mysql.com/doc/refman/8.4/en/example.html'
assert_contains 'another W3C International path remains checked' \
  "$dump_out" 'https://www.w3.org/International/'
assert_contains 'public organization sibling remains checked' \
  "$dump_out" 'https://github.com/melodic-software/ci-runner'
assert_contains 'stale personal-owner URL remains checked' \
  "$dump_out" 'https://github.com/kyle-sexton/provisioning'
assert_contains 'public raw-content sibling remains checked' \
  "$dump_out" 'https://raw.githubusercontent.com/melodic-software/ci-runner/'

lychee --offline --config "$config" \
  components/lychee/fixtures/good/Clean.md components/lychee/fixtures/good/Target.md >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(lychee --offline --config "$config" components/lychee/fixtures/bad/Violations.md 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture flags the missing fragment' "$out" 'Cannot find fragment'
assert_contains 'bad fixture flags the missing file' "$out" 'does-not-exist.md'

[[ $FAILED -eq 0 ]] || exit 1
