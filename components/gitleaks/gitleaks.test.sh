#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config='.gitleaks.toml'

if ! command -v gitleaks >/dev/null 2>&1; then
  skip_suite 'gitleaks not installed'
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bad" "$tmp/allow" "$tmp/reports" "$tmp/stateless" "$tmp/words"

scan_dir() {
  local dir="$1"
  shift
  gitleaks dir "$dir" --config "$config" --no-banner --redact "$@" -i "$dir"
}

gh_prefix='ghp_'
gh_token="${gh_prefix}1A2b3C4d5E6f7G8h9I0jK1l2M3n4O5p6Q7r8"

printf 'GITHUB_TOKEN=%s\n' "$gh_token" >"$tmp/bad/leak.env"
out="$(scan_dir "$tmp/bad" 2>&1)"
rc=$?
assert_exit 'constructed secret is flagged (exit 1)' 1 "$rc"
assert_contains 'reports leaks' "$out" 'leaks found'
assert_not_contains 'detected value is redacted' "$out" "$gh_token"

for format in json sarif; do
  report="$tmp/reports/gitleaks.$format"
  out="$(scan_dir "$tmp/bad" --report-format "$format" --report-path "$report" 2>&1)"
  rc=$?
  assert_exit "$format report preserves detection failure (exit 1)" 1 "$rc"
  assert_file_exists "$format report is generated" "$report"
  report_content="$(<"$report")"
  assert_contains "$format report records the finding" "$report_content" 'github-pat'
  assert_contains "$format report marks the value redacted" "$report_content" 'REDACTED'
  assert_not_contains "$format report omits the detected value" "$report_content" "$gh_token"
  assert_not_contains "$format report command output omits the detected value" "$out" "$gh_token"
done

app_prefix='ghs_'
app_token="${app_prefix}1234567_eyJhbGciOiJSUzI1NiJ9.eyJleHAiOjE3NjAwMDAwMDB9.c2lnbmF0dXJlLXBsYWNlaG9sZGVy"
printf 'GITHUB_TOKEN=%s\n' "$app_token" >"$tmp/stateless/app.env"
out="$(scan_dir "$tmp/stateless" --report-format json --report-path "$tmp/reports/stateless.json" 2>&1)"
rc=$?
assert_exit 'stateless installation token is flagged (exit 1)' 1 "$rc"
report_content="$(<"$tmp/reports/stateless.json")"
assert_contains 'stateless token report names the rule' "$report_content" 'github-app-installation-token'
assert_not_contains 'stateless token is redacted in output' "$out" "$app_token"
assert_not_contains 'stateless token is redacted in the report' "$report_content" "$app_token"

printf 'label = highs_and_lows_of_the_market_over_the_year\nmood = laughs_out_loud_at_the_whole_long_meeting_today\n' \
  >"$tmp/words/words.txt"
scan_dir "$tmp/words" >/dev/null 2>&1
rc=$?
assert_exit 'words ending in ghs_ are not flagged (exit 0)' 0 "$rc"

# The same token silenced with the native gitleaks:allow pragma is ignored.
printf 'EXAMPLE_TOKEN=%s # gitleaks:allow\n' "$gh_token" >"$tmp/allow/ok.env"
scan_dir "$tmp/allow" >/dev/null 2>&1
rc=$?
assert_exit 'gitleaks:allow silences the finding (exit 0)' 0 "$rc"

scan_dir components/gitleaks/fixtures/good >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

history_repo="$tmp/history"
make_repo "$history_repo"
git -C "$history_repo" config core.autocrlf false
head_ref="$(git -C "$history_repo" symbolic-ref --short HEAD)"
git -C "$history_repo" switch -q -c history-only
printf 'GITHUB_TOKEN=%s\n' "$gh_token" >"$history_repo/leak.env"
git -C "$history_repo" add leak.env
git -C "$history_repo" -c commit.gpgsign=false -c core.hooksPath= \
  commit -q -m 'add history-only fixture'
git -C "$history_repo" switch -q "$head_ref"
out="$(gitleaks git "$history_repo" --config "$config" --no-banner --redact \
  --log-opts="--all" -i "$history_repo" 2>&1)"
rc=$?
assert_exit 'all refs includes a non-HEAD branch finding (exit 1)' 1 "$rc"
assert_contains 'all refs reports the history-only leak' "$out" 'leaks found'
assert_not_contains 'all refs output redacts the history-only value' "$out" "$gh_token"

[[ $FAILED -eq 0 ]] || exit 1
