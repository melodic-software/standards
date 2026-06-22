#!/usr/bin/env bash
# Self-test for the assertion library: the PASS and FAIL paths of the core
# assertions must themselves behave. Deliberate-failure paths run in isolated
# subshells so they don't pollute this file's own FAILED counter.
# The capture subshells below set FAILED=0 so a deliberate-failure assertion
# does not pollute this file's own counter (see header). ShellCheck reads that
# as a lost subshell modification; the isolation is intended, so disable the
# pair file-wide (the directive must precede the first command to apply so).
# shellcheck disable=SC2030,SC2031
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

FAILED=0
CASE_NUM=0

out="$(FAILED=0 CASE_NUM=0; assert_eq "eq" foo foo)"
assert_contains "assert_eq emits PASS on match" "$out" "PASS:"

out="$(FAILED=0 CASE_NUM=0; assert_eq "eq" foo bar 2>&1)"
assert_contains "assert_eq emits FAIL on mismatch" "$out" "FAIL:"

out="$(FAILED=0 CASE_NUM=0; assert_contains "c" "hello world" "world")"
assert_contains "assert_contains matches substring" "$out" "PASS:"

out="$(FAILED=0 CASE_NUM=0; assert_not_contains "nc" "hello" "world")"
assert_contains "assert_not_contains passes on absence" "$out" "PASS:"

assert_command_fails "false exits non-zero" false

tmp="$(mktemp)"
assert_file_exists "temp file exists" "$tmp"
rm -f "$tmp"
assert_file_absent "removed file is absent" "$tmp"

[[ $FAILED -eq 0 ]] || exit 1
