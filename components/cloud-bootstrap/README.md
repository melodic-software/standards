# Cloud bootstrap

The canonical per-repository cloud bootstrap (SSOT). The exported payload is
[`cloud-bootstrap.sh`](cloud-bootstrap.sh), materialized to each fleet
repository's `.claude/cloud-bootstrap.sh` by
[`distribution/sync-manifest.yml`](../../distribution/sync-manifest.yml) —
so a fix lands here once and fans out as reviewed sync PRs; a hand-copied
per-repo script drifts, a materialized one cannot while it stays `managed`.

The [cloud-environment component](../cloud-environment/README.md) owns the
account-scoped shared environment (the warm cache); this component owns the
repo-scoped bootstrap (the correctness guarantee). The
[frozen calling contract](../cloud-environment/README.md#calling-contract-frozen)
between them lives there: the environment's setup script runs the
materialized `.claude/cloud-bootstrap.sh` with `CLAUDE_CODE_REMOTE=true` and
`CLAUDE_PROJECT_DIR` set to the checkout root. The same file is also the
repo's SessionStart hook (matcher `startup|resume`), as drift repair against
the ~7-day-stale environment cache.

## What the script does

Everything is data-driven from the consuming repo's own manifests — the
script itself carries no repo names, no marketplace identifiers, and no
pinned versions:

- logs the environment snapshot stamp (`/opt/melodic-env-setup.done`, or its
  `/tmp/melodic-env-setup.done` fallback when `/opt` was unwritable at cache
  build) so every session reports which environment build it booted from;
- Node from `.node-version` (via the VM's nvm), `npm ci` from the root
  `package-lock.json`, and the .NET SDK exactly as `global.json` pins,
  repo-local — each skipped when the manifest is absent or already satisfied;
- repairs the shallow single-branch cloud clone (unshallow + make
  `origin/main` resolve) so base-ref diffs work;
- runs the repo's committed `.claude/cloud-bootstrap.local.sh` when present
  (the enrich seam, below);
- registers every marketplace `.claude/settings.json` declares and installs
  every `enabledPlugins` entry set to `true`, whichever marketplace it names.
  A repo that declares nothing gets nothing.

Idempotent and best effort throughout: a failed step costs a tool or a
plugin, never the session, and the cloud-only guard makes the script a no-op
outside cloud sessions (trusted local machines load the settings declaration
natively).

## Take, enrich, or customize

One lever per mode, the same tri-mode the distribution README defines:

- **Take** — the default: the repo's `managed` manifest entry materializes
  this file byte-exact, and sync PRs carry every future change.
- **Enrich** — commit a `.claude/cloud-bootstrap.local.sh` in the consuming
  repo. The canonical script runs it after the generic toolchain stage; it is
  never synced and never overwritten. Same contract as the caller:
  idempotent, best effort, bash-3.2-safe, always exit 0. Use it for extra
  lockfile locations, pinned hygiene binaries, symlinks — anything
  repo-specific.
- **Customize** — move the component to `locally-owned` for that repository
  in `distribution/sync-manifest.yml` (upstream first, then edit the copy
  downstream), per the
  [distribution lifecycle](../../distribution/README.md). The repo then owns
  the whole file.

## Bash compatibility

Both callers run `bash <script>`, so the interpreter is whatever `bash`
resolves to. Stock macOS still ships bash 3.2: no `mapfile`, no arrays
(empty-array expansion aborts under `set -u` before 4.4) — the script and any
`cloud-bootstrap.local.sh` must hold to newline-delimited strings and
`while read` loops.

## This repository's own copy

standards is the manifest source, not a sync target, so its
`.claude/cloud-bootstrap.sh` is kept byte-identical to the component by
[`cloud-bootstrap.test.sh`](cloud-bootstrap.test.sh) (CI-gated) rather than
by the synchronizer. Its enrich seam,
[`.claude/cloud-bootstrap.local.sh`](../../.claude/cloud-bootstrap.local.sh),
installs each component project's own lockfile — the root `package.json`
declares no workspaces, so a root `npm ci` does not reach them.
