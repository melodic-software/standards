#!/usr/bin/env bash
# Tests the gitleaks component against the root-canonical base config.
#
# Secret inputs are CONSTRUCTED AT RUNTIME from concatenated parts and written
# to a temp dir — no secret-shaped bytes are committed to this repo, so neither
# gitleaks' own dogfood scan nor an external secret scanner (GitGuardian, GitHub
# secret scanning) flags the test scaffolding. The literal joined token never
# appears in this file's source.
#
# Each scan sets -i to its scan target (no .gitleaksignore there) so nothing
# masks the detection under test. Skips cleanly when the engine is absent.
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
mkdir -p "$tmp/bad" "$tmp/allow" "$tmp/reports"

# Real-shape token built from parts — the joined string is never a source literal.
gh_prefix='ghp_'
gh_token="${gh_prefix}1A2b3C4d5E6f7G8h9I0jK1l2M3n4O5p6Q7r8"

# A bare token is flagged.
printf 'GITHUB_TOKEN=%s\n' "$gh_token" >"$tmp/bad/leak.env"
out="$(gitleaks dir "$tmp/bad" --config "$config" --no-banner --redact \
  -i "$tmp/bad" 2>&1)"
rc=$?
assert_exit 'constructed secret is flagged (exit 1)' 1 "$rc"
assert_contains 'reports leaks' "$out" 'leaks found'
assert_not_contains 'detected value is redacted' "$out" "$gh_token"

# Machine-readable reports must contain the finding without retaining the value.
for format in json sarif; do
  report="$tmp/reports/gitleaks.$format"
  out="$(gitleaks dir "$tmp/bad" --config "$config" --no-banner --redact \
    --report-format "$format" --report-path "$report" -i "$tmp/bad" 2>&1)"
  rc=$?
  assert_exit "$format report preserves detection failure (exit 1)" 1 "$rc"
  assert_file_exists "$format report is generated" "$report"
  report_content="$(<"$report")"
  assert_contains "$format report records the finding" "$report_content" 'github-pat'
  assert_contains "$format report marks the value redacted" "$report_content" 'REDACTED'
  assert_not_contains "$format report omits the detected value" "$report_content" "$gh_token"
  assert_not_contains "$format report command output omits the detected value" "$out" "$gh_token"
done

# The same token silenced with the native gitleaks:allow pragma is ignored.
printf 'EXAMPLE_TOKEN=%s # gitleaks:allow\n' "$gh_token" >"$tmp/allow/ok.env"
gitleaks dir "$tmp/allow" --config "$config" --no-banner --redact \
  -i "$tmp/allow" >/dev/null 2>&1
rc=$?
assert_exit 'gitleaks:allow silences the finding (exit 0)' 0 "$rc"

# The committed clean fixture scans clean.
gitleaks dir components/gitleaks/fixtures/good --config "$config" --no-banner --redact \
  -i components/gitleaks/fixtures/good >/dev/null 2>&1
rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"

# --all must include a secret reachable only from a non-HEAD local branch.
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
