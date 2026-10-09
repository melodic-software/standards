#!/usr/bin/env bash
# Tests org-architecture-pointer.sh offline: every repository is a fixture
# directory, so no test needs a GitHub credential or the network.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/org-architecture-pointer/org-architecture-pointer.sh"
work="$(mktemp -d)"
if [[ -z "$work" ]]; then
  printf 'ERROR: could not create a scratch directory\n' >&2
  exit 1
fi
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# repo <name> <file> <body> — a fixture repository holding one file.
repo() {
  mkdir -p "$work/fleet/$1"
  printf '%s\n' "$3" >"$work/fleet/$1/$2"
}

# shellcheck disable=SC2016 # literal Markdown backticks, not an expansion
pointer='Org architecture: private repo `melodic-software/architecture`.'
repo in-agents AGENTS.md "$pointer"
repo in-claude CLAUDE.md "$pointer"
repo in-both AGENTS.md "$pointer"
repo in-both CLAUDE.md "$pointer"
repo shim-only CLAUDE.md '@AGENTS.md'
repo agents-without AGENTS.md '# Repo'
repo neither README.md 'melodic-software/architecture'
mkdir -p "$work/fleet/empty"
repo near-miss AGENTS.md 'melodic-software/architectures-of-others and melodic-software/architecture-x'
repo bare-line AGENTS.md 'See melodic-software/architecture'

# --- file ------------------------------------------------------------------
out="$(bash "$script" file --root "$work/fleet/in-agents" 2>&1)"
assert_exit 'file passes when AGENTS.md names the repo' 0 $?
assert_contains 'file reports the match' "$out" 'OK:'

out="$(bash "$script" file --root "$work/fleet/in-claude" 2>&1)"
assert_exit 'file passes when only CLAUDE.md names the repo' 0 $?

out="$(bash "$script" file --root "$work/fleet/agents-without" 2>&1)"
assert_exit 'file fails when AGENTS.md lacks the substring' 1 $?
assert_contains 'the missing substring is named' "$out" 'melodic-software/architecture'

out="$(bash "$script" file --root "$work/fleet/shim-only" 2>&1)"
assert_exit 'file fails when only a CLAUDE.md shim exists' 1 $?

out="$(bash "$script" file --root "$work/fleet/neither" 2>&1)"
assert_exit 'file ignores other files that name the repo' 1 $?

out="$(bash "$script" file --root "$work/fleet/empty" 2>&1)"
assert_exit 'file fails when neither file exists' 1 $?

out="$(bash "$script" file --root "$work/fleet/near-miss" 2>&1)"
assert_exit 'file fails on a longer repository name sharing the prefix' 1 $?

out="$(bash "$script" file --root "$work/fleet/bare-line" 2>&1)"
assert_exit 'file passes when the name ends the line' 0 $?

# --- fleet -----------------------------------------------------------------
printf '%s\n' in-agents in-claude in-both bare-line >"$work/ok.txt"
out="$(bash "$script" fleet --repos "$work/ok.txt" --fixtures "$work/fleet" 2>&1)"
assert_exit 'fleet passes when every repo conforms' 0 $?
assert_contains 'fleet lists the conforming repos' "$out" 'OK: bare-line in-agents in-both in-claude'

printf '%s\n' in-agents shim-only agents-without neither empty near-miss '' >"$work/mixed.txt"
out="$(bash "$script" fleet --repos "$work/mixed.txt" --fixtures "$work/fleet" 2>&1)"
assert_exit 'fleet fails when any repo does not conform' 1 $?
assert_contains 'fleet names a shim-only repo' "$out" 'MISSING: shim-only:'
assert_contains 'fleet names a repo without the substring' "$out" 'MISSING: agents-without:'
assert_contains 'fleet names a longer-name near miss' "$out" 'MISSING: near-miss:'
assert_contains 'fleet names a repo with neither file' "$out" 'MISSING: empty:'
assert_contains 'fleet still lists the conforming repo' "$out" 'OK: in-agents'

# --- names -----------------------------------------------------------------
# The listing filter both fleet listings apply: sandbox anywhere in the
# topics, archived, the architecture repo itself, and absent or null topics.
listing='[
  {"name": "kept", "archived": false, "topics": ["testing"]},
  {"name": "sandbox-first", "archived": false, "topics": ["sandbox", "testing"]},
  {"name": "archived", "archived": true, "topics": []},
  {"name": "architecture", "archived": false, "topics": []},
  {"name": "no-topics", "archived": false},
  {"name": "null-topics", "archived": false, "topics": null}
]'
expected="$(printf '%s\n' kept no-topics null-topics)"
out="$(printf '%s\n' "$listing" | bash "$script" names 2>&1)"
assert_exit 'names reads a JSON array' 0 $?
assert_eq 'names keeps only audited repositories' "$expected" "$out"
out="$(printf '%s\n' "$listing" | jq -c '.[]' | bash "$script" names 2>&1)"
assert_eq 'names reads a stream of objects, as gh --jq emits' "$expected" "$out"

# --- usage -----------------------------------------------------------------
bash "$script" bogus >/dev/null 2>&1
assert_exit 'an unknown command is a usage error' 2 $?
bash "$script" fleet --repos "$work/absent.txt" --fixtures "$work/fleet" >/dev/null 2>&1
assert_exit 'a missing repository list is a usage error' 2 $?

[[ $FAILED -eq 0 ]] || exit 1
