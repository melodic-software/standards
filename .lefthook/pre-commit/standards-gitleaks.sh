#!/bin/sh
# shellcheck shell=sh
# Lefthook runs a script from every source dir that holds it, so only the fetched remote copy acts.
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
  */info/lefthook-remotes/*) ;;
  *) exit 0 ;;
esac
command -v gitleaks >/dev/null 2>&1 || {
  echo 'standards-gitleaks: gitleaks is not on PATH. Install it: https://github.com/gitleaks/gitleaks#installing' >&2
  exit 1
}
exec gitleaks git --pre-commit --staged --no-banner --config "${src%/*}/../../.gitleaks.toml"
