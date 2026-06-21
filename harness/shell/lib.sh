#!/usr/bin/env bash
# Shared assertion library for *.test.sh shell tests in this repo.
#
# Plain-bash test convention: a *.test.sh file lives next to the script it
# tests, sources this lib, and calls assertions. Not a BATS replacement — a
# lightweight shared helper that keeps the test suite dependency-free.
#
# Source it (CWD-independent — resolves via git toplevel):
#   source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"
#
# Each test file owns FAILED and CASE_NUM counters (auto-initialized below).
# Assertions increment FAILED in the caller's scope on failure; PASS lines go
# to stdout, FAIL lines to stderr. End every test file with:
#   [[ $FAILED -eq 0 ]] || exit 1
#
# Param order: subject (actual / haystack) before expected (needle), so calls
# read as "in <subject>, expect <something>".

[[ -n "${_STANDARDS_TEST_LIB_LOADED:-}" ]] && return 0
readonly _STANDARDS_TEST_LIB_LOADED=1

: "${FAILED:=0}"
: "${CASE_NUM:=0}"

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

# skip_suite <reason> — the whole file cannot run (missing toolchain, wrong
# platform). Prints a SKIP marker and exits 0; the runner classifies a file
# with a SKIP marker and no PASS lines as wholly skipped.
skip_suite() {
  printf 'SKIP: %s\n' "$1" >&2
  exit 0
}

# skip_case <reason> — skip one case while the rest of the file runs.
skip_case() {
  printf 'SKIP: %s\n' "$1" >&2
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected %q in: %s\n' "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

assert_not_contains() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — forbidden %q present in: %s\n' "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

assert_silent() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" output="$2"
  local trimmed="${output#"${output%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  if [[ -z "$trimmed" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected empty/whitespace, got: %s\n' "$CASE_NUM" "$label" "$output" >&2
    FAILED=$((FAILED + 1))
  fi
}

assert_exit() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — exit expected %s got %s\n' "$CASE_NUM" "$label" "$expected" "$actual" >&2
    FAILED=$((FAILED + 1))
  fi
}

# Alias for callers that emphasize stdout semantics.
assert_stdout_contains() {
  assert_contains "$@"
}

assert_file_exists() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected file %s\n' "$CASE_NUM" "$label" "$path" >&2
    FAILED=$((FAILED + 1))
  fi
}

assert_file_absent() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected absent, found %s\n' "$CASE_NUM" "$label" "$path" >&2
    FAILED=$((FAILED + 1))
  fi
}

assert_line_count() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" path="$2" expected="$3"
  local got=0
  [[ -f "$path" ]] && got=$(wc -l <"$path" | tr -d ' ')
  if [[ "$got" == "$expected" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected %s lines got %s\n' "$CASE_NUM" "$label" "$expected" "$got" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_command_fails <label> <cmd...> — passes if <cmd> exits non-zero.
# stdout/stderr discarded; capture earlier if you need to inspect output.
assert_command_fails() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL: [%d] %s — expected non-zero exit, got 0\n' "$CASE_NUM" "$label" >&2
    FAILED=$((FAILED + 1))
  else
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  fi
}

# assert_row_count <label> <output> <expected> <anchor_regex> — count lines in
# <output> matching <anchor_regex>; pass if the count equals <expected>.
assert_row_count() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" out="$2" expected="$3" anchor="$4"
  local actual
  actual=$(grep -cE "$anchor" <<<"$out" || echo 0)
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: [%d] %s — %d rows\n' "$CASE_NUM" "$label" "$expected"
  else
    printf 'FAIL: [%d] %s — expected %d rows got %d\n%s\n' "$CASE_NUM" "$label" "$expected" "$actual" "$out" >&2
    FAILED=$((FAILED + 1))
  fi
}

# make_repo <dir> — fresh git repo with one empty commit and a local identity,
# so tests that need a valid HEAD work in CI without global git config.
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.local
  git -C "$dir" config user.name testuser
  git -C "$dir" commit --allow-empty -m init -q
}
