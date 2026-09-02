#!/usr/bin/env bash
# Cursor Cloud Agent install for the Melodic Software standards repository.
#
# Idempotent and non-interactive. It provisions the toolchain the repository's
# documented local workflow and its always-on Lefthook pre-commit lanes need:
#
#   * the Node runtime pinned in .node-version (via nvm), plus every npm
#     dependency root the repository carries. The root package.json declares no
#     workspaces, so the component and distribution projects each own a lockfile
#     a root install does not reach (the roots ci.yml installs with its own
#     `npm ci --prefix` steps);
#   * the cross-cutting hygiene engines the base Lefthook config invokes on
#     every commit with assert_lefthook_installed (a missing engine fails the
#     hook rather than skipping): shellcheck, typos, gitleaks, and
#     editorconfig-checker. Versions and checksums match the ci-workflows
#     actions this repository pins, so a local commit and CI agree.
#
# Language-specific engines (.NET, Python/ruff/pyright, PowerShell, Go, lychee,
# yq) are provisioned by CI; the component contract tests skip cleanly when
# their engine is absent locally, matching this repository's own design.
#
# Node selection note: the exec daemon ships its own `node` on PATH ahead of
# the nvm-managed one, so this script links the pinned node/npm/npx into the
# earliest writable PATH directory that precedes the daemon. That makes the
# pinned toolchain win for a bare `node` invocation without depending on nvm
# being sourced in every shell.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repo_root"

log() { printf 'cursor-install: %s\n' "$*"; }

# --- Node from .node-version (via nvm) --------------------------------------
node_pin="$(tr -d '[:space:]' <.node-version)"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  log "nvm not found at $NVM_DIR; installing nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

set +u # nvm.sh reads intentionally-unset variables
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install "$node_pin"
nvm alias default "$node_pin" >/dev/null
nvm use "$node_pin" >/dev/null
set -u

node_bin_dir="$NVM_DIR/versions/node/v$node_pin/bin"
if [[ ! -x "$node_bin_dir/node" ]]; then
  log "expected node at $node_bin_dir/node but it is missing"
  exit 1
fi

# --- Make the pinned node win on PATH ---------------------------------------
# Link node/npm/npx into the first writable PATH directory that comes before
# /exec-daemon, whose bundled node would otherwise shadow the pinned one.
link_dir=""
saved_ifs="$IFS"
IFS=:
for dir in $PATH; do
  case "$dir" in
    /exec-daemon | /exec-daemon/*) break ;;
    *) : ;;
  esac
  [[ -d "$dir" ]] || continue
  if [[ -w "$dir" ]]; then
    link_dir="$dir"
    break
  fi
  if sudo -n test -w "$dir" 2>/dev/null; then
    link_dir="$dir"
    break
  fi
done
IFS="$saved_ifs"

if [[ -n "$link_dir" ]]; then
  for bin in node npm npx; do
    if [[ -w "$link_dir" ]]; then
      ln -sf "$node_bin_dir/$bin" "$link_dir/$bin"
    else
      sudo ln -sf "$node_bin_dir/$bin" "$link_dir/$bin"
    fi
  done
  hash -r
  log "linked pinned node/npm/npx into $link_dir"
else
  log "no writable PATH directory precedes the exec daemon; relying on nvm PATH"
fi

log "node $(node --version) / npm $(npm --version)"

# --- npm dependency roots ---------------------------------------------------
for lock in package-lock.json components/*/package-lock.json distribution/package-lock.json; do
  [[ -f "$lock" ]] || continue
  dir="$(dirname -- "$lock")"
  log "npm ci in $dir"
  npm ci --no-audit --no-fund --prefix "$dir"
done

# --- Always-on hygiene engines (Lefthook pre-commit) ------------------------
bin_dir=/usr/local/bin
stamp_dir=/usr/local/share/melodic-cursor

# put_bin <source-path> <dest-name>: install an executable into bin_dir, using
# sudo only when the directory is not directly writable.
put_bin() {
  if [[ -w "$bin_dir" ]]; then
    install -m 0755 "$1" "$bin_dir/$2"
  else
    sudo install -m 0755 "$1" "$bin_dir/$2"
  fi
}

# write_stamp <dest-name> <version>: record the installed version for idempotence.
write_stamp() {
  if [[ -w "$stamp_dir" ]] || { [[ ! -e "$stamp_dir" ]] && [[ -w "$(dirname -- "$stamp_dir")" ]]; }; then
    mkdir -p "$stamp_dir"
    printf '%s\n' "$2" >"$stamp_dir/$1.version"
  else
    sudo mkdir -p "$stamp_dir"
    printf '%s\n' "$2" | sudo tee "$stamp_dir/$1.version" >/dev/null
  fi
}

# install_engine <dest> <version> <url> <sha256> <member-in-archive>
install_engine() {
  dest="$1"
  version="$2"
  url="$3"
  sha="$4"
  member="$5"
  stamp="$stamp_dir/$dest.version"
  if [[ -x "$bin_dir/$dest" ]] && [[ -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$version" ]]; then
    log "$dest $version already installed"
    return 0
  fi
  tmp="$(mktemp -d)"
  log "installing $dest $version"
  curl -fsSL "$url" -o "$tmp/archive.tar.gz"
  printf '%s  %s\n' "$sha" "$tmp/archive.tar.gz" | sha256sum -c - >/dev/null
  tar -xzf "$tmp/archive.tar.gz" -C "$tmp" "$member"
  put_bin "$tmp/$member" "$dest"
  write_stamp "$dest" "$version"
  rm -rf "$tmp"
}

install_engine shellcheck 0.11.0 \
  "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.gz" \
  b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6 \
  shellcheck-v0.11.0/shellcheck

install_engine typos 1.47.2 \
  "https://github.com/crate-ci/typos/releases/download/v1.47.2/typos-v1.47.2-x86_64-unknown-linux-musl.tar.gz" \
  7aef58932fc123b4cf4b40d86468e89a3297d80169051d7cfd13a235e05fc426 \
  ./typos

install_engine gitleaks 8.30.1 \
  "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz" \
  551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb \
  gitleaks

install_engine editorconfig-checker 3.8.0 \
  "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v3.8.0/ec-linux-amd64.tar.gz" \
  613bd88f34165a334adcb6b7e92a123c9de0eada65846d31af63613b779ff3be \
  bin/ec-linux-amd64

hash -r
log "install complete"
