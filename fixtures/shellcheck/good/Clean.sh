#!/usr/bin/env bash
# Good fixture: conforms to the shellcheck ruleset (passes self-lint).
set -euo pipefail

greet() {
  local name="${1:-world}"

  if [[ -n "$name" ]]; then
    printf 'Hello, %s\n' "$name"
  fi

  case "$name" in
    world) printf 'default greeting\n' ;;
    *) printf 'custom greeting\n' ;;
  esac

  if command -v git >/dev/null 2>&1; then
    printf 'git is available\n'
  fi
}

greet "$@"
