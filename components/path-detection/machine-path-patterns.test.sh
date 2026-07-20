#!/usr/bin/env bash
# Tests the path-detection component: each shared body matches the machine-path
# shapes it exists to catch and stays clean on portable placeholder forms.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

# shellcheck source=components/path-detection/machine-path-patterns.sh
source components/path-detection/machine-path-patterns.sh

matches() { printf '%s' "$2" | grep -qE "$1"; }

# Windows user-home: plain, forward-slash, JSON-escaped, and 8.3 short-name.
matches "$HPP_WIN_USER_BODY" 'C:\Users\Alice\project'
assert_exit 'win user: backslash form is flagged' 0 "$?"
matches "$HPP_WIN_USER_BODY" 'C:/Users/alice/project'
assert_exit 'win user: forward-slash form is flagged' 0 "$?"
matches "$HPP_WIN_USER_BODY" 'C:\\Users\\Alice\\project'
assert_exit 'win user: JSON-escaped form is flagged' 0 "$?"
matches "$HPP_WIN_USER_BODY" 'C:\Users\ALICE~1\AppData'
assert_exit 'win user: 8.3 short-name form is flagged' 0 "$?"
matches "$HPP_WIN_USER_BODY" 'C:\Users\<user>\project'
assert_exit 'win user: <user> placeholder stays clean' 1 "$?"
# The single-quoted $env:USERNAME is the point: the probe is the literal
# PowerShell-expansion placeholder, which must stay clean.
# shellcheck disable=SC2016
matches "$HPP_WIN_USER_BODY" 'C:\Users\$env:USERNAME\project'
assert_exit 'win user: env-expansion form stays clean' 1 "$?"
matches "$HPP_WIN_USER_BODY" 'C:\Users\~\project'
assert_exit 'win user: bare tilde shorthand stays clean' 1 "$?"
matches "$HPP_WIN_USER_BODY" 'C:\Users\%USERNAME%\project'
assert_exit 'win user: percent-env user segment stays clean' 1 "$?"
matches "$HPP_WIN_USER_BODY" 'C:/Users/%USERPROFILE%/project'
assert_exit 'win user: percent-env forward-slash form stays clean' 1 "$?"

# macOS / Linux user-home bodies (drivers add their own boundary prefix).
matches "$HPP_MACOS_USER_BODY" '/Users/alice/project'
assert_exit 'macos user: real path is flagged' 0 "$?"
matches "$HPP_MACOS_USER_BODY" '/Users/<user>/project'
assert_exit 'macos user: placeholder stays clean' 1 "$?"
matches "$HPP_LINUX_USER_BODY" '/home/alice/project'
assert_exit 'linux user: real path is flagged' 0 "$?"
matches "$HPP_LINUX_USER_BODY" '/home/{user}/project'
assert_exit 'linux user: templated placeholder stays clean' 1 "$?"

# Repo-checkout roots: plain, forward-slash, 8.3, and the JSON-escaped body.
matches "$HPP_WIN_REPO_BODY" 'D:\repos\acme\project'
assert_exit 'win repo: backslash form is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:/repos/acme/project'
assert_exit 'win repo: forward-slash form is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:\repos\ACME~1\project'
assert_exit 'win repo: 8.3 short-name form is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:\repos\<repo-root>\x'
assert_exit 'win repo: placeholder stays clean' 1 "$?"
matches "$HPP_ESCAPED_WIN_REPO_BODY" 'D:\\repos\\acme\\project'
assert_exit 'win repo: JSON-escaped form is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:\repos\%BUILD_ID%\project'
assert_exit 'win repo: percent-env segment stays clean' 1 "$?"
matches "$HPP_ESCAPED_WIN_REPO_BODY" 'D:\\repos\\%BUILD_ID%\\project'
assert_exit 'win repo: JSON-escaped percent-env segment stays clean' 1 "$?"

# Bare roots (the home/checkout directory itself, no child path) are
# intentionally not matched: the trailing separator every body requires is its
# right boundary, so a match needs at least one child segment past the root.
# These assertions pin that non-match so it cannot silently regress.
matches "$HPP_WIN_USER_BODY" 'C:\Users\Alice'
assert_exit 'win user: bare root without child stays clean' 1 "$?"
matches "$HPP_MACOS_USER_BODY" '/Users/alice'
assert_exit 'macos user: bare root without child stays clean' 1 "$?"
matches "$HPP_LINUX_USER_BODY" '/home/alice'
assert_exit 'linux user: bare root without child stays clean' 1 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:\repos\acme'
assert_exit 'win repo: bare root without child stays clean' 1 "$?"
matches "$HPP_ESCAPED_WIN_REPO_BODY" 'D:\\repos\\acme'
assert_exit 'win repo: JSON-escaped bare root without child stays clean' 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
