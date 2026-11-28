#!/usr/bin/env bash

cursor_install::choose_link_dir() {
  local node_bin="$1" dir="" saved_ifs="$IFS"
  IFS=:
  for dir in $PATH; do
    case "$dir" in
      /exec-daemon | /exec-daemon/*) break ;;
      *) : ;;
    esac
    [[ -d "$dir" ]] || continue
    if [[ "$dir" -ef "$node_bin" ]]; then
      continue
    fi
    if [[ -w "$dir" ]] || sudo -n test -w "$dir" 2>/dev/null; then
      printf '%s\n' "$dir"
      IFS="$saved_ifs"
      return 0
    fi
  done
  IFS="$saved_ifs"
}

cursor_install::link_bins() {
  local node_bin="$1" link_dir="$2" bin
  for bin in node npm npx; do
    if [[ -e "$link_dir/$bin" && "$link_dir/$bin" -ef "$node_bin/$bin" ]]; then
      continue
    fi
    if [[ -w "$link_dir" ]]; then
      ln -sf "$node_bin/$bin" "$link_dir/$bin"
    else
      sudo ln -sf "$node_bin/$bin" "$link_dir/$bin"
    fi
  done
}

if [[ "${CURSOR_INSTALL_LIBONLY:-}" == 1 ]]; then
  return 0
fi

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repo_root"

log() { printf 'cursor-install: %s\n' "$*"; }

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

link_dir="$(cursor_install::choose_link_dir "$node_bin_dir")"
if [[ -n "$link_dir" ]]; then
  cursor_install::link_bins "$node_bin_dir" "$link_dir"
  hash -r
  log "linked pinned node/npm/npx into $link_dir"
else
  log "no writable PATH directory precedes the exec daemon; relying on nvm PATH"
fi

log "node $(node --version) / npm $(npm --version)"

for lock in package-lock.json components/*/package-lock.json distribution/package-lock.json; do
  [[ -f "$lock" ]] || continue
  dir="$(dirname -- "$lock")"
  log "npm ci in $dir"
  npm ci --no-audit --no-fund --ignore-scripts --prefix "$dir"
done

hooks_skipped=false
case "${CI:-}" in
  '' | 0 | false) ;;
  *) case "${LEFTHOOK:-}" in '' | 0 | false) hooks_skipped=true ;; *) ;; esac ;;
esac
if [[ "$hooks_skipped" == false ]]; then
  npm run prepare || log 'npm run prepare failed; git hooks are not installed'
fi

bin_dir=/usr/local/bin
stamp_dir=/usr/local/share/melodic-cursor

put_bin() {
  if [[ -w "$bin_dir" ]]; then
    install -m 0755 "$1" "$bin_dir/$2"
  else
    sudo install -m 0755 "$1" "$bin_dir/$2"
  fi
}

write_stamp() {
  if [[ -w "$stamp_dir" ]] || { [[ ! -e "$stamp_dir" ]] && [[ -w "$(dirname -- "$stamp_dir")" ]]; }; then
    mkdir -p "$stamp_dir"
    printf '%s\n' "$2" >"$stamp_dir/$1.version"
  else
    sudo mkdir -p "$stamp_dir"
    printf '%s\n' "$2" | sudo tee "$stamp_dir/$1.version" >/dev/null
  fi
}

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

install_engine typos 1.52.2 \
  "https://github.com/crate-ci/typos/releases/download/v1.52.2/typos-v1.52.2-x86_64-unknown-linux-musl.tar.gz" \
  3b13d1291281d39d01822e54035636487a7a0f228e70097899b1e33aeb0e7e93 \
  ./typos

install_engine gitleaks 8.30.1 \
  "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz" \
  551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb \
  gitleaks

install_engine editorconfig-checker 4.0.2 \
  "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v4.0.2/editorconfig-checker-linux-amd64.tar.gz" \
  44efaef3ed14c6ab52eb87481d78e5e5c204796dccf26e2f4598a61ba17f8003 \
  editorconfig-checker

hash -r
log "install complete"
