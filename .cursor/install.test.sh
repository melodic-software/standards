#!/usr/bin/env bash
# Contract tests for .cursor/install.sh: the PATH-link helpers must not abort
# when nvm already owns the first writable directory, and the four Lefthook
# hygiene-engine pins must match the ci-workflows action defaults at the SHA
# this repository already pins in ci.yml.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

# shellcheck source=.cursor/install.sh
CURSOR_INSTALL_LIBONLY=1 source "$root/.cursor/install.sh"

# --- PATH-link helpers ------------------------------------------------------

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

nvm_bin="$scratch/nvm-bin"
other_bin="$scratch/other-bin"
mkdir -p "$nvm_bin" "$other_bin"
for bin in node npm npx; do
  printf '#!/bin/sh\necho %s\n' "$bin" >"$nvm_bin/$bin"
  chmod +x "$nvm_bin/$bin"
done

# Codex finding: nvm use prepends $node_bin_dir, so a naive walk picks that
# directory and GNU ln aborts on a same-file self-link.
PATH="$nvm_bin:/exec-daemon:/usr/bin"
found="$(cursor_install::choose_link_dir "$nvm_bin")"
assert_eq 'nvm bin dir is skipped when it is the first writable PATH entry' '' "$found"

PATH="$nvm_bin:$other_bin:/exec-daemon:/usr/bin"
found="$(cursor_install::choose_link_dir "$nvm_bin")"
assert_eq 'search continues to the next writable dir before exec-daemon' "$other_bin" "$found"

cursor_install::link_bins "$nvm_bin" "$other_bin"
assert_eq 'node link target is the nvm binary' "$nvm_bin/node" "$(readlink "$other_bin/node")"
assert_eq 'npm link target is the nvm binary' "$nvm_bin/npm" "$(readlink "$other_bin/npm")"
assert_eq 'npx link target is the nvm binary' "$nvm_bin/npx" "$(readlink "$other_bin/npx")"

# Second pass must be a no-op, not a GNU ln same-file abort.
cursor_install::link_bins "$nvm_bin" "$nvm_bin"
self_link_rc=$?
assert_exit 'self-link into the nvm bin dir does not abort' 0 "$self_link_rc"

PATH="$nvm_bin:/exec-daemon:$other_bin:/usr/bin"
found="$(cursor_install::choose_link_dir "$nvm_bin")"
assert_eq 'a writable dir after exec-daemon is not selected' '' "$found"

# --- Engine pin lockstep with ci-workflows ----------------------------------

parse_install_pin() {
  local name="$1"
  awk -v name="$name" '
    $1 == "install_engine" && $2 == name {
      ver = $3
      next
    }
    ver != "" && $1 ~ /^[0-9a-f]{64}$/ {
      print ver, $1
      exit
    }
  ' "$root/.cursor/install.sh"
}

parse_ci_action_sha() {
  local action="$1"
  awk -v action="$action" '
    $1 == "uses:" && $2 ~ "ci-workflows/.github/actions/" action "@" {
      n = split($2, parts, "@")
      print parts[n]
      exit
    }
  ' "$root/.github/workflows/ci.yml"
}

parse_action_defaults() {
  local file="$1"
  awk '
    $1 == "version:" { want = "version"; next }
    $1 == "sha256:" { want = "sha256"; next }
    want != "" && $1 == "default:" {
      print want, $2
      want = ""
    }
  ' "$file"
}

parse_ci_shellcheck_inline() {
  awk '
    $1 ~ /^ver=/ { split($1, a, "="); ver = a[2] }
    $1 ~ /^sha=/ { split($1, a, "="); sha = a[2] }
    ver != "" && sha != "" { print ver, sha; exit }
  ' "$root/.github/workflows/ci.yml"
}

for engine in shellcheck typos gitleaks editorconfig-checker; do
  pin="$(parse_install_pin "$engine")"
  if [[ -n "$pin" ]]; then
    pass "install.sh declares $engine version and sha256"
  else
    fail "install.sh declares $engine version and sha256" "no install_engine pin"
  fi
done

action_name_for() {
  case "$1" in
    editorconfig-checker) printf '%s\n' editorconfig ;;
    *) printf '%s\n' "$1" ;;
  esac
}

tmp_actions="$scratch/actions"
mkdir -p "$tmp_actions"
for engine in shellcheck typos gitleaks editorconfig-checker; do
  action="$(action_name_for "$engine")"
  sha="$(parse_ci_action_sha "$action")"
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    fail "ci.yml pins ci-workflows $action at a full SHA" "got ${sha:-empty}"
    continue
  fi
  url="https://raw.githubusercontent.com/melodic-software/ci-workflows/${sha}/.github/actions/${action}/action.yml"
  dest="$tmp_actions/${action}.yml"
  if ! curl -fsSL "$url" -o "$dest"; then
    if [[ "${CI:-}" == true ]]; then
      fail "fetch $action action.yml at ${sha:0:7}" "curl failed"
      continue
    fi
    skip_case "cannot fetch $action action.yml (need network); remaining lockstep skipped"
    break
  fi
  defaults="$(parse_action_defaults "$dest")"
  action_ver="$(awk '$1=="version"{print $2; exit}' <<<"$defaults")"
  action_sha="$(awk '$1=="sha256"{print $2; exit}' <<<"$defaults")"
  install_pin="$(parse_install_pin "$engine")"
  install_ver="${install_pin%% *}"
  install_sha="${install_pin#* }"
  assert_eq "$engine version matches ci-workflows $action@${sha:0:7}" "$action_ver" "$install_ver"
  assert_eq "$engine sha256 matches ci-workflows $action@${sha:0:7}" "$action_sha" "$install_sha"
done

inline="$(parse_ci_shellcheck_inline)"
install_shellcheck="$(parse_install_pin shellcheck)"
assert_eq 'shellcheck pin matches the in-repo ci.yml lockstep duplicate' "$inline" "$install_shellcheck"

[[ $FAILED -eq 0 ]] || exit 1
