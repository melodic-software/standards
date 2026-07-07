# Track B — config & file distribution: build & activation plan

The Track B counterpart to [plan.md](plan.md). Findings and the mechanism
rationale live in [research/config-distribution.md](research/config-distribution.md);
this file is the build sequence and the gated activation checklist. Nothing here
is wired yet — the artifacts below are inert until the gated steps are approved.

## Decisions (recap)

From the 2026-06-28 research (do not re-litigate; see the research doc):

- **Two layers.** Layer 1 = true single-source via native `extends` / package
  registries, for the tools that support it. Layer 2 = first-party automated sync
  for the irreducible remainder.
- **Maximum single-source.** Adopt Layer 1 wherever a tool supports it.
- **Build the sync first-party** in `ci-workflows` (not a third-party action).
- **Operating rule.** Edits happen upstream in `standards`; downstream synced
  copies are read-only-by-convention; changes route through an upstream PR.

## Layer assignment

- **Layer 1 — `extends`/package (build the base once, consumer carries a stub):**
  - `biome.json`, `tsconfig.json` → publish `@melodic-software/biome-config` /
    `@melodic-software/tsconfig` to GitHub Packages (the npm scope must equal
    the org login); consumers extend the package. Sources live under
    [`packages/`](../../packages/), which carry only the package manifest — the
    config is staged in from `modules/typescript/` at publish time, so the
    module stays the single committed source.
  - `markdownlint` → package `extends` if confirmed, else Layer 2 **[re-verify]**.
  - `.NET` (`dotnet.globalconfig` + analyzer ruleset; optionally
    `Directory.Build.props`) → NuGet config package. Note: package-delivered
    files are cache-only, not agent-editable — acceptable for hands-off
    enforcement; keep any file an agent must edit locally on Layer 2 instead.
- **Layer 2 — sync the real file (read-only downstream):** `ruff.toml`,
  `pyrightconfig.json`, `.gitleaks.toml`, `.shellcheckrc`, `_typos.toml`,
  `.editorconfig-checker.json`, `PSScriptAnalyzerSettings.psd1`,
  `modules/lefthook/*.yml`, root `.editorconfig`, `.gitattributes`, and the
  `harness/` + `fixtures/` directories (only into repos that run them).

## The distribution manifest (Layer 2)

A first-party manifest, owned by `standards`, that the sync workflow reads. It
must encode the two destination layouts already in use across the constellation
(see [rollout.md](rollout.md)): some consumers copy configs to the repo **root**
and pass explicit `config` inputs; others vendor them under **`modules/`** and
rely on the action defaults. The live draft manifest is the single source of truth:
[`distribution/sync-manifest.yml`](../../distribution/sync-manifest.yml) (inert
until the engine is wired). Schema:

- `files.<tool>` — `source` (path in standards) plus a destination per layout
  (`root`, `modules`). An absent layout key means "not applicable to that layout"
  and the engine skips it — used by the `*-stub` files, which are modules-layout
  only (root-layout consumers already have the real config at root).
- `targets[]` — `repo` (owner/name), `layout` (root|modules), and `include` (the
  `files` keys that repo receives).

It carries the full Layer-2 set — including `comment-hygiene` (the file whose
manual re-sync motivated Track B) and the root extend-stubs the modules-layout
consumers need — plus every known consumer with its rollout.md layout. **Confirm
each target's include list against the live repo at activation** (rollout.md is
a dated snapshot).

Still open for activation: whether `lefthook` fragments and the `harness/` +
`fixtures/` directories ride this manifest (they need directory, not per-file,
sync) or a separate stanza, since not every consumer runs the harness.

## The sync mechanism (Layer 2, first-party)

Two pieces, each its own PR, dogfooded, SHA-pinned (architecture
[D5](architecture.md)), one concern per change:

1. **Reusable workflow in `ci-workflows`** (e.g. `standards-sync.yml`): checks out
   `standards` at a pinned ref, reads the manifest, copies each included file to
   its per-layout destination in each target, and opens a PR per target via a
   pinned `create-pull-request`. PR-per-repo is the review surface and the
   out-of-sync signal (drift). A sync run is *execution*, so it belongs in
   `ci-workflows` next to Track A — consistent with the seam rules.
2. **Caller workflow in `standards`**: live at
   [`.github/workflows/sync.yml`](../../.github/workflows/sync.yml) (the source
   of truth — the snippet this section used to carry is superseded). Triggers on
   push to `main` (paths: the distributed files), a weekly schedule, and manual
   dispatch (dry-run by default, with a `targets` allowlist for pilots/staged
   rollout); calls the reusable engine SHA-pinned (D5) with the App secrets.
   It was added at activation — not earlier, because an unpinned ref to a
   not-yet-merged reusable workflow would fail standards' own zizmor/actionlint
   lanes — and activated in two stages (dispatch-only until the single-target
   pilot passed, then the push + schedule triggers).

The reusable engine itself is authored (inert) at
`ci-workflows/.github/workflows/standards-sync.yml` — `dry-run` defaults true, so
it plans without writing until the gates clear; validate it against `ci-workflows`'
own actionlint + zizmor lanes before merging.

Mark every synced file as upstream-owned (a header comment where the format
allows, plus CODEOWNERS in the consumer) so an agent knows to change it upstream,
not in place.

## Auth (gated — IaC-first)

The default `GITHUB_TOKEN` cannot write to other repos, so the sync needs a
cross-repo write credential. Use a **GitHub App** (installation token), not a PAT:
least-privilege (`contents: write`, `pull_requests: write`), rotatable — aligns
with the secrets policy. GitHub Apps are free.

**Provider limitation — App creation is manual.** The Pulumi GitHub provider
cannot create a GitHub App: it only exposes
[authentication *as* an existing App](https://www.pulumi.com/registry/packages/github/api-docs/provider/)
(app ID / installation ID / private key) and
[`AppInstallationRepository`](https://www.pulumi.com/registry/packages/github/api-docs/appinstallationrepository/)
for granting an **already-installed** App access to repos; App creation is
unsupported upstream
([terraform-provider-github#2389](https://github.com/integrations/terraform-provider-github/issues/2389)).
Gating activation on "provision the App via Pulumi" would stall at step 1, so
the flow is a one-time manual bootstrap that hands off to IaC:

1. **Bootstrap (manual, once per account):** register the App by hand — or via
   the [App-manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest),
   which keeps the permission set reviewable as code — with `contents: write` +
   `pull_requests: write` only; install it on the account; generate a private
   key. Record the app ID / installation ID; store the private key per the
   secrets policy.
2. **Repo grants stay UI-managed (decision 2026-07-06, superseding the
   original "manage grants via Pulumi" intent).** `AppInstallationRepository`
   turned out to be unusable here: the grants API rejects GitHub App
   installation tokens, and `github-iac`'s provider authenticates as exactly
   that (its deploy model deliberately stores no PAT-class secret — adding one
   just for grants was weighed and declined; see the closed
   melodic-software/github-iac#38). So the installation's repository access is
   "Only select repositories", edited in the UI when the manifest's target set
   changes — recorded here as provider-inexpressible for this credential model,
   the same class as App registration/installation. A forgotten grant is
   self-signaling: that target's sync leg fails to mint a token.

**Cross-account caveat.** A GitHub App is installed **per account**. The starter
targets span both the org (`melodic-software/*`) and the personal account
(`kyle-sexton/*`), so a single org App cannot mint tokens for the personal
targets. Either install the App on **both** accounts (each via its own
`github-iac` — org `melodic-software/github-iac` and personal
`kyle-sexton/github-iac` — with its own private-key secret), or run the sync as
two installations. `create-github-app-token` mints per-owner (the engine already
scopes by `owner` + `repositories`), so the matrix just needs the right
installation reachable for each target's owner.

## GitHub Packages (gated — cost decision)

Layer 1 for JS/TS (and the .NET NuGet package) publishes to GitHub Packages.

- **Public packages are free.** If `@melodic-software/biome-config` /
  `@melodic-software/tsconfig` (and the .NET config package) may be public, this
  is the free path — surface it as the question and default to it.
- **Private packages are billable** (storage/transfer on the Team plan) — do not
  default here; only if the configs must stay private, and only with approval.

**Decision 2026-07-06: public.** A package first published from this (private)
repo starts private; flip its visibility to public in the package settings UI
right after first publish — there is no API for the flip, and the interim
private storage (a few kB) sits within the plan's free allowance. Note the DX
caveat either way: GitHub Packages npm requires auth **even for public
installs** (`GITHUB_TOKEN` in Actions; a `read:packages` token locally).

Consumer cost of Layer 1: package `extends` pulls a `node_modules` install, so it
suits JS/TS-bearing repos, not pure .NET/PowerShell ones.

## Activation checklist

Ungated (author now, inert until wired):

- [x] Finalize the manifest against the live consumer repos.
- [x] Author the `ci-workflows` reusable sync workflow (PR, dogfooded;
  ci-workflows #50, plus #56 for the `targets` pilot/rollout filter).
- [x] Author the `standards` caller workflow (PR #63 — dispatch-only until the
  pilot confirms; push + schedule triggers follow).

Gated (need explicit approval before they land):

- [x] **Re-confirm targets against the live repos** — done 2026-07-06: every
  consumer is root-layout now (`kyle-sexton/github-iac` had migrated off
  `modules/` since the rollout.md snapshot — exactly the drift this gate
  exists to catch); dotfiles, both `.github` repos, and ci-workflows' root
  hygiene files added as targets.
- [x] **GitHub Packages visibility** — public (free) confirmed 2026-07-06 for
  `@melodic-software/*`; the .NET config package inherits the same call when it
  is built.
- [x] **GitHub App + access** — org side done 2026-07-06: `melodic-standards-sync`
  (App ID 4233369) registered + installed with exactly `contents: write` +
  `pull_requests: write`, secrets on `standards`. Still open (manual UI, see
  Auth): flip the org installation from "all repositories" to "only select
  repositories" (the 4 org targets), make the App public, and install it on
  the **personal account** (kyle-sexton targets cannot mint tokens until then).
- [ ] Publish the Layer-1 packages; convert pilot consumers to `extends` stubs.
  Package sources + the idempotent publish workflow landed and both packages
  published (`@1.0.0`) 2026-07-06 ([`packages/`](../../packages/),
  `publish-packages.yml`); still open: the public-visibility flip (manual UI —
  no API), then the pilot consumer conversion (medley, the JS/TS-bearing
  consumer), which is blocked on that flip (a private package is unreadable
  from medley's CI token).
  - [x] `@melodic-software/biome-config` MUST carry the enforced `organizeImports`
    `groups` config (`level: on`, URL → node/bun → packages → aliases → relative,
    blank-line separated) currently live in `modules/typescript/biome.json` — NOT
    Biome's plain `"organizeImports": "on"`. Guaranteed structurally: the package
    stages the module file itself at publish time (never a re-authored copy), so
    consumers inherit the enforced grouping by construction.
- [ ] Pilot the Layer-2 sync on one consumer; verify PR + read-only marking;
  then roll out per [rollout.md](rollout.md). Pilot ran green 2026-07-06
  against `melodic-software/github-iac` (its PR #37 carried exactly the drift
  accumulated since the last hand re-sync — merged, signed by the App bot),
  and the org-side rollout completed the same day: all four org targets
  synced and merged (`github-iac` #37, `claude-code-plugins` #27, `.github`
  #8, `ci-workflows` #61). Still open before checking this off: the
  **read-only marking** (upstream-owned header comment + consumer CODEOWNERS)
  and the personal-account legs (blocked on the App install, see the App
  checklist item).

## Self-dogfooding: standards' own configs (the modules/ vs root gap)

A gap surfaced while authoring the Track B docs, and it is the same root cause
Track B addresses. standards vendors its rulesets under `modules/<tool>/` (the
catalog), but most tools auto-discover their config from the **repo root**. CI is
fine — every `ci-workflows` action passes `--config modules/<tool>/...`
explicitly. But **local** surfaces (the lefthook lanes, editors, an AI agent's
editing hook) auto-discover, find nothing at root, and fall back to **tool
defaults** — so local and CI disagree. The shipped `modules/lefthook/base.yml`
omits `--config` by design and **cannot be overridden from a consumer's root
`lefthook.yml`** (verified empirically: an extended file's settings win over the
root file), so the only committed fix is a root-discoverable config.

Fix applied — a tiny root **stub** that `extends` the module SSOT (no duplicated
rules; ruff additionally re-anchors one ignore block, below), for the tools whose
format supports a path-based extend, each verified to parity with the CI
`--config` run:

- `ruff.toml` → `extend = "modules/python/ruff.toml"`, plus a
  `[lint.extend-per-file-ignores]` block re-anchoring the module's path-anchored
  ignores (`tests/**`) at the repo root. Ruff resolves an extended file's
  relative patterns against that file's own directory but against the CWD under
  `--config`, so a pure-extend stub silently narrows the test ignores to
  `modules/python/tests/**` while CI ignores repo-root `tests/**` (8/8 errors on
  the bad fixture and test-file ignore parity, verified both ways).
- `.gitleaks.toml` → `[extend] path = "modules/gitleaks/.gitleaks.toml"` (loads
  the chain stub→module→defaults).
- `biome.jsonc` → `"extends": ["./modules/typescript/biome.json"]`, `root: true`
  over the module's `root: false` (2/2 errors, both ways). It is `.jsonc`, not
  `.json`, because Biome **silently** ignores a commented `biome.json` (falls
  back to defaults with no error), so a commented stub must use `.jsonc`.

Not stubbable — documented as **reference-mode** (CI `--config` is authoritative;
local auto-discovery uses defaults, so author to the stricter default, a safe
subset):

- **markdown** — the module ships a *markdownlint-cli2-format* file, but
  markdownlint's `extends` expects a *markdownlint-format* (flat rules) file; a
  root stub falls back to defaults (verified). Enabling a stub needs a module
  refactor (split the rules into a markdownlint-format file that the cli2 config
  and a root stub both extend) — **deferred** (it would also give consumers
  Layer-1 `extends` for markdown; trigger: the JS/TS Layer-1 package work).
- **typos, shellcheck, editorconfig-checker (`.editorconfig-checker.json`),
  psscriptanalyzer** — no extend mechanism. (`.editorconfig` itself already lives
  at root, so it is unaffected.)
- **pyright, tsc** — no local lane (the overlays leave type-check to CI), so no
  gap.

The Claude editing hook is a `settings.json` surface (separate from the repo); it
auto-discovers like the other local tooling, so the stubs fix it for
ruff/gitleaks/biome, and markdown stays on defaults until the refactor.

Track B relevance: the `modules/`-layout consumers (e.g. `kyle-sexton/github-iac`)
have this identical gap, so these stubs are part of what the manifest distributes
to them; the root-layout consumers already have their config at root and need no
stub.

## Future-pain triggers (from the research)

- A consumer goes public / forks out-of-org → Layer-2 push-with-token is
  unaffected; Layer-1 package `extends` needs an accessible registry — re-check
  visibility (same watch-item class as Track A).
- A tool drops remote `extends` → fall back to Layer 2; keep it as the floor.
- New language → add files + manifest entries; scales linearly.
