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
# The stub logs its argv, drains its own stdin (so a resolver that passed the
# caller's stdin to curl would lose it), prints STUB_BODY plus the -w status
# line, and exits 22 for a status of 400 or more, as --fail-with-body does.
cat >"$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_CURL_LOG"
cat >/dev/null
printf '%s\n%s' "$STUB_BODY" "$STUB_STATUS"
[[ "$STUB_STATUS" -lt 400 ]] || exit 22
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
