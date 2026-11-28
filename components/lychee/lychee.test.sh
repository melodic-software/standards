#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='lychee.toml'

command -v lychee >/dev/null 2>&1 || skip_suite 'lychee not installed'
command -v python3 >/dev/null 2>&1 || skip_suite 'python3 not installed (serves the status-code HTTP fixture)'
require_min_version lychee "$(lychee --version | awk '{ print $2 }')" 0.24.2

path_fixture_root="$(mktemp -d)"
http_fixture_root="$(mktemp -d)"
if [[ -z "$path_fixture_root" || -z "$http_fixture_root" ]]; then
  printf 'ERROR: could not create scratch fixture directories\n' >&2
  exit 1
fi
http_server_pid=''
cleanup() {
  if [[ -n "$http_server_pid" ]]; then
    kill "$http_server_pid" 2>/dev/null
    wait "$http_server_pid" 2>/dev/null
  fi
  rm -rf "$path_fixture_root" "$http_fixture_root"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
boundary_cases=(
  components/lychee/fixtures:intended
  components/lychee/fixtures-old:fixtures-old
  notcomponents/lychee/fixtures:notcomponents
  components/lychee/nested/fixtures:nested-middle
  nested/components/lychee/fixtures:nested-prefix
)
for boundary in "${boundary_cases[@]}"; do
  mkdir -p "$path_fixture_root/${boundary%%:*}"
  printf '<https://www.rfc-editor.org/rfc/rfc3986?boundary=%s>\n' "${boundary#*:}" \
    >"$path_fixture_root/${boundary%%:*}/PathBoundary.md"
done

fixture_path_rule='^(\./)?components[\\/][^\\/]+[\\/]fixtures([\\/]|$)'
path_dump="$(
  cd "$path_fixture_root" || exit 1
  for boundary in "${boundary_cases[@]}"; do
    lychee --dump --exclude-path "$fixture_path_rule" -- "${boundary%%:*}/PathBoundary.md"
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
unhidden_dump="$(cd "$dot_root" && lychee --dump --config "$root/$config" --hidden=false \
  './**/*.md' 2>&1)"
assert_not_contains 'without hidden the glob skips .github/' "$unhidden_dump" 'dot=.github'

layer_root="$path_fixture_root/layers"
mkdir -p "$layer_root"
printf "exclude = ['dot=\\\\.workshop']\n" >"$layer_root/extend.toml"
printf 'hidden = false\n' >"$layer_root/partial.toml"
printf 'hidden = true\n' >"$layer_root/complete.toml"
printf '<https://bsky.app/profile/layer-probe>\n' >"$dot_root/Bsky.md"
extend_dump="$(cd "$dot_root" && lychee --dump --config "$root/$config" \
  --config "$layer_root/extend.toml" --exclude 'dot=\.claude/rules' './**/*.md' 2>&1)"
assert_not_contains 'extension: the layered exclude applies' "$extend_dump" 'dot=.workshop'
assert_not_contains 'extension: the standards exclude list still applies' "$extend_dump" 'layer-probe'
assert_not_contains 'extension: a command-line --exclude adds to both lists' "$extend_dump" 'dot=.claude/rules'
assert_row_count 'extension: the standards exclude_path still applies' "$extend_dump" 0 'dot=\.work$'
assert_contains 'extension: the standards hidden still applies' "$extend_dump" 'dot=.github'
partial_dump="$(cd "$dot_root" && lychee --dump --config "$root/$config" \
  --config "$layer_root/partial.toml" --hidden=true './**/*.md' 2>&1)"
assert_contains 'control: a flag after both configs wins over them' "$partial_dump" 'dot=.github'
partial_dump="$(cd "$dot_root" && lychee --dump --config "$root/$config" \
  --config "$layer_root/partial.toml" './**/*.md' 2>&1)"
assert_not_contains 'partial override: the layered scalar wins' "$partial_dump" 'dot=.github'
complete_dump="$(cd "$dot_root" && lychee --dump --config "$layer_root/complete.toml" \
  './**/*.md' 2>&1)"
assert_row_count 'complete override: the standards exclude_path is gone' "$complete_dump" 1 'dot=\.work$'
assert_contains 'complete override: the standards exclude list is gone' "$complete_dump" 'layer-probe'
rm -f -- "$dot_root/Bsky.md"
printf 'dot=\\.claude/rules\n' >"$dot_root/.lycheeignore"
ignore_dump="$(cd "$dot_root" && lychee --dump --config "$root/$config" \
  --config "$layer_root/extend.toml" './**/*.md' 2>&1)"
rm -f -- "$dot_root/.lycheeignore"
assert_not_contains '.lycheeignore adds to layered configs' "$ignore_dump" 'dot=.claude/rules'
assert_contains '.lycheeignore leaves other links checked' "$ignore_dump" 'dot=.github'

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
assert_not_contains 'current Miro help article is excluded' "$dump_out" \
  'https://help.miro.com/hc/en-us/articles/31624028247058'
assert_not_contains 'current MySQL isolation manual page is excluded' "$dump_out" \
  'https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html'
assert_not_contains 'current ACM DL paper is excluded' "$dump_out" \
  'https://dl.acm.org/doi/10.1145/3611643.3613871'
assert_not_contains 'current ACM Queue article is excluded' "$dump_out" \
  'https://queue.acm.org/detail.cfm?id=3454124'
assert_row_count 'current Genius API docs root is excluded' "$dump_out" 0 \
  '^https://docs\.genius\.com/?$'
assert_row_count 'x.com profile is excluded' "$dump_out" 0 '^https://x\.com/ExampleHandle/?$'
assert_not_contains 'x.com article is excluded' "$dump_out" \
  'https://x.com/ExampleHandle/article/1'
assert_not_contains 'x.com i/ article is excluded' "$dump_out" 'https://x.com/i/article/1'
assert_not_contains 'GitHub REST API endpoint is excluded' "$dump_out" \
  'https://api.github.com/repos/melodic-software/standards'
for checked in \
  'https://isdown.app/status/anthropic' \
  'https://www.w3.org/International/wiki/WorkingWithTimeZones' \
  'https://www.ntia.gov/files/ntia/publications/sbom_minimum_elements_report.pdf' \
  'https://www.linkedin.com/posts/example' \
  'https://x.com/ExampleHandle/status/1' \
  'https://x.com/i/status/1' \
  'https://x.com/i/web/status/1'; do
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
assert_contains 'another Miro help article remains checked' "$dump_out" \
  'https://help.miro.com/hc/en-us/articles/example'
assert_contains 'public organization sibling remains checked' \
  "$dump_out" 'https://github.com/melodic-software/ci-runner'
assert_contains 'stale personal-owner URL remains checked' \
  "$dump_out" 'https://github.com/kyle-sexton/provisioning'
assert_contains 'public raw-content sibling remains checked' \
  "$dump_out" 'https://raw.githubusercontent.com/melodic-software/ci-runner/'

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

python3 - "$http_fixture_root/port" "$http_fixture_root/hits" \
  <<'PY' >/dev/null 2>"$http_fixture_root/server.err" &
import socketserver
import sys
import time
from http.server import BaseHTTPRequestHandler


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(sys.argv[2], "a", encoding="utf-8") as hits:
            hits.write(self.path + "\n")
        last = self.path.rstrip("/").rsplit("/", 1)[-1]
        if last == "hang":
            time.sleep(5)
            last = "200"
        self.send_response(int(last))
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_HEAD = do_GET

    def log_message(self, *args):
        pass


# Threaded, so the hanging path does not hold up the others. Port 0 takes an
# ephemeral port, and the port file is written only after the bind succeeds —
# that ordering is what makes the caller's readiness poll mean "the server is
# listening" rather than "the process started".
socketserver.ThreadingTCPServer.daemon_threads = True
server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
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
  fail 'status-code fixture server reports its bound port' \
    "no port after 5s; server stderr: $(cat "$http_fixture_root/server.err" 2>/dev/null)"
else
  status_probe='lychee-status-probe'
  for code in 200 429 500 503 599 404 410 hang; do
    printf '<http://127.0.0.1:%s/%s/%s>\n' "$http_port" "$status_probe" "$code" \
      >"$http_fixture_root/Status$code.md"
  done

  status_dump="$(lychee --dump --config "$config" --include "$status_probe" \
    "$http_fixture_root/Status429.md" 2>&1)"
  assert_contains 'status fixture URL is checked, not silently excluded' \
    "$status_dump" "http://127.0.0.1:$http_port/$status_probe/429"

  probe() { lychee --no-progress --config "$config" --include "$status_probe" "$@" 2>&1; }

  for code in 200 429 500 503 599; do
    status_out="$(probe "$http_fixture_root/Status$code.md")"
    rc=$?
    assert_exit "$code passes the run" 0 "$rc"
    assert_contains "$code is counted as a checked OK link" "$status_out" '1 OK'
  done
  assert_row_count 'accepted 429 is requested once, not retried' \
    "$(<"$http_fixture_root/hits")" 1 "/$status_probe/429\$"

  for code in 404 410; do
    status_out="$(probe "$http_fixture_root/Status$code.md")"
    rc=$?
    assert_nonzero "dead link $code fails the run" "$rc"
    assert_contains "dead link $code fails on the status code itself" \
      "$status_out" "Rejected status code: $code"
  done

  status_out="$(probe --timeout 1 --max-retries 0 "$http_fixture_root/Statushang.md")"
  rc=$?
  assert_exit 'timeout passes the run' 0 "$rc"
  assert_contains 'timeout is still reported' "$status_out" '1 Timeouts'
  probe --accept-timeouts=false --timeout 1 --max-retries 0 "$http_fixture_root/Statushang.md" >/dev/null
  rc=$?
  assert_nonzero 'without accept_timeouts a timeout fails the run' "$rc"
fi

[[ $FAILED -eq 0 ]] || exit 1
