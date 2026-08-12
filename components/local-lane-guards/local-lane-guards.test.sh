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
printf 'root = /home/alice/project/src\n' >"$tmpdir/path-bad/config.ini"
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

# --- reference-integrity ---
make_repo "$tmpdir/ref-clean"
printf '# Target\n\nBody.\n' >"$tmpdir/ref-clean/target.md"
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
