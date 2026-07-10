# conventions

Prose standards that tooling cannot enforce — the reasoning-only tier of this catalog. Where `components/` owns executable policy and its contract tests, `conventions/` holds judgments a human or agent makes: engineering conventions and code-review criteria. The split between the two is itself a convention — see [engineering/enforceability-tiers.md](engineering/enforceability-tiers.md).

Two concerns live here:

- **[engineering/](engineering/)** — the standards a contributor follows while writing: philosophy, architecture and design, naming, simplicity, code organization, and the source-of-truth disciplines.
- **[review/](review/)** — the criteria a reviewer applies to a change: code quality, error handling, concurrency, performance, security, cross-platform, observability, testing, AI-generated code, and thin per-stack overlays.

## How this is consumed

Prose is read, not executed. A reviewer or an authoring agent reads these files; no tool walks the directory tree to find them. That makes the distribution model deliberately simple and decoupled:

- **Adopt by copy or by pointer.** A consuming repo either copies the files it adopts into its own tree, or points its contributor and review guides at this directory. Either way there is **no runtime coupling** to this repo — nothing here is fetched or imported at build or review time.
- **Curate on adoption.** These are agent-agnostic standards. A consumer wires them into whatever harness it uses (a contributor guide, a review checklist, an agent's instructions) without this catalog dictating that harness. Adopt the files that fit; the standards do not assume a particular toolchain, repository layout, or agent.
- **Single owner, no double-statement.** Where a component config or hook lane already enforces a convention, prose references that enforcement rather than restating the rule, keeping executable policy the one source of truth.

## On testing this directory

These files carry no fixtures or unit tests, by nature: a reasoning-only standard has no pass/fail a script can assert. What *is* mechanically verified is that the prose itself passes the repository's Markdown, spelling, EditorConfig, and link-integrity policies.
