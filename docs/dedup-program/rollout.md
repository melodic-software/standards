# Constellation rollout — adoption tracker

Where each repo in the `melodic-software` + `kyle-sexton` constellation stands on
adopting the `ci-workflows` execution layer and the `standards` drop-in configs,
and what is left. Companion to [plan.md](plan.md): plan.md tracks **building** the
reusable blocks; this file tracks **deploying** them across repos. Keep it current
as adoption lands — it is the single "where are we / what's left" view.

The build program (Phases 0–6 + Later) and this rollout proceed in parallel: a
repo onboards using whatever blocks already exist, and gains the rest as later
phases land. A repo does not need to wait for the whole program to start.

## Adoption status

Snapshot 2026-06-24, rows re-verified 2026-07-06 at Track B activation;
re-verify against the live repos before acting (they change). "Consumes" =
references `ci-workflows` actions/workflows by pinned SHA. "Gate" = emits the
single required `ci-status` check the org `ci-gate` ruleset keys on.

| Repo | Stack | Workflows | Consumes | Gate | standards configs | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `melodic/standards` | multi (configs) | 2 | ✅ full | ✅ inline | full (`modules/`) | **Integrated** — model consumer; all lanes incl. Phase 3 hygiene |
| `melodic/ci-workflows` | platform | 6 | self-dogfoods | ✅ inline | full (`modules/`) | **Platform** (this repo) |
| `melodic/medley` | .NET + polyglot | 27 | ◐ many | ✅ | full | **Harvest source** — cut over in three waves (PRs #1156–#1160, #1161, #1162+#1167); remaining inline lanes are inline by decision (skill-governance, Pester, dotnet/ts), not for want of a platform block (see note) |
| `melodic/claude-code-plugins` | markdown + JSON + shell | 2 | ✅ full | ✅ | full (root) | **Integrated** — all lanes incl. shellcheck + advisory zizmor; org `ci-gate` enforcing (requires-ci applied, PR #17) |
| `melodic/github-iac` | C# (Pulumi) | 2 | ✅ full | ✅ | full (root) | **Integrated** — all lanes; org `ci-gate` enforcing (requires-ci applied, PR #16) |
| `melodic/.github` | org meta files | 3 | ✅ full | ✅ | partial (root) | **Integrated** — markdown/typos/gitleaks/editorconfig/lychee + eol-renormalize (no comment-hygiene lane) |
| `kyle-sexton/github-iac` | C# (Pulumi) | 2 | ✅ full | ✅ | full (root) | **Integrated** — all lanes; self-gated via per-repo `ci-gate` ruleset; migrated off `modules/` to root ahead of Track B activation |
| `kyle-sexton/provisioning` | PowerShell | 2 | ✅ full | ✅ | full (root) | **Integrated** — all PowerShell-appropriate lanes; self-gated via per-repo `ci-gate` ruleset |
| `kyle-sexton/dotfiles` | chezmoi + PS + shell | 1 | ✅ full | ✅ | full (root) | **Integrated** — editorconfig/typos/gitleaks/markdown/lychee/PSSA + hygiene lanes |
| `kyle-sexton/.github` | personal meta files | 1 | ✅ | ✅ | markdown only | **Integrated** — markdown lane |

**Comment-hygiene policy widening — propagated 2026-06-24.** The org-default
comment-hygiene policy was widened at the `standards` SSOT
(`modules/comment-hygiene/comment-hygiene-patterns.sh`): it now also flags
`cc-issue`, GitHub closing-keyword+`#N`, `issue`/`issues`/`tracked`,
`owner/repo#N` and `GH-N` references, and scans block (`/* *`) and HTML (`<!--`)
comment lines. No Dependabot covers vendored configs, so the four config-vendoring
consumers were re-synced byte-identical to the SSOT and re-pinned to current
`ci-workflows` main (`9567b8b`): `claude-code-plugins` (#9), `github-iac` org
(#21), `kyle-sexton/github-iac` (#15), `provisioning` (#18). `standards` (SSOT —
re-pin only, #42) and `medley` (re-pin only, #1169) were brought to the same
`ci-workflows` SHA. Every repo re-verified clean under the widened policy.

> **This hand re-sync was the motivating pain for Track B — now automated.**
> The upstream→downstream config cascade landed 2026-07-06
> ([config-distribution-plan.md](config-distribution-plan.md)): the sync engine
> opens a PR per target from the distribution manifest, piloted green against
> `melodic/github-iac` (its PR #37 carried exactly the drift accumulated since
> the last hand re-sync). Every consumer is root-layout now — the `modules/`
> vendoring convention is retired downstream (`modules/<tool>/` paths remain
> only for files the actions reference by explicit path: comment-hygiene,
> lychee, lefthook fragments, dotnet Layer-1 props).

## Per-repo onboarding scope

Recommended lanes are grounded in each repo's actual tracked file types
(2026-06-23); confirm at onboarding. Every onboarded repo also gets: the drop-in
`standards` configs at its root (`.editorconfig`, `.gitattributes`, `_typos.toml`,
`.gitleaks.toml`, plus per-language module configs) and a local `ci-status`
gateway job aggregating its lanes (D2).

- **`standards`** — **done** (PR #25): adopted `exec-bit`,
  `machine-specific-paths`, `eol-renormalize`, `comment-hygiene` by SHA-pin;
  landed the canonical `comment-hygiene` module upstream (`ci-workflows` holds
  the vendored copy). 15 shebang scripts fixed to mode 100755 along the way.
- **`github-iac` (both org + personal, near-identical C# Pulumi)** — **done**: both
  onboarded all lanes — `dotnet-build`, `dotnet-format`, `editorconfig`, `typos`,
  `gitleaks`, `actionlint`, `check-jsonschema` (dependabot + workflows), `markdown`,
  the four hygiene lanes, `zizmor`, `osv-scanner` — into a local `ci-status` gateway,
  plus Dependabot (7-day cooldown) and the standards configs. The two differ only in
  config placement: org copies them to the repo root and passes explicit `config`
  inputs; personal vendors them under `modules/` and relies on the actions' defaults.
  Personal self-gates via a per-repo `ci-gate` ruleset; org now enforces via the
  `requires-ci` custom property (PR #16, applied).
- **`provisioning` (PowerShell)** — **done**: onboarded all PowerShell-appropriate
  lanes — `powershell` (PSScriptAnalyzer), `editorconfig`, `typos`, `gitleaks`,
  `actionlint`, `markdown`, `lychee` (offline), the four hygiene lanes — into a
  `ci-status` gateway, plus standards configs at root and Lefthook. No `shellcheck`
  (no `.sh`). Self-gated via a per-repo `ci-gate` ruleset.
- **`claude-code-plugins` (greenfield, public)** — **done** (PR #4): onboarded
  `markdown`, `typos`, `gitleaks`, `editorconfig`, `shellcheck`, `actionlint`,
  `check-jsonschema` (plugin manifests via schemastore + dependabot + workflows),
  the four hygiene lanes, and advisory `zizmor` into a local `ci-status` gateway,
  plus scheduled advisory `link-check`, Dependabot (`github-actions`, 7-day
  cooldown), and the standards configs at root. `shellcheck` was included on day
  one (not deferred) because the repo already tracks shell hooks; `osv-scanner`
  was skipped (no dependency lockfiles). Adopting `exec-bit` required dropping a
  vestigial shebang from the sourced `hook-utils.sh` to match the standards
  sourced-library convention. The D3 opinionated bundle was deferred in favour of
  granular lanes (trigger to build it: a second greenfield consumer to amortise
  it). Org `ci-gate` enforcing via the `requires-ci` custom property (github-iac
  PR #17), which also reconciled `ci-workflows` to its live `public` visibility so
  this public repo can reference it.
- **`medley`** — cut over in **two waves** (2026-06-24), per the **option-b**
  decision: cut over every lane with a working `ci-workflows` equivalent and
  leave the rest inline — no coverage lost, `ci-status` green throughout.
  **First wave** (PRs #1156–#1160): `typos`, `actionlint`, `check-jsonschema`,
  `eol-renormalize`, `exec-bit`, `machine-specific-paths`, `markdown` (lint),
  `ruff`, plus advisory `zizmor` + `osv-scanner` (reusable workflows); also
  re-synced `.editorconfig-checker.json` `Version` to `""` (the standards
  canonical). **Second wave** (PR #1161): the six lanes the first wave had left
  inline behind action parity/strictness gaps, now consuming the enhancements
  built in `ci-workflows` #25–#28 — `editorconfig-check` (git-tracked discovery,
  #26; the `eol-renormalize` half had cut over in the first wave), `shellcheck`
  (`severity: warning`, #25), `shfmt` (new action, #25), `powershell` PSSA
  (`fail-on-no-files: true` + the transient #1708 retry, #25/#27),
  `secret-scan`/`gitleaks` (`scan-mode: git` + `redact: true`, #25/#28), and
  `pyright` (`warnings-as-errors: false`, #25). Versions are inherited
  (platform-owns convention). The `claude-review` reusable workflow and the
  interactive `@claude` lane were adopted/split out-of-band earlier.
  **Third wave** (PRs #1162, #1167) collapsed the remaining inline lanes that had
  a buildable equivalent: #1162 removed the redundant `markdown`/`ruff`/
  `check-jsonschema` version overrides (platform-owns) and repaired the
  `tool-version-drift-check` workflow (its ShellCheck/shfmt blocks moved upstream
  into `ci-workflows`' own drift-check); #1167 cut over `comment-hygiene`
  (execution to the action; medley keeps its policy library + scoping inputs),
  `reference-integrity` heading-cite (to the action; byte-identical core, the
  identical 1081-file corpus), and re-pinned `shellcheck`/`powershell` to
  git-tracked discovery. The platform blocks they needed were built/widened in
  `ci-workflows` #30–#39 + standards #39. What stays inline is now **by
  decision**: `skill-governance` (keep-local contract), the `Pester` job (bespoke
  runners + a failure-comment a thin reusable workflow cannot host — the `Pester`
  workflow exists for simpler consumers), the offline-`lychee` half, and the
  `dotnet`/`typescript` ecosystem pipelines.
  **Repo-specific lanes** (the `ci-status` gateway, automerge bots, issue
  labeling, recurring issues, CodeQL, dependency-review, E2E, visual, drift
  detectors) stay local by design. The by-decision inline blocks are tracked in
  [plan.md](plan.md) Phase 4.

## Sequence

Onboarding proceeds incrementally; this is the intended order, not a hard gate.

1. ~~**`standards`** Phase 3 adoption~~ — **done** (PR #25).
2. ~~**`github-iac`** — stand up CI on one as the reusable onboarding template,
   then apply to the second.~~ — **done** (org gate enforcement: PR #16).
3. ~~**`provisioning`**~~ — **done** (self-gated via per-repo `ci-gate` ruleset).
4. ~~**`claude-code-plugins`** — greenfield CI, bundle candidate~~ — **done**
   (PR #4; org `ci-gate` enforcing via github-iac PR #17).
5. ~~**`medley`** Phase 6 cutover (largest; sequenced last).~~ — **done** in three
   waves: cleanly-referenceable lanes (PRs #1156–#1160), the parity-gap lanes
   consuming `ci-workflows` #25–#28 (PR #1161), and the inline-collapse wave that
   built the last gap blocks and cut over comment-hygiene + heading-cite +
   git-tracked shellcheck/powershell (PRs #1162, #1167 against `ci-workflows`
   #30–#39). What stays inline now does so by decision (see the `medley` note
   above + [plan.md](plan.md) Phase 4).

Each is its own sizeable PR, dogfooded green before merge. Governance reminder:
once a repo emits `ci-status` and is tagged `requires-ci`, the org `ci-gate`
ruleset blocks merges on it — onboarding the workflow and the ruleset tag must
land together, or PRs block indefinitely.
