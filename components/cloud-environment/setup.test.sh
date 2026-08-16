#!/usr/bin/env bash
# Tests the cloud-environment component: the canonical setup script parses,
# honors its ordering contract (the completion stamp is written only after the
# parallel install tracks finish), and the README documents the same bootstrap
# URL and stamp path the script implements — the drift a copy-paste consumer
# would actually hit.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/cloud-environment/setup.sh"
readme="$root/components/cloud-environment/README.md"

bash -n "$script" 2>/dev/null
rc=$?
assert_exit 'setup.sh parses (bash -n)' 0 "$rc"

tail -n 1 "$script" | grep -qx 'exit 0'
rc=$?
assert_exit 'setup.sh ends with exit 0 (cache-build contract)' 0 "$rc"

# Ordering contract: the stamp write must come after the `wait` barrier, so an
# interrupted build can never leave a stamp behind.
wait_ln="$(grep -n '^wait$' "$script" | head -n 1 | cut -d: -f1)"
stamp_ln="$(grep -n '>"[$]STAMP"' "$script" | head -n 1 | cut -d: -f1)"
if [[ -n "$wait_ln" && -n "$stamp_ln" && "$stamp_ln" -gt "$wait_ln" ]]; then
  pass 'completion stamp is written only after the wait barrier'
else
  fail 'completion stamp is written only after the wait barrier' \
    "wait at line '${wait_ln:-none}', stamp write at line '${stamp_ln:-none}'"
fi

# Pin lockstep: the warm-cache Node version the script installs must match the
# fleet pin this repository itself carries in .node-version — the drift the
# README's update-lifecycle section otherwise leaves to manual diligence. (The
# .NET version list has no in-repo manifest to check against; it stays a
# documented manual obligation.)
node_pin_repo="$(tr -d '[:space:]' <"$root/.node-version")"
node_pin_script="$(sed -n 's/.*nvm install \([0-9][0-9.]*\).*/\1/p' "$script" | head -n 1)"
if [[ -n "$node_pin_script" ]]; then
  pass 'setup.sh declares a Node pin (nvm install <version>)'
else
  fail 'setup.sh declares a Node pin (nvm install <version>)' \
    'no "nvm install <version>" line found'
fi
assert_eq 'setup.sh Node pin matches the repo .node-version' \
  "$node_pin_repo" "$node_pin_script"

# README/script drift guards.
stamp_path="$(sed -n "s/^STAMP='\(.*\)'\$/\1/p" "$script")"
if [[ -n "$stamp_path" ]]; then
  pass 'setup.sh declares a stamp path'
else
  fail 'setup.sh declares a stamp path' "no STAMP='...' assignment found"
fi
assert_contains 'README documents the stamp path the script writes' \
  "$(cat "$readme")" "$stamp_path"
assert_contains 'README bootstrap URL matches the component path' \
  "$(cat "$readme")" \
  'raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/setup.sh'

[[ $FAILED -eq 0 ]] || exit 1
