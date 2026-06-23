# Inventory — current CI state across the constellation

Current-state audit of CI execution in each repo, and a classification of what
to lift into `ci-workflows`. Snapshot taken 2026-06-22/23; re-verify against the
live repos before acting on any row (they change).

## What `ci-workflows` provides today

Composite actions (19): `markdown`, `shellcheck`, `powershell` (PSScriptAnalyzer
via bundled `Invoke-Pssa.ps1`); `editorconfig`, `typos`, `gitleaks`; `actionlint`,
`check-jsonschema`; `lychee-offline` (offline link/anchor integrity); the
repo-hygiene set `exec-bit`, `machine-specific-paths`, `comment-hygiene`,
`eol-renormalize`; and the ecosystem static-analysis set `ruff`, `pyright`
(Python), `biome`, `tsc` (JS/TS), `dotnet-build`, `dotnet-format` (.NET).

Reusable workflows (4): `link-check` (online, advisory, scheduled, files a rolling
tracking issue), `zizmor` (Actions security lint, advisory), `osv-scanner`
(dependency vuln scan, advisory, event-split), and `claude-review` (automated PR
code review, advisory).

## Consumers

### standards

The model consumer. Its `ci.yml` references nearly every `ci-workflows` composite
action (18 of 19 — all but `check-jsonschema`) plus the `zizmor` and `osv-scanner`
reusable workflows, and its `link-check.yml` is a thin caller of the `link-check`
reusable workflow — all pinned by SHA (Dependabot-bumped). The only lanes that
stay local are its per-module fixture tests (standards-specific). Owns the
upstream `modules/<tool>/` config that the config-driven actions consume.

### claude-code-plugins

No CI at all (no `.github/workflows`). Greenfield consumer; wants a turnkey
quality bundle rather than hand-wired lanes.

### medley

The largest consumer and the main duplication target. ~40 lanes across ~27
workflow files, orchestrated by `ci-status.yml` (inline change-detection via
`git diff` + regex per ecosystem; cross-cutting checks always run). Pins all
marketplace actions by SHA. Consumes `ci-workflows` only for the `claude-review`
reusable workflow today (its first reference); every overlapping **quality** lane
is still reimplemented inline or via a third-party action — the Phase 6 cutover
target.

### Greenfield / bare consumers

`github-iac` (org + personal, C# Pulumi), `provisioning` (PowerShell), and
`claude-code-plugins` (greenfield, markdown + plugin JSON) have little or no
quality CI today and are onboarding targets rather than harvest sources — they
have no inline lanes to lift, only blocks to adopt. Their per-repo lane
recommendations and onboarding status live in the adoption tracker
([rollout.md](rollout.md)), not here.

## Classification

Four buckets. `DUP-COVERED` = overlaps an existing `ci-workflows` action (but the
consumer's version may do more — see backfill notes). `DUP-LIFT` = generic and
reusable, not yet here, a lift target. `ECOSYSTEM` = language-stack build/test,
genuinely more repo-specific (lifted in a later phase, opt-in by reference).
`REPO-SPECIFIC` = unique to one repo, stays local.

### DUP-COVERED (exists here; backfill to make medley's cutover lossless)

| Lane (medley) | Backfill needed in `ci-workflows` |
| --- | --- |
| markdown lint | none for lint itself; medley also runs skill-governance + reference-integrity (see DUP-LIFT) |
| shellcheck | medley shell lane also runs shfmt + Pester + bash tests (see DUP-LIFT) |
| powershell (PSScriptAnalyzer) | medley uses the same per-file `Invoke-Pssa.ps1` pattern this repo bundles; confirm input parity |
| lychee (offline link/anchor) | medley adds a heading-cite resolver (see DUP-LIFT) |
| lychee (online docs link check) | covered by the `link-check.yml` reusable workflow; confirm input parity |

### DUP-LIFT (generic; lift as composable building blocks)

Single-tool step lanes (→ composite action):

- `typos` (config already in `standards/modules/typos`)
- `editorconfig-checker` (config already in `standards/modules/editorconfig`)
- `gitleaks` secret scan (config already in `standards/modules/gitleaks`)
- `actionlint` (GitHub Actions workflow linter)
- `check-jsonschema` (YAML schema validation)
- `shfmt` (shell formatter)
- `eol-renormalize` (index-level line-ending drift check)
- `exec-bit` (shebang files must be mode 0755)
- `machine-specific-paths` (reject absolute/user-home paths in tracked files)
- `comment-hygiene` (comment-format scan; patterns become a config input)
- `reference-integrity` heading-cite resolver (pairs with `lychee-offline`)

Whole-job concerns (→ reusable workflow):

- `osv-scanner` (dependency vulnerability scan; advisory today)
- `zizmor` (Actions security lint; advisory today)
- `dependabot-automerge` (semver-gated auto-merge)
- `issue-labeling` (form-driven label assignment)
- `skill-governance` (SKILL.md / portability validation; needs path inputs)
- `Pester` (PowerShell tests; Windows runner)
- bash test harness with walltime regression gate

### ECOSYSTEM (later phase; opt-in by reference)

`.NET` build/test, `.NET` E2E (browser + SQL), Playwright visual regression,
`.NET` format + OpenAPI-freshness, NuGet lockfile regen, TypeScript (Biome,
`npm audit`, `tsc`), Python (ruff, pyright, pytest, pip-audit), CodeQL,
dependency-review.

The lint/format/type-check/build slice of these already shipped out-of-band as
composite actions (see [plan.md](plan.md) out-of-band additions); only the
heavier test / E2E / coverage / security-scan lanes here remain future work.

### REPO-SPECIFIC (stays local)

medley: `recurring-issues`, `onboard-drift`, `claude-assistant` (interactive
`@claude` follow-up), `agent-automation-automerge`, `html-no-remote-fetch`,
`tool-version-drift-check`. Automated `claude-review` is no longer local — it was
lifted out-of-band to a `ci-workflows` reusable workflow that medley now consumes
by SHA-pin (see [plan.md](plan.md)); only the interactive `claude-assistant` lane
stays repo-specific.
standards: per-module fixture-assertion lanes.

## Lift ordering rationale

The cheapest, best-aligned first wave is the trio whose **config already exists**
in `standards` (`typos`, `editorconfig`, `gitleaks`): only the execution action
is missing, so there is no config work and they immediately benefit standards
(retiring its inline copies) as well as medley. Sequencing is detailed in
[plan.md](plan.md); the design rules each must follow are in
[architecture.md](architecture.md).
