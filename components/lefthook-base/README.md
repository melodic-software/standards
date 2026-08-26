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

No fragment in this component set declares a `skip`, at the hook level or the
command level. Whether a lane sits out merge and rebase commits is the
consumer's call, written per lane in its own root `lefthook.yml`.

That is a policy, not an oversight, and it took two attempts to get right.

A hook-level `skip` short-circuits the entire merged `pre-commit` hook.
Lefthook's `extends` folds every fragment and the consumer's root file into one
hook, and an extended file's setting wins over the consumer's, so a single
`skip: [merge, rebase]` in this fragment disabled every lane on a merge commit
-- Gitleaks included, and any security lane the consuming repository declared
itself. A repository owning an artifact guard over captured traffic had nothing
in its own file mentioning a skip and inherited the bypass invisibly. Skipping
a spelling gate on a conflict resolution is right; skipping a secret scan is
not, because a credential staged while resolving a conflict enters history
exactly as permanently as one typed by hand.

Moving the skip onto each command fixes that and breaks a second contract. The
extended file still wins, so a `skip` on a lane defeats the consumer's
documented `skip: true` override for that same lane -- covered by
`lefthook-shellcheck`'s contract test. Both failures have one root: a fragment
deciding something only the consumer has the standing to decide.

So consumers own it. A repository that wants relief from long rebases writes
`skip: [merge, rebase]` on the hygiene lanes it chooses. It should never write
one on a secret scan.

`lefthook-merge-skip.test.sh` pins all of it: Gitleaks and a consumer-declared
security lane both run under forced merge state, a consumer can still opt its
own lane out, and every fragment in the component set is asserted to declare no
`skip` at all -- an invariant over the whole set rather than the files a given
change happens to touch.

`lefthook-base.test.sh` builds a temporary consumer, composes the managed
fragment, and proves the Markdownlint lane resolves the consumer's own
`node_modules/.bin` binary rather than an arbitrary one on `PATH`, and that a
missing local install fails loudly with its remediation.
