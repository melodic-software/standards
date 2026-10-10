#!/usr/bin/env bash
# Tests the rendered-views SessionStart hook against a stub vault-exec placed
# beside a copy of the script, the way setup.sh installs the pair: it runs only
# in a cloud session, writes a non-empty secret value, leaves the file alone
# otherwise, never sees a caller's VAULT_EXEC_VAULT, and always exits 0 with
# nothing on stdout.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config"
cp "$root/components/cloud-environment/rendered-views-sync" "$tmp/bin/"
dest="$tmp/config/rendered-views.md"
# The stub logs its argv and the VAULT_EXEC_VAULT it sees, then acts on
# STUB_MODE: value sets RV_MD to STUB_VALUE and runs the command, absent runs
# it with RV_MD unset (what --optional does on a failed read), and fail exits 1.
cat >"$tmp/bin/vault-exec" <<'STUB'
#!/usr/bin/env bash
printf 'argv=%s vault=%s\n' "$*" "${VAULT_EXEC_VAULT-unset}" >>"$STUB_LOG"
while [[ $# -gt 0 && "$1" != '--' ]]; do shift; done
shift
case "$STUB_MODE" in
  value) RV_MD="$STUB_VALUE" exec "$@" ;;
  absent) exec env -u RV_MD "$@" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/vault-exec"
export STUB_LOG="$tmp/stub.log"

# run <remote> <mode> [value]: sets out, err, rc.
run() {
  : >"$STUB_LOG"
  out="$(CLAUDE_CODE_REMOTE="$1" STUB_MODE="$2" STUB_VALUE="${3:-}" \
    CLAUDE_CONFIG_DIR="$tmp/config" VAULT_EXEC_VAULT=kv-attacker RV_MD='medium: repo' \
    "$tmp/bin/rendered-views-sync" 2>"$tmp/err")"
  rc=$?
  err="$(cat "$tmp/err")"
}

run false value 'medium: hosted'
assert_exit 'outside a cloud session the hook exits 0' 0 "$rc"
assert_eq 'outside a cloud session vault-exec is never called' '' "$(cat "$STUB_LOG")"
assert_file_absent 'outside a cloud session no file is written' "$dest"

run true value 'medium: hosted'
assert_exit 'a secret value exits 0' 0 "$rc"
assert_eq 'the file holds the secret value' 'medium: hosted' "$(cat "$dest")"
assert_eq 'the hook prints nothing to stdout' '' "$out"
assert_contains 'vault-exec reads rendered-views-md optionally' "$(cat "$STUB_LOG")" \
  'argv=--optional --env RV_MD=rendered-views-md --'
assert_contains "a caller's VAULT_EXEC_VAULT is not seen by vault-exec" "$(cat "$STUB_LOG")" \
  'vault=unset'
assert_not_contains 'the value is not in vault-exec argv' "$(cat "$STUB_LOG")" 'medium: hosted'
assert_eq 'the file has mode 0644' 644 "$(stat -c '%a' "$dest")"

run true absent
assert_exit 'an absent secret exits 0' 0 "$rc"
assert_eq "an absent secret leaves the file, ignoring the caller's RV_MD" 'medium: hosted' "$(cat "$dest")"

run true value ''
assert_exit 'an empty secret exits 0' 0 "$rc"
assert_eq 'an empty secret leaves the file' 'medium: hosted' "$(cat "$dest")"

run true value $'medium: artifact\r'
assert_exit 'a value holding a carriage return exits 0' 0 "$rc"
assert_eq 'a value holding a carriage return leaves the file' 'medium: hosted' "$(cat "$dest")"

run true fail
assert_exit 'a failing vault-exec exits 0' 0 "$rc"
assert_eq 'a failing vault-exec leaves the file' 'medium: hosted' "$(cat "$dest")"
assert_contains 'a failure logs one line to stderr' "$err" 'rendered-views-sync: '
assert_eq 'a failure prints nothing to stdout' '' "$out"
assert_eq 'no temp file is left behind' '' "$(find "$tmp/config" -name '*.sync.*')"

rm "$tmp/bin/vault-exec"
run true value 'medium: artifact'
assert_exit 'a missing vault-exec exits 0' 0 "$rc"
assert_eq 'a missing vault-exec leaves the file' 'medium: hosted' "$(cat "$dest")"

[[ $FAILED -eq 0 ]] || exit 1
