#!/bin/sh
# shellcheck shell=sh
# Lefthook runs a script from every source dir that holds it, so only the fetched remote copy acts.
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
  */info/lefthook-remotes/*) ;;
  *) exit 0 ;;
esac
command -v shellcheck >/dev/null 2>&1 || {
  echo 'standards-shellcheck: shellcheck is not on PATH. Install it: https://github.com/koalaman/shellcheck#installing' >&2
  exit 1
}
exec shellcheck --rcfile "${src%/*}/../../.shellcheckrc" "$@"
