#!/usr/bin/env bash
# Heading-cite resolver. Verifies every `file.md` "Anchor" prose cite in the
# scanned markdown corpus against the actual anchor vocabulary of the cited
# file: markdown headings (h1-h6) plus bold lead-ins (bullet `- **Name**`,
# paragraph `**Name**`, table-cell `| **Name**`). Pairs with the lychee-offline
# action (which covers link/fragment targets); this resolves prose-cited anchors
# a link checker cannot see.
# Dependency-free: one POSIX-awk process (no gawk extensions — runs on gawk,
# mawk, BSD awk); file contents are read via getline so no per-file forks and no
# ARGV-length ceiling. Exit 0 clean, 1 on unresolved cites, 2 usage.
#
# The corpus is `git ls-files <globs>` minus an optional caller-supplied exclude
# regex; a consumer scopes out generated / vendored / work trees via EXCLUDE.
set -euo pipefail

# Corpus selection — overridden by the composite action via env.
GLOBS="${GLOBS:-*.md}"
EXCLUDE="${EXCLUDE:-}"

usage() {
  cat <<'EOF'
Usage: check-heading-cites.sh [options]

Resolve every `file.md` "Anchor" prose cite in the durable markdown corpus
(backtick path `file.md` "Anchor" OR namespaced prose path/file.md "Anchor" when the
path contains `/`)
cited file's anchor set (headings + bold lead-ins). Anchor match is
exact OR prefix-with-delimiter-guard (cite may quote a truncated anchor; the
next character of the full anchor must be one of: space, "(", ":"). Both sides
are normalized before comparison: backticks stripped, one trailing period
stripped, leading "N. " ordinal stripped — formatting-only churn in a heading
must not break prose cites. Path resolution order: exact repo-root path, then
source-dir-relative, then unique suffix match corpus-wide.

Corpus = `git ls-files $GLOBS` (default *.md) minus the $EXCLUDE regex; both are
set by the composite action's `globs` / `exclude` inputs.

Options:
  --root <dir>           Repo root to enumerate + resolve against (default: the cwd's git toplevel).
  --corpus-file <file>   Override corpus enumeration with a newline-delimited path list (test seam).
  --help                 Show this help and exit.

Exemption markers:
  <!-- heading-cite-ignore -->        exempts cites on the NEXT line
  <!-- heading-cite-ignore-line -->   exempts cites on the SAME line

Output: one `file:line: unresolved cite → target "anchor" (reason: ...)` line
per finding (reason: no-file | no-anchor). Silent on a clean corpus.
Exit codes: 0 clean, 1 findings, 2 usage error.
EOF
}

err() { echo "ERROR: $*" >&2; }

# Single-pass POSIX-awk core. stdin = corpus path list (relative to cwd).
# Pass 1 (main loop): register every path. END: getline-scan each file building
# the anchor index AND the cite list, then resolve + report.
read -r -d '' AWK_PROG <<'AWK' || true
BEGIN {
  SEP = "\037"
  BOM = "\357\273\277"
  CITE_RE = "`/?[-A-Za-z0-9._/]+\\.md` +\"[^\"]+\""
  PROSE_CITE_RE = "[-A-Za-z0-9._/]*\\/[-A-Za-z0-9._/]+\\.md \"[^\"]+\""
  nfiles = 0
  ncites = 0
  found = 0
}
NF > 0 {
  if (!($0 in pathset)) { pathset[$0] = 1; files[++nfiles] = $0 }
}
END {
  for (i = 1; i <= nfiles; i++) scan_file(files[i])
  for (i = 1; i <= ncites; i++) {
    resolved = resolve_path(cite_target[i], dirof(cite_file[i]))
    if (resolved == "") report(i, "no-file")
    else if (!anchor_ok(resolved, cite_anchor[i])) report(i, "no-anchor")
  }
  exit found ? 1 : 0
}
function report(i, reason) {
  printf "%s:%d: unresolved cite → %s \"%s\" (reason: %s)\n", \
    cite_file[i], cite_line[i], cite_target[i], cite_anchor[i], reason
  found = 1
}
function scan_file(path,   line, lineno, infence, skipnext, skipthis, tmp, fc, flen, fence_char, fence_len) {
  lineno = 0
  infence = 0
  skipnext = 0
  while ((getline line < path) > 0) {
    lineno++
    sub(/\r$/, "", line)
    if (lineno == 1 && index(line, BOM) == 1) line = substr(line, 4)
    skipthis = skipnext
    skipnext = 0
    if (index(line, "<!-- heading-cite-ignore-line -->") > 0) skipthis = 1
    else if (index(line, "<!-- heading-cite-ignore -->") > 0) skipnext = 1
    # CommonMark fence pairing: a closing fence must use the same character
    # and at least the opener's run length — inner shorter fences are content
    # (a ````-wrapped prompt containing ``` blocks must stay ONE fence).
    tmp = line
    sub(/^ */, "", tmp)
    fc = substr(tmp, 1, 1)
    if ((fc == "`" || fc == "~") && substr(tmp, 1, 3) == fc fc fc) {
      flen = 3
      while (substr(tmp, flen + 1, 1) == fc) flen++
      if (!infence) { infence = 1; fence_char = fc; fence_len = flen }
      else if (fc == fence_char && flen >= fence_len) infence = 0
      continue
    }
    if (infence) continue
    index_anchors(path, line)
    if (!skipthis) {
      extract_cites(path, lineno, line)
      extract_prose_cites(path, lineno, line)
    }
  }
  close(path)
}
function index_anchors(path, line,   a, rest, p) {
  a = ""
  if (substr(line, 1, 1) == "#") {
    if (match(line, /^#+/) && RLENGTH <= 6 && substr(line, RLENGTH + 1, 1) == " ")
      a = trim(substr(line, RLENGTH + 2))
  } else if (match(line, /^[-*+] \*\*/)) {
    rest = substr(line, RLENGTH + 1)
    p = index(rest, "**")
    if (p > 1) a = substr(rest, 1, p - 1)
  } else if (substr(line, 1, 2) == "**") {
    rest = substr(line, 3)
    p = index(rest, "**")
    if (p > 1) a = substr(rest, 1, p - 1)
  } else if (substr(line, 1, 4) == "| **") {
    rest = substr(line, 5)
    p = index(rest, "**")
    if (p > 1) a = substr(rest, 1, p - 1)
  }
  a = normanchor(a)
  if (a != "" && !((path, a) in anchorset)) {
    anchorset[path, a] = 1
    anchorlist[path] = (path in anchorlist) ? anchorlist[path] SEP a : a
  }
}
# Formatting-only normalization applied to BOTH indexed anchors and cite
# anchors before comparison: backticks, one trailing period, leading "N. "
# ordinal. Keeps the gate's signal on real renames, not markup churn.
function normanchor(s) {
  gsub(/`/, "", s)
  sub(/^[0-9]+\. /, "", s)
  sub(/\.$/, "", s)
  return s
}
function extract_cites(path, lineno, line,   work, m, t) {
  work = line
  while (match(work, CITE_RE)) {
    m = substr(work, RSTART, RLENGTH)
    work = substr(work, RSTART + RLENGTH)
    t = substr(m, 2)
    t = substr(t, 1, index(t, "`") - 1)
    sub(/^\//, "", t)
    work = add_cite_from_match(path, lineno, t, m, work)
  }
}
function extract_prose_cites(path, lineno, line,   work, m, t, sp, url_pos) {
  work = line
  while (match(work, PROSE_CITE_RE)) {
    if (RSTART > 1 && substr(work, RSTART - 1, 1) == "`") {
      work = substr(work, RSTART + RLENGTH)
      continue
    }
    m = substr(work, RSTART, RLENGTH)
    work = substr(work, RSTART + RLENGTH)
    sp = index(m, " \"")
    if (sp < 1) continue
    t = substr(m, 1, sp - 1)
    if (t ~ /^https?:\/\// || t ~ /^\/\//) {
      continue
    }
    url_pos = index(line, t " \"")
    if (url_pos > 3 && substr(line, url_pos - 3, 3) == "://") {
      continue
    }
    work = add_cite_from_match(path, lineno, t, m, work)
  }
}
# Record the cite carried by the current match, then continue scanning any
# chained anchor continuations. Shared by extract_cites and
# extract_prose_cites, which differ only in how they derive `t` (the target)
# and `m` (the matched text) before calling in.
function add_cite_from_match(path, lineno, t, m, work,   q1) {
  q1 = index(m, "\"")
  add_cite(path, lineno, t, substr(m, q1 + 1, length(m) - q1 - 1))
  return extract_chained(path, lineno, t, work)
}
# Chained continuation anchors: `file.md` "A" + "B" [+ "C" ...] — each anchor
# verified against the same target.
function extract_chained(path, lineno, t, work,   m, q1) {
  while (match(work, /^ \+ "[^"]+"/)) {
    m = substr(work, RSTART, RLENGTH)
    work = substr(work, RSTART + RLENGTH)
    q1 = index(m, "\"")
    add_cite(path, lineno, t, substr(m, q1 + 1, length(m) - q1 - 1))
  }
  return work
}
function add_cite(path, lineno, t, a) {
  if (substr(t, 1, 1) == "<") return
  gsub(/\\`/, "`", a)
  ncites++
  cite_file[ncites] = path
  cite_line[ncites] = lineno
  cite_target[ncites] = t
  cite_anchor[ncites] = a
}
# Resolution order: exact repo-root path -> source-dir-relative -> unique
# corpus-wide suffix match (guarded: candidate must be longer than the target
# and the suffix must start at a "/" boundary). Memoized per (dir, target).
function resolve_path(target, dir,   key, cand, p, hits, hit, lt, lp) {
  key = dir SUBSEP target
  if (key in resolvememo) return resolvememo[key]
  cand = ""
  if (target in pathset) cand = target
  if (cand == "" && dir != "") {
    p = normpath(dir "/" target)
    if (p in pathset) cand = p
  }
  if (cand == "") {
    lt = length(target)
    hits = 0
    for (p in pathset) {
      lp = length(p)
      if (lp > lt && substr(p, lp - lt + 1) == target && substr(p, lp - lt, 1) == "/") {
        hits++
        hit = p
        if (hits > 1) break
      }
    }
    if (hits == 1) cand = hit
  }
  resolvememo[key] = cand
  return cand
}
# Anchor match: exact, OR cite is a truncated prefix of a real anchor whose
# next character is a delimiter (space, "(", ":"). Memoized per (path, anchor).
function anchor_ok(path, a,   key, ok, la, n, arr, i, act, c) {
  a = normanchor(a)
  if ((path, a) in anchorset) return 1
  key = path SUBSEP a
  if (key in anchmemo) return anchmemo[key]
  ok = 0
  la = length(a)
  n = split((path in anchorlist) ? anchorlist[path] : "", arr, SEP)
  for (i = 1; i <= n; i++) {
    act = arr[i]
    if (length(act) > la && substr(act, 1, la) == a) {
      c = substr(act, la + 1, 1)
      if (c == " " || c == "(" || c == ":") { ok = 1; break }
    }
  }
  anchmemo[key] = ok
  return ok
}
function dirof(path) {
  if (match(path, /^.*\//)) return substr(path, 1, RLENGTH - 1)
  return ""
}
function normpath(p,   n, parts, i, m, out, stack) {
  n = split(p, parts, "/")
  m = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") {
      if (m > 0) m--
      continue
    }
    stack[++m] = parts[i]
  }
  out = ""
  for (i = 1; i <= m; i++) out = (i == 1) ? stack[i] : out "/" stack[i]
  return out
}
function trim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}
AWK

main() {
  local root="" corpus_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)
        root="${2:?--root needs a path}"
        shift 2
        ;;
      --corpus-file)
        corpus_file="${2:?--corpus-file needs a path}"
        shift 2
        ;;
      --help | -h)
        usage
        return 0
        ;;
      *)
        err "unknown argument: $1"
        usage >&2
        return 2
        ;;
    esac
  done

  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
    root="${root:-$PWD}"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand $tmpdir now, not at EXIT time; it never changes after this point
  trap "rm -rf '$tmpdir'" EXIT

  local corpus="${corpus_file:-$tmpdir/corpus.txt}"
  if [[ -z "$corpus_file" ]]; then
    # noglob: GLOBS are git PATHSPECS, not shell globs — without `set -f` an
    # unquoted `*.md` would expand against the cwd (matching only top-level
    # files) instead of reaching git, which matches recursively.
    set -f
    # shellcheck disable=SC2086  # GLOBS intentionally word-splits into pathspecs
    # The `|| true` is scoped to grep -vE alone (its exit 1 when EXCLUDE filters
    # out every path is a legitimate empty corpus). A git ls-files failure must
    # NOT be swallowed: under pipefail it propagates and set -e fails closed,
    # rather than yielding an empty corpus that passes the gate green.
    git -C "$root" ls-files -- $GLOBS | tr -d '\r' \
      | { if [[ -n "$EXCLUDE" ]]; then grep -vE "$EXCLUDE" || true; else cat; fi } \
      | LC_ALL=C sort -u >"$corpus"
    set +f
  fi

  (cd "$root" && awk "$AWK_PROG" <"$corpus")
}

main "$@"
