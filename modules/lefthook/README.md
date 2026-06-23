# lefthook module

Local git hooks via [Lefthook](https://lefthook.dev/): fast, staged-only
developer feedback that runs the **same** tools this platform already
standardizes — before code leaves the machine. CI remains the authoritative
gate; these hooks just shorten the loop.

The config leans strict — lanes are **check-only** (a hook never silently
rewrites and re-stages your work) and `assert_lefthook_installed` fails loudly if
the binary is missing rather than skipping a check, in line with the
warnings-as-errors posture of the rest of the catalog.

## How it stays decoupled

`standards` is adopted by **copy**, with **no runtime coupling** to this repo
(see [`docs/migration-plan.md`](../../docs/migration-plan.md) Principles). Two
Lefthook composition mechanisms were evaluated against that constraint:

- **`remotes:`** — pulls config from another git repo. Verified to be a live
  `git clone` cached under `.git/info/lefthook-remotes` with a mandatory
  first-fetch and ongoing (configurable) refetch. That is a runtime dependency on
  the upstream repo for every developer — **rejected** (it is exactly the
  coupling the platform forbids).
- **`extends:`** of a copied (vendored) file — the chosen mechanism. The fragment
  is copied into the consumer repo; a consumer's own root `lefthook.yml`
  `extends` it. This is the same open/closed shape the overlays already use
  (Biome `extends` a base, `tsconfig`/`Directory.Build.props` extend/import one).

`extends` paths resolve **relative to the repo root**, and precedence is
`root lefthook.yml` → `extends` → `lefthook-local.yml`. So:

- The **base/overlay fragments win** over a consumer's root config on the same
  lane — the standard cannot be silently weakened in committed config.
- A consumer **adds** new lanes, or **opts a lane out** with `skip: true`, from
  its own root config (a new key merges onto the inherited lane) — without
  editing the fragment.
- A **gitignored `lefthook-local.yml`** overrides anything for one machine — the
  per-developer escape hatch.

Lanes are also **path-free**: each runs `<tool> {staged_files}` and lets the tool
discover its own standards config from the repo root. The fragments never pass a
`--config` path and never re-configure a tool — the per-tool module owns the
config, the per-module fixtures lanes own proving it, these lanes only invoke.

## Contents

- `base.yml` — the foundation every consumer extends. Cross-cutting hygiene lanes
  ([typos](../typos/), [gitleaks](../gitleaks/), [editorconfig](../editorconfig/),
  [shellcheck](../shellcheck/), [markdownlint](../markdown/)) plus the strict
  top-level settings (`min_version`, `assert_lefthook_installed`,
  `glob_matcher: doublestar`, `pre-commit` parallel + skip on merge/rebase).
- `lefthook-powershell.yml` — opt-in [PowerShell](../powershell/) lane
  (PSScriptAnalyzer). It calls `psscriptanalyzer-staged.ps1` via `pwsh -File`
  rather than an inline `-Command` (a complex inline command is split incorrectly
  by the shells Lefthook spawns on Windows); the runner resolves the repo-root
  `PSScriptAnalyzerSettings.psd1` itself and is copied alongside the fragment.
- `lefthook-python.yml` — opt-in [Python](../python/) lanes (`ruff check`,
  `ruff format --check`).
- `lefthook-typescript.yml` — opt-in [TypeScript](../typescript/) lane (Biome).
- `lefthook-dotnet.yml` — opt-in [.NET](../dotnet/) lane (`dotnet format
  whitespace`).

All lanes are **pre-commit** only. There is no `commit-msg` lane (a
conventional-commit validator would mean forking a tool outside this catalog) and
no `pre-push` lane (CI is the gate; pre-push duplicates it and slows pushes).

**Type-checkers and full builds are deliberately CI-only**, not hooked: Pyright,
`tsc`, and the .NET analyzer build need whole-project context (not a per-file
staged check) and would double-report against their CI lanes. The hooks give fast
lint/format feedback; CI owns type correctness.

## Engine

[Lefthook](https://lefthook.dev/) v2 (`min_version: 2.0.0`). Pin it as a project
dependency so every contributor and CI runner gets the same version — for an
npm-based repo, the `lefthook` npm package (a single per-platform binary via
optional dependencies) in `devDependencies`, which is what this repo dogfoods and
what Dependabot tracks. Non-npm repos pin via their package manager (Homebrew,
mise, winget, …) with `min_version` as the floor.

Each lane needs its tool on `PATH` when it runs (the hooks check tools, not just
Lefthook): `typos`, `gitleaks`, `shellcheck`, `editorconfig-checker`, and Node
(for `npx markdownlint-cli2`) for the base; plus `ruff`, Node + Biome, `pwsh` +
PSScriptAnalyzer, or the .NET SDK for the overlays you adopt. Some installs expose
the EditorConfig checker as `ec` (or `ec-windows-amd64` via winget) rather than
`editorconfig-checker` — alias it, or override that lane's `run`.

## Adopt in a repo

1. Copy `base.yml` (and any overlay fragments for languages you use) into the
   consuming repo at `modules/lefthook/` — `extends` resolves relative to the
   repo root, so keep this path. The PowerShell overlay also ships
   `psscriptanalyzer-staged.ps1`; copy it alongside the fragment, same path.
2. Author a root `lefthook.yml` that composes them and adds your project scope:

   ```yaml
   extends:
     - modules/lefthook/base.yml
     - modules/lefthook/lefthook-typescript.yml   # only the overlays you use
   pre-commit:
     commands:
       biome:
         exclude: "vendor/**"        # narrow a lane (new key merges onto the base)
       my-own-lane:
         glob: "**/*.proto"
         run: buf lint {staged_files}   # add your own
   ```

3. Adopt the matching tool modules so each lane's config is discoverable from the
   repo root (e.g. drop `_typos.toml` / `.gitleaks.toml` at the root; have a root
   `biome.json` that `extends` the shipped one).
4. Wire installation so hooks self-install. The `lefthook` npm package installs
   the git hooks from its own `postinstall` (gated off when `CI=true`), so an npm
   repo gets local hooks just by adding the devDependency; set `LEFTHOOK=1` to
   force a CI install, or add `"prepare": "lefthook install"` to be explicit. A
   non-npm repo runs `lefthook install` from its bootstrap. Gitignore
   `lefthook-local.yml` as the per-developer override file.

To opt a lane out entirely, set `skip: true` on it in your root config; to change
it for one machine only, override it in a gitignored `lefthook-local.yml`.

> **`lefthook validate` is pre-merge.** It checks the main config file before
> merging `extends`, so a root config that overrides an inherited lane with a
> `skip:`/`exclude:` stub (no `run:` of its own) will not pass `validate` even
> though the merged config is correct. Inspect the effective merged config with
> `lefthook dump`; the installed hooks run against that merged config regardless.

## Test

`lefthook.test.sh` (on the shell harness) builds a throwaway git repo, vendors
`base.yml`, and composes it from a root `lefthook.yml` via `extends` — proving the
adoption shape works end-to-end: the extended shellcheck lane passes a clean
staged file, fails a non-conforming one (surfacing a ShellCheck code), and is
opted out by a consumer `skip: true` without editing the fragment. It skips
cleanly when `lefthook` or `shellcheck` is absent. CI additionally runs
`lefthook validate` against this repo's own root config, which parses and merges
every fragment and confirms the result is schema-valid.
