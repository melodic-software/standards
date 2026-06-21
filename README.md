# standards

Curated, drop-in code-quality standards for `melodic-software` repositories — linting, static analysis, and repo hygiene that constrain both human contributors and agentic AI tools, consistently, across repos.

This repo is the **single source of truth** (upstream). Consuming repos (downstream) adopt individual modules; they are never forced to take the whole thing, and they never couple back to this repo at runtime.

## What lives here

A modular catalog — each module is self-contained and independently adoptable:

- `modules/base/` — language-agnostic config: editorconfig, git hygiene, secret scan, spell check, markdown lint, link check, shell lint
- `modules/<language>/` — opt-in per-language static analysis: PowerShell, .NET, Python, TypeScript
- `harness/` — the lint dispatcher and shell/Pester test runners the modules rely on
- `hooks/` — git-hook (Lefthook) lanes
- `ci/` — reusable CI workflows
- `conventions/` — prose standards and review criteria that tooling cannot enforce
- `fixtures/` — good/bad samples that prove each module behaves
- `docs/` — the migration plan and decision records

## What does not live here

- Project scaffolding and build config — a separate `project-template` repo
- AI-agent guardrails (hooks, agents, skills) — a separate agent/marketplace repo
- Application, library, or product code

## Status

Bootstrapping. See [`docs/migration-plan.md`](docs/migration-plan.md) for the phased plan. The first modules are **Markdown** and **PowerShell**.
