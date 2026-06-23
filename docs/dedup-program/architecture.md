# Architecture and design decisions

The rules every building block in this program follows, each grounded in
official or authoritative sources (cited inline). Research is verified as of
2026-06; re-verify fast-moving items (flagged below) before relying on them.

## D1 — Choose the reuse primitive by scope, not by habit

GitHub defines two reuse primitives: a **composite action** bundles **steps**
and is invoked at the step level (`steps: - uses:`); a **reusable workflow**
contains **jobs** and is invoked at the job level (`jobs.<id>.uses:`).

Decision rule:

- A single-tool, same-machine **step sequence** (lint/format/scan that just runs
  on the caller's checkout) → **composite action**.
- A **whole-job concern** that needs its own job-level `permissions`, the secrets
  interface, `concurrency`, its own `runs-on`, scheduling (`on: schedule`), or
  multiple jobs (e.g. files an issue, auto-merges, scheduled scans) → **reusable
  workflow**.

Why these map as they do: composite actions have no jobs, so they cannot set
`runs-on`, job-level `permissions`, `concurrency`, `matrix`, or use the
`secrets` interface; reusable workflows can. A reusable workflow can `uses:` a
composite action, but not vice versa. Nesting limits: reusable workflows up to
10 levels, composite actions up to 10 deep, counted independently. (The
sometimes-cited "4-level" reusable-workflow limit is outdated.)

- https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action
- https://docs.github.com/en/actions/sharing-automations/reusing-workflows
- https://docs.github.com/en/actions/sharing-automations/avoiding-duplication
- https://github.com/actions/runner/blob/main/docs/adrs/1144-composite-actions.md

## D2 — The ci-status gateway stays consumer-local

The single required check (`ci-status`) is a job that `needs:` the lane jobs and
aggregates their results. Because composite actions cannot define jobs or gate
other jobs, the gateway is correctly a small local job each consumer keeps, not
something this repo provides. This keeps the required-check name un-nested and is
the seam the org `ci-gate` ruleset gates on.

## D3 — Granular and composable, with an optional bundle

Prefer many small single-responsibility building blocks that a consumer composes,
over few monolithic ones. This is a single-responsibility convention (community
consensus, not GitHub doctrine — flagged as such); the *mechanism* (nesting,
composition) is officially supported per D1. A greenfield consumer
(claude-code-plugins) may also want an opinionated higher-level unit that runs
the common quality set; if provided, it is built **from** the granular units, not
instead of them. Avoid the anti-patterns the sources call out: over-nesting
(bounded at 10) and leaky/unsanitized inputs (an injection risk).

- https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations

## D4 — Open-closed input design

Extend a building block only by adding **optional inputs whose defaults preserve
prior behavior**, so advancing a pinned SHA never breaks an existing call. Never
remove or repurpose an input, and never make an optional input required, within a
major version; use `deprecationMessage` to phase one out before a major bump.
This follows GitHub's action-versioning guidance ("a major version can add new
capabilities but should not break existing input compatibility").

Mechanics to design around:

- **Composite action inputs are strings only** (`description`, `required`,
  `default`, `deprecationMessage`); booleans/numbers/lists are strings parsed by
  the action. **Reusable-workflow inputs are typed** (`boolean`/`number`/
  `string`). Expose `version`, `config`/`config-path`, `globs`, `exclude` as
  discrete, well-named optional inputs with safe string defaults.
- Composite outputs require an explicit `value:`.

- https://github.com/actions/toolkit/blob/main/docs/action-versioning.md
- https://docs.github.com/en/actions/sharing-automations/creating-actions/metadata-syntax-for-github-actions

## D5 — Pin by SHA, including first-party

Pin every referenced action/workflow to a full commit SHA — GitHub's stated "only
way to use an action as an immutable release" — with the version as a trailing
comment (`uses: owner/x@<sha> # vX.Y.Z`) so Dependabot (`github-actions`
ecosystem) updates both. This applies to first-party org actions too: the
tj-actions/changed-files compromise (CVE-2025-30066) rewrote all tags to
malicious code, and SHA-pinned consumers were immune. The tradeoff (SHA pin needs
Dependabot churn; a moving tag would auto-distribute fixes but also auto-
distribute a compromise) is resolved in favor of SHA pinning plus Dependabot.

Fast-moving, re-verify before relying: immutable *releases* are GA (2025-10),
but consume-by-semver **immutable actions** were still in preview mid-2026;
artifact attestations / provenance and workflow lock files are evolving.

- https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file
- https://github.com/advisories/ghsa-mrrh-fwg8-r2c3

## D6 — Cross-repo private consumption

Referencing a private repo's action/workflow within the same org is authorized,
not automatic: the **provider** repo's `Settings > Actions > General > Access`
must be set to "Accessible from repositories in the organization." Once granted,
the run's scoped token gets read access to the provider for that run — no PAT, no
checkout of the provider needed. Constraints that bound the whole program:

- A **public** caller can only reference **public** repos — so provider-private +
  consumer-public **breaks**, and a consumer **outside the org** **breaks**.
- There is no per-consumer allow-list; org access exposes the provider to any
  private/internal repo in the org.

Implication: keep `ci-workflows` access set to the org and keep all consumers
private or internal. This is the basis of the visibility watch-item in the
[README](README.md).

- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository

## D7 — Composite-action gotchas to engineer for

- Set `shell:` on **every** `run` step (no composite-level default shell).
- Locate bundled scripts via `$GITHUB_ACTION_PATH`, never a hard-coded repo path.
- The `secrets` and (reported) `vars` contexts are unavailable inside composites;
  pass needed values as inputs/env.
- Writes to `$GITHUB_ENV` leak to the calling job — namespace variables or prefer
  outputs.
- No `pre:`/`post:` cleanup in composites; use a final `if: always()` step, or a
  JS action when guaranteed cleanup is required.
- `success()`/`failure()` inside a composite evaluate against the composite's own
  status, not the job's.

- https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action
- https://github.com/actions/runner/issues/1478

## Source confidence

Official GitHub docs and GitHub-owned repos/ADRs back D1, D4, D5, D6, and D7.
The granularity convention in D3 is community consensus where official guidance
is scope-based rather than prescriptive. Items flagged "re-verify" in D5 are
fast-moving; confirm status before depending on them.
