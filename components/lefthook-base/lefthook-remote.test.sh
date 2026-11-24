#!/usr/bin/env bash
# Tests the lefthook remote form of lefthook-base and lefthook-shellcheck: a
# consumer lists the two lefthook-remote.yml configs under `remotes:`, lefthook
# fetches this repository into .git/info/lefthook-remotes/, and each job's
# script under .lefthook/pre-commit/ passes its tool the standards config that
# sits two directories above the script itself.
#
# Recording shims stand in for the tools, so the argv each script builds is an
# artifact on disk; only lefthook gates the suite. Where real typos and
# ShellCheck binaries are on PATH, a fixture only the standards config rejects shows
# the fetched config is the one in force.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
real_path="$PATH"
scripts=(standards-typos standards-gitleaks standards-editorconfig standards-markdownlint standards-shellcheck)
configs=(_typos.toml .gitleaks.toml .editorconfig-checker.json .markdownlint-cli2.jsonc .shellcheckrc)
tools=(typos gitleaks editorconfig-checker markdownlint-cli2 shellcheck)
flags=(-c --config -config --config --rcfile)

# The files a consumer fetches, committed on main in a stand-in remote.
seed_remote() {
  local dest="$1" cfg
  mkdir -p "$dest/components/lefthook-base" "$dest/components/lefthook-shellcheck"
  cp -R "$root/.lefthook" "$dest/.lefthook"
  for cfg in "${configs[@]}"; do cp "$root/$cfg" "$dest/$cfg"; done
  cp "$root/components/lefthook-base/lefthook-remote.yml" "$dest/components/lefthook-base/"
  cp "$root/components/lefthook-shellcheck/lefthook-remote.yml" "$dest/components/lefthook-shellcheck/"
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

# The config a recorded call named, resolved from the directory the hook ran in.
config_of() {
  (cd "$1" && resolved "$(flag_value "$2" "$3")")
}

clear_logs() {
  local tool
  for tool in "${tools[@]}"; do rm -f "$work/$tool.log"; done
}

# Case 1: run directly, each script resolves its config from its own location,
# whichever directory the remote was fetched into, and passes the files on.
for at in "$work/a/.git/info/lefthook-remotes/standards-main" "$work/b/x/.git/info/lefthook-remotes/r"; do
  seed_remote "$at"
  mkdir -p "$work/cwd/node_modules/.bin"
  cp "$shims/markdownlint-cli2" "$work/cwd/node_modules/.bin/"
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

# Case 2: a copy of a script outside a fetched remote (this repository's own
# work tree) exits 0 without running its tool, so it never runs twice.
for script in "${scripts[@]}"; do
  clear_logs
  (cd "$work/cwd" && PATH="$shims:$real_path" sh "$root/.lefthook/pre-commit/$script.sh" doc.md)
  assert_exit "$script in a work tree exits 0" 0 "$?"
  assert_eq "$script in a work tree runs no tool" '' "$(ls "$work"/*.log 2>/dev/null)"
done

# Case 3: a real consumer. lefthook install fetches the stand-in remote at main
# and a commit's staged files reach each job the way lefthook-base selects them.
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
      - components/lefthook-shellcheck/lefthook-remote.yml
YAML
(cd "$consumer" && lefthook install >/dev/null 2>&1)
fetched="$(find "$consumer/.git/info/lefthook-remotes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"
assert_file_exists 'lefthook install fetched the remote' "$fetched/.lefthook/pre-commit/standards-typos.sh"
dump="$(cd "$consumer" && lefthook dump 2>/dev/null)"
for script in "${scripts[@]}"; do
  assert_contains "the merged config holds $script" "$dump" "name: $script"
done

mkdir -p "$consumer/node_modules/.bin" "$consumer/docs" "$consumer/lib/deep"
cp "$shims/markdownlint-cli2" "$consumer/node_modules/.bin/"
printf '# Title\n' >"$consumer/docs/doc.md"
printf '# Notes\n' >"$consumer/NOTES.md"
printf 'root\n' >"$consumer/README.txt"
printf '#!/usr/bin/env bash\necho ok\n' >"$consumer/run.sh"
cp "$consumer/run.sh" "$consumer/lib/deep/x.bash"
git -C "$consumer" add docs/doc.md NOTES.md README.txt run.sh lib/deep/x.bash
cp "$consumer/lefthook.yml" "$work/lefthook.yml"
# The globs select root and nested files once each under either matcher, so a
# consumer still extending lefthook-base (glob_matcher: doublestar) gets the same.
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
  for tool in typos editorconfig-checker; do
    assert_eq "$matcher matcher: $tool gets every staged file" 'NOTES.md README.txt docs/doc.md lib/deep/x.bash run.sh' \
      "$(sed '1,2d' "$work/$tool.log" 2>/dev/null | sort | xargs)"
  done
  assert_eq "$matcher matcher: markdownlint gets each staged markdown file once" 'NOTES.md docs/doc.md' \
    "$(sed '1,2d' "$work/markdownlint-cli2.log" 2>/dev/null | sort | xargs)"
  assert_eq "$matcher matcher: shellcheck gets each staged shell script once" 'lib/deep/x.bash run.sh' \
    "$(sed '1,2d' "$work/shellcheck.log" 2>/dev/null | sort | xargs)"
done
cp "$work/lefthook.yml" "$consumer/lefthook.yml"

# Case 4: with no local markdownlint-cli2, the job fails like the other tools.
rm -rf "$consumer/node_modules"
clear_logs
out="$(cd "$consumer" && PATH="$shims:$real_path" lefthook run pre-commit --job standards-markdownlint 2>&1)"
assert_nonzero 'a missing markdownlint-cli2 fails its job' "$?"
assert_contains 'the failure names the missing binary' "$out" 'node_modules/.bin/markdownlint-cli2 not found. Run: npm ci'

# Case 5: a missing tool fails its job with an install pointer.
# node stays reachable: an npm-installed lefthook is a node script.
mkdir -p "$work/bare-bin"
for bin in git lefthook node; do
  if command -v "$bin" >/dev/null 2>&1; then ln -s "$(command -v "$bin")" "$work/bare-bin/$bin"; fi
done
bare_path="$work/bare-bin:/usr/bin:/bin"
if PATH="$bare_path" command -v typos >/dev/null 2>&1; then
  skip_case 'typos is installed system-wide, so no PATH hides it'
else
  out="$(cd "$consumer" && PATH="$bare_path" lefthook run pre-commit --job standards-typos 2>&1)"
  assert_nonzero 'a missing typos fails its job' "$?"
  assert_contains 'the failure names the missing tool' "$out" 'typos is not on PATH'
fi

# Case 6: real tools against fixtures only the standards config rejects.
git -C "$consumer" -c commit.gpgsign=false commit -q -m seed --no-verify
if command -v typos >/dev/null 2>&1; then
  printf 'The %s box.\n' "gr""ey" >"$consumer/box.txt"
  assert_exit 'typos alone accepts the fixture' 0 "$(
    cd "$consumer" && typos --isolated box.txt >/dev/null 2>&1
    echo $?
  )"
  git -C "$consumer" add box.txt
  (cd "$consumer" && lefthook run pre-commit --job standards-typos >/dev/null 2>&1)
  assert_nonzero 'standards-typos rejects it with the fetched _typos.toml' "$?"
  git -C "$consumer" rm -q --cached box.txt
else
  skip_case 'typos not on PATH'
fi
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2016 # the fixture's own text
  printf '#!/usr/bin/env bash\nx=1\nif [ -n "$x" ]; then echo "$x"; fi\n' >"$consumer/single.sh"
  assert_exit 'shellcheck without an rcfile accepts the fixture' 0 "$(
    cd "$consumer" && shellcheck --norc single.sh >/dev/null 2>&1
    echo $?
  )"
  git -C "$consumer" add single.sh
  out="$(cd "$consumer" && lefthook run pre-commit --job standards-shellcheck 2>&1)"
  assert_nonzero 'standards-shellcheck rejects it with the fetched .shellcheckrc' "$?"
  assert_contains 'the finding is the rcfile-enabled double-bracket check' "$out" 'SC2292'
else
  skip_case 'shellcheck not on PATH'
fi

[[ $FAILED -eq 0 ]] || exit 1
