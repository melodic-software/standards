# standards

Curated, drop-in code-quality standards — linting, static analysis, and repo hygiene — that constrain both human contributors and agentic AI tools, consistently, across any repository.

This repo is the **single source of truth** (upstream). Consuming repos (downstream) adopt individual modules; they are never forced to take the whole thing, and they never couple back to this repo at runtime.

## What lives here

A modular catalog — each module is self-contained and independently adoptable.
Configs sort into two channels by how the tool finds them:

- **Copy-only, at the repo root** — `.editorconfig`, `.gitattributes`, `.gitignore`. Editors and Git discover these only by walking the directory tree, so they cannot be referenced; the root files here *are* the published standard.
- `modules/<tool>/` — **referenceable** drop-in configs a tool reads from an explicit path: Markdown, PowerShell, the editorconfig checker, and the typos, gitleaks, shellcheck, and lychee scanners; per-language overlays (.NET, Python, TypeScript)
- `modules/lefthook/` — **local git hooks** (Lefthook): copy-and-`extends` fragments that run the same standardized tools as fast, staged-only pre-commit checks; a consumer's own root `lefthook.yml` composes them
- `harness/` — the shell test runner the modules rely on
- `fixtures/` — good/bad samples that prove each module behaves
- `conventions/` — **prose standards tooling cannot enforce**: engineering conventions and code-review criteria. The reasoning-only counterpart to the modules; adopted by copy or pointer, with no runtime coupling
- `docs/` — the migration plan and decision records

## What does not live here

- Project scaffolding and build config — a separate `project-template` repo
- AI-agent guardrails (hooks, agents, skills) — a separate agent/marketplace repo
- Application, library, or product code

## Status

Bootstrapping. See [`docs/migration-plan.md`](docs/migration-plan.md) for the phased plan. Shipped so far: **Markdown**, **PowerShell**, **base hygiene** (`.editorconfig` / `.gitattributes` / `.gitignore` + the editorconfig checker), **typos** (spell checking), **gitleaks** (secret scanning), **shellcheck** (shell-script analysis), **lychee** (offline link/anchor integrity), the **.NET / Python / TypeScript** overlays, **local git hooks** (Lefthook), and the **conventions** prose (engineering conventions + code-review criteria).
