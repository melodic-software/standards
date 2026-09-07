# shellcheck shell=bash
# Comment-hygiene detection policy — org-wide default ruleset.
#
# Library, NOT executable. Pure functions: no env reads, no file I/O, no exit
# calls. The comment-hygiene composite action sources this file and handles file
# enumeration, path scoping, and exit-code mapping. POSIX ERE only for
# cross-platform parity: bash =~ delegates to the platform's regex library, so
# non-POSIX extensions would not behave identically on Linux CI and Git Bash.
#
# Policy: comments in production code must not carry deferred-work markers
# (TODO / FIXME / HACK / XXX) or issue-tracker references: cc-issue, GitHub
# closing keywords with a number (fix(es|ed)/close[sd]/resolve[sd] #N), issue /
# issues / tracked + N (# optional), owner/repo#N, GH-N, and PR #N. Track
# outstanding work in the issue tracker, not in code comments, so it stays
# visible and does not rot silently in the source.
#
# This file is the managed policy payload and is not edited downstream. Route a
# reusable change upstream; a repository with genuinely different policy opts
# out and owns the complete component. Execution remains in ci-workflows.

# chp::_record_violation <lineno> <kind> <detail>
#
# Emit one "lineno:kind:detail" line and increment the caller's `violations`
# local via bash dynamic scoping; private to chp::scan_text.
chp::_record_violation() {
  printf '%s:%s:%s\n' "$1" "$2" "$3"
  violations=$((violations + 1))
}

# chp::_scan_comment_line <entry>
#
# Apply the policy rules to one "lineno:text" comment line. Private to
# chp::scan_text; increments the caller's `violations` local via dynamic
# scoping (same as chp::_record_violation).
chp::_scan_comment_line() {
  local lineno="${1%%:*}"
  local line="${1#*:}"

  # Warning markers — FIXME/HACK share one rule and the report names the
  # marker matched; TODO has its own rule so its reported detail is always the
  # canonical "TODO" spelling regardless of the case matched.
  if [[ "$line" =~ (^|[^[:alnum:]_])(FIXME|HACK)([^[:alnum:]_]|$) ]]; then
    chp::_record_violation "$lineno" warning-marker "${BASH_REMATCH[2]}"
    return
  fi
  # XXX is uppercase-only: lowercase xxx collides with the CSS keyword
  # xxx-large and with placeholder text, so this one rule is case-sensitive.
  shopt -u nocasematch
  if [[ "$line" =~ (^|[^[:alnum:]_])XXX([^[:alnum:]_]|$) ]]; then
    shopt -s nocasematch
    chp::_record_violation "$lineno" warning-marker XXX
    return
  fi
  shopt -s nocasematch
  if [[ "$line" =~ (^|[^[:alnum:]_])TODO([^[:alnum:]_]|$) ]]; then
    chp::_record_violation "$lineno" warning-marker TODO
    return
  fi

  # Internal continuous-collaboration issue marker.
  if [[ "$line" =~ cc-issue ]]; then
    chp::_record_violation "$lineno" tracker-ref cc-issue
    return
  fi

  # GitHub closing keywords only close an issue when paired with a #number, so
  # require the # — that keeps prose like "fix 3 bugs" or "close the handle"
  # clean while catching "fixes #12" / "resolves #42" / "closed #7".
  if [[ "$line" =~ (^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref closing-keyword
    return
  fi

  # issue / issues / tracked references (the # is optional here).
  if [[ "$line" =~ (^|[^[:alnum:]_])(issues?|tracked)[[:space:]]*:?[[:space:]]*#?[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref issue-reference
    return
  fi

  # owner/repo#N — same- or cross-repo issue reference (e.g. org/app#123). The
  # owner segment excludes '.' — the only character needed to keep a bare domain
  # host (e.g. foo.com/bar#3 or example.com/page#2) from being misread as
  # owner/repo, since a dotted host cannot be an owner. '_' stays in the owner
  # class because GitHub Enterprise Managed User logins carry an '_SHORTCODE'
  # suffix (e.g. mona-cat_octo), so dropping it would miss real owner refs in
  # EMU repos. The repo segment also keeps '.' and '_' because repository names
  # allow them; the leading boundary still excludes '.'/'-' so a host embedded
  # mid-token is not a match start either.
  if [[ "$line" =~ (^|[^[:alnum:]_/.-])[A-Za-z0-9_-]+/[A-Za-z0-9._-]+#[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref repo-issue
    return
  fi

  # GH-N shorthand.
  if [[ "$line" =~ (^|[^[:alnum:]_])GH-[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref gh-reference
    return
  fi

  if [[ "$line" =~ (^|[^[:alnum:]_])PR[[:space:]]*#[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref pr-reference
    return
  fi
  # Jira-style keys (PROJ-123) are intentionally NOT matched: the bare
  # LETTERS-NUMBER shape collides with technical tokens (UTF-8, SHA-256,
  # ISO-8601, RFC-2119, CVE-2025-…, P-256) and POSIX ERE cannot exclude them.
  # Deferred until a Jira-using consumer supplies an explicit project-key list.
}

# chp::scan_text <content>
#
# Scan the comment lines of <content> (those starting with //, #, /*, *, or
# <!--, after optional indentation) for banned markers and tracker references.
#
# A single-line <content> (no newline) is the local-lane git-grep hit shape:
# the comment-start pattern is matched in-process so a tree scan does not
# spawn awk once per candidate. Multi-line content still uses one awk.
#
# Output (stdout): "lineno:kind:detail" per violation, lineno relative to
# <content>. Exit: 0 = clean, 1 = one or more violations.
chp::scan_text() {
  local content="$1"
  local entry violations=0
  local nocase_was=0

  # Rules match case-insensitively (Todo:, fixme, gh-3, …) — except XXX, which
  # is matched uppercase-only below. Save/restore the shell option so a scan
  # never leaks nocasematch to the caller.
  if shopt -q nocasematch; then
    nocase_was=1
  else
    shopt -s nocasematch
  fi

  # Same comment-start pattern the awk extractor uses. Stored in a variable so
  # bash 3.2 does not eat backslashes in an unquoted =~ operand.
  local comment_re='^[[:space:]]*(//|#|/\*|\*|<!--)'
  if [[ "$content" != *$'\n'* ]]; then
    if [[ "$content" =~ $comment_re ]]; then
      chp::_scan_comment_line "1:$content"
    fi
  else
    while IFS= read -r entry; do
      chp::_scan_comment_line "$entry"
    done < <(awk '/^[[:space:]]*(\/\/|#|\/\*|\*|<!--)/ { print NR ":" $0 }' <<<"$content")
  fi

  if [[ $nocase_was -eq 0 ]]; then
    shopt -u nocasematch
  fi
  if [[ $violations -gt 0 ]]; then
    return 1
  fi
  return 0
}
