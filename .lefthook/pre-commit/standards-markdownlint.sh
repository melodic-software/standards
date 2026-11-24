#!/bin/sh
# shellcheck shell=sh
# Lefthook runs a script from every source dir that holds it, so only the fetched remote copy acts.
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
  */info/lefthook-remotes/*) ;;
  *) exit 0 ;;
esac
bin=node_modules/.bin/markdownlint-cli2
[ -x "$bin" ] || {
  echo "standards-markdownlint: $bin not found. Run: npm ci" >&2
  exit 1
}
exec "$bin" --config "${src%/*}/../../.markdownlint-cli2.jsonc" "$@"
