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

Snapshot 2026-06-23; re-verify against the live repos before acting (they
change). "Consumes" = references `ci-workflows` actions/workflows by pinned SHA.
"Gate" = emits the single required `ci-status` check the org `ci-gate` ruleset
keys on.

| Repo | Stack | Workflows | Consumes | Gate | standards configs | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `melodic/standards` | multi (configs) | 2 | ✅ full | ✅ inline | full (`modules/`) | **Integrated** — model consumer; all lanes incl. Phase 3 hygiene |
| `melodic/ci-workflows` | platform | 6 | self-dogfoods | ✅ inline | full (`modules/`) | **Platform** (this repo) |
| `melodic/medley` | .NET + polyglot | 27 | ◐ `claude-review` | ✅ | full | **Harvest source** → Phase 6 cutover (first reference adopted: `claude-review`) |
| `melodic/claude-code-plugins` | markdown + JSON + shell | 2 | ✅ full | ✅ | full (root) | **Integrated** — all lanes incl. shellcheck + advisory zizmor; org `ci-gate` enforcing (requires-ci applied, PR #17) |
| `melodic/github-iac` | C# (Pulumi) | 2 | ✅ full | ✅ | full (root) | **Integrated** — all lanes; org `ci-gate` enforcing (requires-ci applied, PR #16) |
| `kyle-sexton/github-iac` | C# (Pulumi) | 2 | ✅ full | ✅ | full (`modules/`) | **Integrated** — all lanes; self-gated via per-repo `ci-gate` ruleset |
| `kyle-sexton/provisioning` | PowerShell | 2 | ✅ full | ✅ | full (root) | **Integrated** — all PowerShell-appropriate lanes; self-gated via per-repo `ci-gate` ruleset |

(`chezmoi` dotfiles live under `~/.local/share/chezmoi`, outside `D:\repos`, and
are out of scope here.)

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
- **`medley`** — Phase 6 cutover: replace each overlapping inline lane with a
  SHA-pinned reference, lane-by-lane, verifying `ci-status` parity. Repo-specific
  lanes stay local. Tracked in [plan.md](plan.md) Phase 6. Already consumes the
  out-of-band `claude-review` reusable workflow — its first `ci-workflows`
  reference, with the interactive `@claude` assistant split into a local lane (see
  [plan.md](plan.md) out-of-band additions).

## Sequence

Onboarding proceeds incrementally; this is the intended order, not a hard gate.

1. ~~**`standards`** Phase 3 adoption~~ — **done** (PR #25).
2. ~~**`github-iac`** — stand up CI on one as the reusable onboarding template,
   then apply to the second.~~ — **done** (org gate enforcement: PR #16).
3. ~~**`provisioning`**~~ — **done** (self-gated via per-repo `ci-gate` ruleset).
4. ~~**`claude-code-plugins`** — greenfield CI, bundle candidate~~ — **done**
   (PR #4; org `ci-gate` enforcing via github-iac PR #17).
5. **`medley`** Phase 6 cutover (largest; sequenced last). ← next

Each is its own sizeable PR, dogfooded green before merge. Governance reminder:
once a repo emits `ci-status` and is tagged `requires-ci`, the org `ci-gate`
ruleset blocks merges on it — onboarding the workflow and the ruleset tag must
land together, or PRs block indefinitely.
