#!/usr/bin/env bash
# Tests the commit-convention component: the convention file's types equal the
# pr-convention-policy `title.allowedTypes` and the `types` default of the
# ci-workflows check-contract action at the ref this repository pins; the
# guardrails resolver reads the file at its well-known path when it is tracked;
# the guardrails commit-msg hook accepts and rejects the expected subjects; and
# this repository's own copy at that path is byte-identical to the component.
# standards is the manifest source, not a sync target, so that equality stands
# in for the synchronizer here.
#
# Needs the pr-convention-policy dependencies (`npm ci --prefix
# components/pr-convention-policy`) for the YAML parser, and network access to
# read the pinned check-contract action. A failed fetch fails the suite.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

source_file="$root/components/commit-convention/commit-convention.yml"
well_known="docs/conventions/source-control/commit-convention.yml"
resolver="$root/.githooks/guardrails/resolve-convention-pattern.sh"
hook="$root/.githooks/guardrails/commit-msg-convention.sh"
policy="$root/components/pr-convention-policy/policy.json"
yaml_package="$root/components/pr-convention-policy/package.json"

# Node one-liners resolve `yaml` from the pr-convention-policy dependencies.
node_eval() {
  node -e "const yaml = require('module').createRequire(process.argv[1])('yaml');
const fs = require('fs');
$1" "$yaml_package" "${@:2}"
}

# Comma-joined, sorted types.
sorted_csv() { tr ',' '\n' | sed '/^$/d' | LC_ALL=C sort | paste -sd, -; }

# --- The file itself ---
parsed="$(node_eval 'const d = yaml.parse(fs.readFileSync(process.argv[2], "utf8"));
process.stdout.write(JSON.stringify([d.dialect, d.subject_pattern, d.pr_title_pattern]));' "$source_file")"
rc=$?
assert_exit 'the convention file parses as YAML' 0 "$rc"
dialect="$(node -e 'process.stdout.write(JSON.parse(process.argv[1])[0] ?? "")' "$parsed")"
pattern="$(node -e 'process.stdout.write(JSON.parse(process.argv[1])[1] ?? "")' "$parsed")"
pr_title="$(node -e 'process.stdout.write(JSON.parse(process.argv[1])[2] ?? "")' "$parsed")"
assert_eq 'dialect is posix-ere' 'posix-ere' "$dialect"
# shellcheck disable=SC2016  # the backticks are literal: the resolver's deferral marker
assert_eq 'pr_title_pattern defers to subject_pattern' 'Same as `subject_pattern`.' "$pr_title"
if [[ "$pattern" == *"'"* ]]; then
  fail 'subject_pattern holds no single quote' 'the resolver strips one quote pair and does no escape processing'
else
  pass 'subject_pattern holds no single quote'
fi

cmp -s "$source_file" "$root/$well_known"
rc=$?
assert_exit "this repository's $well_known is byte-identical to the component" 0 "$rc"
git -C "$root" ls-files --error-unmatch -- "$well_known" >/dev/null 2>&1
rc=$?
assert_exit "this repository tracks $well_known" 0 "$rc"

# --- Types lockstep ---
file_types="$(sed -E -n 's/^\^\(\(([a-z|]+)\).*/\1/p' <<<"$pattern" | tr '|' ',' | sorted_csv)"
if [[ -n "$file_types" ]]; then
  pass 'the type alternation is extractable from subject_pattern'
else
  fail 'the type alternation is extractable from subject_pattern' "pattern: $pattern"
fi
policy_types="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).title.allowedTypes.join(","))' "$policy" | sorted_csv)"
assert_eq 'types equal pr-convention-policy title.allowedTypes' "$policy_types" "$file_types"

require_scope="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).title.requireScope))' "$policy")"
assert_eq 'pr-convention-policy keeps the scope optional, as the pattern does' 'false' "$require_scope"

contract_pin="$(sed -E -n 's#^ *uses: melodic-software/ci-workflows/\.github/actions/pr-require-checks/check-contract@([0-9a-f]{40}).*#\1#p' \
  "$root/.github/workflows/pr-require-checks.yml" | sort -u)"
if [[ "$contract_pin" =~ ^[0-9a-f]{40}$ ]]; then
  pass 'pr-require-checks.yml pins one check-contract SHA'
else
  fail 'pr-require-checks.yml pins one check-contract SHA' "got: $contract_pin"
fi
action_yml="$TEST_TMPDIR/check-contract-action.yml"
auth=()
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
[[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
if curl -fsSL "${auth[@]+"${auth[@]}"}" -H 'Accept: application/vnd.github.raw' \
  "https://api.github.com/repos/melodic-software/ci-workflows/contents/.github/actions/pr-require-checks/check-contract/action.yml?ref=$contract_pin" \
  -o "$action_yml"; then
  pass "fetched check-contract action.yml at ${contract_pin:0:7}"
  action_types="$(node_eval 'const d = yaml.parse(fs.readFileSync(process.argv[2], "utf8"));
process.stdout.write(String(d?.inputs?.types?.default ?? ""));' "$action_yml" | sorted_csv)"
  assert_eq "types equal the check-contract types default at ${contract_pin:0:7}" "$action_types" "$file_types"
else
  fail "fetched check-contract action.yml at ${contract_pin:0:7}" 'fetch-error: the contents API read failed'
fi

# --- The resolver reads the tracked file at the well-known path ---
repo="$TEST_TMPDIR/consumer"
make_repo "$repo"
mkdir -p "$repo/${well_known%/*}"
cp "$source_file" "$repo/$well_known"

out="$(bash "$resolver" "$repo" subject_pattern 2>/dev/null)"
rc=$?
assert_exit 'resolver ignores the file while it is untracked' 1 "$rc"

git -C "$repo" add -- "$well_known"
out="$(bash "$resolver" "$repo" subject_pattern 2>"$TEST_TMPDIR/resolver.err")"
rc=$?
assert_exit 'resolver resolves subject_pattern from the tracked file' 0 "$rc"
assert_eq 'resolver prints the pattern the YAML parser reads' "$pattern" "$out"
assert_silent 'resolver writes no diagnostic' "$(cat "$TEST_TMPDIR/resolver.err")"
out="$(bash "$resolver" "$repo" pr_title_pattern 2>/dev/null)"
rc=$?
assert_exit 'resolver resolves pr_title_pattern through the deferral' 0 "$rc"
assert_eq 'pr_title_pattern resolves to subject_pattern' "$pattern" "$out"

out="$(bash "$resolver" "$root" subject_pattern 2>/dev/null)"
rc=$?
assert_exit 'resolver resolves subject_pattern in this repository' 0 "$rc"
assert_eq "this repository's resolved pattern is the component's" "$pattern" "$out"

# --- The commit-msg hook accepts and rejects ---
check_subject() {
  local subject="$1" msg="$TEST_TMPDIR/msg"
  printf '%s\n' "$subject" >"$msg"
  (cd "$repo" && GIT_EDITOR=: bash "$hook" "$msg" >/dev/null 2>&1)
}
for subject in 'feat(x): y' 'security: z' "Merge branch 'main' into x" 'Revert "feat: y"' 'fix!: drop flag'; do
  check_subject "$subject"
  assert_exit "commit-msg hook accepts: $subject" 0 "$?"
done
for subject in 'update stuff' 'feat:nospace' 'feature: y' 'Feat: y' 'Initial commit'; do
  check_subject "$subject"
  assert_exit "commit-msg hook rejects: $subject" 1 "$?"
done

[[ $FAILED -eq 0 ]] || exit 1
