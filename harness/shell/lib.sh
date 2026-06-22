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
# Every assertion routes its result through pass()/fail(), which increment the
# counters in the caller's scope; PASS lines go to stdout, FAIL lines to stderr.
# End every test file with:
#   [[ $FAILED -eq 0 ]] || exit 1
#
# Param order: the label comes first. Equality and exit-code assertions take the
# expected value then the actual; containment assertions take the subject
# (haystack) then the needle.

[[ -n "${_SH_TEST_LIB_LOADED:-}" ]] && return 0
readonly _SH_TEST_LIB_LOADED=1

: "${FAILED:=0}"
: "${CASE_NUM:=0}"

# pass <label> — record a passing case.
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

# fail <label> <detail> — record a failing case with a free-form detail message.
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — %s\n' "$CASE_NUM" "$1" "$2" >&2
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
  local trimmed="${output#"${output%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  if [[ -z "$trimmed" ]]; then
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

# Alias for callers that emphasize stdout semantics.
assert_stdout_contains() {
  assert_contains "$@"
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
  local got=0
  [[ -f "$path" ]] && got=$(wc -l <"$path" | tr -d ' ')
  if [[ "$got" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected $expected lines got $got"
  fi
}

# assert_command_fails <label> <cmd...> — passes if <cmd> exits non-zero.
# stdout/stderr discarded; capture earlier if you need to inspect output.
assert_command_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label" "expected non-zero exit, got 0"
  else
    pass "$label"
  fi
}

# assert_row_count <label> <output> <expected> <anchor_regex> — count lines in
# <output> matching <anchor_regex>; pass if the count equals <expected>.
assert_row_count() {
  local label="$1" out="$2" expected="$3" anchor="$4"
  local actual
  # grep -c prints the count (0 on no match) and exits 1 when nothing matched;
  # || true swallows that exit without appending a second line to the count.
  actual=$(grep -cE "$anchor" <<<"$out" || true)
  if [[ "$actual" == "$expected" ]]; then
    pass "$label — $expected rows"
  else
    fail "$label" "expected $expected rows got $actual"$'\n'"$out"
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
