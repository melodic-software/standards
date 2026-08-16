#!/usr/bin/env bash
# Tests the cloud-bootstrap component: the canonical script parses, stays
# generic (no repo or marketplace identifiers — everything is data-driven from
# the consuming repo's own manifests), keeps its calling-contract landmarks
# (cloud-only guard, enrich seam, hook-output JSON), reads the same
# environment stamp the cloud-environment component writes, and this
# repository's own materialized copy is byte-identical to the component —
# standards is the manifest source, not a sync target, so this equality is
# what stands in for the synchronizer here.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/cloud-bootstrap/cloud-bootstrap.sh"
materialized="$root/.claude/cloud-bootstrap.sh"
readme="$root/components/cloud-bootstrap/README.md"
env_setup="$root/components/cloud-environment/setup.sh"

bash -n "$script" 2>/dev/null
rc=$?
assert_exit 'cloud-bootstrap.sh parses (bash -n)' 0 "$rc"

cmp -s "$script" "$materialized"
rc=$?
assert_exit 'repo .claude/cloud-bootstrap.sh is byte-identical to the component' 0 "$rc"

# Generic-by-construction: the canonical script must not name a marketplace,
# a repository, or a pinned tool version — those live in each repo's own
# manifests and settings, or in its cloud-bootstrap.local.sh extension.
if grep -qE 'claude-code-plugins|marketplace=|source_repo=' "$script"; then
  fail 'canonical script carries no hardcoded marketplace or repo identifiers' \
    "$(grep -nE 'claude-code-plugins|marketplace=|source_repo=' "$script" | head -n 3)"
else
  pass 'canonical script carries no hardcoded marketplace or repo identifiers'
fi

assert_contains 'cloud-only guard present (CLAUDE_CODE_REMOTE)' \
  "$(cat "$script")" 'CLAUDE_CODE_REMOTE'
assert_contains 'enrich seam runs .claude/cloud-bootstrap.local.sh' \
  "$(cat "$script")" '.claude/cloud-bootstrap.local.sh'
assert_contains 'SessionStart hook output JSON is emitted' \
  "$(cat "$script")" 'hookSpecificOutput'

# Cross-component lockstep: the environment stamp this script reports is the
# stamp path the cloud-environment component declares and writes.
stamp_path="$(sed -n "s/^STAMP='\(.*\)'\$/\1/p" "$env_setup")"
if [[ -n "$stamp_path" ]]; then
  pass 'cloud-environment setup.sh declares a stamp path'
else
  fail 'cloud-environment setup.sh declares a stamp path' \
    "no STAMP='...' assignment found"
fi
assert_contains 'bootstrap reads the stamp path cloud-environment writes' \
  "$(cat "$script")" "$stamp_path"

# README/script drift guards.
assert_contains 'README documents the materialized path' \
  "$(cat "$readme")" '.claude/cloud-bootstrap.sh'
assert_contains 'README documents the enrich seam filename' \
  "$(cat "$readme")" '.claude/cloud-bootstrap.local.sh'

[[ $FAILED -eq 0 ]] || exit 1
