#!/usr/bin/env bash

[[ -n "${_SH_TEST_LIB_LOADED:-}" ]] && return 0
readonly _SH_TEST_LIB_LOADED=1

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — %s\n' "$CASE_NUM" "$1" "$2" >&2
  FAILED=$((FAILED + 1))
}

skip_suite() {
  skip_case "$1"
  exit 0
}

skip_case() {
  printf 'SKIP: %s\n' "$1" >&2
}

require_min_version() {
  local label="$1" have="$2" min="$3"
  if [[ ! "$have" =~ ^[0-9] ]]; then
    printf 'ERROR: %s reported an unparsable version: %q (fix the --version parse)\n' "$label" "$have" >&2
    exit 1
  fi
  # awk, not `sort -V`: POSIX sort has no -V, and this must run on any POSIX sort:
  # https://pubs.opengroup.org/onlinepubs/9799919799/utilities/sort.html
  if awk -v a="$have" -v b="$min" 'BEGIN {
    na = split(a, aa, "."); nb = split(b, bb, ".");
    n = (na > nb) ? na : nb;
    for (i = 1; i <= n; i++) {
      x = aa[i] + 0; y = bb[i] + 0;
      if (x < y) exit 0;   # have < min  -> below
      if (x > y) exit 1;   # have > min  -> at/above
    }
    exit 1;                # equal       -> at/above
  }'; then
    skip_suite "$label $have < $min"
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected $(printf '%q' "$expected") got $(printf '%q' "$actual")"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label" "expected $(printf '%q' "$needle") in: $haystack"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label" "forbidden $(printf '%q' "$needle") present in: $haystack"
  fi
}

assert_silent() {
  local label="$1" output="$2"
  if [[ -z "${output//[[:space:]]/}" ]]; then
    pass "$label"
  else
    fail "$label" "expected empty/whitespace, got: $output"
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "exit expected $expected got $actual"
  fi
}

assert_nonzero() {
  local label="$1" rc="$2"
  if [[ "$rc" -ne 0 ]]; then
    pass "$label"
  else
    fail "$label" "expected non-zero exit, got 0"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    pass "$label"
  else
    fail "$label" "expected file $path"
  fi
}

assert_file_absent() {
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    pass "$label"
  else
    fail "$label" "expected absent, found $path"
  fi
}

assert_line_count() {
  local label="$1" path="$2" expected="$3"
  if [[ ! -f "$path" ]]; then
    fail "$label" "expected file $path"
    return
  fi
  local got
  got=$(wc -l <"$path" | tr -d ' ')
  if [[ "$got" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected $expected lines got $got"
  fi
}

assert_command_fails() {
  local label="$1"
  shift
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  assert_nonzero "$label" "$rc"
}

assert_row_count() {
  local label="$1" out="$2" expected="$3" anchor="$4"
  local actual
  # grep -c prints 0 and exits 1 on no match; || true keeps the count a single line:
  # https://pubs.opengroup.org/onlinepubs/9799919799/utilities/grep.html
  actual=$(grep -cE "$anchor" <<<"$out" || true)
  if [[ "$actual" == "$expected" ]]; then
    pass "$label — $expected rows"
  else
    fail "$label" "expected $expected rows got $actual"$'\n'"$out"
  fi
}

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.local
  git -C "$dir" config user.name testuser
  git -C "$dir" -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -m init -q
}
