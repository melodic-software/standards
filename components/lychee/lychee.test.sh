#!/usr/bin/env bash
# Tests the lychee component: the good fixture's local links and anchors resolve
# on disk, the bad fixture's broken references are flagged, JavaScript-rendered
# fragments are remapped away, and a manual online run retries a 429 and then
# fails it instead of accepting it.
# Skips cleanly when the engine or the fixture server's runtime is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='lychee.toml'

command -v lychee >/dev/null 2>&1 || skip_suite 'lychee not installed'
command -v python3 >/dev/null 2>&1 || skip_suite 'python3 not installed (serves the status-code HTTP fixture)'
# The include_fragments = "full" config key requires a recent lychee.
require_min_version lychee "$(lychee --version | awk '{ print $2 }')" 0.24.2

path_fixture_root="$(mktemp -d)"
http_fixture_root="$(mktemp -d)"
# Without errexit a failed mktemp leaves the variable empty, and every scratch
# path built from it would then resolve against the filesystem root.
if [[ -z "$path_fixture_root" || -z "$http_fixture_root" ]]; then
  printf 'ERROR: could not create scratch fixture directories\n' >&2
  exit 1
fi
# Armed before the fixture server launches, so an abort in between still reaps
# both scratch trees; the PID stays empty until there is a process to kill.
http_server_pid=''
cleanup() {
  if [[ -n "$http_server_pid" ]]; then
    kill "$http_server_pid" 2>/dev/null
    # Reap before removing the tree: kill only requests termination, and a
    # still-running child would otherwise outlive the script as an orphan.
    wait "$http_server_pid" 2>/dev/null
  fi
  rm -rf "$path_fixture_root" "$http_fixture_root"
}
trap cleanup EXIT
# A canceled CI job signals rather than exits, and bash does not run an EXIT
# trap for a signal it has no handler for; converting each to an exit keeps
# cleanup on one path instead of duplicating it per signal.
trap 'exit 130' INT
trap 'exit 143' TERM
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

# Consumers pass a `**/*.md` glob, so only a glob input exercises `hidden` and
# the `.work/` and `.claude/worktrees/` path excludes; explicit file paths
# bypass both. One link per location names where it came from.
dot_root="$path_fixture_root/dot-directories"
mkdir -p "$dot_root/.github" "$dot_root/.work" "$dot_root/nested/.work" \
  "$dot_root/.claude/worktrees/lane" "$dot_root/.claude/rules" "$dot_root/.workshop"
for location in .github .work nested/.work .claude/worktrees/lane .claude/rules .workshop; do
  printf '<https://www.rfc-editor.org/rfc/rfc3986?dot=%s>\n' "$location" \
    >"$dot_root/$location/Link.md"
done
glob_dump="$(cd "$dot_root" && lychee --dump --config "$root/$config" './**/*.md' 2>&1)"
rc=$?
assert_exit 'dot-directory glob dump needs no network and exits 0' 0 "$rc"
assert_contains 'glob input reaches .github/' "$glob_dump" 'dot=.github'
assert_contains 'glob input reaches .claude/ outside worktrees' "$glob_dump" 'dot=.claude/rules'
assert_contains '.work lookalike directory stays checked' "$glob_dump" 'dot=.workshop'
assert_not_contains 'root .work/ is excluded' "$glob_dump" 'dot=.work>'
assert_row_count 'no .work/ link at any depth is checked' "$glob_dump" 0 'dot=(nested/)?\.work$'
assert_not_contains '.claude/worktrees/ is excluded' "$glob_dump" 'dot=.claude/worktrees'
# Control: the same glob without `hidden` skips the dot-directories, so the
# .github/ assertion above passes because of the config key.
unhidden_dump="$(cd "$dot_root" && lychee --dump --config "$root/$config" --hidden=false \
  './**/*.md' 2>&1)"
assert_not_contains 'without hidden the glob skips .github/' "$unhidden_dump" 'dot=.github'

# The private-repo inventory is derived, not copied: the two entries must be
# byte-identical to what private-repo-inventory.sh renders for the set it reads
# back from the file (sorted, unique, both hosts carrying the same set). Whether
# that set matches actual repository visibility is the inventory check's job
# (the `check` step in the same CI lane and the scheduled workflow), so no
# repository name is hard-coded here — the earlier copy of the list in this
# test was exactly the drift the script exists to remove.
inventory_script="$root/components/lychee/private-repo-inventory.sh"
inventory_list="$(bash "$inventory_script" list --config "$config")"
assert_nonzero 'private-repo inventory is non-empty' "${#inventory_list}"
rendered_rules="$(bash "$inventory_script" generate --config "$config" \
  --private-list <(printf '%s\n' "$inventory_list"))"
private_org_rule="$(grep -F \
  "  '^https?://github\\.com/melodic-software/" "$config" || true)"
assert_eq 'private GitHub exclusion is the rendered inventory entry' \
  "$(printf '%s\n' "$rendered_rules" | sed -n 1p)" "$private_org_rule"
private_raw_rule="$(grep -F \
  "  '^https?://raw\\.githubusercontent\\.com/melodic-software/" "$config" || true)"
assert_eq 'private raw-content exclusion is the rendered inventory entry' \
  "$(printf '%s\n' "$rendered_rules" | sed -n 2p)" "$private_raw_rule"
assert_eq 'obsolete personal-owner private exclusion is absent' '0' \
  "$(grep -cF 'github\.com/kyle-sexton/' "$config" || true)"

dump_out="$(lychee --dump --config "$config" \
  components/lychee/fixtures/good/Exclusions.md 2>&1)"
rc=$?
assert_exit 'URL exclusion boundary dump needs no network and exits 0' 0 "$rc"
exclusions_fixture="$(<components/lychee/fixtures/good/Exclusions.md)"
for repo in $inventory_list; do
  # The fixture must actually cite each inventoried repo, or the exclusion
  # assertion below would pass on an absent link rather than an excluded one.
  assert_contains "exclusions fixture cites melodic-software/$repo" \
    "$exclusions_fixture" "<https://github.com/melodic-software/$repo>"
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
assert_not_contains 'current firecrawl-cli package page is excluded' "$dump_out" \
  'https://www.npmjs.com/package/firecrawl-cli'
assert_not_contains 'current Miro API package page is excluded' "$dump_out" \
  'https://www.npmjs.com/package/@mirohq/miro-api'
assert_not_contains 'current MySQL isolation manual page is excluded' "$dump_out" \
  'https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html'
assert_not_contains 'current ACM DL paper is excluded' "$dump_out" \
  'https://dl.acm.org/doi/10.1145/3611643.3613871'
assert_not_contains 'current ACM Queue article is excluded' "$dump_out" \
  'https://queue.acm.org/detail.cfm?id=3454124'
# Row count, not a substring absence: the excluded URL is the host ROOT, so
# every sibling path that must stay checked contains it as a prefix and would
# satisfy assert_not_contains only by deleting the sibling control. A
# line-anchored count asserts the root itself is gone while the sibling below
# proves the rest of the host is still checked.
assert_row_count 'current Genius API docs root is excluded' "$dump_out" 0 \
  '^https://docs\.genius\.com/?$'
# Row count: the profile URL is a prefix of the status URL that stays checked.
assert_row_count 'x.com profile is excluded' "$dump_out" 0 '^https://x\.com/ExampleHandle/?$'
assert_not_contains 'x.com article is excluded' "$dump_out" \
  'https://x.com/ExampleHandle/article/1'
assert_not_contains 'x.com i/ article is excluded' "$dump_out" 'https://x.com/i/article/1'
# Each URL below passed a GitHub-runner retest, so its exclude was dropped.
for checked in \
  'https://help.miro.com/hc/en-us/articles/31624028247058' \
  'https://isdown.app/status/anthropic' \
  'https://www.w3.org/International/wiki/WorkingWithTimeZones' \
  'https://www.ntia.gov/files/ntia/publications/sbom_minimum_elements_report.pdf' \
  'https://www.linkedin.com/posts/example' \
  'https://x.com/ExampleHandle/status/1'; do
  assert_contains "runner-passing URL is checked: $checked" "$dump_out" "$checked"
done
assert_not_contains 'example.com is excluded by lychee default' "$dump_out" \
  'https://example.com/placeholder'
assert_not_contains 'example.org is excluded by lychee default' "$dump_out" \
  'https://www.example.org/placeholder'
assert_eq 'config carries no example-domain exclude' '0' \
  "$(grep -cF 'example\.' "$config" || true)"
assert_contains 'another Medium path remains checked' "$dump_out" 'https://medium.com/example'
assert_contains 'another npm package remains checked' "$dump_out" 'https://www.npmjs.com/package/example'
assert_contains 'another MySQL manual path remains checked' "$dump_out" \
  'https://dev.mysql.com/doc/refman/8.4/en/example.html'
assert_contains 'another ACM DL DOI remains checked' "$dump_out" \
  'https://dl.acm.org/doi/10.1145/example'
assert_contains 'another ACM Queue article remains checked' "$dump_out" \
  'https://queue.acm.org/detail.cfm?id=1'
assert_contains 'another Genius docs path remains checked' "$dump_out" \
  'https://docs.genius.com/example'
assert_contains 'public organization sibling remains checked' \
  "$dump_out" 'https://github.com/melodic-software/ci-runner'
assert_contains 'stale personal-owner URL remains checked' \
  "$dump_out" 'https://github.com/kyle-sexton/provisioning'
assert_contains 'public raw-content sibling remains checked' \
  "$dump_out" 'https://raw.githubusercontent.com/melodic-software/ci-runner/'

# Expected rows are the fixture URLs with the fragment cut by hand, the rule the
# remap comment in the config states; the second group proves each rule is
# scoped and does not strip every fragment on its host.
remap_dump="$(lychee --dump --config "$config" components/lychee/fixtures/good/Remap.md 2>&1)"
rc=$?
assert_exit 'remap dump needs no network and exits 0' 0 "$rc"
for remapped in \
  'https://github.com/example-owner/example-repo/issues/1' \
  'https://github.com/example-owner/example-repo/pull/2/files' \
  'https://github.com/example-owner/example-repo/pull/3' \
  'https://github.com/example-owner/example-repo/discussions/4' \
  'https://pypi.org/project/example-package/' \
  'https://docs.github.com/en/graphql/reference/objects' \
  'https://docs.github.com/graphql/reference/enums'; do
  assert_row_count "remapped without its fragment: $remapped" "$remap_dump" 1 \
    "^$(printf '%s' "$remapped" | sed 's/[.]/\\./g')\$"
done
assert_row_count 'no remapped row keeps a JavaScript-rendered fragment' "$remap_dump" 0 \
  '#(issuecomment-|discussion_r|pullrequestreview-|discussioncomment-|files$|pullrequest$|mergeablestate$)'
for kept in \
  'https://github.com/example-owner/example-repo/blob/main/README.md#usage' \
  'https://github.com/example-owner/example-repo/issues/5#event-555' \
  'https://pypi.org/project/example-package/#description' \
  'https://docs.github.com/en/rest/issues/issues#list-repository-issues'; do
  assert_contains "fragment outside the remap rules is kept: $kept" "$remap_dump" "$kept"
done

lychee --offline --config "$config" \
  components/lychee/fixtures/good/Clean.md components/lychee/fixtures/good/Target.md >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

out="$(lychee --offline --config "$config" components/lychee/fixtures/bad/Violations.md 2>&1)"
rc=$?
assert_exit 'bad fixture exits 2' 2 "$rc"
assert_contains 'bad fixture flags the missing fragment' "$out" 'Cannot find fragment'
assert_contains 'bad fixture flags the missing file' "$out" 'does-not-exist.md'

# Status handling only takes effect against a real response, so nothing above can
# reach it. A local server answers 429 on one path and 200 on a control path,
# and records every request to the throttled path: the config sets no `accept`,
# so a 429 must be retried and then fail, while the 200 control proves the
# server and the default accepted range work.
python3 - "$http_fixture_root/port" "$http_fixture_root/throttled-hits" \
  <<'PY' >/dev/null 2>"$http_fixture_root/server.err" &
import socketserver
import sys
from http.server import BaseHTTPRequestHandler


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        throttled = "throttled" in self.path
        if throttled:
            with open(sys.argv[2], "a", encoding="utf-8") as hits:
                hits.write(self.command + "\n")
        self.send_response(429 if throttled else 200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_HEAD = do_GET

    def log_message(self, *args):
        pass


# Port 0 takes an ephemeral port, and the port file is written only after the
# bind succeeds — that ordering is what makes the caller's readiness poll mean
# "the server is listening" rather than "the process started".
server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PY
http_server_pid=$!

for _ in {1..50}; do
  [[ -s "$http_fixture_root/port" ]] && break
  sleep 0.1
done
http_port=''
if [[ -s "$http_fixture_root/port" ]]; then
  http_port="$(<"$http_fixture_root/port")"
fi

if [[ -z "$http_port" ]]; then
  # A silent skip would let the status-code contract go unexercised while the
  # suite reports green, so an unbindable server is a harness defect, not an
  # environmental skip. The captured stderr carries the only account of why the
  # bind never happened.
  fail 'status-code fixture server reports its bound port' \
    "no port after 5s; server stderr: $(cat "$http_fixture_root/server.err" 2>/dev/null)"
else
  # The config excludes loopback, so the fixture URL needs --include to be
  # checked at all; that keeps the production exclusion intact. The pattern is a
  # bare token because MSYS/git-bash rewrites backslashes inside an argument
  # containing `://`, which would silently mangle an anchored URL regex.
  status_probe='lychee-status-probe'
  printf '<http://127.0.0.1:%s/%s/throttled>\n' "$http_port" "$status_probe" \
    >"$http_fixture_root/Throttled.md"
  printf '<http://127.0.0.1:%s/%s/live>\n' "$http_port" "$status_probe" \
    >"$http_fixture_root/Live.md"

  status_dump="$(lychee --dump --config "$config" --include "$status_probe" \
    "$http_fixture_root/Throttled.md" 2>&1)"
  assert_contains 'rate-limited fixture URL is checked, not silently excluded' \
    "$status_dump" "http://127.0.0.1:$http_port/$status_probe/throttled"

  live_out="$(lychee --no-progress --config "$config" --include "$status_probe" \
    "$http_fixture_root/Live.md" 2>&1)"
  rc=$?
  assert_exit '200 control exits 0' 0 "$rc"
  # Exit 0 alone is also what checking nothing looks like; the OK count proves a
  # request was made and its 200 was accepted.
  assert_contains '200 control is counted as a checked OK link' "$live_out" '1 OK'

  throttled_out="$(lychee --no-progress --config "$config" --include "$status_probe" \
    "$http_fixture_root/Throttled.md" 2>&1)"
  rc=$?
  assert_nonzero 'persistent 429 fails the run' "$rc"
  # A dead or unreachable server also exits non-zero; naming the status keeps the
  # case from passing for the wrong reason.
  assert_contains 'persistent 429 fails on the status code itself' \
    "$throttled_out" 'Rejected status code: 429'
  # One request would mean the 429 was taken as final; more than one proves
  # lychee retried it, the behavior an accepted 429 would skip.
  throttled_hits="$(wc -l <"$http_fixture_root/throttled-hits" 2>/dev/null || printf '0')"
  if ((throttled_hits > 1)); then
    pass "persistent 429 is retried before failing: $throttled_hits requests"
  else
    fail 'persistent 429 is retried before failing' "requests: $throttled_hits"
  fi
fi

[[ $FAILED -eq 0 ]] || exit 1
