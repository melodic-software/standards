#!/usr/bin/env bash
# Verify every tracked file whose content starts with a shebang (#! at byte 0)
# has git index mode 100755. A shebang file committed as 100644 loses its
# executable bit on clone/checkout, so anything that execs it (CI hooks,
# bootstrap scripts, tooling) fails with "Permission denied". The check is
# extension-agnostic: shebangs appear in .py / .js / .ts / .sh / .rb and more.
#
# Deliberately NOT `set -e`: git grep's "no matches" exit 1 is a legitimate
# clean result, distinguished from a fatal error by hand below.
#
# Bash 3.2-safe (stock macOS): no associative arrays, no empty
# "${array[@]}" under `set -u`. Indexed `read -ra` for PATHS is 3.2. Mode
# lookup is POSIX awk (same dependency as check-heading-cites.sh).
set -uo pipefail

# Scan pathspec (word-split; default '.' = whole repo).
read -ra paths <<<"${PATHS:-.}"

# Two-pass shebang detection — extension-agnostic, two Git spawns total:
#   1. `git grep --cached -z -nIE '^#!'` finds every blob containing `#!` at
#      the start of a line. `-I` skips binaries. `-z` NUL-separates the path
#      so filenames with non-ASCII / tabs / newlines survive. `-n` emits the
#      line number: line 1 matching `^#!` is the POSIX-text equivalent of
#      bytes 0-1 being `#!` (the previous per-candidate `git cat-file blob`
#      check), which filters markdown examples, docs with embedded snippets,
#      and `#!` appearing past line 1 without loading each blob.
#   2. One `git ls-files --stage -z` plus one awk join on exact recorded
#      path (a directory-shaped pathspec also selects descendants, so
#      attribution is by exact path lookup). The first staged entry for a
#      path wins, matching the previous per-path `ls-files --stage` which
#      read one NUL record.
#
# Pre-seed grep output into a tempfile so the `git grep` exit code can be
# read before consuming the output:
#   0   = at least one match
#   1   = no matches (legitimate — zero shebang-looking files)
#   128 (or other) = fatal (object read, promisor fetch, corrupt index). A
#         blob:none checkout can surface real read errors here, so fail CLOSED
#         rather than swallow them into a silent pass.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
candidates="$work/grep"
errfile="$work/err"
shebangs="$work/shebangs"
index="$work/index"
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
# NUL records, not a bash array: stock macOS bash 3.2 errors on an empty
# "${array[@]}" under `set -u`, and has no `declare -A`.
n_shebang=0
: >"$shebangs"
while IFS= read -r -d '' path; do
  IFS= read -r -d '' lineno || break
  IFS= read -r _line || true
  [[ "$lineno" == 1 ]] || continue
  [[ -n "$path" ]] || continue
  printf '%s\0' "$path" >>"$shebangs"
  n_shebang=$((n_shebang + 1))
done <"$candidates"

if [[ "$n_shebang" -eq 0 ]]; then
  echo "All shebang files are mode 100755 in the index."
  exit 0
fi

ls_rc=0
git -c core.quotePath=false ls-files --stage -z -- "${paths[@]}" \
  >"$index" 2>"$errfile" || ls_rc=$?
if [[ "$ls_rc" -ne 0 ]]; then
  echo "::error::git ls-files --stage failed (exit $ls_rc) — refusing to pass the exec-bit gate without a full index scan."
  echo "::group::git ls-files stderr"
  cat "$errfile"
  echo "::endgroup::"
  exit 1
fi

# RS is a single character in POSIX awk; NUL is that character. Associative
# arrays are awk's, not bash's — gawk, mawk, and BSD awk all have them.
failed=0
awk '
BEGIN { RS = "\0" }
FNR == NR {
  if ($0 != "") shebang[$0] = 1
  next
}
{
  if ($0 == "") next
  tab = index($0, "\t")
  if (tab == 0) next
  meta = substr($0, 1, tab - 1)
  path = substr($0, tab + 1)
  if (!(path in shebang)) next
  if (path in seen) next
  seen[path] = 1
  sp = index(meta, " ")
  if (sp == 0) next
  mode = substr(meta, 1, sp - 1)
  if (mode != "100644" && mode != "100755") next
  if (mode == "100644") {
    printf "::error file=%s::%s has a shebang but git index mode is 100644; run: git update-index --chmod=+x -- \"%s\"\n", path, path, path
    found = 1
  }
}
END { exit found ? 1 : 0 }
' "$shebangs" "$index" || failed=1

if [[ "$failed" -eq 0 ]]; then
  echo "All shebang files are mode 100755 in the index."
fi
exit "$failed"
