# Lefthook base

Default staged-file feedback for cross-cutting repository hygiene. The exported
`lefthook.yml` fragment supplies strict Lefthook settings plus Typos, Gitleaks,
EditorConfig, and Markdownlint commands. It invokes each tool without policy
flags so the matching root-canonical config remains the single rule owner.

This component is independent from language adapters. A consumer composes only
the fragments it needs from its root `lefthook.yml`; the sync manifest owns the
stable downstream destinations. A repository can add local commands or
explicitly opt out of an inherited lane with Lefthook's native `skip: true`
override. CI remains the authoritative gate.

The fragment is check-only: hooks do not rewrite and restage work. The
repository pins Lefthook in `package.json` and validates the composed local
adapter in CI.

## Merge and rebase commits

Typos, EditorConfig and Markdownlint each opt out of `merge` and `rebase`
individually. Gitleaks does not, and neither does anything a consumer declares
in its own root file.

The distinction is load-bearing, so it is worth stating why the skip is not
written once at the hook level where it would be shorter. Lefthook's `extends`
merges every fragment and the consumer's root file into a single `pre-commit`
hook, and an extended file's setting wins over the consumer's. A hook-level
`skip` in this fragment therefore short-circuits the entire merged hook: the
lanes here, the lanes a language adapter adds, and the lanes the consuming
repository wrote itself. Skipping a spelling or formatting gate on a conflict
resolution is right — a developer should not be failed on lines they did not
write. Skipping a secret scan is not: a credential staged while resolving a
conflict enters history exactly as permanently as one typed by hand.

The consumer case is the sharper one. A repository that owns a security lane of
its own — an artifact guard over captured traffic, say — has nothing in its file
mentioning a skip, and would inherit the bypass invisibly. Governing the opt-out
per command keeps that decision where the lane is declared.

`lefthook-merge-skip.test.sh` pins this: it forces merge state, and asserts that
Gitleaks and a consumer-declared lane both still run while the hygiene lanes do
not. It also fails if a hook-level `skip` reappears in the fragment.

`lefthook-base.test.sh` builds a temporary consumer, composes the managed
fragment, and proves the Markdownlint lane resolves the consumer's own
`node_modules/.bin` binary rather than an arbitrary one on `PATH`, and that a
missing local install fails loudly with its remediation.
