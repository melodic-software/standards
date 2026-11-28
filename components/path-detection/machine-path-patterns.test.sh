#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

# shellcheck source=components/path-detection/machine-path-patterns.sh
source components/path-detection/machine-path-patterns.sh

matches() { printf '%s' "$2" | grep -qE "$1"; }

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
# shellcheck disable=SC2016
matches "$HPP_WIN_USER_BODY" 'C:\Users\$env:USERNAME\project'
assert_exit 'win user: env-expansion form stays clean' 1 "$?"
matches "$HPP_WIN_USER_BODY" 'C:\Users\~\project'
assert_exit 'win user: bare tilde shorthand stays clean' 1 "$?"
matches "$HPP_WIN_USER_BODY" 'C:\Users\%USERNAME%\project'
assert_exit 'win user: percent-env user segment stays clean' 1 "$?"
matches "$HPP_WIN_USER_BODY" 'C:/Users/%USERPROFILE%/project'
assert_exit 'win user: percent-env forward-slash form stays clean' 1 "$?"

span=$(printf '%s' 'C:\Users\build%2026\project' | grep -oE "$HPP_WIN_USER_BODY")
assert_eq 'win user: literal % stays inside the matched segment' 'C:\Users\build%2026' "$span"
span=$(printf '%s' '/Users/build%2026/project' | grep -oE "$HPP_MACOS_USER_BODY")
assert_eq 'macos user: literal % stays inside the matched segment' '/Users/build%2026' "$span"
span=$(printf '%s' '/home/build%2026/project' | grep -oE "$HPP_LINUX_USER_BODY")
assert_eq 'linux user: literal % stays inside the matched segment' '/home/build%2026' "$span"
matches "$HPP_MACOS_USER_BODY" '/Users/%USER%/project'
assert_exit 'macos user: percent-env segment stays clean' 1 "$?"
matches "$HPP_LINUX_USER_BODY" '/home/%USER%/project'
assert_exit 'linux user: percent-env segment stays clean' 1 "$?"

span=$(printf '%s' 'C:\Users\build-%USERNAME%\project' | grep -oE "$HPP_WIN_USER_BODY")
assert_eq 'win user: embedded percent-env token is not claimed' 'C:\Users\build-' "$span"
span=$(printf '%s' 'D:\repos\build-%BUILD_ID%\project' | grep -oE "$HPP_WIN_REPO_BODY")
assert_eq 'win repo: embedded percent-env token is not claimed' 'D:\repos\build-' "$span"

matches "$HPP_MACOS_USER_BODY" '/Users/alice/project'
assert_exit 'macos user: real path is flagged' 0 "$?"
matches "$HPP_MACOS_USER_BODY" '/Users/<user>/project'
assert_exit 'macos user: placeholder stays clean' 1 "$?"
matches "$HPP_LINUX_USER_BODY" '/home/alice/project'
assert_exit 'linux user: real path is flagged' 0 "$?"
matches "$HPP_LINUX_USER_BODY" '/home/{user}/project'
assert_exit 'linux user: templated placeholder stays clean' 1 "$?"

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
span=$(printf '%s' 'D:\repos\build%2026\project' | grep -oE "$HPP_WIN_REPO_BODY")
assert_eq 'win repo: literal % stays inside the matched segment' 'D:\repos\build%2026' "$span"
span=$(printf '%s' 'D:\\repos\\build%2026\\project' | grep -oE "$HPP_ESCAPED_WIN_REPO_BODY")
assert_eq 'win repo: JSON-escaped literal % stays inside the matched segment' 'D:\\repos\\build%2026' "$span"

matches "$HPP_WIN_REPO_BODY" 'C:\Projects\acme\project'
assert_exit 'win repo: Projects root is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:\dev\acme\project'
assert_exit 'win repo: dev root is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:/Dev/acme/project'
assert_exit 'win repo: Dev root forward-slash form is flagged' 0 "$?"
matches "$HPP_ESCAPED_WIN_REPO_BODY" 'C:\\Projects\\acme\\project'
assert_exit 'win repo: JSON-escaped Projects root is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'C:\Projects\<repo-root>\x'
assert_exit 'win repo: Projects placeholder stays clean' 1 "$?"

matches "$HPP_WIN_USER_BODY" 'C:\Users\Alice'
assert_exit 'win user: bare home value is flagged' 0 "$?"
matches "$HPP_MACOS_USER_BODY" '/Users/alice'
assert_exit 'macos user: bare home value is flagged' 0 "$?"
matches "$HPP_LINUX_USER_BODY" '/home/alice'
assert_exit 'linux user: bare home value is flagged' 0 "$?"
matches "$HPP_WIN_REPO_BODY" 'root = C:/Dev/GitHub'
assert_exit 'win repo: bare checkout value at EOL is flagged' 0 "$?"
matches "$HPP_ESCAPED_WIN_REPO_BODY" 'D:\\repos\\acme'
assert_exit 'win repo: JSON-escaped bare checkout value is flagged' 0 "$?"

matches "$HPP_WIN_USER_BODY" 'C:\Users'
assert_exit 'win user: parent root alone stays clean' 1 "$?"
matches "$HPP_WIN_REPO_BODY" 'D:/repos/'
assert_exit 'win repo: parent root alone stays clean' 1 "$?"

matches "$HPP_MACOS_USER_BODY" '/Users/ for details see the guide'
assert_exit 'macos user: root then whitespace prose stays clean' 1 "$?"
span=$(printf '%s' 'C:/Projects/melodic - personal repos (reference/reading only)' | grep -oE "$HPP_WIN_REPO_BODY")
assert_eq 'win repo: prose match is the path token, never a greedy span' 'C:/Projects/melodic' "$span"

[[ $FAILED -eq 0 ]] || exit 1
