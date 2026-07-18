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

private_org_rule="$(grep -F \
  "  '^https?://github\\.com/melodic-software/" "$config" || true)"
assert_eq 'private GitHub exclusion is one exact transferred-org inventory' \
  "  '^https?://github\\.com/melodic-software/(claude-code-plugins|dotfiles|github-iac|medley|provisioning|standards)(\\.git)?([/#?]|$)'," \
  "$private_org_rule"
private_raw_rule="$(grep -F \
  "  '^https?://raw\\.githubusercontent\\.com/melodic-software/" "$config" || true)"
assert_eq 'private raw-content exclusion uses the same exact inventory' \
  "  '^https?://raw\\.githubusercontent\\.com/melodic-software/(claude-code-plugins|dotfiles|github-iac|medley|provisioning|standards)/'," \
  "$private_raw_rule"
assert_eq 'obsolete personal-owner private exclusion is absent' '0' \
  "$(grep -cF 'github\.com/kyle-sexton/' "$config" || true)"

dump_out="$(lychee --dump --config "$config" \
  components/lychee/fixtures/good/Exclusions.md 2>&1)"
rc=$?
assert_exit 'URL exclusion boundary dump needs no network and exits 0' 0 "$rc"
for repo in claude-code-plugins dotfiles github-iac medley provisioning standards; do
  assert_not_contains "private inventory excludes melodic-software/$repo" \
    "$dump_out" "https://github.com/melodic-software/$repo"
done
assert_not_contains 'private raw-content URL is excluded' \
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
assert_contains 'another Medium path remains checked' "$dump_out" 'https://medium.com/example'
assert_contains 'another Miro help path remains checked' "$dump_out" \
  'https://help.miro.com/hc/en-us/articles/example'
assert_contains 'another IsDown path remains checked' "$dump_out" 'https://isdown.app/status/example'
assert_contains 'another npm package remains checked' "$dump_out" 'https://www.npmjs.com/package/example'
assert_contains 'another MySQL manual path remains checked' "$dump_out" \
  'https://dev.mysql.com/doc/refman/8.4/en/example.html'
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
