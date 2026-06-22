# Migration plan

Phased plan to populate this repo by extracting the language-agnostic quality tooling from the `melodic-software/medley` sandbox (branch `chore/reset-to-template`), decoupled from medley specifics.

## Principles

- **Distribution follows the consumption mechanism.** Executable CI logic is *referenced* (`uses:@sha`); a config a tool finds by walking the directory tree is *copied*. A tree-walked config cannot be referenced, and executable logic should not be copied — match each artifact to how its tool consumes it.
- **Churn decides the channel.** High-churn surfaces (CI execution) are referenced and versioned; the low-churn copy-only residue (root configs) is synced manually until churn justifies automation.
- **No runtime coupling *to this repo*.** `standards` is pure config + fixtures + dogfood CI. The referenced (runtime-coupled) executable workflows live in a *separate* repo (`ci-workflows`), so adopting a `standards` module never makes a consumer depend on `standards` at runtime.
- **Configurable, not forkable (open/closed).** Reusable workflows expose typed `inputs` with global-standard defaults; consumers override repo-specific scope (globs, exclude paths, tool versions, config path) via inputs, never by editing the workflow.
- **Dogfood.** Every module runs against its home repo in CI; each repo is its own first consumer.

## Topology — three repositories

The standard is delivered by a small repo family, each owning one concern with one distribution model:

- **`standards`** (this repo) — source of truth for code-quality **config** (linter/analyzer rulesets) + fixtures + dogfood CI. Adopted by *copy*. No runtime coupling to it.
- **`ci-workflows`** — reusable, configurable CI **execution**: the workflows that install and run each tool, plus runner scripts such as `Invoke-Pssa.ps1`. Consumed by reference (`uses: melodic-software/ci-workflows/.github/workflows/<tool>.yml@<sha>`), SHA-pinned and kept current by Dependabot (reviewed PRs, never auto-merged). High churn lives here.
- **`github-config`** — governance-as-code (org rulesets + custom properties). Its `ci-gate` ruleset *requires* the `ci-status` check.

They meet at stable contracts, not by merging: `github-config` requires `ci-status` → each repo produces it via a thin **local `ci-status` gateway job** (a small copied stub that `needs:` the referenced reusable workflows and aggregates their results; kept local so the required-check name stays un-nested) → the reusable workflows run the tools against the consumer's *copied* `standards` config.

## Repo shape (modular catalog)

A catalog you migrate *from*, organized by module — not a clone-and-go template.

```text
standards/
  .editorconfig .gitattributes .gitignore   # copy-only configs, canonical at root
  modules/                                   # path-pointed configs, copied to consumers (one dir per tool)
    markdown/ powershell/ editorconfig/      # editorconfig/ holds the checker config; rules live at root
    typos/ gitleaks/ shellcheck/ lychee/     # future scanner modules
    dotnet/ python/ typescript/              # future language overlays
  harness/         # shell-test runner + shared test lib
  fixtures/        # good/bad samples per module (the test inputs)
  .github/workflows/   # dogfood CI: callers that use ci-workflows (not reusable workflows themselves)
  hooks/           # future: Lefthook lanes
  conventions/     # future: decoupled prose (review criteria + engineering standards)
  docs/            # this plan + ADRs
```

**Adoption channels.** *Execution* (reusable workflows + runner scripts) is **referenced** from `ci-workflows` (`uses:@sha`) — one source, no copy. *Config* is **copied** into each consumer (no cross-repo runtime read): a tool that takes an explicit path (`--config`, npm `extends`) reads the copy whose canonical home is `modules/<tool>/`; a tool that only walks the directory tree (`.editorconfig`, `.gitattributes`, `.gitignore`) reads the copy at the consumer root, mirroring the canonical root files here (which this repo dogfoods). Each module carries a small manifest mapping its files to the path they occupy in a consuming repo, so adoption is mechanical and later scriptable.

## Cross-cutting method

- **Decoupling (every migrated file):** strip medley specifics — hardcoded paths, skill names, `.NET`/`Platform.*` references, and agent-harness pointers (`/quality-gate`, `.claude/rules`, …). Parameterize scopes.
- **Test strategy (no application code needed):**
  1. Unit tests — the `*.test.sh` and Pester suites via the ported shell harness.
  2. Fixtures — committed good/bad `.md` and `.ps1` that CI asserts pass/fail.
  3. Self-dogfood — the repo lints itself in CI.

## Phases

### Phase 0 — Bootstrap

Create the repo (done); commit this plan; port the harness (`tools/lint`, `tools/shell-test-runner` + `run-shell-tests.sh`, `tests/shell/lib.sh`); stand up `fixtures/` and a CI job that runs the harness. Exit: harness green on an empty module set.

### Phase 1 — Markdown + PowerShell

- **Markdown module:** decoupled `.markdownlint-cli2.jsonc` + good/bad fixtures here; the markdownlint-cli2 CI lane (Node) lives in `ci-workflows` as a reusable workflow. Excludes medley's heading-cite / near-dup corpus gates.
- **PowerShell module:** decoupled `PSScriptAnalyzerSettings.psd1` + fixtures here; the runner (`Invoke-Pssa.ps1`) and the pwsh CI lane live in `ci-workflows` (execution). standards keeps a minimal harness to assert fixtures pass/fail.
- Exit: both run clean on the repo (via `ci-workflows` reusable workflows behind a local `ci-status` gateway), correctly flag the bad fixtures, and a downstream repo (`kyle-sexton/provisioning`) adopts both as the first consumer.

### Phase 2 — Base hygiene

- **Copy-only hygiene configs (done):** `.editorconfig`, `.gitattributes`, `.gitignore` canonical at root, plus the `editorconfig/` checker module + CI lane. `.gitattributes` is the single authority for line endings — `.ps1`/`.psm1`/`.psd1` pinned `lf` (verified to run on PowerShell 7 and Windows PowerShell 5.1), `.cmd`/`.bat` pinned `crlf`; editorconfig `end_of_line` is an editor hint and the checker's end-of-line check is disabled.
- **Referenceable scanner modules (next):** typos, gitleaks (`--config`), shellcheck, lychee — each a vertical slice like markdown/powershell. Plus the base Lefthook lane and remaining base CI.
- **Deferred:** `.dockerignore` and `.npmrc` placement — pick up with the relevant overlay (containers, Node) rather than the agnostic base.

### Phase 3 — Overlays plus remaining CI and hooks

.NET, Python, TypeScript modules (config + fixtures here); split medley's multi-stack workflows (`shell-lint`, `yaml-ci`, `markdown-ci`, `security-codeql`) into per-lane **reusable workflows in `ci-workflows`**, and `lefthook.yml` into per-lane pieces. This is the bulk lift-and-shift from medley: harvest each lane, strip medley specifics, parameterize via inputs.

### Phase 4 — Prose

Migrate the decoupled review criteria and engineering conventions into `conventions/`, stripping the agent-harness pointers (content is the standard; the harness stays in the agent repo).

## Out of scope (separate efforts, already mapped)

- **Agent-guardrails repo** — `.claude/` hooks, agents, skills, and the plugin marketplace.
- **`project-template` repo** — build scaffold (`Directory.Build.*`, `global.json`, `package.json`, …). It *depends on* this repo; never the reverse.

## Upstream / downstream

Upstream is this repo (config source of truth) and `ci-workflows` (execution source of truth); downstream consumers are `provisioning`, `dotfiles`, and future repos. The two channels sync differently: **referenced** execution updates via SHA bumps in reviewed Dependabot PRs (no drift by construction); **copied** config flows down (a new standard propagates) and up (a consumer contributes an improvement back) — proven manually in Phase 1, with consumers never silently forking. Config-sync automation stays deferred until churn justifies it; the per-module manifests are its seed.
