#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
real_path="$PATH"
scripts=(standards-gitleaks standards-editorconfig)
configs=(.gitleaks.toml .editorconfig-checker.json)
tools=(gitleaks editorconfig-checker)
flags=(--config -config)

seed_remote() {
  local dest="$1" cfg
  mkdir -p "$dest/components/lefthook-base"
  cp -R "$root/.lefthook" "$dest/.lefthook"
  for cfg in "${configs[@]}"; do cp "$root/$cfg" "$dest/$cfg"; done
  cp "$root/components/lefthook-base/lefthook-remote.yml" "$dest/components/lefthook-base/"
}

shims="$work/shims"
mkdir -p "$shims"
for tool in "${tools[@]}"; do
  cat >"$shims/$tool" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$work/$tool.log"
SH
  chmod +x "$shims/$tool"
done

flag_value() {
  awk -v f="$2" 'prev == f { print; exit } { prev = $0 }' "$1" 2>/dev/null
}

resolved() {
  [[ -f "$1" ]] && printf '%s/%s' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
}

config_of() {
  (cd "$1" && resolved "$(flag_value "$2" "$3")")
}

clear_logs() {
  local tool
  for tool in "${tools[@]}"; do rm -f "$work/$tool.log"; done
}

for at in "$work/a/.git/info/lefthook-remotes/standards-main" "$work/b/x/.git/info/lefthook-remotes/r"; do
  seed_remote "$at"
  mkdir -p "$work/cwd"
  for i in "${!scripts[@]}"; do
    clear_logs
    (cd "$work/cwd" && PATH="$shims:$real_path" sh "$at/.lefthook/pre-commit/${scripts[$i]}.sh" doc.md)
    assert_exit "${scripts[$i]} from ${at#"$work"/} exits 0 when its tool passes" 0 "$?"
    assert_eq "${scripts[$i]} from ${at#"$work"/} passes ${flags[$i]} the ${configs[$i]} beside it" \
      "$(resolved "$at/${configs[$i]}")" "$(config_of "$work/cwd" "$work/${tools[$i]}.log" "${flags[$i]}")"
    if [[ "${scripts[$i]}" == standards-gitleaks ]]; then
      assert_contains 'standards-gitleaks scans the staged diff' "$(cat "$work/gitleaks.log")" '--staged'
    else
      assert_contains "${scripts[$i]} passes the hook's files to its tool" "$(tail -n 1 "$work/${tools[$i]}.log")" 'doc.md'
    fi
  done
done

at="$work/a/.git/info/lefthook-remotes/standards-main"
mkdir -p "$work/own"
for i in "${!scripts[@]}"; do
  printf 'own\n' >"$work/own/${configs[$i]}"
  clear_logs
  (cd "$work/own" && PATH="$shims:$real_path" sh "$at/.lefthook/pre-commit/${scripts[$i]}.sh" doc.md)
  assert_exit "${scripts[$i]} with the repository's own ${configs[$i]} exits 0" 0 "$?"
  assert_eq "${scripts[$i]} passes the repository's own ${configs[$i]}, not the standards one" \
    "$(resolved "$work/own/${configs[$i]}")" "$(config_of "$work/own" "$work/${tools[$i]}.log" "${flags[$i]}")"
done

for script in "${scripts[@]}"; do
  clear_logs
  (cd "$work/cwd" && PATH="$shims:$real_path" sh "$root/.lefthook/pre-commit/$script.sh" doc.md)
  assert_exit "$script in a work tree exits 0" 0 "$?"
  assert_eq "$script in a work tree runs no tool" '' "$(ls "$work"/*.log 2>/dev/null)"
done

src="$work/standards"
seed_remote "$src"
git -C "$src" init -q -b main
git -C "$src" add -A
git -C "$src" -c user.name=t -c user.email=t@example.local -c commit.gpgsign=false commit -q -m src --no-verify

consumer="$work/consumer"
make_repo "$consumer"
cat >"$consumer/lefthook.yml" <<YAML
remotes:
  - git_url: $src
    ref: main
    configs:
      - components/lefthook-base/lefthook-remote.yml
YAML
(cd "$consumer" && lefthook install >/dev/null 2>&1)
fetched="$(find "$consumer/.git/info/lefthook-remotes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"
assert_file_exists 'lefthook install fetched the remote' "$fetched/.lefthook/pre-commit/standards-gitleaks.sh"
dump="$(cd "$consumer" && lefthook dump 2>/dev/null)"
for script in "${scripts[@]}"; do
  assert_contains "the merged config holds $script" "$dump" "name: $script"
done

mkdir -p "$consumer/docs" "$consumer/lib/deep"
printf '# Title\n' >"$consumer/docs/doc.md"
printf '# Notes\n' >"$consumer/NOTES.md"
printf 'root\n' >"$consumer/README.txt"
printf '#!/usr/bin/env bash\necho ok\n' >"$consumer/run.sh"
cp "$consumer/run.sh" "$consumer/lib/deep/x.bash"
git -C "$consumer" add docs/doc.md NOTES.md README.txt run.sh lib/deep/x.bash
cp "$consumer/lefthook.yml" "$work/lefthook.yml"
for matcher in default doublestar; do
  cp "$work/lefthook.yml" "$consumer/lefthook.yml"
  [[ "$matcher" == default ]] || printf 'glob_matcher: %s\n' "$matcher" >>"$consumer/lefthook.yml"
  clear_logs
  (cd "$consumer" && PATH="$shims:$real_path" lefthook run pre-commit >/dev/null 2>&1)
  assert_exit "$matcher matcher: the remote jobs pass when every tool passes" 0 "$?"
  for i in "${!scripts[@]}"; do
    assert_eq "$matcher matcher: ${scripts[$i]} passes ${flags[$i]} the fetched ${configs[$i]}" \
      "$(resolved "$fetched/${configs[$i]}")" "$(config_of "$consumer" "$work/${tools[$i]}.log" "${flags[$i]}")"
  done
  assert_eq "$matcher matcher: editorconfig-checker gets every staged file" 'NOTES.md README.txt docs/doc.md lib/deep/x.bash run.sh' \
    "$(sed '1,2d' "$work/editorconfig-checker.log" 2>/dev/null | sort | xargs)"
done
for gone in standards-typos standards-markdownlint standards-shellcheck; do
  assert_not_contains "the merged config holds no $gone job: the claude-code-plugins remote runs that tool" "$dump" "name: $gone"
done
cp "$work/lefthook.yml" "$consumer/lefthook.yml"

mkdir -p "$work/bare-bin"
for bin in git lefthook node; do
  if command -v "$bin" >/dev/null 2>&1; then ln -s "$(command -v "$bin")" "$work/bare-bin/$bin"; fi
done
bare_path="$work/bare-bin:/usr/bin:/bin"
if PATH="$bare_path" command -v gitleaks >/dev/null 2>&1; then
  skip_case 'gitleaks is installed system-wide, so no PATH hides it'
else
  out="$(cd "$consumer" && PATH="$bare_path" lefthook run pre-commit --job standards-gitleaks 2>&1)"
  assert_nonzero 'a missing gitleaks fails its job' "$?"
  assert_contains 'the failure names the missing tool' "$out" 'gitleaks is not on PATH'
fi

[[ $FAILED -eq 0 ]] || exit 1
