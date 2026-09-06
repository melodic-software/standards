#!/usr/bin/env bash
# Verify every tracked file whose content starts with a shebang (#! at byte 0)
# has git index mode 100755. A shebang file committed as 100644 loses its
# executable bit on clone/checkout, so anything that execs it (CI hooks,
# bootstrap scripts, tooling) fails with "Permission denied". The check is
# extension-agnostic: shebangs appear in .py / .js / .ts / .sh / .rb and more.
#
# Deliberately NOT `set -e`: git grep's "no matches" exit 1 is a legitimate
# clean result, distinguished from a fatal error by hand below.
set -uo pipefail

# Scan pathspec (word-split; default '.' = whole repo).
read -ra paths <<<"${PATHS:-.}"

failed=0
# Two-pass shebang detection — extension-agnostic, two Git spawns total:
#   1. `git grep --cached -z -nIE '^#!'` finds every blob containing `#!` at
#      the start of a line. `-I` skips binaries. `-z` NUL-separates the path
#      so filenames with non-ASCII / tabs / newlines survive. `-n` emits the
#      line number: line 1 matching `^#!` is the POSIX-text equivalent of
#      bytes 0-1 being `#!` (the previous per-candidate `git cat-file blob`
#      check), which filters markdown examples, docs with embedded snippets,
#      and `#!` appearing past line 1 without loading each blob.
#   2. One `git ls-files --stage -z` builds an exact-recorded-path mode map
#      (a directory-shaped pathspec also selects descendants, so attribution
#      is by exact path lookup, never by "the pathspec that selected it").
#      The first staged entry for a path wins, matching the previous
#      per-path `ls-files --stage` which read one NUL record.
#
# Pre-seed grep output into a tempfile so the `git grep` exit code can be
# read before consuming the output:
#   0   = at least one match
#   1   = no matches (legitimate — zero shebang-looking files)
#   128 (or other) = fatal (object read, promisor fetch, corrupt index). A
#         blob:none checkout can surface real read errors here, so fail CLOSED
#         rather than swallow them into a silent pass.
candidates=$(mktemp)
errfile=$(mktemp)
trap 'rm -f "$candidates" "$errfile"' EXIT
grep_rc=0
# stderr to its own file: $candidates is parsed as path-NUL-lineno-NUL-line
# records, so a stderr line merged in would corrupt an adjacent record and
# silently drop a real shebang file. stderr is only needed for the
# fatal-error report.
git -c core.quotePath=false grep --cached -z -nIE '^#!' -- "${paths[@]}" \
  >"$candidates" 2>"$errfile" || grep_rc=$?
if [[ "$grep_rc" -ne 0 && "$grep_rc" -ne 1 ]]; then
  echo "::error::git grep failed (exit $grep_rc) — refusing to pass the exec-bit gate without a full candidate scan."
  echo "::group::git grep stderr"
  cat "$errfile"
  echo "::endgroup::"
  exit 1
fi

# Line-1 `^#!` hits are the shebang files. `git grep -z -n` writes
# path NUL lineno NUL line-text LF (observed on git 2.x; -z NUL-delimits
# the filename and, with -n, the line number, then the line ends with LF).
shebang_paths=()
while IFS= read -r -d '' path; do
  IFS= read -r -d '' lineno || break
  IFS= read -r _line || true
  [[ "$lineno" == 1 ]] || continue
  [[ -n "$path" ]] || continue
  shebang_paths+=("$path")
done <"$candidates"

if ((${#shebang_paths[@]} == 0)); then
  echo "All shebang files are mode 100755 in the index."
  exit 0
fi

# Reuse $candidates for the staged-mode map. Fail closed on a fatal
# ls-files the same way grep is failed closed above.
ls_rc=0
git -c core.quotePath=false ls-files --stage -z -- "${paths[@]}" \
  >"$candidates" 2>"$errfile" || ls_rc=$?
if [[ "$ls_rc" -ne 0 ]]; then
  echo "::error::git ls-files --stage failed (exit $ls_rc) — refusing to pass the exec-bit gate without a full index scan."
  echo "::group::git ls-files stderr"
  cat "$errfile"
  echo "::endgroup::"
  exit 1
fi

declare -A index_mode=()
while IFS= read -r -d '' entry; do
  [[ -n "$entry" ]] || continue
  # Entry format: "<mode> <hash> <stage>\t<path>". Split on the first tab; the
  # metadata half never contains tabs.
  rest=${entry%%$'\t'*}
  candidate_path=${entry#*$'\t'}
  # First staged entry wins (unmerged paths can carry up to three stages).
  [[ -n "${index_mode[$candidate_path]+x}" ]] && continue
  read -r mode _hash _stage <<<"$rest"
  index_mode["$candidate_path"]=$mode
done <"$candidates"

for path in "${shebang_paths[@]}"; do
  [[ -n "${index_mode[$path]+x}" ]] || continue
  mode=${index_mode[$path]}
  case "$mode" in
    100644 | 100755) ;;
    *) continue ;;
  esac
  if [[ "$mode" == "100644" ]]; then
    echo "::error file=$path::$path has a shebang but git index mode is 100644; run: git update-index --chmod=+x -- \"$path\""
    failed=1
  fi
done

if [[ "$failed" -eq 0 ]]; then
  echo "All shebang files are mode 100755 in the index."
fi
exit "$failed"
