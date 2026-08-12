#!/usr/bin/env bash
# Prove grep [[:cntrl:]] regex and Bash glob [[:cntrl:]] agree for embedded bytes.
set -euo pipefail
export LC_ALL=C

readonly CONTROL_RE='[[:cntrl:]]'
root="$(git rev-parse --show-toplevel)"
fixture="$root/distribution/fixtures/control-char-equivalence.tsv"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

[[ -f "$fixture" ]] || fail 'fixture present' "missing $fixture"

grep_embedded_has_control() {
  local path="$1"
  printf '%s' "$path" | grep -q "$CONTROL_RE"
}

bash_embedded_has_control() {
  local path="$1"
  [[ "$path" == *[[:cntrl:]]* ]]
}

path_with_byte() {
  local byte="$1" oct path
  oct=$(printf '%03o' "$byte")
  eval "path=\$'p\\${oct}s'"
  printf '%s' "$path"
}

# shellcheck disable=SC2310
while IFS=$'\t' read -r byte oct posix_control grep_expected bash_expected; do
  [[ "$byte" == byte ]] && continue
  path="$(path_with_byte "$byte")"
  grep_actual=no
  bash_actual=no
  if grep_embedded_has_control "$path"; then grep_actual=yes; fi
  if bash_embedded_has_control "$path"; then bash_actual=yes; fi
  assert_eq "byte $byte posix_control in fixture" "$posix_control" \
    "$( [[ "$byte" -le 31 || "$byte" -eq 127 ]] && echo yes || echo no )"
  assert_eq "byte $byte grep matches fixture" "$grep_expected" "$grep_actual"
  assert_eq "byte $byte bash matches fixture" "$bash_expected" "$bash_actual"
  if [[ "$byte" != 10 ]]; then
    assert_eq "byte $byte grep and bash agree" "$grep_actual" "$bash_actual"
  else
    assert_eq 'byte 10 (LF) bash detects embedded newline' yes "$bash_actual"
    assert_eq 'byte 10 (LF) grep misses embedded newline (line mode)' no "$grep_actual"
  fi
done <"$fixture"

plain='docs/adr/README.md'
grep_plain=no
bash_plain=no
if printf '%s' "$plain" | grep -q "$CONTROL_RE"; then grep_plain=yes; fi
if [[ "$plain" == *[[:cntrl:]]* ]]; then bash_plain=yes; fi
assert_eq 'plain path has no control (grep)' no "$grep_plain"
assert_eq 'plain path has no control (bash)' no "$bash_plain"

[[ $FAILED -eq 0 ]] || exit 1
