# Research — config & file distribution to consumers

How to stop manually copy/syncing this repo's drop-in files into downstream
consumers. The CI-execution dedup program scopes config OUT ("adopted by
copy"); this revisits that decision for the *files themselves* (configs, prose,
harness, fixtures).

Research verified 2026-06-28 against official docs / maintainer repos (tagged
`[blog]` otherwise). Fast-moving specifics are flagged **[re-verify]**; claims
the research harness could not independently re-confirm (it was API-rate-limited)
are flagged **[primary-sourced, unverified-by-harness]**.

## Decisions taken (2026-06-28)

- **Maximum single-source.** Pursue true de-duplication wherever a tool supports
  it (native remote `extends` + package registries), not just automated copying.
- **Build the sync mechanism first-party** in `ci-workflows`, not a third-party
  action — keeps the broad-write-permission supply chain first-party and
  SHA-pinned (architecture D5), and a sync bot is *execution*, which fits that
  repo's seam.
- Open work graduates into [plan.md](../plan.md) / [rollout.md](../rollout.md)
  when this moves from research to build.

## The core finding

No single mechanism is simultaneously zero-duplication, no-new-infra, and
universal across all tools. The two families do different jobs, so the answer is
**two layers**:

- **Layer 1 — true de-duplication.** Content lives *once* upstream; the consumer
  references it (native `extends`, or a package registry). Removes duplication —
  but only for tools that support remote references, and the strongest form needs
  publishing infra.
- **Layer 2 — automated sync.** A first-party job copies the real file into each
  consumer and opens a PR. Files still exist everywhere (duplication remains),
  but the manual labor and drift are gone. Universal; minimal infra.

Two hard constraints shaped this and eliminate the "obvious" answers:

- **A) Source layout != destination layout.** `modules/<tool>/<file>` upstream
  must land at each tool's natural path (often repo root) downstream.
- **B) Agent-editable in place.** A coding agent must read/edit a *real* file at
  the natural path.

Ruled out by A+B:

- **git submodule / subtree** — fail A (mount a tree at a fixed path; no per-file
  remap) and B (content sits in a subdir the tools-at-root can't read; symlink /
  sparse-checkout workarounds are fragile, and symlinks are a Windows pain
  point).
- **NuGet config package** for arbitrary editing — see Layer 1; it ships config
  but restores to the package cache, not an editable repo file (fails B).

## Layer 1 — native `extends` / package distribution

The consumer keeps a tiny *real, editable* stub pointing at a shared base, so
policy lives once. Per-tool support, each verified against the tool's own docs:

- **Biome — yes.** `extends` accepts file paths *and npm packages* (e.g.
  `@org/biome-config/biome`); also loads `.editorconfig` (v1.9+)
  **[re-verify version]**.
- **TypeScript `tsconfig` — yes.** `extends` uses Node-style resolution, so it
  can extend a base inside an installed npm package.
- **markdownlint-cli2 — partial.** `extends` is supported; resolution is
  delegated to the `markdownlint` lib — confirm package-based resolution
  **[re-verify]**.
- **Ruff — no.** `extend` is a filesystem path only; no remote/package support in
  the docs **[re-verify — Astral moves fast]**.
- **editorconfig — n/a.** `root` + cascade, not a remote-extends model.
- **gitleaks, shellcheck, typos, psscriptanalyzer, pyright, lefthook — no.**
  Treat as Layer 2 whole-file sync.

Cross-repo `extends` needs the base *reachable*: a relative path can't span
repos, so the base must be published as a package (GitHub Packages npm registry)
for true single-source. Per the maximum-single-source decision, publish
`@melodic/biome-config` and `@melodic/tsconfig`; consumers carry a stub
(`{"extends": ["@melodic/biome-config"]}`).

- Cost: package-based `extends` pulls a `node_modules` install — natural in JS/TS
  repos, unwanted weight in a pure .NET/PowerShell repo. So this layer targets
  the JS/TS-bearing consumers.

For .NET, the analogue is a NuGet config package: `.globalconfig` plus a `.props`
(with a `GlobalAnalyzerConfigFiles` item, in the package `build/` folder)
distributes analyzer config; `Directory.Build.props`/`.targets` inject MSBuild
logic; Central Package Management (`Directory.Packages.props`,
`ManagePackageVersionsCentrally`) centralizes versions. True single-source — but
with `PackageReference`, packages restore to the machine-wide global-packages
cache, *not an editable repo file* (fails constraint B). `.editorconfig` can't be
packaged at all (must exist on disk).

- So .NET forces the sharpest version of the tradeoff: single-source enforcement
  (NuGet package) vs. agent-editable (synced loose file). Choose per file:
  default analyzer/globalconfig to the package; keep anything an agent must edit
  locally as a Layer-2 sync.

Sources: Biome configuration reference; TypeScript `tsconfig` `extends`; Ruff
configuration; markdownlint-cli2 configuration; Microsoft Learn — code-analysis
config files, MSBuild props/targets in NuGet, Central Package Management,
PackageReference; `[blog]` esslinger.dev, kenmuse.com.

## Layer 2 — first-party automated sync (the irreducible remainder)

Everything without remote `extends` (and any base not packaged) needs the real
file copied into each consumer, kept current automatically.

### Operating rule — synced files are read-only downstream

A file-sync mechanism makes upstream authoritative and overwrites one-way: an
agent editing a *synced* file *downstream* is seen as drift and reverted on the
next run. Therefore:

- **Edits happen upstream in `standards`** (constraint B holds at the source of
  truth).
- **Downstream synced copies are read-only-by-convention.** A needed change is a
  PR *upstream*, which re-cascades — that is the bidirectional path (constraint
  C), routed through upstream by design, not an in-place downstream edit. Mark
  synced files (header comment / CODEOWNERS / manifest) so an agent knows not to
  edit them locally.
- Configs that genuinely must be *locally* agent-editable should be Layer-1 stubs
  (editable) over a shared base, not whole-file syncs.

### Build (chosen) vs. buy

A sync mechanism needs write tokens to every consumer — a larger blast radius
than the `tj-actions/changed-files` compromise that architecture D5 cites. The
buy options are unattractive: the popular original
<https://github.com/BetaHuhn/repo-file-sync-action> is stale (last push 2024-08,
364 stars); the maintained fork
<https://github.com/step-security/repo-file-sync-action> is current (release
v1.21.3 2026-05-06, pushed 2026-06-22) but 0-star / unvetted (vendor mirror).
Both verified 2026-06-28.

- **Decision: build first-party in `ci-workflows`** — a reusable workflow that
  checks out `standards`, copies per a manifest (source→dest remap satisfies
  constraint A), and opens a PR per target via `create-pull-request`. Stays
  first-party and SHA-pinned per D5; PR-per-repo is reviewable and the PR's
  existence is the drift signal (constraint D).
- The third-party actions remain the reference for the manifest shape: a
  `.github/sync.yml` whose keys are `owner/repo@branch` and whose `dest:` option
  remaps path/filename per file (the capability to reproduce). If buying is ever
  reconsidered, SHA-pin + Dependabot, no exceptions.

### Not a fit — Renovate / Dependabot

Renovate is *not* a file-content sync tool: `customManagers` (formerly
`regexManagers`) only detect/update dependency version strings; config presets
share Renovate config, not arbitrary files (verified). Keep it for SHA-pin bumps.
Dependabot is likewise dependency-scoped.

### Heavier alternative — template-update tooling (deferred)

`copier` has built-in `copier update` (diff-based 3-way merge, tracked via a
committed `.copier-answers.yml`) (verified). `cruft` adds `cruft check` (CI drift
via exit code) over cookiecutter, tracking the template git hash in `.cruft.json`
**[primary-sourced, unverified-by-harness]**. Strong for whole-project
scaffolding + ongoing update; overkill for config sync. Defer, with trigger:
frequent greenfield repo creation.

Sources: repo-file-sync-action (BetaHuhn + step-security) READMEs; netlify
file-sync-action README; Renovate docs (managers, custom managers, presets,
configuration); copier "Updating a project"; cruft README + docs.

## Per-artifact recommendation

- **biome, tsconfig (JS/TS repos)** — Layer 1, package `extends` (`@melodic/*`).
- **markdownlint** — Layer 1 if package-`extends` confirmed, else Layer 2
  **[re-verify]**.
- **ruff, gitleaks, shellcheck, typos, psscriptanalyzer, pyright, lefthook,
  `.editorconfig`, `.gitattributes`** — Layer 2 sync (read-only downstream).
- **`dotnet.globalconfig`, analyzer ruleset** — Layer 1, NuGet config package.
- **`Directory.Build.props`** — NuGet package if hands-off; Layer 2 sync if it
  must stay agent-editable.
- **`conventions/**` (prose)** — reference, don't copy (read-on-demand; copying
  is pure drift surface, and matches the repo's own reference-don't-duplicate
  rule).
- **`harness/**`, `fixtures/**`** — Layer 2 directory sync, only into repos that
  run the harness.

## Industry pattern (innersource)

GitHub's enterprise guidance frames this as innersource: template repositories
for standardized setups + a dedicated `.github` org repo for org defaults.
Templates cover new-repo bootstrap but *not* ongoing sync — the gap Layer 2
fills. Consensus = `.github` defaults + a sync mechanism for ongoing
propagation. Sources: GitHub Docs (use innersource);
<https://github.com/resources/articles/innersource>.

## Future-pain risks

- **Tool changes remote-`extends` support** (e.g. Ruff never adds it; Biome
  changes it): fall back to Layer 2 — keep it as the durable floor.
- **Repo goes public / forks out-of-org:** Layer-2 push-with-token is
  unaffected; package-`extends` needs an accessible registry (GitHub Packages
  visibility) — re-check when a consumer's visibility changes (same watch-item
  class as the CI-execution program).
- **New language:** add `modules/<tool>/` + manifest entries; scales linearly.
- **Manifest sprawl:** generate consumer entries from the `github-iac` inventory
  so onboarding a repo is one IaC change.

## Re-verify before building

- Biome npm-package `extends` + `.editorconfig` loading (version-gated).
- markdownlint-cli2 package-based `extends` resolution.
- Ruff remote/package `extend` (unsupported at research time).
- `.globalconfig` NuGet mechanics (`GlobalAnalyzerConfigFiles`) on current SDK.
- GitHub Packages npm publish/consume auth for private cross-repo `extends`.
- copier `update` preconditions; cruft `check`/`update` (harness-abstained).
