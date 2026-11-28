#!/bin/sh
# shellcheck shell=sh
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
  */info/lefthook-remotes/*) ;;
  *) exit 0 ;;
esac
command -v editorconfig-checker >/dev/null 2>&1 || {
  echo 'standards-editorconfig: editorconfig-checker is not on PATH (alias ec to it). Install it: https://github.com/editorconfig-checker/editorconfig-checker#installation' >&2
  exit 1
}
# editorconfig-checker reads one config: the repository's own replaces this one whole.
# https://github.com/editorconfig-checker/editorconfig-checker#configuration
if [ -f .editorconfig-checker.json ]; then
  exec editorconfig-checker -config .editorconfig-checker.json "$@"
fi
exec editorconfig-checker -config "${src%/*}/../../.editorconfig-checker.json" "$@"
