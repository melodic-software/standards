#!/bin/sh
# shellcheck shell=sh
# Lefthook runs a script from every source dir that holds it, so only the fetched remote copy acts.
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
  */info/lefthook-remotes/*) ;;
  *) exit 0 ;;
esac
command -v typos >/dev/null 2>&1 || {
  echo 'standards-typos: typos is not on PATH. Install it: https://github.com/crate-ci/typos#install' >&2
  exit 1
}
exec typos -c "${src%/*}/../../_typos.toml" "$@"
