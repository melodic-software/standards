#!/usr/bin/env bash
# Tests the cloud Key Vault resolver against a stubbed curl on PATH: the argv
# contract the mcp-launcher depends on, pass-through of stdin and exit code,
# and that no secret value reaches curl's argv or vault-exec's output.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/cloud-environment/vault-exec"
value='s3cr3t-VALUE-9f2'

tmp="$(mktemp -d)"
mkdir -p "$tmp/bin"
# The stub logs its argv, one line per call, drains its own stdin (so a
# resolver that passed the caller's stdin to curl would lose it), prints a body
# plus the -w status line, and exits 22 for a status of 400 or more, as
# --fail-with-body does. With STUB_SEQ set, call N answers its Nth status
# (the last one repeats) with an error body until a 200 gets STUB_BODY;
# STUB_SLEEP delays each call.
cat >"$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_CURL_LOG"
cat >/dev/null
[[ -z "${STUB_SLEEP:-}" ]] || sleep "$STUB_SLEEP"
status="$STUB_STATUS" body="$STUB_BODY"
if [[ -n "${STUB_SEQ:-}" ]]; then
  read -ra seq <<<"$STUB_SEQ"
  n=$(wc -l <"$STUB_CURL_LOG")
  ((n <= ${#seq[@]})) || n=${#seq[@]}
  status="${seq[n - 1]}"
  [[ "$status" == 200 ]] || body="{\"error\":{\"code\":\"E$status\"}}"
fi
printf '%s\n%s' "$body" "$status"
[[ "$status" -lt 400 ]] || exit 22
STUB
chmod +x "$tmp/bin/curl"
export STUB_CURL_LOG="$tmp/curl.log"
export PATH="$tmp/bin:$PATH"
ok_body="{\"value\": \"$value\", \"id\": \"https://kv/secrets/x/1\"}"

# run <status> <body> <stdin> <vault-exec args...>: sets out, err, rc.
run() {
  local status="$1" body="$2" input="$3"
  shift 3
  : >"$STUB_CURL_LOG"
  out="$(printf '%s' "$input" | STUB_STATUS="$status" STUB_BODY="$body" \
    "$script" "$@" 2>"$tmp/err")"
  rc=$?
  err="$(cat "$tmp/err")"
}

export EXPECT="$value"
# shellcheck disable=SC2016 # $TOKEN and $EXPECT expand in the child shell
run 200 "$ok_body" '' --env TOKEN=my-secret -- \
  bash -c '[[ "${TOKEN-unset}" == "$EXPECT" ]] && echo ran-ok'
assert_exit 'a resolved secret runs the command' 0 "$rc"
assert_eq 'the command sees the secret in its environment' 'ran-ok' "$out"
assert_contains 'curl reads the default vault' "$(cat "$STUB_CURL_LOG")" \
  'https://kv-melo-devtools-prod.vault.azure.net/secrets/my-secret?api-version=7.4'
assert_not_contains 'curl sends no auth header (the proxy adds it)' "$(cat "$STUB_CURL_LOG")" 'Authorization'
assert_not_contains "curl's argv never holds the value" "$(cat "$STUB_CURL_LOG")" "$value"
assert_not_contains 'stderr never holds the value' "$err" "$value"

run 200 "$ok_body" '' --env TOKEN=my-secret -- true
assert_eq 'stdout carries nothing of its own' '' "$out"
assert_eq 'stderr is silent on success' '' "$err"

run 200 "$ok_body" 'from-caller' --env TOKEN=my-secret -- cat
assert_eq "the caller's stdin reaches the command" 'from-caller' "$out"

run 200 "$ok_body" '' --env TOKEN=my-secret -- bash -c 'exit 7'
assert_exit "the command's exit code passes through" 7 "$rc"

# shellcheck disable=SC2016 # $TOKEN expands in the child shell
run 200 '{"value": "line\n"}' '' --env TOKEN=my-secret -- bash -c 'printf "[%s]" "$TOKEN"'
assert_eq 'a trailing newline in the value survives' $'[line\n]' "$out"

VAULT_EXEC_VAULT=kv-other-01 run 200 "$ok_body" '' --env TOKEN=my-secret -- true
assert_contains 'VAULT_EXEC_VAULT changes the host' "$(cat "$STUB_CURL_LOG")" \
  'https://kv-other-01.vault.azure.net/secrets/my-secret?api-version=7.4'

for status in 403 404; do
  # shellcheck disable=SC2016 # $TOKEN expands in the child shell
  TOKEN=stale run "$status" '{"error":{"code":"Forbidden"}}' '' \
    --optional --env TOKEN=my-secret -- bash -c 'echo "ran ${TOKEN-unset}"'
  assert_exit "--optional runs the command after a $status" 0 "$rc"
  assert_eq "--optional leaves the name unset after a $status" 'ran unset' "$out"
  assert_contains "--optional warns with the secret name and status ($status)" "$err" \
    "TOKEN not set: secret 'my-secret' in kv-melo-devtools-prod failed (HTTP $status"
done

run 403 '{"error":{"code":"Forbidden"}}' '' --env TOKEN=my-secret -- touch "$tmp/ran"
assert_exit 'without --optional a failed read exits 1' 1 "$rc"
assert_file_absent 'without --optional a failed read never runs the command' "$tmp/ran"
assert_contains 'the failure names the secret and status' "$err" "secret 'my-secret' in kv-melo-devtools-prod failed (HTTP 403"

run 200 '{"id": "no value"}' '' --env TOKEN=my-secret -- touch "$tmp/ran"
assert_exit 'a response without a string value fails the read' 1 "$rc"
assert_file_absent 'a response without a value never runs the command' "$tmp/ran"

export VAULT_EXEC_RETRY_DELAY_SEC=0
for seq in '500 200' '429 200' '500 500 200'; do
  # shellcheck disable=SC2016 # $TOKEN and $EXPECT expand in the child shell
  STUB_SEQ="$seq" run 200 "$ok_body" '' --env TOKEN=my-secret -- \
    bash -c '[[ "${TOKEN-unset}" == "$EXPECT" ]] && echo ran-ok'
  assert_exit "a retried read that succeeds runs the command ($seq)" 0 "$rc"
  assert_eq "only the final response sets the value ($seq)" 'ran-ok' "$out"
  assert_eq "one curl call per attempt ($seq)" "$(wc -w <<<"$seq")" "$(wc -l <"$STUB_CURL_LOG")"
  assert_not_contains "curl is never asked to retry itself ($seq)" "$(cat "$STUB_CURL_LOG")" '--retry'
  assert_contains "each attempt is capped at 10 seconds ($seq)" "$(cat "$STUB_CURL_LOG")" '--max-time 10 '
done

STUB_SEQ='404 200' run 200 "$ok_body" '' --env TOKEN=my-secret -- touch "$tmp/ran"
assert_exit 'a 404 is not retried' 1 "$rc"
assert_eq 'a 404 takes one attempt' 1 "$(wc -l <"$STUB_CURL_LOG")"

STUB_SEQ='503' run 200 "$ok_body" '' --env TOKEN=my-secret -- touch "$tmp/ran"
assert_exit 'a read that keeps failing exits 1' 1 "$rc"
assert_eq 'a read that keeps failing stops after three attempts' 3 "$(wc -l <"$STUB_CURL_LOG")"
assert_contains 'the last status is reported' "$err" "secret 'my-secret' in kv-melo-devtools-prod failed (HTTP 503"
assert_file_absent 'a read that keeps failing never runs the command' "$tmp/ran"

# $SECONDS ticks on whole-second boundaries, so the budget is 2 and the first
# attempt alone (2 s) is enough to spend it.
started=$SECONDS
# shellcheck disable=SC2016 # $A and $B expand in the child shell
VAULT_EXEC_BUDGET_SEC=2 STUB_SLEEP=2 STUB_SEQ='500' run 200 "$ok_body" '' \
  --optional --env A=one --env B=two -- bash -c 'echo "ran ${A-unset} ${B-unset}"'
assert_exit '--optional still runs the command once the budget is spent' 0 "$rc"
assert_eq 'no secret is set once the budget is spent' 'ran unset unset' "$out"
assert_eq 'no attempt starts after the budget is spent' 1 "$(wc -l <"$STUB_CURL_LOG")"
assert_contains 'a secret skipped for time says so' "$err" \
  "B not set: secret 'two' in kv-melo-devtools-prod failed (HTTP none, time budget spent"
[[ $((SECONDS - started)) -le 4 ]] && within=yes || within=no
assert_eq 'the run stops within the budget' yes "$within"
assert_not_contains 'each attempt is capped by the time left' "$(cat "$STUB_CURL_LOG")" '--max-time 10 '

check_usage() {
  local label="$1"
  shift
  run 200 "$ok_body" '' "$@"
  assert_exit "bad usage exits 2: $label" 2 "$rc"
  assert_eq "bad usage reads no secret: $label" '' "$(cat "$STUB_CURL_LOG")"
}
check_usage 'no --' --env TOKEN=my-secret true
check_usage 'no command' --env TOKEN=my-secret --
check_usage 'no --env' -- true
check_usage 'NAME is not an env var name' --env 1TOKEN=my-secret -- true
check_usage 'no = in the pair' --env TOKEN -- true
check_usage 'secret name with an underscore' --env TOKEN=my_secret -- true
check_usage 'secret name over 127 characters' --env "TOKEN=$(printf 'a%.0s' {1..128})" -- true
check_usage 'unknown flag' --verbose --env TOKEN=my-secret -- true
VAULT_EXEC_VAULT='evil.example.com/x' check_usage 'vault override that is not a vault name' \
  --env TOKEN=my-secret -- true

rm -rf "$tmp"
[[ $FAILED -eq 0 ]] || exit 1
