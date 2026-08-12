#!/usr/bin/env bash
# Fail when tracked files contain machine-specific absolute paths — a
# developer's checkout root or user-home directory. Portable placeholders such
# as C:\Users\<user>\ and <repo-root>/ are allowed (the negative character
# classes exclude '<').
#
# POSIX ERE only (grep -E) for cross-platform parity — never grep -P (macOS BSD
# grep lacks it).
set -euo pipefail

# The per-OS regex BODIES (HPP_*) live in the path-detection component — the
# org-shared, standards-managed materialization — so a pattern change lands
# upstream once and reaches every scan driver in lockstep. This driver keeps
# only its own wrapping (the PATH_BOUNDARY prefix and git-grep execution).
#
# Relative layout is identical in-source (components/local-lane-guards →
# ../path-detection) and when synced beside path-detection-tools
# (tools/shared/local-lane-guards → ../path-detection).
# shellcheck source=../path-detection/machine-path-patterns.sh
source "${BASH_SOURCE[0]%/*}/../path-detection/machine-path-patterns.sh"

# Boundary for the slash-rooted macOS/Linux bodies so a substring like
# "doc/Users/guide" inside a longer word does not false-match.
PATH_BOUNDARY="(^|[[:space:]\"'\`(=]|file://)"
MACOS_PATTERN="${PATH_BOUNDARY}${HPP_MACOS_USER_BODY}"
LINUX_PATTERN="${PATH_BOUNDARY}${HPP_LINUX_USER_BODY}"

read -ra scan_paths <<<"${EXTENSIONS:-}"
read -ra excludes <<<"${EXCLUDE:-}"

failed=0
run_check() {
  local label=$1 pattern=$2 matches rc=0
  # Capture git grep's status separately so a fatal error (bad pathspec, blob
  # read failure: exit >=2) fails the gate CLOSED instead of looking like a
  # clean "no match". Exit 1 (no match) is the only non-zero treated as clean.
  # Piping straight to head would lose that status under pipefail + `|| true`.
  matches=$(git grep -nIE "$pattern" -- "${scan_paths[@]}" "${excludes[@]}") || rc=$?
  if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
    echo "::error::git grep failed (exit $rc) scanning for ${label} — refusing to pass without a full scan." >&2
    exit 1
  fi
  if [[ -n "$matches" ]]; then
    echo "Machine-specific path detected (${label}):" >&2
    # head caps display noise only; the scan status is already validated above.
    echo "$matches" | head -20 >&2 || true
    echo "" >&2
    failed=1
  fi
}

# OS home paths (placeholders excluded by the character class).
run_check "Windows user path" "$HPP_WIN_USER_BODY"
run_check "macOS user path" "$MACOS_PATTERN"
run_check "Linux user path" "$LINUX_PATTERN"

# Repo checkout roots (plain and escaped backslash forms).
run_check "Windows repo path" "$HPP_WIN_REPO_BODY"
run_check "Escaped Windows repo path" "$HPP_ESCAPED_WIN_REPO_BODY"

if [[ "$failed" -ne 0 ]]; then
  echo "Use portable placeholders (<repo-root>, <user>) or relative paths." >&2
  exit 1
fi

echo "No machine-specific absolute paths detected."
