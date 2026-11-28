#!/bin/sh
# shellcheck shell=sh
src=$(printf '%s\n' "$0" | tr '\134' '/')
case "$src" in
  */info/lefthook-remotes/*) ;;
  *) exit 0 ;;
esac
command -v gitleaks >/dev/null 2>&1 || {
  echo 'standards-gitleaks: gitleaks is not on PATH. Install it: https://github.com/gitleaks/gitleaks#installing' >&2
  exit 1
}
if [ -f .gitleaks.toml ]; then
  exec gitleaks git --pre-commit --staged --no-banner --config .gitleaks.toml
fi
exec gitleaks git --pre-commit --staged --no-banner --config "${src%/*}/../../.gitleaks.toml"
