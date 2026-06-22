# Migration plan

Phased plan to populate this repo by extracting the language-agnostic quality tooling from the `melodic-software/medley` sandbox (branch `chore/reset-to-template`), decoupled from medley specifics.

## Principles

- **Reference, don't copy.** The repo is the single source of truth; downstream repos adopt modules and update on their own cadence. No runtime coupling back to this repo.
- **Churn decides the channel.** High-churn surfaces (agent guardrails, CI) are referenced; the low-churn copy-only residue is synced manually until evidence justifies automation.
- **Dogfood.** Every module runs against this repo itself in CI. The repo is its own first consumer.

## Repo shape (modular catalog)

A catalog you migrate *from*, organized by module — not a clone-and-go template.

```text
standards/
  .editorconfig .gitattributes .gitignore   # copy-only configs, canonical at root
  modules/                                   # referenceable, drop-in configs (one dir per tool)
    markdown/ powershell/ editorconfig/      # editorconfig/ holds the checker config; rules live at root
    typos/ gitleaks/ shellcheck/ lychee/     # future scanner modules
    dotnet/ python/ typescript/              # future language overlays
  harness/         # shell-test runner + shared test lib
  fixtures/        # good/bad samples per module (the test inputs)
  .github/workflows/   # one CI lane per module
  hooks/           # future: Lefthook lanes
  conventions/     # future: decoupled prose (review criteria + engineering standards)
  docs/            # this plan + ADRs
```

**Two adoption channels by discovery mechanism.** Configs a tool finds by an
explicit path (`--config`, npm `extends`, a reusable workflow) are
*referenceable* — they live once in a `modules/<tool>/` directory and consumers
point at them. Configs a tool finds only by walking the directory tree
(`.editorconfig`, `.gitattributes`, `.gitignore`) are *copy-only* — they cannot
be referenced, so they live canonically at the **repo root**, where those root
files *are* the published standard (and the repo dogfoods them). Each module
carries a small manifest mapping its files to the path they occupy in a
consuming repo, so adoption is mechanical and later scriptable.

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

- **Markdown module:** decoupled `.markdownlint-cli2.jsonc` + good/bad fixtures + local run + CI lane (markdownlint-cli2, Node). Excludes medley's heading-cite / near-dup corpus gates.
- **PowerShell module:** decoupled `PSScriptAnalyzerSettings.psd1` + `Invoke-Pssa.ps1` (+ Pester) + fixtures + the PSScriptAnalyzer hook/CI lane (pwsh).
- Exit: both run clean on the repo, correctly flag the bad fixtures, and `kyle-sexton/provisioning` adopts both as the first downstream consumer.

### Phase 2 — Base hygiene

- **Copy-only hygiene configs (done):** `.editorconfig`, `.gitattributes`, `.gitignore` canonical at root, plus the `editorconfig/` checker module + CI lane. `.gitattributes` is the single authority for line endings — `.ps1`/`.psm1`/`.psd1` pinned `lf` (verified to run on PowerShell 7 and Windows PowerShell 5.1), `.cmd`/`.bat` pinned `crlf`; editorconfig `end_of_line` is an editor hint and the checker's end-of-line check is disabled.
- **Referenceable scanner modules (next):** typos, gitleaks (`--config`), shellcheck, lychee — each a vertical slice like markdown/powershell. Plus the base Lefthook lane and remaining base CI.
- **Deferred:** `.dockerignore` and `.npmrc` placement — pick up with the relevant overlay (containers, Node) rather than the agnostic base.

### Phase 3 — Overlays plus remaining CI and hooks

.NET, Python, TypeScript modules; split the multi-stack workflows (`shell-lint`, `yaml-ci`, `markdown-ci`, `security-codeql`) and `lefthook.yml` into per-lane pieces.

### Phase 4 — Prose

Migrate the decoupled review criteria and engineering conventions into `conventions/`, stripping the agent-harness pointers (content is the standard; the harness stays in the agent repo).

## Out of scope (separate efforts, already mapped)

- **Agent-guardrails repo** — `.claude/` hooks, agents, skills, and the plugin marketplace.
- **`project-template` repo** — build scaffold (`Directory.Build.*`, `global.json`, `package.json`, …). It *depends on* this repo; never the reverse.

## Upstream / downstream

Upstream is this repo (source of truth); downstream consumers are `provisioning`, `dotfiles`, and future repos. The drop-in is proven manually in Phase 1. Changes flow down (a new standard propagates) and up (a consumer contributes an improvement back); consumers never silently fork and diverge. Automation stays deferred until churn justifies it.
