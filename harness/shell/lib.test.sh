#!/usr/bin/env bash
# Self-test for the assertion library: the PASS and FAIL paths of every
# assertion must themselves behave. Deliberate-failure paths run in isolated
# subshells (FAILED=0 CASE_NUM=0) so they don't pollute this file's own
# counters. ShellCheck reads those subshell-local resets as lost modifications
# (SC2030/SC2031); the isolation is intended, so disable the pair file-wide (the
# directive must precede the first command to apply file-wide).
# shellcheck disable=SC2030,SC2031
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

FAILED=0
CASE_NUM=0

# --- assert_eq ---
out="$(FAILED=0 CASE_NUM=0; assert_eq "eq" foo foo)"
assert_contains "assert_eq emits PASS on match" "$out" "PASS:"
out="$(FAILED=0 CASE_NUM=0; assert_eq "eq" foo bar 2>&1)"
assert_contains "assert_eq emits FAIL on mismatch" "$out" "FAIL:"

# --- assert_contains / assert_not_contains ---
out="$(FAILED=0 CASE_NUM=0; assert_contains "c" "hello world" "world")"
assert_contains "assert_contains matches substring" "$out" "PASS:"
out="$(FAILED=0 CASE_NUM=0; assert_contains "c" "hello" "world" 2>&1)"
assert_contains "assert_contains fails on absence" "$out" "FAIL:"
out="$(FAILED=0 CASE_NUM=0; assert_not_contains "nc" "hello" "world")"
assert_contains "assert_not_contains passes on absence" "$out" "PASS:"
out="$(FAILED=0 CASE_NUM=0; assert_not_contains "nc" "hello" "ell" 2>&1)"
assert_contains "assert_not_contains fails on presence" "$out" "FAIL:"

# --- assert_exit ---
out="$(FAILED=0 CASE_NUM=0; assert_exit "ex" 0 0)"
assert_contains "assert_exit passes on equal codes" "$out" "PASS:"
out="$(FAILED=0 CASE_NUM=0; assert_exit "ex" 0 1 2>&1)"
assert_contains "assert_exit fails on differing codes" "$out" "FAIL:"

# --- assert_silent ---
out="$(FAILED=0 CASE_NUM=0; assert_silent "s" "   ")"
assert_contains "assert_silent passes on whitespace-only" "$out" "PASS:"
out="$(FAILED=0 CASE_NUM=0; assert_silent "s" "noise" 2>&1)"
assert_contains "assert_silent fails on output" "$out" "FAIL:"

# --- assert_command_fails ---
assert_command_fails "false exits non-zero" false

# --- assert_file_exists / assert_file_absent ---
tmp="$(mktemp)"
assert_file_exists "temp file exists" "$tmp"
rm -f "$tmp"
assert_file_absent "removed file is absent" "$tmp"

# --- assert_line_count ---
tmp="$(mktemp)"
printf 'a\nb\nc\n' >"$tmp"
out="$(FAILED=0 CASE_NUM=0; assert_line_count "lc" "$tmp" 3)"
assert_contains "assert_line_count counts newlines" "$out" "PASS:"
rm -f "$tmp"

# --- assert_row_count (including the zero-match path) ---
out="$(FAILED=0 CASE_NUM=0; assert_row_count "rc" $'x1\nx2\ny3' 2 '^x')"
assert_contains "assert_row_count counts matches" "$out" "PASS:"
out="$(FAILED=0 CASE_NUM=0; assert_row_count "rc-zero" "no matches here" 0 '^x')"
assert_contains "assert_row_count handles zero matches" "$out" "PASS:"

# --- make_repo ---
tmpd="$(mktemp -d)"
make_repo "$tmpd/r"
assert_file_exists "make_repo initializes a git repo" "$tmpd/r/.git/HEAD"
rm -rf "$tmpd"

[[ $FAILED -eq 0 ]] || exit 1
