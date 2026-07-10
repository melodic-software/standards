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
