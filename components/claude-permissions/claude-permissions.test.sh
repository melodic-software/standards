#!/usr/bin/env bash
# Guards the withdraw-tombstone contract the README states: `allow` and
# `withdraw` stay disjoint (the composer subtracts `withdraw` after its union,
# so a row present in both is evicted on the next apply — a regrant that
# forgets to delete its tombstone is silently defeated), and every tombstone
# is a non-empty exact string. Fails the build here instead of on the fleet.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

if ! command -v jq >/dev/null 2>&1; then
  skip_suite 'jq not installed'
fi

config="components/claude-permissions/claude-permissions.json"

# in_list <list> <row> — succeeds when .claudePermissions.<list> holds <row>.
in_list() {
  jq -e --arg list "$1" --arg row "$2" \
    '.claudePermissions[$list] | index($row) != null' "$config" >/dev/null
}

# require_rows <list> <detail> <row>... — each row must be present.
require_rows() {
  local list="$1" detail="$2" row
  shift 2
  for row in "$@"; do
    if in_list "$list" "$row"; then
      pass "$list includes $row"
    else
      fail "$list includes $row" "$detail"
    fi
  done
}

# forbid_deny_rows <detail> <row>... — each row must be absent from deny.
forbid_deny_rows() {
  local detail="$1" row
  shift
  for row in "$@"; do
    if in_list deny "$row"; then
      fail "deny omits $row" "$detail"
    else
      pass "deny omits $row"
    fi
  done
}

# assert_none <label> <detail> <rows> — pass when <rows> is empty.
assert_none() {
  if [[ -n "$3" ]]; then
    fail "$1" "$2: $3"
  else
    pass "$1"
  fi
}

schema_version="$(jq -r '.claudePermissions.schemaVersion' "$config")"
assert_eq "schemaVersion is the supported value" "1" "$schema_version"

# The cloud-environment composer (components/cloud-environment/setup.sh)
# unions these rows into a live settings file and refuses a floor whose rows
# are not strings or whose deny half is empty, which would leave cloud sessions
# with no floor at all.
composable="$(jq -r '.claudePermissions
  | (.allow | type == "array") and (.deny | type == "array" and length > 0)
    and ([.allow[], .deny[]] | all(type == "string" and length > 0))' "$config")"
assert_eq "allow and deny are non-empty-string rows with a non-empty deny" "true" "$composable"

empty_tombstones="$(jq -r '[.claudePermissions.withdraw[] | select((type != "string") or (. == ""))] | length' "$config")"
assert_eq "every withdraw entry is a non-empty string" "0" "$empty_tombstones"

overlap="$(jq -r '(.claudePermissions.allow // []) as $allow
  | [(.claudePermissions.withdraw // [])[] | select(. as $row | $allow | index($row))]
  | join("\n")' "$config")"
assert_none 'allow and withdraw are disjoint' \
  'rows present in both (regrant must delete its tombstone)' "$overlap"

# Restore denies cover only the whole-tree discards (`.`, `:/`). Path-scoped
# `git restore -- <path>` has no allow row, so the classifier judges it, and a
# bare `git restore *` catch-all would also deny `git restore --staged <path>`.
require_rows deny 'missing required restore discard rule' \
  'Bash(git restore .)' \
  'Bash(git restore :/)' \
  'PowerShell(git restore .)' \
  'PowerShell(git restore :/)' \
  'PowerShell(git * restore .)' \
  'PowerShell(git * restore :/)'

# `-n` is the short form of `--no-verify`; the glob forms `commit -n` alone
# cannot match when other arguments precede the flag.
require_rows deny 'missing required --no-verify short-form rule' \
  'Bash(git commit * -n *)' \
  'Bash(git commit * -n)' \
  'Bash(git commit -n *)' \
  'Bash(git commit -n)'

# The Bash LEFTHOOK denies anchor on the inline-env spelling (`LEFTHOOK=0 cmd`),
# which PowerShell lacks; its bypass shapes reference the env var by name:
#   $env:LEFTHOOK = '0'; git commit …
#   Set-Item env:LEFTHOOK 0; git commit …
#   ${env:LEFTHOOK} = "false"; git commit …
#   Set-Item -Path Env:\LEFTHOOK -Value 0; git commit …
#   [Environment]::SetEnvironmentVariable('LEFTHOOK', '0')
# PowerShell rule matching is case-insensitive
# (https://code.claude.com/docs/en/permissions), so `*:lefthook*` covers every
# drive-qualified form in any casing, `*env:*lefthook*` the provider path with a
# separator (`Env:\LEFTHOOK`), and `*SetEnvironmentVariable*LEFTHOOK*`
# covers the .NET call. A bare `*LEFTHOOK*` row is not used: case-insensitive, it
# also denies reading lefthook.yml. `*lefthook* uninstall*` denies removing the hooks.
require_rows deny 'missing required lefthook bypass rule' \
  'Bash(LEFTHOOK*=0 *)' \
  'Bash(LEFTHOOK*=FALSE *)' \
  'Bash(LEFTHOOK*=false *)' \
  'PowerShell(*:lefthook*)' \
  'PowerShell(*SetEnvironmentVariable*LEFTHOOK*)' \
  'PowerShell(*env:*lefthook*)' \
  'PowerShell(*lefthook* uninstall*)'

# Worktree removal: only the double force (which overrides a claim lock) is
# denied. A single-force deny would pre-empt the classifier, and any allow row
# would bypass its session-created check. Both allow spellings stay tombstoned.
require_rows deny 'missing required double-force worktree rule' \
  'Bash(git *worktree remove*--force --force*)' \
  'Bash(git *worktree remove*--force -f*)' \
  'Bash(git *worktree remove*-f --force*)' \
  'Bash(git *worktree remove*-f -f*)' \
  'PowerShell(git *worktree remove*--force --force*)' \
  'PowerShell(git *worktree remove*--force -f*)' \
  'PowerShell(git *worktree remove*-f --force*)' \
  'PowerShell(git *worktree remove*-f -f*)'

require_rows withdraw 'worktree removal is judged by the classifier' \
  'Bash(git worktree remove *)' 'PowerShell(git worktree remove *)'

# The double-force rows are `git *worktree remove...`; the `git ` anchor keeps
# unrelated commands that merely contain the text out of the deny. Claude's `*`
# matches any text, so the cases below translate each row to a regex.
glob_to_regex() { printf '^%s$' "$(printf '%s' "$1" | sed -e 's/[.[\^$+?(){}|]/\\&/g' -e 's/\*/.*/g')"; }
while IFS= read -r row; do
  body="${row#*(}"
  re="$(glob_to_regex "${body%)}")"
  flags="${body#*remove*}"
  flags="${flags#\*}"
  flags="${flags%\*)}"
  flags="${flags%\*}"
  for cmd in "git worktree remove $flags /tmp/wt" "git -C /repo worktree remove $flags /tmp/wt"; do
    if [[ "$cmd" =~ $re ]]; then pass "$row matches: $cmd"; else fail "$row matches: $cmd" "git form not matched"; fi
  done
  for cmd in 'grep "worktree remove --force --force" notes.md' "printf 'worktree remove -f -f'" \
    'rg "worktree remove --force -f" .' "echo 'worktree remove -f --force'"; do
    if [[ "$cmd" =~ $re ]]; then fail "$row skips: $cmd" 'unrelated command matched'; else pass "$row skips: $cmd"; fi
  done
done < <(jq -r '.claudePermissions.deny[] | select(test("^(Bash|PowerShell)\\(git \\*worktree remove"))' "$config")

# A deny row with `git worktree remove` as a literal prefix is a retired
# single-force spelling.
single_force="$(jq -r '[.claudePermissions.deny[] | select(test("^(Bash|PowerShell)\\(git worktree remove"))] | join("\n")' "$config")"
assert_none 'deny has no single-force worktree rows' 'retired rows returned' "$single_force"

forbid_deny_rows 'retired deny must not return' \
  'Bash(gh pr merge --auto *)' \
  'Bash(gh pr merge --auto)'

# settings.local.json is personal overrides, not a credential store, and a
# Read deny also blocks Edit — those rows must not return.
#
# The two .claude.json rows were retired for the same mechanical reason: a Read
# deny blocks Edit and Write on the same path, so they blocked the documented way
# to manage the file, not just reads of it. Official docs also record that a
# Read/Edit denial does not apply to a subprocess that opens the file itself, so
# the rows never denied a determined reader — they only denied the first-class
# tools. `Read()` rules are path/glob only, so no rule could keep the OAuth and
# MCP fields denied while exposing the rest; the file is protected by operator
# judgment rather than by a rule that could not express the distinction.
forbid_deny_rows 'retired Read deny must not return' \
  'Read(**/.claude/settings.local.json)' \
  'Read(.claude/settings.local.json)' \
  'Read(**/.claude.json)' \
  'Read(~/.claude.json)'

# Routine gh SDLC work is allowed in both shells, while admin, merge-commit and rebase merges, bypass_rules, repository
# and gist deletion, and token disclosure stay denied. The allow rows must not
# reach gh api writes, secrets, rulesets, workflow dispatch, reruns or releases.
# `matching_rows <surface> <shell> <command>` prints every row of that surface
# and shell matching the command; PowerShell rules match case-insensitively
# (https://code.claude.com/docs/en/permissions).
matching_rows() {
  local surface="$1" shell="$2" cmd="$3" row body re
  while IFS= read -r row; do
    body="${row#*(}"
    re="$(glob_to_regex "${body%)}")"
    if [[ "$shell" == PowerShell ]]; then shopt -s nocasematch; fi
    if [[ "$cmd" =~ $re ]]; then printf '%s\n' "$row"; fi
    shopt -u nocasematch
  done < <(jq -r --arg surface "$surface" --arg shell "$shell(" \
    '.claudePermissions[$surface][] | select(startswith($shell))' "$config")
}

for shell in Bash PowerShell; do
  # `-R OWNER/REPO` must survive the short `-r` denies, which PowerShell
  # matches case-insensitively.
  for cmd in 'gh pr merge 1 -R melodic-software/x --squash --auto' 'gh pr merge -R melodic-software/x 1 --squash' \
    'gh pr merge 1 --squash --auto -R melodic-software/x' 'gh pr merge 1 -R melodic-software/x -d --squash' \
    'gh pr close 1' 'gh pr ready 1' \
    'gh pr reopen 1' 'gh pr update-branch 1' 'gh issue develop 1' 'gh run cancel 1' 'gh workflow view ci.yml'; do
    if [[ -n "$(matching_rows allow "$shell" "$cmd")" && -z "$(matching_rows deny "$shell" "$cmd")" ]]; then
      pass "$shell allows: $cmd"
    else
      fail "$shell allows: $cmd" 'routine gh row missing or denied'
    fi
  done
  for cmd in 'gh pr merge 1 -R melodic-software/x --squash --admin' 'gh pr merge --admin 1' \
    'gh pr merge 1 --merge' 'gh pr merge 1 --rebase' 'gh pr merge 1 -m' 'gh pr merge 1 -r' \
    'gh pr merge 1 -m --auto' 'gh pr merge 1 -r --auto' 'gh pr merge -m 1' 'gh pr merge -r --auto 1' \
    'gh pr merge 1 -R melodic-software/x -r --auto' 'gh repo delete o/r --yes' 'gh gist delete 1' \
    'gh auth token' 'gh auth token --hostname github.com' 'gh auth status --show-token' 'gh auth status -t' \
    'gh api -X PUT repos/o/r/pulls/1/merge-async -f bypass_rules=true'; do
    if [[ -n "$(matching_rows deny "$shell" "$cmd")" ]]; then
      pass "$shell denies: $cmd"
    else
      fail "$shell denies: $cmd" 'no deny row matches'
    fi
  done
  for cmd in 'gh api -X POST repos/o/r/issues' 'gh secret set TOKEN' 'gh ruleset create' \
    'gh workflow run deploy.yml' 'gh run rerun 1' 'gh release create v1.0.0' 'gh auth status'; do
    rows="$(matching_rows allow "$shell" "$cmd")"
    if [[ -z "$rows" ]]; then
      pass "$shell leaves to the classifier: $cmd"
    else
      fail "$shell leaves to the classifier: $cmd" "allowed by: $rows"
    fi
  done
done

# Sessions run git as `git -C <dir> <subcommand>`, which no `Bash(git
# <subcommand> ...)` row matches, so each such deny row needs its
# `Bash(git -C * <subcommand> ...)` twin or a -C spelling escapes it. No allow
# row takes that form: the `*` after `-C` also spans git's global options
# (`-c core.hooksPath=`, `-c core.sshCommand=`), so a -C allow would approve
# more than its plain row, and -C commands go to the classifier instead.
missing_twins="$(jq -r '.claudePermissions.deny | . as $deny
  | .[] | select(test("^Bash\\(git [a-z][a-z-]*"))
  | sub("^Bash\\(git "; "Bash(git -C * ") | select(. as $t | $deny | index($t) | not)' "$config")"
assert_none 'every Bash git deny row has its git -C twin' 'add these rows' "$missing_twins"
c_allows="$(jq -r '[.claudePermissions.allow[] | select(startswith("Bash(git -C "))] | join("\n")' "$config")"
assert_none 'allow has no git -C rows' 'its * spans git global options' "$c_allows"
for cmd in 'git -C /repo worktree add -B b /tmp/wt' 'git -C /repo push --force origin b' \
  'git -C /repo -c core.hooksPath=/dev/null commit -m x' 'git -C /repo -c core.sshCommand=x fetch origin' \
  'git -C /repo --config-env=core.sshCommand=E push origin b' 'git -C /repo --exec-path=/tmp/x pull'; do
  if [[ -n "$(matching_rows deny Bash "$cmd")" ]]; then
    pass "Bash denies: $cmd"
  else
    fail "Bash denies: $cmd" 'no deny row matches the -C form'
  fi
done
for cmd in 'git -C /repo commit -F msg.txt' 'git -C /repo switch -c feature'; do
  if [[ -z "$(matching_rows deny Bash "$cmd")" ]]; then
    pass "Bash leaves to the classifier: $cmd"
  else
    fail "Bash leaves to the classifier: $cmd" 'a deny row matches a routine -C form'
  fi
done

# `git worktree add --force` checks out a branch another worktree already holds,
# or reuses a registered path, which can clobber a peer session's worktree.
for shell in Bash PowerShell; do
  for cmd in 'git worktree add --force /tmp/wt b' 'git worktree add -f /tmp/wt b' \
    'git worktree add /tmp/wt b --force' 'git worktree add /tmp/wt -f b'; do
    if [[ -n "$(matching_rows deny "$shell" "$cmd")" ]]; then
      pass "$shell denies: $cmd"
    else
      fail "$shell denies: $cmd" 'no deny row matches worktree add with force'
    fi
  done
done
for cmd in 'git -C /repo worktree add --force /tmp/wt b' 'git -C /repo worktree add /tmp/wt -f b'; do
  if [[ -n "$(matching_rows deny Bash "$cmd")" ]]; then
    pass "Bash denies: $cmd"
  else
    fail "Bash denies: $cmd" 'no deny row matches the -C form'
  fi
done
if [[ -z "$(matching_rows deny Bash 'git worktree add -b feature /tmp/wt origin/main')" ]]; then
  pass 'Bash leaves a plain worktree add alone'
else
  fail 'Bash leaves a plain worktree add alone' 'a force deny row matches a worktree add without force'
fi

[[ $FAILED -eq 0 ]] || exit 1
