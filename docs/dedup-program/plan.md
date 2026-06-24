# Phased plan

The sequenced roadmap. Phases are ordered by duplication density, low coupling,
and config-readiness, not by ecosystem. Nothing is permanently excluded —
ecosystem build/test lanes are simply sequenced later and remain opt-in by
reference. Each building block follows the rules in
[architecture.md](architecture.md); the targets come from
[inventory.md](inventory.md).

## Working method per item

For every lane lifted:

1. **Research** the tool/version/usage against authoritative sources; record
   findings under `research/<tool>.md`. Confirm the latest stable version and
   recommended CI invocation; flag anything unverified.
2. **Build** the building block in `ci-workflows` (composite action or reusable
   workflow per D1), lift-and-shift the consumer's current behavior, then
   backfill optional inputs for any extra behavior (D4).
3. **Dogfood** it in this repo's `ci.yml` behind the local `ci-status` gateway.
4. **Release** via PR (squash, signed, `ci-status` green); it becomes referenceable
   at that SHA.
5. **Consume** downstream: replace the inline lane in each consumer with a
   SHA-pinned reference, customizing via inputs; verify the consumer's `ci-status`
   stays green; retire the inline copy.

A phase is done when every block in it is built, dogfooded, released, and adopted
by at least the consumers that already run that lane.

## Phase 0 — Inventory, architecture, plan

Establish the plan-of-record (this folder).

- [x] Cross-repo inventory and classification
- [x] Architecture decisions backed by research
- [x] Phased plan
- [x] Confirm `ci-workflows` Actions access is set to org-accessible (D6)

## Phase 1 — Config-ready trio (quick wins)

Lanes whose config already lives in `standards` (`modules/typos`,
`modules/editorconfig`, `modules/gitleaks`) — only the execution action is
missing, so there is no config work and both standards and medley benefit.

- [x] `typos` composite action
- [x] `editorconfig-checker` composite action
- [x] `gitleaks` composite action (binary install + checksum verify, SARIF
  output, PR annotations as optional inputs)
- [x] Adopt in `standards` (retire its inline copies)

## Phase 2 — Actions and security linting

- [x] `actionlint` composite action
- [x] `check-jsonschema` (YAML schema) composite action
- [x] `zizmor` reusable workflow (Actions security lint)
- [x] `osv-scanner` reusable workflow (dependency vuln scan)

`zizmor` and `osv-scanner` are advisory in medley today; keep them advisory on
lift and decide promotion separately.

## Phase 3 — Cross-cutting repo hygiene

Generic shell checks medley runs as always-on gateway jobs. Pattern lists become
config (new `standards` modules where a ruleset is involved).

- [x] `exec-bit` composite action
- [x] `machine-specific-paths` composite action
- [x] `comment-hygiene` composite action (patterns via config input)
- [x] `eol-renormalize` composite action
- [x] Adopt in `standards`: land the canonical `comment-hygiene` module upstream
  (this repo holds only a vendored copy) and adopt the four lanes by SHA-pin

## Phase 4 — Backfill DUP-COVERED gaps for a lossless medley cutover

Extend existing actions / add siblings so medley loses no coverage when it
switches markdown/shell/powershell/lychee to references.

> **Status (2026-06-24):** medley's first cutover wave ran under **option b** —
> cut over every lane with a working equivalent, leave the rest inline (no
> coverage lost, `ci-status` green; PRs #1156–#1160). The **action enhancements**
> the parity-gap lanes needed were then built (`ci-workflows` #25–#28) and medley
> ran a **second wave** consuming them — six more lanes cut over by reference
> (PR #1161; see [rollout.md](rollout.md)). The remaining unbuilt **gap blocks**
> below (no `ci-workflows` equivalent yet) stay inline in medley; they are
> single-consumer (medley-only) today, the trigger to build being a second
> consumer or an explicit decision to fully collapse medley's inline CI.

Gap blocks:

- [x] `shfmt` composite action (`ci-workflows` #25) — own action; medley's bash
  lane adopted it in the second wave (#1161)
- [ ] `reference-integrity` heading-cite resolver (pairs with `lychee-offline`)
- [ ] `Pester` reusable workflow (Windows runner)
- [ ] `skill-governance` reusable workflow (path inputs)

Action parity/strictness gaps surfaced by the first cutover wave — each kept a
medley lane inline because the action could not match the repo's tuned lane. Most
are now built (`ci-workflows` #25–#28) and consumed by medley's second wave
(#1161); the rest stay deferred:

- [x] `editorconfig`: now defaults to git-tracked discovery (`ec` with no path),
  so generated artifacts that a raw filesystem walk would gate (no-final-newline:
  `.lycheecache`, `.work/<slug>/baselines/*`) are skipped (`ci-workflows` #26).
- [x] `shellcheck`: added a `severity` input (medley runs `-S warning`; the
  action's default is `style`) (`ci-workflows` #25).
- [x] `pyright`: added a `warnings-as-errors` toggle so the lane need not force
  `--warnings` (medley runs bare strict-mode pyright, tolerating
  `reportMissingTypeStubs: "warning"`) (`ci-workflows` #25).
- [ ] `comment-hygiene`: hardcoded coarse prefilter is narrower than medley's
  (misses `cc-issue` / `tracked: #` / `melodic/medley#`). Make it configurable
  or widen it and re-sync the standards SSOT.
- [x] `gitleaks`: added a `scan-mode` input (`git` full-history vs `dir`
  working-tree) plus a `redact` input to mask findings; medley's `secret-scan`
  cut over to `scan-mode: git` + `redact: true` (`ci-workflows` #25 scan-mode,
  #28 redact).
- [ ] `lychee-offline` consumption: medley has no `lychee.toml` and the action's
  default `config` path does not exist in a consumer. Ship a sane default or
  document the config a consumer must add.

Confirmed during the cutover:

- [x] `powershell` action input parity with medley's `Invoke-Pssa.ps1` usage —
  confirmed (same per-file pattern + settings). The zero-file tripwire guard is
  now a `fail-on-no-files` input and the transient PSScriptAnalyzer #1708 NRE
  gets an in-action retry (`ci-workflows` #25, #27); medley's PowerShell lane cut
  over with `fail-on-no-files: true` in the second wave (#1161).
- [x] `markdown` action input parity with medley's usage — confirmed (lint lane
  cut over green). `link-check` reusable-workflow parity not yet exercised
  (medley's scheduled docs-link-check and offline lychee stay inline).

## Phase 5 — Automation reusable workflows

- [ ] `dependabot-automerge` reusable workflow (semver-gated)
- [ ] `issue-labeling` reusable workflow (allowed labels via inputs)

## Phase 6 — Consumer cutover and constellation onboarding

Deploy the blocks across every constellation repo. Per-repo status, recommended
lanes, and the live sequence are tracked in [rollout.md](rollout.md); the
checkboxes below mirror it.

- [x] `github-iac` (org + personal, C# Pulumi): stand up CI from the building
  blocks; onboard one as the template, then mirror to the other
- [x] `provisioning` (PowerShell): stand up CI from the building blocks
- [x] claude-code-plugins: stand up CI from the building blocks (greenfield;
  granular lanes adopted, the D3 opinionated bundle deferred to a second
  greenfield consumer)
- [x] medley: cut over each overlapping inline lane **that has a working
  equivalent** to a SHA-pinned reference, verifying `ci-status` parity
  lane-by-lane (option b — first wave PRs #1156–#1160, second wave PR #1161,
  2026-06-24). Remaining gap blocks stay inline pending the unbuilt Phase 4
  blocks above; details in [rollout.md](rollout.md).
- [ ] standards: keep current as new blocks land

## Later — ecosystem lanes (separate decision)

The lint/format/type-check/build slice already shipped out-of-band as composite
actions (see Out-of-band additions below); what remains here is the heavier
`.NET` / TypeScript / Python test + E2E + coverage work plus Playwright and
CodeQL. Higher per-repo configurability and coupling; lift in a dedicated phase
once the quality layer is proven. Opt-in by reference, so repos that do not use a
stack simply never call it. Scope and approach to be planned when Phase 6 is
underway.

## Out-of-band additions

Capabilities added outside the phased sequence above, recorded here so the build
history stays accurate.

- [x] `claude-review` reusable workflow — automated PR code review wrapping
  `anthropics/claude-code-action`. A peer of the Phase 2 `zizmor` / `osv-scanner`
  reusable workflows (a whole-job concern per [D1](architecture.md): job-level
  `permissions` plus a `secrets` interface, SHA-pinned per D5, org-private
  consumption per D6). Built and dogfooded here (the repo is its own first
  caller), then adopted by `medley`, which split its prior single review workflow
  into a thin caller of this workflow plus a repo-local interactive `@claude`
  assistant lane. Unlike the [inventory.md](inventory.md) lift targets, this was
  not a de-duplication of a copied lane but a new shared platform capability; its
  security rationale and pin/permission rules live with the workflow itself, not
  here.
- [x] Ecosystem static-analysis composite actions — `ruff` + `pyright` (Python),
  `biome` + `tsc` (JS/TS), `dotnet-build` + `dotnet-format` (.NET). The
  lint/format/type-check/build slice of the ecosystem lanes the "Later" section
  defers, built and dogfooded here ahead of that sequence (each per D1/D4, config
  supplied by the caller; no `research/` note was filed). The heavier per-stack
  test / E2E / coverage / security-scan lanes remain future work.

## Out of scope

Repo-specific lanes listed in [inventory.md](inventory.md) stay local. Tool
*config* (rulesets) stays upstream in `standards`; this program only moves
execution.
