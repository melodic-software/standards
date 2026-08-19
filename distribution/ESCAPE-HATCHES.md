# Escape hatches

The sanctioned ways a consuming repository steps outside a synced default.
This document is the consumer-facing index; the [Lifecycle](README.md#lifecycle)
table in the distribution README records the same moves from the manifest's
perspective.

## Opting a repository out of a managed component

Any file this manifest marks `managed` for a repository is replaced on the
next sync, so a local edit to such a file is silently lost. When a managed
copy is wrong, fix the cause upstream in `melodic-software/standards` and let
the sync carry the correction back — never patch the materialized copy
downstream.

To opt a repository out of a managed component, or to customize its copy,
propose a `melodic-software/standards` pull request moving the component from
`managed` to `locally-owned` for that repository in
[`distribution/sync-manifest.yml`](sync-manifest.yml). The synchronizer never
reads, changes, or deletes a `locally-owned` file, so after that change lands
the repository may edit or delete its copy in an ordinary local pull request.
The manifest PR is where the exception is recorded and reviewed — one visible
decision upstream instead of a fight against the sync bot downstream.

## Scoping an engine run to specific targets

Every [engine command](README.md#commands) validates the complete manifest
first — validation is never scoped down, and `validate` accepts no target
filters at all. The filters below narrow which targets a run then acts on:

- `--targets OWNER/REPO[,OWNER/REPO...]` — `matrix` and `plan` only: an exact
  comma-separated allowlist; empty (or omitted) selects every target in
  manifest order. Use it to dry-run one repository's plan without walking the
  fleet.
- `--target OWNER/REPO` — `mappings`, `dest-paths`, and `apply`: the single
  target the command operates on. `apply` additionally verifies the checkout's
  `origin` URL actually identifies that repository before writing anything.
- `--target-root DIR` — `apply` only: the local, disposable target checkout
  that receives the materialization. `apply` never commits, pushes, merges, or
  deletes files; a wrong result is discarded with the checkout.

## Skipping Lefthook lanes

- **Durable, per-repository:** override an inherited lane with Lefthook's
  native `skip: true` in the repository's own `lefthook.yml` — the opt-out the
  lefthook-base component documents. Durable exceptions belong in the
  committed config where review sees them.
- **One-off, human-only:** the `LEFTHOOK=0` environment variable skips every
  hook for a single command — `LEFTHOOK=0 git commit …` in a POSIX shell, or
  in PowerShell:

  ```powershell
  $env:LEFTHOOK = '0'; git commit …
  ```

  Agent sessions are deny-floored out of this bypass in both shells by the
  claude-permissions component (the inline-env Bash forms and every
  `env:LEFTHOOK` reference in PowerShell), and that deny floor is not
  relaxable downstream — an agent that believes a hook is wrong fixes the
  hook's cause or asks a human, never bypasses it. The `--no-verify` git
  flag is likewise denied to agents in both shells; humans remain trusted
  to use either sparingly and to fix the underlying hook failure instead
  of making bypass a habit.
