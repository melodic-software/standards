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
  modules/
    base/          # language-agnostic (editorconfig, git-hygiene, secrets,
                   #   spelling, markdown, links, shell, ec-check)
    powershell/    # overlay
    dotnet/ python/ typescript/   # overlays
  harness/         # lint dispatcher + shell-test runner + shared test lib
  hooks/           # Lefthook lanes (base + per-module)
  ci/              # reusable workflow callers
  conventions/     # decoupled prose: review criteria + engineering standards
  fixtures/        # good/bad samples per linter (the test inputs)
  docs/            # this plan + ADRs
```

Each module carries a small manifest mapping its files to the path they occupy in a consuming repo, so adoption is mechanical and later scriptable.

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

editorconfig, gitattributes, gitignore, dockerignore, gitleaks, typos, shellcheck, ec-check, lycheeignore + the base Lefthook lane + base CI (editorconfig, typos, secret-scan, osv, docs-link-check, actions-lint). Settle minor ambiguities here (`.gitattributes` per-language EOL split, `.npmrc` placement).

### Phase 3 — Overlays plus remaining CI and hooks

.NET, Python, TypeScript modules; split the multi-stack workflows (`shell-lint`, `yaml-ci`, `markdown-ci`, `security-codeql`) and `lefthook.yml` into per-lane pieces.

### Phase 4 — Prose

Migrate the decoupled review criteria and engineering conventions into `conventions/`, stripping the agent-harness pointers (content is the standard; the harness stays in the agent repo).

## Out of scope (separate efforts, already mapped)

- **Agent-guardrails repo** — `.claude/` hooks, agents, skills, and the plugin marketplace.
- **`project-template` repo** — build scaffold (`Directory.Build.*`, `global.json`, `package.json`, …). It *depends on* this repo; never the reverse.

## Upstream / downstream

Upstream is this repo (source of truth); downstream consumers are `provisioning`, `dotfiles`, and future repos. The drop-in is proven manually in Phase 1. Changes flow down (a new standard propagates) and up (a consumer contributes an improvement back); consumers never silently fork and diverge. Automation stays deferred until churn justifies it.
