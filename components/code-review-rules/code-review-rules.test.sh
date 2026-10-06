#!/usr/bin/env bash
# Tests code-review-rules.sh offline: every repository is a fixture directory,
# so no test needs a GitHub credential or the network.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/code-review-rules/code-review-rules.sh"
work="$(mktemp -d "$root/.code-review-rules-fixture.XXXXXX")"
if [[ -z "$work" ]]; then
  printf 'ERROR: could not create a scratch directory under %s\n' "$root" >&2
  exit 1
fi
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

intro='Each line names a rule CI does not enforce; the linked file states it in full.'
# shellcheck disable=SC2016 # literal Markdown backticks, not an expansion
synced='- Org-wide criteria: [`REVIEW.md`](REVIEW.md), synced from `melodic-software/standards`.'
# shellcheck disable=SC2016 # literal Markdown backticks, not an expansion
remote='- Org-wide criteria: [`REVIEW.md`](https://github.com/melodic-software/standards/blob/main/REVIEW.md) in `melodic-software/standards`.'

# repo <name> <agents-body|-> [review] — a fixture repository; `-` writes no
# AGENTS.md, and a third argument writes a root REVIEW.md.
repo() {
  mkdir -p "$work/fleet/$1"
  [[ "$2" == - ]] || printf '%s\n' "$2" >"$work/fleet/$1/AGENTS.md"
  [[ $# -lt 3 ]] || printf '# Review instructions\n' >"$work/fleet/$1/REVIEW.md"
}

section() {
  printf '# Repo\n\n## Code Review Rules\n\n%s\n\n%s\n- Local rule: [rule](docs/rule.md).\n\n## Next\n' "$1" "$2"
}

repo synced "$(section "$intro" "$synced")" review
repo remote "$(section "$intro" "$remote")"
repo no-agents -
repo no-heading '# Repo'
repo no-intro "$(section 'Some other intro.' "$synced")" review
repo no-pointer "$(section "$intro" '- Local rule: [rule](docs/rule.md).')" review
repo wrong-target "$(section "$intro" "$remote")" review
# shellcheck disable=SC2016 # literal Markdown backticks, not an expansion
stale='- Org-wide criteria: [`REVIEW.md`](docs/REVIEW.md), synced from `melodic-software/standards`.'
repo duplicate-stale "$(section "$intro" "$(printf '%s\n%s' "$synced" "$stale")")" review
repo duplicate-same "$(section "$intro" "$(printf '%s\n%s' "$synced" "$synced")")" review
repo duplicate-unlinked "$(section "$intro" "$(printf '%s\n%s' "$synced" '- Org-wide criteria: see the standards repository.')")" review
repo pointer-outside "$(printf '# Repo\n\n## Code Review Rules\n\n%s\n\n## Next\n\n%s\n' "$intro" "$synced")" review
# shellcheck disable=SC2016 # a literal Markdown fence, not an expansion
fence='```'
repo pointer-fenced "$(section "$intro" "$(printf '%smarkdown\n%s\n%s' "$fence" "$synced" "$fence")")" review
repo heading-fenced "$(printf '# Repo\n\n%smarkdown\n## Code Review Rules\n\n%s\n\n%s\n%s\n' "$fence" "$intro" "$synced" "$fence")" review
repo unclosed-fence "$(printf '# Repo\n\n%s\nsnippet\n\n' "$fence"; section "$intro" "$synced")" review
repo mixed-fences "$(printf '# Repo\n\n~~~text\n%s\n~~~\n\n' "$fence"; section "$intro" "$synced")" review
repo nested-fence "$(printf '# Repo\n\n%s`markdown\n%s\n' "$fence" "$fence"; section "$intro" "$synced"; printf '%s`\n' "$fence")" review

# --- file ------------------------------------------------------------------
out="$(bash "$script" file --root "$work/fleet/synced" 2>&1)"
assert_exit 'file passes a repo with the synced REVIEW.md pointer' 0 $?
assert_contains 'file reports agreement' "$out" 'OK:'

out="$(bash "$script" file --root "$work/fleet/remote" 2>&1)"
assert_exit 'file passes a repo without REVIEW.md that links the canonical copy' 0 $?

out="$(bash "$script" file --root "$work/fleet/no-agents" 2>&1)"
assert_exit 'file fails without a root AGENTS.md' 1 $?
assert_contains 'the missing file is named' "$out" 'no root AGENTS.md'

out="$(bash "$script" file --root "$work/fleet/no-heading" 2>&1)"
assert_exit 'file fails without the heading' 1 $?
assert_contains 'the missing heading is named' "$out" "no '## Code Review Rules' heading"

out="$(bash "$script" file --root "$work/fleet/no-intro" 2>&1)"
assert_exit 'file fails without the inherited intro line' 1 $?
assert_contains 'the missing intro is named' "$out" 'inherited intro line is missing'

out="$(bash "$script" file --root "$work/fleet/no-pointer" 2>&1)"
assert_exit 'file fails without the REVIEW.md pointer' 1 $?
assert_contains 'the missing pointer is named' "$out" 'REVIEW.md pointer line is missing'

out="$(bash "$script" file --root "$work/fleet/wrong-target" 2>&1)"
assert_exit 'file fails when a repo with REVIEW.md links the remote copy' 1 $?
assert_contains 'the expected target is named' "$out" 'must link REVIEW.md'

out="$(bash "$script" file --root "$work/fleet/duplicate-stale" 2>&1)"
assert_exit 'file fails when a stale pointer sits beside the correct one' 1 $?
assert_contains 'the duplicate pointer is counted' "$out" '2 org-wide criteria pointer lines, expected one'

out="$(bash "$script" file --root "$work/fleet/duplicate-same" 2>&1)"
assert_exit 'file fails when the correct pointer appears twice' 1 $?
assert_contains 'a repeated pointer is counted' "$out" '2 org-wide criteria pointer lines, expected one'

out="$(bash "$script" file --root "$work/fleet/duplicate-unlinked" 2>&1)"
assert_exit 'file fails when a second org-wide criteria line links nothing' 1 $?
assert_contains 'an unlinked second pointer is counted' "$out" '2 org-wide criteria pointer lines, expected one'

out="$(bash "$script" file --root "$work/fleet/pointer-outside" 2>&1)"
assert_exit 'file fails when the pointer sits under a later heading' 1 $?
assert_contains 'a pointer outside the section does not count' "$out" 'REVIEW.md pointer line is missing'

out="$(bash "$script" file --root "$work/fleet/pointer-fenced" 2>&1)"
assert_exit 'file fails when the pointer sits only in a fenced example' 1 $?
assert_contains 'a fenced pointer does not count' "$out" 'REVIEW.md pointer line is missing'

out="$(bash "$script" file --root "$work/fleet/heading-fenced" 2>&1)"
assert_exit 'file fails when the whole section sits in a fenced example' 1 $?
assert_contains 'a fenced heading does not count' "$out" "no '## Code Review Rules' heading"

out="$(bash "$script" file --root "$work/fleet/unclosed-fence" 2>&1)"
assert_exit 'file fails when an unclosed fence above swallows the section' 1 $?
assert_contains 'the unclosed fence is named as the cause' "$out" 'a code fence is never closed'

out="$(bash "$script" file --root "$work/fleet/mixed-fences" 2>&1)"
assert_exit 'a backtick fence inside a tilde fence does not close it' 0 $?

out="$(bash "$script" file --root "$work/fleet/nested-fence" 2>&1)"
assert_exit 'a shorter fence inside a four-backtick fence does not close it' 1 $?
assert_contains 'a section inside the longer fence does not count' "$out" "no '## Code Review Rules' heading"

# --- fleet -----------------------------------------------------------------
printf '%s\n' synced remote >"$work/ok.txt"
out="$(bash "$script" fleet --repos "$work/ok.txt" --fixtures "$work/fleet" 2>&1)"
assert_exit 'fleet passes when every repo conforms' 0 $?
assert_contains 'fleet lists the conforming repos' "$out" 'OK: remote synced'

printf '%s\n' synced no-agents wrong-target duplicate-stale '' >"$work/mixed.txt"
out="$(bash "$script" fleet --repos "$work/mixed.txt" --fixtures "$work/fleet" 2>&1)"
assert_exit 'fleet fails when any repo does not conform' 1 $?
assert_contains 'fleet names a repo without AGENTS.md' "$out" 'MISSING: no-agents: no root AGENTS.md'
assert_contains 'fleet names a repo with the wrong pointer' "$out" 'MISSING: wrong-target: the REVIEW.md pointer'
assert_contains 'fleet names a repo with a duplicate pointer' "$out" 'MISSING: duplicate-stale: 2 org-wide criteria pointer lines'
assert_contains 'fleet still lists the conforming repo' "$out" 'OK: synced'

# --- usage -----------------------------------------------------------------
bash "$script" bogus >/dev/null 2>&1
assert_exit 'an unknown command is a usage error' 2 $?
bash "$script" fleet --repos "$work/absent.txt" --fixtures "$work/fleet" >/dev/null 2>&1
assert_exit 'a missing repository list is a usage error' 2 $?
