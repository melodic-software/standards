#!/usr/bin/env bash
# Self-test for the assertion library: the PASS and FAIL paths of every
# assertion must themselves behave. Deliberate-failure paths run inside $(...)
# command substitutions, so their FAILED/CASE_NUM increments stay in the
# subshell and never skew this file's own counters.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

# --- assert_eq ---
out="$(assert_eq "eq" foo foo)"
assert_contains "assert_eq emits PASS on match" "$out" "PASS:"
out="$(assert_eq "eq" foo bar 2>&1)"
assert_contains "assert_eq emits FAIL on mismatch" "$out" "FAIL:"
out="$(assert_eq "eq" "" "")"
assert_contains "assert_eq handles empty strings" "$out" "PASS:"
out="$(assert_eq "eq" $'a\nb' $'a\nb')"
assert_contains "assert_eq handles multi-line values" "$out" "PASS:"

# --- assert_contains / assert_not_contains ---
out="$(assert_contains "c" "hello world" "world")"
assert_contains "assert_contains matches substring" "$out" "PASS:"
out="$(assert_contains "c" "hello" "world" 2>&1)"
assert_contains "assert_contains fails on absence" "$out" "FAIL:"
out="$(assert_contains "c" $'one\ntwo' "two")"
assert_contains "assert_contains searches across lines" "$out" "PASS:"
out="$(assert_not_contains "nc" "hello" "world")"
assert_contains "assert_not_contains passes on absence" "$out" "PASS:"
out="$(assert_not_contains "nc" "hello" "ell" 2>&1)"
assert_contains "assert_not_contains fails on presence" "$out" "FAIL:"

# --- assert_exit ---
out="$(assert_exit "ex" 0 0)"
assert_contains "assert_exit passes on equal codes" "$out" "PASS:"
out="$(assert_exit "ex" 0 1 2>&1)"
assert_contains "assert_exit fails on differing codes" "$out" "FAIL:"

# --- assert_nonzero ---
out="$(assert_nonzero "nz" 2)"
assert_contains "assert_nonzero passes on non-zero rc" "$out" "PASS:"
out="$(assert_nonzero "nz" 0 2>&1)"
assert_contains "assert_nonzero fails on zero rc" "$out" "FAIL:"

# --- assert_silent ---
out="$(assert_silent "s" "   ")"
assert_contains "assert_silent passes on whitespace-only" "$out" "PASS:"
out="$(assert_silent "s" "noise" 2>&1)"
assert_contains "assert_silent fails on output" "$out" "FAIL:"

# --- assert_command_fails ---
assert_command_fails "false exits non-zero" false
out="$(assert_command_fails "cf" true 2>&1)"
assert_contains "assert_command_fails fails when the command succeeds" "$out" "FAIL:"
# errexit immunity: the failing subject must not abort a `set -e` caller before
# the assertion records (regression guard for the run-bare refactor).
out="$(set -e; assert_command_fails "errexit-safe" false)"
assert_contains "assert_command_fails is safe under set -e" "$out" "PASS:"

# --- skip_case (unlike skip_suite, control must continue past it) ---
out="$(skip_case "one case skipped" 2>&1; printf 'continued\n')"
assert_contains "skip_case emits a SKIP marker" "$out" "SKIP:"
assert_contains "skip_case does not exit" "$out" "continued"

# --- require_min_version (skip_suite exits 0, so run each in a subshell) ---
out="$(require_min_version tool 1.2.3 1.2.0 2>&1)"
assert_silent "require_min_version is silent when have > min" "$out"
out="$(require_min_version tool 1.2.0 1.2.0 2>&1)"
assert_silent "require_min_version allows the exact minimum" "$out"
out="$(require_min_version tool 1.2.0 1.10.0 2>&1)"; rc=$?
assert_contains "require_min_version skips when have < min" "$out" "SKIP:"
assert_exit "skip_suite exits 0 so the runner counts a skip, not a failure" 0 "$rc"
out="$(require_min_version tool 1.9.0 1.10.0 2>&1)"
assert_contains "require_min_version compares by version, not lexically" "$out" "SKIP:"
out="$(require_min_version tool "" 1.0.0 2>&1)"; rc=$?
assert_contains "require_min_version errors on an unparsable (empty) version" "$out" "ERROR:"
assert_nonzero "require_min_version exits non-zero on an empty version" "$rc"
out="$(require_min_version tool nightly 1.0.0 2>&1)"; rc=$?
assert_contains "require_min_version errors on a non-numeric version token" "$out" "ERROR:"
assert_nonzero "require_min_version exits non-zero on a non-numeric version" "$rc"

# --- assert_file_exists / assert_file_absent ---
tmp="$(mktemp)"
assert_file_exists "temp file exists" "$tmp"
out="$(assert_file_absent "fa" "$tmp" 2>&1)"
assert_contains "assert_file_absent fails on an existing file" "$out" "FAIL:"
rm -f "$tmp"
assert_file_absent "removed file is absent" "$tmp"
out="$(assert_file_exists "fe" "$tmp" 2>&1)"
assert_contains "assert_file_exists fails on a missing file" "$out" "FAIL:"

# --- assert_line_count ---
tmp="$(mktemp)"
printf 'a\nb\nc\n' >"$tmp"
out="$(assert_line_count "lc" "$tmp" 3)"
assert_contains "assert_line_count counts newlines" "$out" "PASS:"
out="$(assert_line_count "lc" "$tmp" 2 2>&1)"
assert_contains "assert_line_count fails on a wrong count" "$out" "FAIL:"
out="$(assert_line_count "lc" "$tmp.missing" 0 2>&1)"
assert_contains "assert_line_count fails on a missing file" "$out" "FAIL:"
rm -f "$tmp"

# --- assert_row_count (including the zero-match path) ---
out="$(assert_row_count "rc" $'x1\nx2\ny3' 2 '^x')"
assert_contains "assert_row_count counts matches" "$out" "PASS:"
out="$(assert_row_count "rc-zero" "no matches here" 0 '^x')"
assert_contains "assert_row_count handles zero matches" "$out" "PASS:"
out="$(assert_row_count "rc" $'x1\ny2' 2 '^x' 2>&1)"
assert_contains "assert_row_count fails on a wrong count" "$out" "FAIL:"

# --- make_repo ---
tmpd="$(mktemp -d)"
make_repo "$tmpd/r"
assert_file_exists "make_repo initializes a git repo" "$tmpd/r/.git/HEAD"
rm -rf "$tmpd"

[[ $FAILED -eq 0 ]] || exit 1
