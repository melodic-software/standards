#!/usr/bin/env bash
# Shared assertion library for *.test.sh shell tests in this repo.
#
# Plain-bash test convention: a *.test.sh file lives next to the config or
# script it tests, sources this lib, and calls assertions. Not a BATS
# replacement — a lightweight shared helper that keeps the test suite
# dependency-free.
#
# Source it (CWD-independent — resolves via git toplevel). Hoist the toplevel into
# `root` once and reuse it for the source path and any later paths, rather than
# invoking `git rev-parse` twice:
#   root="$(git rev-parse --show-toplevel)"
#   source "$root/harness/shell/lib.sh"
#
# This lib auto-initializes the FAILED and CASE_NUM counters (below), so test
# files need not declare them. Every assertion routes its result through
# pass()/fail(), which increment the counters in the caller's scope; PASS lines
# go to stdout, FAIL lines to stderr.
# End every test file with:
#   [[ $FAILED -eq 0 ]] || exit 1
#
# Param order: the label comes first. Equality and exit-code assertions take the
# expected value then the actual; containment assertions take the subject
# (haystack) then the needle.

[[ -n "${_SH_TEST_LIB_LOADED:-}" ]] && return 0
readonly _SH_TEST_LIB_LOADED=1

# Reset unconditionally (not `: "${FAILED:=0}"`): the lib owns these counters, so
# an inherited or exported FAILED/CASE_NUM from the runner's environment must not
# leak in and skew a file's tally. The load guard above runs this once per process.
FAILED=0
CASE_NUM=0

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

# require_min_version <label> <have> <min> — skip the whole suite when the tool's
# reported version <have> is below <min> (compared numerically, so 1.9 < 1.10).
# <label> names the tool in the skip message. An empty or non-version <have> means
# the caller's version-parse broke (the tool's --version format changed): that is a
# harness defect, not an environmental skip, so fail loudly rather than silently
# gating on the wrong version or dropping the suite.
require_min_version() {
  local label="$1" have="$2" min="$3"
  if [[ ! "$have" =~ ^[0-9] ]]; then
    printf 'ERROR: %s reported an unparsable version: %q (fix the --version parse)\n' "$label" "$have" >&2
    exit 1
  fi
  # Dotted-numeric compare in awk rather than `sort -V`: the version-sort flag is a
  # GNU extension that BSD/macOS sort lacks, and the self-test exercises this path
  # unconditionally (no tool gate), so it must run on the macOS system toolchain.
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

# assert_nonzero <label> <rc> — passes if the captured exit code <rc> is non-zero.
# For tools whose failure code varies (1 vs 2); use assert_exit when the code is
# fixed, or assert_command_fails to run-and-check a command in one call.
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

# assert_command_fails <label> <cmd...> — passes if <cmd> exits non-zero.
# stdout/stderr discarded; capture earlier if you need to inspect output.
assert_command_fails() {
  local label="$1"
  shift
  # Capture via `|| rc=$?` so the deliberately-failing command stays errexit-immune
  # (a bare `"$@"` would abort a `set -e` caller before assert_nonzero records).
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  assert_nonzero "$label" "$rc"
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
# so tests that need a valid HEAD work in CI without global git config. The
# commit overrides ambient global config (commit signing, hooks path) so a
# contributor's machine behaves like CI.
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.local
  git -C "$dir" config user.name testuser
  git -C "$dir" -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -m init -q
}
