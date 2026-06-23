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
| `melodic/ci-workflows` | platform | 4 | self-dogfoods | ✅ inline | full (`modules/`) | **Platform** (this repo) |
| `melodic/medley` | .NET + polyglot | 26 | ❌ all inline | ✅ | full | **Harvest source** → Phase 6 cutover |
| `melodic/claude-code-plugins` | markdown + JSON | 0 | ❌ | ❌ | `.gitattributes` only | **Greenfield** — bundle candidate (D3) |
| `melodic/github-iac` | C# (Pulumi) | 1 (`deploy.yml`) | ❌ | ❌ | none | **Bare** — no quality CI |
| `kyle-sexton/github-iac` | C# (Pulumi) | 1 (`deploy.yml`) | ❌ | ❌ | none | **Bare** — no quality CI |
| `kyle-sexton/provisioning` | PowerShell | 0 | ❌ | ❌ | `.gitattributes` only | **Bare** — no CI |

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
- **`github-iac` (both org + personal, near-identical C# Pulumi)** — lanes:
  `dotnet-build`, `dotnet-format`, `editorconfig`, `typos`, `gitleaks`,
  `actionlint`, `check-jsonschema` (dependabot + workflows), `markdown`, the four
  hygiene lanes, `zizmor`, `osv-scanner`. Onboard one as the template, then mirror
  to the other.
- **`provisioning` (PowerShell)** — lanes: `powershell` (PSScriptAnalyzer),
  `editorconfig`, `typos`, `gitleaks`, `actionlint`, `markdown`, the four hygiene
  lanes. No `shellcheck` (no `.sh`).
- **`claude-code-plugins` (greenfield, markdown + plugin JSON today)** — lanes:
  `markdown`, `typos`, `gitleaks`, `editorconfig`, `check-jsonschema` (plugin
  manifests), `actionlint`, the four hygiene lanes, `link-check`. Grows
  `shellcheck`/`biome`/`tsc` as skills/hooks/agents land. Candidate for the
  opinionated quality bundle (D3), built from the granular units.
- **`medley`** — Phase 6 cutover: replace each overlapping inline lane with a
  SHA-pinned reference, lane-by-lane, verifying `ci-status` parity. Repo-specific
  lanes stay local. Tracked in [plan.md](plan.md) Phase 6.

## Sequence

Onboarding proceeds incrementally; this is the intended order, not a hard gate.

1. ~~**`standards`** Phase 3 adoption~~ — **done** (PR #25).
2. **`github-iac`** — stand up CI on one as the reusable onboarding template,
   then apply to the second. ← next
3. **`provisioning`**.
4. **`claude-code-plugins`** — greenfield CI, bundle candidate.
5. **`medley`** Phase 6 cutover (largest; sequenced last).

Each is its own sizeable PR, dogfooded green before merge. Governance reminder:
once a repo emits `ci-status` and is tagged `requires-ci`, the org `ci-gate`
ruleset blocks merges on it — onboarding the workflow and the ruleset tag must
land together, or PRs block indefinitely.
