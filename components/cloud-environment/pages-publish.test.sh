#!/usr/bin/env bash
# Tests pages-publish against stubbed getent, vault-exec, curl and gitleaks on
# PATH. The stub curl records each call's argv (NUL-separated) and stdin, and
# the assertions read those records: secrets reach curl only on stdin, the
# config comes only from the passwd home, and the scan refuses or reroutes.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/cloud-environment/pages-publish"

tmp="$(mktemp -d)"
mkdir -p "$tmp/bin" "$tmp/calls" "$tmp/home" "$tmp/scratch" "$tmp/other"
pages="$(realpath "$tmp/scratch")"

cat >"$tmp/bin/getent" <<'STUB'
#!/usr/bin/env bash
printf '%s:x:%s:%s::%s:/bin/bash\n' "$2" "$(id -u)" "$(id -g)" "$STUB_HOME"
STUB
# vault-exec stub: each --env NAME=secret sets NAME to SENTINEL-<secret>, then
# the command runs. STUB_VAULT_RC makes the read fail.
cat >"$tmp/bin/vault-exec" <<'STUB'
#!/usr/bin/env bash
[[ -z "${STUB_VAULT_RC:-}" ]] || exit "$STUB_VAULT_RC"
while [[ "$1" != -- ]]; do
  pair="$2"
  export "${pair%%=*}=SENTINEL-${pair#*=}"
  shift 2
done
shift
exec "$@"
STUB
# curl stub: call N answers the Nth "<status>:<body>" entry of STUB_SEQ
# (';'-separated; the last one repeats) as body, newline, status.
cat >"$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
n=$(($(find "$STUB_CALLS" -name 'argv.*' | wc -l) + 1))
printf '%s\0' "$@" >"$STUB_CALLS/argv.$n"
cat >"$STUB_CALLS/stdin.$n"
IFS=';' read -ra seq <<<"$STUB_SEQ"
((n <= ${#seq[@]})) || n=${#seq[@]}
entry="${seq[n - 1]}"
printf '%s\n%s' "${entry#*:}" "${entry%%:*}"
STUB
cat >"$tmp/bin/gitleaks" <<'STUB'
#!/usr/bin/env bash
exit "${STUB_GITLEAKS_RC:-0}"
STUB
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" STUB_HOME="$tmp/home" STUB_CALLS="$tmp/calls" TMPDIR="$pages"

pid='AbCdEfGhIjKlMnOpQrStUv'
pid2='ZyXwVuTsRqPoNmLkJiHgFe'
pub_ok="201:https://public.example.test/$pid/"
priv_ok="201:https://private.example.test/$pid2/"

# write_config <home> [KEY=VALUE overrides...]: a valid six-key config, mode 0600.
write_config() {
  local dir="$1/.config/pages-publish"
  shift
  mkdir -p "$dir"
  {
    printf '%s\n' '# pages-publish operator config' \
      PUBLIC_ENDPOINT=https://public.example.test PRIVATE_ENDPOINT=https://private.example.test/ \
      PUBLIC_TOKEN_SECRET=pub-token PRIVATE_TOKEN_SECRET=priv-token \
      PRIVATE_ACCESS_ID_SECRET=priv-access-id PRIVATE_ACCESS_KEY_SECRET=priv-access-key
    printf '%s\n' "$@"
  } | awk -F= '{v[$1] = $0; if (!($1 in o)) { o[$1] = NR; k[NR] = $1 } }
      END { for (i = 1; i <= NR; i++) if (i in k) print v[k[i]] }' >"$dir/config"
  chmod 600 "$dir/config"
}

stamp="<!-- rv-gen:explain-change sha256:$(printf 'ab%.0s' {1..32}) -->"
# page <name> <body line>: a stamped page under the temp dir.
page() {
  printf '<!doctype html>\n%s\n<p>%s</p>\n' "$stamp" "$2" >"$pages/$1.html"
  printf '%s' "$pages/$1.html"
}

# run <args...>: sets out, err, rc, calls (curl call count), argv_all, stdin_all.
run() {
  rm -f "$tmp/calls/"*
  out="$("$script" "$@" 2>"$tmp/err")"
  rc=$?
  err="$(cat "$tmp/err")"
  calls="$(find "$tmp/calls" -name 'argv.*' | wc -l | tr -d ' ')"
  argv_all="$(cat "$tmp/calls"/argv.* 2>/dev/null | tr '\0' '\n')"
  stdin_all="$(cat "$tmp/calls"/stdin.* 2>/dev/null)"
}
argv_of() { tr '\0' '\n' <"$tmp/calls/argv.$1"; }
url_of() { argv_of "$1" | tail -n 1; }

write_config "$tmp/home"
clean="$(page clean 'A plain page about settings.local.json and CLAUDE.local.md.')"

export STUB_SEQ="$pub_ok"
run "$clean" --visibility public
assert_exit 'a clean public page uploads' 0 "$rc"
assert_eq 'stdout is the JSON line built from the returned URL' \
  "{\"id\":\"$pid\",\"visibility\":\"public\",\"url\":\"https://public.example.test/$pid/\"}" "$out"
assert_eq 'one curl call' 1 "$calls"
assert_eq 'the PUT creates on the public origin' 'https://public.example.test/_upload' "$(url_of 1)"
assert_contains 'the method is PUT' "$(argv_of 1)" $'-X\nPUT'
assert_contains 'Content-Type is text/html; charset=utf-8' "$argv_all" 'Content-Type: text/html; charset=utf-8'
assert_contains 'the body is the page file' "$argv_all" "--data-binary"$'\n'"@$clean"
assert_contains 'curl is held to https' "$argv_all" $'--proto\n=https'
assert_contains 'curl reads its config from stdin' "$argv_all" $'--config\n-'
assert_eq 'curl skips every .curlrc (-q is its first argument)' '-q' "$(argv_of 1 | head -n 1)"
assert_not_contains 'no secret is in curl argv' "$argv_all" 'SENTINEL'
assert_contains 'the bearer token is a stdin config line' "$stdin_all" \
  'header = "Authorization: Bearer SENTINEL-pub-token"'
assert_not_contains 'a public upload sends no Access header' "$stdin_all" 'CF-Access'
assert_not_contains 'a public upload resolves no Access secret' "$stdin_all" 'priv-access'

STUB_SEQ="$priv_ok" run "$clean" --visibility private
assert_exit 'a private page uploads' 0 "$rc"
assert_contains 'the PUT goes to the private origin' "$argv_all" 'https://private.example.test/_upload'
assert_contains 'a private upload sends the Access client id on stdin' "$stdin_all" \
  'header = "CF-Access-Client-Id: SENTINEL-priv-access-id"'
assert_contains 'a private upload sends the Access client secret on stdin' "$stdin_all" \
  'header = "CF-Access-Client-Secret: SENTINEL-priv-access-key"'
assert_contains 'a private upload uses the private bearer token' "$stdin_all" 'Bearer SENTINEL-priv-token'
assert_not_contains 'no private secret is in curl argv' "$argv_all" 'SENTINEL'
assert_contains 'stdout reports private' "$out" '"visibility":"private"'

run "$clean" --visibility public --id "$pid"
assert_exit 'a republish with --id succeeds' 0 "$rc"
assert_eq 'the PUT replaces that id' "https://public.example.test/_upload/$pid" "$(url_of 1)"

# Input rules: exit 3, no network.
printf '%s\n' "$stamp" >"$tmp/other/outside.html"
run "$tmp/other/outside.html" --visibility public
assert_exit 'a page outside the temp dir exits 3' 3 "$rc"
assert_eq 'a page outside the temp dir makes no call' 0 "$calls"
ln -s "$tmp/other/outside.html" "$pages/link.html"
run "$pages/link.html" --visibility public
assert_exit 'a temp-dir symlink to a file outside it exits 3' 3 "$rc"
printf '<p>no stamp</p>\n' >"$pages/unstamped.html"
run "$pages/unstamped.html" --visibility public
assert_exit 'an unstamped page exits 3' 3 "$rc"
assert_eq 'an unstamped page makes no call' 0 "$calls"
run "$pages" --visibility public
assert_exit 'a directory exits 3' 3 "$rc"

# Credential shapes: one sample per shape, each built at run time so this file
# holds no credential-shaped literal. Each refuses with exit 4 before any call.
hex32="$(printf '0123456789abcdef%.0s' 1 2)"
hex64="$(printf '0123456789abcdef%.0s' 1 2 3 4)"
cred_samples=(
  "private key|-----BEGIN RSA ""PRIVATE KEY-----"
  "AWS access key|key AKIA""ABCDEFGHIJKLMNOP here"
  "GitHub token|ghp""_$(printf 'a%.0s' {1..36})"
  "Anthropic key|sk-ant""-$(printf 'b%.0s' {1..24})"
  "OpenAI key|sk-proj""-$(printf 'c%.0s' {1..24})"
  "Slack token|xoxb""-1234567890-abc"
  "Stripe key|sk_live""_abcdefghijkl"
  "password or secret assignment|PASSWORD = \"hunter2hunter2\""
  "R2 key pair|$hex32 $hex64"
  "R2 key label|secretAccessKey: \"ABCDEFGHIJKLMNOPQRST\""
  "Azure client secret|abc8Q""~$(printf 'd%.0s' {1..34})"
  "Cloudflare API token|cfut""_$(printf 'E%.0s' {1..40})0badf00d"
  "page upload token|pgup""_$(printf 'f%.0s' {1..24})"
)
for sample in "${cred_samples[@]}"; do
  label="${sample%%|*}"
  file="$(page cred "${sample#*|}")"
  run "$file" --visibility private
  assert_exit "a $label refuses with exit 4" 4 "$rc"
  assert_eq "a $label makes no call" 0 "$calls"
  assert_contains "the refusal names the $label and its line" "$err" "line 3 looks like a $label"
  assert_not_contains "the refusal never prints the $label match" "$err" "${sample#*|}"
done

run "$(page stamped "$stamp $hex32")" --visibility public
assert_exit 'the stamp hash beside a 32-hex token is not an R2 key pair' 0 "$rc"
assert_contains 'a page whose only 64-hex is the stamp stays public' "$out" '"visibility":"public"'

STUB_GITLEAKS_RC=1 run "$clean" --visibility public
assert_exit 'a gitleaks finding refuses with exit 4' 4 "$rc"
assert_eq 'a gitleaks finding makes no call' 0 "$calls"

# Machine paths and private hostnames: the page goes to the private origin.
# The user segment goes through $u: the repo's machine-path check skips one.
u=alice
path_samples=(
  "Linux home path|/home/$u/src/app.ts"
  "macOS home path|/Users/$u/src/app.ts"
  "Windows user path|C:\\Users\\$u\\src"
  'WSL share path|\\wsl.localhost\Ubuntu\home'
  'WSL mount path|/mnt/c/Users/alice'
  'root home path|see /root/.bashrc'
  'scratchpad slug|projects/-home-alice-repo/x'
  'private hostname|ssh build01.internal'
)
for sample in "${path_samples[@]}"; do
  label="${sample%%|*}"
  STUB_SEQ="$priv_ok" run "$(page path "${sample#*|}")" --visibility public
  assert_exit "a $label uploads" 0 "$rc"
  assert_contains "a $label is sent to the private origin" "$argv_all" 'https://private.example.test/_upload'
  assert_contains "a $label is reported private" "$out" '"visibility":"private"'
done

# Escaped forms: a rendered page writes a shape as HTML entities, splits it
# across highlighter tags, or escapes it inside inline JSON. None matches the
# raw bytes. A credential the host's own normalization reveals refuses, as the
# host would; one only the wider decoding reveals sends the page private.
a18="$(printf 'a%.0s' {1..18})"
bs="\\"
host_creds=(
  "HTML entity|ghp&#95;$a18$a18"
  "hex HTML entity|ghp&#X5F;$a18$a18"
  "tag split|ghp_$a18<span class=\"n\">$a18</span>"
)
for sample in "${host_creds[@]}"; do
  form="${sample%%|*}"
  run "$(page cred "${sample#*|}")" --visibility private
  assert_exit "a credential as a $form refuses with exit 4" 4 "$rc"
  assert_eq "a credential as a $form makes no call" 0 "$calls"
  assert_contains "a credential as a $form names the decoded line" "$err" 'decoded line 3 looks like a'
done
wide_creds=(
  "JSON unicode escape|ghp${bs}u005f$a18$a18"
  "JSON quote escape|{$bs\"password$bs\":$bs\"hunter2hunter2$bs\"}"
  "named entity the host leaves|ghp&lowbar;$a18$a18"
  "numeric entity without its semicolon|ghp&#95$a18$a18"
)
for sample in "${wide_creds[@]}"; do
  form="${sample%%|*}"
  STUB_SEQ="$priv_ok" run "$(page cred "${sample#*|}")" --visibility public
  assert_exit "a credential as a $form uploads" 0 "$rc"
  assert_contains "a credential as a $form is sent to the private origin" "$argv_all" 'https://private.example.test/_upload'
  assert_contains "a credential as a $form names the decoded line" "$err" 'on decoded line 3'
done

# A character that decodes to nothing valid (NUL, past U+10FFFF) still
# separates the text around it, so two token halves never join into a shape.
for sep in '&#0;' '&#x0;' '&#99999999;' '\u{110000}' '\u0000' '\x00'; do
  STUB_SEQ="$pub_ok" run "$(page cred "ghp_$a18$sep$a18")" --visibility public
  assert_exit "token halves around $sep upload" 0 "$rc"
  assert_contains "token halves around $sep stay public" "$out" '"visibility":"public"'
done
escaped_paths=(
  "Linux home path as an HTML entity|&#x2F;home&#x2F;$u&#47;src"
  "Linux home path as a named entity|&sol;home&sol;$u&sol;src"
  "Linux home path split by tags|/home/<b>$u</b>/src"
  "Linux home path as a JSON escape|\\/home\\/$u\\/src"
  "Linux home path as a JSON unicode escape|\\u002Fhome\\u002f$u\\x2Fsrc"
  'private hostname as an HTML entity|ssh build01&period;internal'
  'private hostname split by tags|ssh build01.<span>internal</span>'
  'private hostname as a JSON escape|"host":"build01\u002einternal"'
)
for sample in "${escaped_paths[@]}"; do
  label="${sample%%|*}"
  STUB_SEQ="$priv_ok" run "$(page path "${sample#*|}")" --visibility public
  assert_exit "a $label uploads" 0 "$rc"
  assert_contains "a $label is sent to the private origin" "$argv_all" 'https://private.example.test/_upload'
done

# The path-detection bodies, run on the decoded copy, add the shapes the
# Worker list misses; an escaped placeholder decodes to the <user> form they
# leave clean.
hpp_paths=(
  "Linux home path|home is /home/$u"
  "Windows user path|C:/Users/$u"
  "Windows checkout path|D:\\repos\\$u"
)
for sample in "${hpp_paths[@]}"; do
  label="${sample%%|*}"
  STUB_SEQ="$priv_ok" run "$(page path "${sample#*|}")" --visibility public
  assert_contains "a $label without the Worker shape is sent private" "$err" "the page holds a $label"
  assert_contains "a $label without the Worker shape is reported private" "$out" '"visibility":"private"'
done
lt='&lt;'
STUB_SEQ="$pub_ok" run "$(page path "see /home/${lt}user&gt;/src and /Users/${lt}user&gt;")" --visibility public
assert_exit 'an escaped <user> placeholder uploads' 0 "$rc"
assert_contains 'an escaped <user> placeholder stays public' "$out" '"visibility":"public"'
STUB_SEQ="$pub_ok" run "$(page path "a &amp;&lt;b&gt; &#0; &#99999999; &bogus; \\q \\\\ trailing \\")" --visibility public
assert_exit 'stray entities and escapes upload' 0 "$rc"
assert_contains 'stray entities and escapes stay public' "$out" '"visibility":"public"'

# The embedded copy of the path-detection bodies matches the library.
lib_bodies="$(grep -E '^HPP_[A-Z_]+=' "$root/components/path-detection/machine-path-patterns.sh")"
own_bodies="$(grep -E '^HPP_[A-Z_]+=' "$script")"
assert_eq 'pages-publish carries every path-detection body' 5 "$(grep -c . <<<"$lib_bodies")"
assert_eq 'the path-detection bodies in pages-publish match the library' "$lib_bodies" "$own_bodies"

# Decoding stays linear on a 2 MiB single line of each separator.
for unit in '<a' '&#' '\u' '&#x2F;'; do
  big="$pages/big.html"
  {
    printf '%s\n' "$stamp"
    yes "$unit" | tr -d '\n' | head -c 2097152
    printf '\n'
  } >"$big"
  start=$SECONDS
  STUB_SEQ="$pub_ok" run "$big" --visibility public
  assert_eq "a 2 MiB line of '$unit' scans in under 20 s" 1 "$((SECONDS - start < 20))"
done

STUB_SEQ="$priv_ok" run "$(page path "/home/$u/x")" --visibility public --id "$pid"
assert_exit 'a forced-private republish succeeds' 0 "$rc"
assert_eq 'a forced-private republish makes one call' 1 "$calls"
assert_eq 'a forced-private republish creates on the private origin' \
  'https://private.example.test/_upload' "$(url_of 1)"
assert_not_contains 'a forced-private republish drops the public id' "$argv_all" "$pid"
assert_contains 'a forced-private republish returns the new id' "$out" "\"id\":\"$pid2\""

# Host answers.
STUB_SEQ="409:private-required;$priv_ok" run "$clean" --visibility public --id "$pid"
assert_exit 'a 409 private-required is retried privately' 0 "$rc"
assert_eq 'a 409 retry makes exactly two calls' 2 "$calls"
assert_eq 'the first try replaces the public id' \
  "https://public.example.test/_upload/$pid" "$(url_of 1)"
assert_eq 'the retry creates on the private origin' \
  'https://private.example.test/_upload' "$(url_of 2)"
assert_not_contains 'the retry drops the public id' "$(argv_of 2)" "$pid"
assert_contains 'the retry carries the Access headers' "$(cat "$tmp/calls/stdin.2")" 'CF-Access-Client-Id'
assert_contains 'the retry is reported private' "$out" "{\"id\":\"$pid2\",\"visibility\":\"private\""

STUB_SEQ="409:private-required-x;$priv_ok" run "$clean" --visibility public
assert_exit 'a 409 whose body is not exactly private-required exits 6' 6 "$rc"
assert_eq 'a 409 with another body is not retried' 1 "$calls"

PP_ACCESS_ID=CALLER-SENTINEL-id PP_ACCESS_KEY=CALLER-SENTINEL-key PP_TOKEN=CALLER-SENTINEL-token \
  STUB_SEQ="$pub_ok" run "$clean" --visibility public
assert_exit 'a public upload with caller PP_* variables succeeds' 0 "$rc"
assert_not_contains 'caller PP_* values never reach curl argv' "$argv_all" 'CALLER-SENTINEL'
assert_not_contains 'caller PP_* values never reach curl stdin' "$stdin_all" 'CALLER-SENTINEL'
assert_not_contains 'caller PP_ACCESS_* adds no Access header to a public upload' "$stdin_all" 'CF-Access'

STUB_SEQ='422:credential:aws' run "$clean" --visibility public
assert_exit 'a host 422 exits 4' 4 "$rc"
STUB_SEQ='500:boom' run "$clean" --visibility public
assert_exit 'a host 500 exits 6' 6 "$rc"
STUB_SEQ='201:not a url' run "$clean" --visibility public
assert_exit 'a response without a page URL exits 6' 6 "$rc"
STUB_VAULT_RC=1 run "$clean" --visibility public
assert_exit 'an unresolvable token exits 6' 6 "$rc"
assert_eq 'an unresolvable token makes no call' 0 "$calls"

# Delete.
STUB_SEQ='204:' run --delete "$pid" --visibility public
assert_exit '--delete exits 0 on 204' 0 "$rc"
assert_eq '--delete prints nothing' '' "$out"
assert_contains '--delete sends DELETE' "$argv_all" $'-X\nDELETE'
assert_contains '--delete targets that id' "$argv_all" "https://public.example.test/_upload/$pid"
assert_not_contains '--delete sends no body' "$argv_all" '--data-binary'
STUB_SEQ='204:' run --delete "$pid" --visibility private
assert_contains 'a private --delete sends the Access headers' "$stdin_all" 'CF-Access-Client-Secret: SENTINEL-priv-access-key'
assert_not_contains 'a private --delete keeps secrets out of argv' "$argv_all" 'SENTINEL'
STUB_SEQ='404:' run --delete "$pid" --visibility public
assert_exit '--delete exits 6 on anything but 204' 6 "$rc"

# Config: only the passwd home counts, and it must be valid.
mkdir -p "$tmp/decoy"
write_config "$tmp/decoy" PUBLIC_ENDPOINT=https://decoy.example.test
HOME="$tmp/decoy" XDG_CONFIG_HOME="$tmp/decoy/.config" \
  PAGES_PUBLISH_PUBLIC_ENDPOINT=https://env.example.test STUB_SEQ="$pub_ok" \
  run "$clean" --visibility public
assert_exit 'a hostile HOME and XDG_CONFIG_HOME are ignored' 0 "$rc"
assert_contains 'curl sees the passwd-home endpoint' "$argv_all" 'https://public.example.test/_upload'
assert_not_contains 'curl never sees the decoy endpoint' "$argv_all" 'decoy.example.test'
assert_not_contains 'a run-time PAGES_PUBLISH_PUBLIC_ENDPOINT is ignored' "$argv_all" 'env.example.test'

check_config() {
  local label="$1"
  run "$clean" --visibility public
  assert_exit "config exits 5: $label" 5 "$rc"
  assert_eq "config refusal makes no call: $label" 0 "$calls"
  write_config "$tmp/home"
}
chmod 644 "$tmp/home/.config/pages-publish/config"
check_config 'mode 0644'
write_config "$tmp/home" PUBLIC_ENDPOINT=http://public.example.test
check_config 'an http endpoint'
write_config "$tmp/home" PRIVATE_ACCESS_KEY_SECRET=
check_config 'a missing key'
write_config "$tmp/home" EXTRA=1
check_config 'an unknown key'
write_config "$tmp/home" PUBLIC_TOKEN_SECRET='bad name'
check_config 'a secret name that is not a vault name'
rm "$tmp/home/.config/pages-publish/config"
check_config 'no config file'

check_usage() {
  local label="$1"
  shift
  run "$@"
  assert_exit "usage exits 2: $label" 2 "$rc"
  assert_eq "usage makes no call: $label" 0 "$calls"
}
check_usage 'no visibility' "$clean"
check_usage 'visibility not public or private' "$clean" --visibility internal
check_usage 'malformed id' "$clean" --visibility public --id short
check_usage 'no file' --visibility public
check_usage '--delete with a file' "$clean" --delete "$pid" --visibility public
check_usage 'unknown option' "$clean" --visibility public --force

rm -rf "$tmp"
[[ $FAILED -eq 0 ]] || exit 1
