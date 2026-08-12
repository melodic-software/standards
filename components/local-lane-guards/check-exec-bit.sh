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
# Two-pass shebang detection — extension-agnostic:
#   1. `git grep --cached -lIE '^#!'` narrows to candidate blobs containing
#      `#!` on any line. `-I` skips binaries (images, PDFs excluded for free).
#      `-z` NUL-separates paths and `-c core.quotePath=false` disables
#      C-escaping, so filenames with non-ASCII / tabs / newlines survive.
#   2. For each candidate, verify the blob's first two bytes are literally
#      `#!`. This filters markdown examples, docs with embedded shell snippets,
#      and `#!` patterns appearing past line 1.
#
# Pre-seed candidates into a tempfile so the `git grep` exit code can be read
# before consuming the output:
#   0   = at least one match
#   1   = no matches (legitimate — zero shebang files)
#   128 (or other) = fatal (object read, promisor fetch, corrupt index). A
#         blob:none checkout can surface real read errors here, so fail CLOSED
#         rather than swallow them into a silent pass.
candidates=$(mktemp)
errfile=$(mktemp)
trap 'rm -f "$candidates" "$errfile"' EXIT
grep_rc=0
# stderr to its own file: $candidates is a NUL-delimited path list consumed by
# the read loop below, so a stderr line (no NUL terminator) merged in would
# corrupt an adjacent record and silently drop a real shebang file. stderr is
# only needed for the fatal-error report.
git -c core.quotePath=false grep --cached -z -lIE '^#!' -- "${paths[@]}" \
  >"$candidates" 2>"$errfile" || grep_rc=$?
if [[ "$grep_rc" -ne 0 && "$grep_rc" -ne 1 ]]; then
  echo "::error::git grep failed (exit $grep_rc) — refusing to pass the exec-bit gate without a full candidate scan."
  echo "::group::git grep stderr"
  cat "$errfile"
  echo "::endgroup::"
  exit 1
fi

while IFS= read -r -d '' path; do
  [[ -n "$path" ]] || continue
  # Read the first staged entry for $path as one NUL-terminated record so
  # tabs / newlines embedded in the path survive (going through `tr '\0' '\n'`
  # then `head -n1` would truncate a path containing '\n' at the wrong place).
  IFS= read -r -d '' entry < <(
    git -c core.quotePath=false ls-files --stage -z -- "$path"
  ) || true
  [[ -n "$entry" ]] || continue
  # Entry format: "<mode> <hash> <stage>\t<path>". Split on the first tab; the
  # metadata half never contains tabs.
  rest=${entry%%$'\t'*}
  candidate_path=${entry#*$'\t'}
  [[ "$candidate_path" == "$path" ]] || continue
  read -r mode hash _stage <<<"$rest"
  case "$mode" in
    100644 | 100755) ;;
    *) continue ;;
  esac
  blob=$(git cat-file blob "$hash" 2>/dev/null)
  [[ "${blob:0:2}" == "#!" ]] || continue
  if [[ "$mode" == "100644" ]]; then
    echo "::error file=$path::$path has a shebang but git index mode is 100644; run: git update-index --chmod=+x -- \"$path\""
    failed=1
  fi
done <"$candidates"

if [[ "$failed" -eq 0 ]]; then
  echo "All shebang files are mode 100755 in the index."
fi
exit "$failed"
