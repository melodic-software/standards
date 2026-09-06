#!/usr/bin/env bash
# Contract test for local-lane-guards: dispatcher help/unknown-guard, and each
# driver fails closed on a planted finding while passing a clean temp repo.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

HERE="$root/components/local-lane-guards"
DISPATCH="$HERE/run-local-lane-guards.sh"

out="$("$DISPATCH" --help)"
assert_exit 'dispatcher --help exits 0' 0 "$?"
assert_contains 'help lists every guard' "$out" 'comment-hygiene'
assert_contains 'help lists exec-bit' "$out" 'exec-bit'
assert_contains 'help lists machine-specific-paths' "$out" 'machine-specific-paths'
assert_contains 'help lists reference-integrity' "$out" 'reference-integrity'

"$DISPATCH" not-a-guard >/dev/null 2>&1
assert_exit 'unknown guard exits 2' 2 "$?"

# Every driver exercise runs inside an isolated git repo so pathspecs and
# index-mode checks cannot see this repository's own tree.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email 'local-lane-guards-test@example.com'
  git -C "$dir" config user.name 'local-lane-guards-test'
}

# --- exec-bit ---
make_repo "$tmpdir/exec-clean"
printf '#!/usr/bin/env bash\necho ok\n' >"$tmpdir/exec-clean/ok.sh"
git -C "$tmpdir/exec-clean" add ok.sh
git -C "$tmpdir/exec-clean" update-index --chmod=+x -- ok.sh
git -C "$tmpdir/exec-clean" commit -qm 'clean shebang'
(
  cd "$tmpdir/exec-clean" || exit 1
  bash "$DISPATCH" exec-bit >/dev/null
)
assert_exit 'exec-bit passes a 100755 shebang' 0 "$?"

make_repo "$tmpdir/exec-bad"
printf '#!/usr/bin/env bash\necho bad\n' >"$tmpdir/exec-bad/bad.sh"
git -C "$tmpdir/exec-bad" add bad.sh
# leave mode 100644
git -C "$tmpdir/exec-bad" commit -qm 'bad shebang'
(
  cd "$tmpdir/exec-bad" || exit 1
  bash "$DISPATCH" exec-bit >/dev/null 2>&1
)
assert_exit 'exec-bit fails a 100644 shebang' 1 "$?"

# A `#!` past line 1 is not a shebang file (docs, fenced examples). The
# previous cat-file byte-0 check skipped these; line-number 1 is the same
# filter without a per-candidate blob read.
make_repo "$tmpdir/exec-not-byte0"
# shellcheck disable=SC2016 # backticks and #! are fixture content, not expansion
printf 'example:\n```\n#!/usr/bin/env bash\necho demo\n```\n' >"$tmpdir/exec-not-byte0/README.md"
git -C "$tmpdir/exec-not-byte0" add README.md
git -C "$tmpdir/exec-not-byte0" commit -qm 'embedded shebang example'
(
  cd "$tmpdir/exec-not-byte0" || exit 1
  bash "$DISPATCH" exec-bit >/dev/null
)
assert_exit 'exec-bit ignores a #! that is not at byte 0' 0 "$?"

# Spawn census: N shebang files must not spawn N git ls-files / cat-file.
# Drift-immune counter, same PATH-shim method as distribution/sync-manifest.test.sh.
spawn_dir="$tmpdir/exec-spawn"
make_repo "$spawn_dir"
i=1
while [[ "$i" -le 8 ]]; do
  printf '#!/usr/bin/env bash\necho %s\n' "$i" >"$spawn_dir/s$i.sh"
  git -C "$spawn_dir" add "s$i.sh"
  git -C "$spawn_dir" update-index --chmod=+x -- "s$i.sh"
  i=$((i + 1))
done
git -C "$spawn_dir" commit -qm 'eight shebang files'
mkdir -p "$spawn_dir/bin"
cat >"$spawn_dir/bin/git" <<'SH'
#!/usr/bin/env bash
REAL_GIT="${REAL_GIT:?}"
COUNT_DIR="${COUNT_DIR:?}"
for argument in "$@"; do
  case "$argument" in
  grep)
    echo $(($(cat "$COUNT_DIR/grep" 2>/dev/null || echo 0) + 1)) >"$COUNT_DIR/grep"
    ;;
  ls-files)
    echo $(($(cat "$COUNT_DIR/ls-files" 2>/dev/null || echo 0) + 1)) >"$COUNT_DIR/ls-files"
    ;;
  cat-file)
    echo $(($(cat "$COUNT_DIR/cat-file" 2>/dev/null || echo 0) + 1)) >"$COUNT_DIR/cat-file"
    ;;
  esac
done
exec "$REAL_GIT" "$@"
SH
chmod +x "$spawn_dir/bin/git"
: >"$spawn_dir/grep"
: >"$spawn_dir/ls-files"
echo 0 >"$spawn_dir/cat-file"
real_git="$(command -v git)"
(
  cd "$spawn_dir" || exit 1
  COUNT_DIR="$spawn_dir" REAL_GIT="$real_git" PATH="$spawn_dir/bin:$PATH" \
    bash "$DISPATCH" exec-bit >/dev/null
)
assert_exit 'exec-bit passes eight 100755 shebang files under a git shim' 0 "$?"
assert_eq 'exec-bit greps the index once' '1' "$(cat "$spawn_dir/grep")"
assert_eq 'exec-bit batches staged-mode reads into one ls-files' '1' "$(cat "$spawn_dir/ls-files")"
assert_eq 'exec-bit does not cat-file per candidate' '0' "$(cat "$spawn_dir/cat-file")"
if grep -E '^[[:space:]]*declare[[:space:]]+-A' "$HERE/check-exec-bit.sh" >/dev/null; then
  fail 'exec-bit stays bash-3.2-safe (no declare -A)' \
    'found a declare -A assignment (comments may mention the forbidden form)'
else
  pass 'exec-bit stays bash-3.2-safe (no declare -A)'
fi

# --- machine-specific-paths ---
make_repo "$tmpdir/path-clean"
printf 'root = <repo-root>/src\n' >"$tmpdir/path-clean/config.ini"
git -C "$tmpdir/path-clean" add config.ini
git -C "$tmpdir/path-clean" commit -qm 'portable path'
(
  cd "$tmpdir/path-clean" || exit 1
  bash "$DISPATCH" machine-specific-paths >/dev/null
)
assert_exit 'machine-specific-paths passes a portable placeholder' 0 "$?"

make_repo "$tmpdir/path-bad"
# Build the planted path at runtime without a contiguous `/home/<user>/`
# literal in this source — the repo-wide gate (and older action-bundled
# patterns that still admit `%` in the user segment) would flag it.
user=alice
home_root="/ho"'me'"/$user"
printf 'root = %s/project/src\n' "$home_root" >"$tmpdir/path-bad/config.ini"
git -C "$tmpdir/path-bad" add config.ini
git -C "$tmpdir/path-bad" commit -qm 'machine path'
(
  cd "$tmpdir/path-bad" || exit 1
  bash "$DISPATCH" machine-specific-paths >/dev/null 2>&1
)
assert_exit 'machine-specific-paths fails a Linux home path' 1 "$?"

# --- comment-hygiene ---
make_repo "$tmpdir/ch-clean"
printf '# A plain explanatory comment.\necho ok\n' >"$tmpdir/ch-clean/clean.sh"
git -C "$tmpdir/ch-clean" add clean.sh
git -C "$tmpdir/ch-clean" commit -qm 'clean comment'
(
  cd "$tmpdir/ch-clean" || exit 1
  bash "$DISPATCH" comment-hygiene >/dev/null
)
assert_exit 'comment-hygiene passes a clean comment' 0 "$?"

make_repo "$tmpdir/ch-bad"
printf '# TODO: replace this stub\necho bad\n' >"$tmpdir/ch-bad/bad.sh"
git -C "$tmpdir/ch-bad" add bad.sh
git -C "$tmpdir/ch-bad" commit -qm 'todo comment'
(
  cd "$tmpdir/ch-bad" || exit 1
  bash "$DISPATCH" comment-hygiene >/dev/null 2>&1
)
assert_exit 'comment-hygiene fails a TODO comment' 1 "$?"

# Spawn census: N git-grep comment hits must not spawn N awk (single-line
# fast path in the policy library). Drift-immune PATH shim, same method as
# the exec-bit census above.
ch_spawn="$tmpdir/ch-spawn"
make_repo "$ch_spawn"
i=1
while [[ "$i" -le 8 ]]; do
  printf '# TODO: item %s\necho %s\n' "$i" "$i" >"$ch_spawn/c$i.sh"
  git -C "$ch_spawn" add "c$i.sh"
  i=$((i + 1))
done
git -C "$ch_spawn" commit -qm 'eight todo comments'
mkdir -p "$ch_spawn/bin"
echo 0 >"$ch_spawn/awk"
real_awk="$(command -p -v awk)"
cat >"$ch_spawn/bin/awk" <<'SH'
#!/bin/bash
COUNT_DIR="${COUNT_DIR:?}"
echo $(($(<"$COUNT_DIR/awk") + 1)) >"$COUNT_DIR/awk"
exec "$REAL_AWK" "$@"
SH
chmod +x "$ch_spawn/bin/awk"
(
  cd "$ch_spawn" || exit 1
  COUNT_DIR="$ch_spawn" REAL_AWK="$real_awk" PATH="$ch_spawn/bin:$PATH" \
    bash "$DISPATCH" comment-hygiene >/dev/null 2>&1 || true
)
assert_eq 'comment-hygiene does not spawn awk per git-grep hit' '0' "$(cat "$ch_spawn/awk")"

# --- reference-integrity ---
make_repo "$tmpdir/ref-clean"
printf '# Target\n\nBody.\n' >"$tmpdir/ref-clean/target.md"
# shellcheck disable=SC2016 # backticks are markdown cite syntax, not shell expansion
printf 'See `target.md` "Target" for details.\n' >"$tmpdir/ref-clean/source.md"
git -C "$tmpdir/ref-clean" add target.md source.md
git -C "$tmpdir/ref-clean" commit -qm 'resolving cite'
(
  cd "$tmpdir/ref-clean" || exit 1
  bash "$DISPATCH" reference-integrity >/dev/null
)
assert_exit 'reference-integrity passes a resolving cite' 0 "$?"

make_repo "$tmpdir/ref-bad"
printf '# Target\n\nBody.\n' >"$tmpdir/ref-bad/target.md"
# shellcheck disable=SC2016 # backticks are markdown cite syntax, not shell expansion
printf 'See `target.md` "Missing Anchor" for details.\n' >"$tmpdir/ref-bad/source.md"
git -C "$tmpdir/ref-bad" add target.md source.md
git -C "$tmpdir/ref-bad" commit -qm 'broken cite'
(
  cd "$tmpdir/ref-bad" || exit 1
  bash "$DISPATCH" reference-integrity >/dev/null 2>&1
)
assert_exit 'reference-integrity fails an unresolved cite' 1 "$?"

# Dispatcher `all` on a clean repo succeeds end-to-end.
make_repo "$tmpdir/all-clean"
printf '#!/usr/bin/env bash\necho ok\n' >"$tmpdir/all-clean/ok.sh"
printf '# fine\necho x\n' >"$tmpdir/all-clean/note.sh"
printf 'path = <repo-root>/a\n' >"$tmpdir/all-clean/cfg.ini"
# shellcheck disable=SC2016 # backticks are markdown cite syntax, not shell expansion
printf '# Heading\n\nSee `doc.md` "Heading".\n' >"$tmpdir/all-clean/doc.md"
git -C "$tmpdir/all-clean" add ok.sh note.sh cfg.ini doc.md
git -C "$tmpdir/all-clean" update-index --chmod=+x -- ok.sh note.sh
git -C "$tmpdir/all-clean" commit -qm 'all clean'
(
  cd "$tmpdir/all-clean" || exit 1
  bash "$DISPATCH" all >/dev/null
)
assert_exit 'dispatcher all passes a clean repo' 0 "$?"

[[ $FAILED -eq 0 ]] || exit 1
