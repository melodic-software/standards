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

## Remote form

`lefthook-remote.yml` runs the same four checks from a Lefthook
[remote](https://lefthook.dev/configuration/remotes/) instead of a synced
copy. A consumer lists it under a `remotes:` entry for this repository:

```yaml
min_version: "2.0.5"
assert_lefthook_installed: true
remotes:
  - git_url: https://github.com/melodic-software/standards
    ref: main
    refetch_frequency: 24h
    configs:
      - components/lefthook-base/lefthook-remote.yml
      - components/lefthook-shellcheck/lefthook-remote.yml
```

Each job runs a script under the repository root's `.lefthook/pre-commit/`,
where Lefthook requires a remote's scripts to live. The script finds the
standards config two directories above itself in the fetched copy and passes it
to its tool: Typos `-c _typos.toml`, Gitleaks `--config .gitleaks.toml`,
EditorConfig-checker `-config .editorconfig-checker.json`, and
markdownlint-cli2 `--config .markdownlint-cli2.jsonc`. Files are selected as in
`lefthook.yml`: every staged file for Typos and EditorConfig-checker, staged
Markdown for markdownlint-cli2, and the staged diff for Gitleaks.

The remote form needs Lefthook 2.0.5 or later, the first release that passes
`args` such as `{staged_files}` to a script
([changelog](https://github.com/evilmartians/lefthook/blob/master/CHANGELOG.md#205-2025-12-02),
[`args`](https://lefthook.dev/configuration/args/)); an older Lefthook runs the
scripts with no files. The remote form declares no top-level settings, because
remote configs merge after the consumer's `lefthook.yml` and would override it.
So the consumer's own `lefthook.yml` carries the settings `lefthook.yml` would
have supplied through `extends`: `min_version: "2.0.5"` and
`assert_lefthook_installed: true`, as in the example, and `parallel: true`
under `pre-commit` if it wants the jobs run in parallel. The globs match the
same files with or without `glob_matcher: doublestar`.

A missing tool fails its job with an install pointer, as in `lefthook.yml`;
for markdownlint-cli2 the pointer is `npm ci`, which the job does not run
itself. A script outside a fetched remote, such as this repository's own work
tree, exits without running its tool, because Lefthook runs a script from every
source directory that holds it. A failed refetch leaves the last fetched copy
in force, with a warning.

`lefthook-remote.test.sh` runs each script from two fetched locations and
checks the config path it passes, then has a consumer fetch a stand-in remote
and checks the files and configs each job receives. Where Typos or ShellCheck
is installed, it commits a fixture only the standards config rejects.

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
`node_modules/.bin` binary rather than an arbitrary one on `PATH`. Because
`node_modules` is per worktree, a missing local binary makes the lane run
`npm ci` and then lint; if that install fails or leaves no binary, the lane
fails loudly with its remediation.
