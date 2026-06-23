# conventions

Prose standards that tooling cannot enforce — the reasoning-only tier of this catalog. Where `modules/` holds configs a linter or analyzer executes, `conventions/` holds the judgments a human or agent makes: engineering conventions and code-review criteria. The split between the two is itself a convention — see [engineering/enforceability-tiers.md](engineering/enforceability-tiers.md).

Two concerns live here:

- **[engineering/](engineering/)** — the standards a contributor follows while writing: philosophy, architecture and design, naming, simplicity, code organization, and the source-of-truth disciplines.
- **[review/](review/)** — the criteria a reviewer applies to a change: code quality, error handling, concurrency, performance, security, cross-platform, observability, testing, AI-generated code, and thin per-stack overlays.

## How this is consumed

Prose is read, not executed. A reviewer or an authoring agent reads these files; no tool walks the directory tree to find them. That makes the distribution model deliberately simple and decoupled:

- **Adopt by copy or by pointer.** A consuming repo either copies the files it adopts into its own tree, or points its contributor and review guides at this directory. Either way there is **no runtime coupling** to this repo — nothing here is fetched or imported at build or review time.
- **Curate on adoption.** These are agent-agnostic standards. A consumer wires them into whatever harness it uses (a contributor guide, a review checklist, an agent's instructions) without this catalog dictating that harness. Adopt the files that fit; the standards do not assume a particular toolchain, repository layout, or agent.
- **Single owner, no double-statement.** Where a convention is already enforced by a `modules/<tool>/` config or a hook lane, the prose references that it is enforced there rather than restating the rule — so the tool config stays the one source of truth and the prose cannot drift from it.

## On testing this directory

These files carry no fixtures or unit tests, by nature: a reasoning-only standard has no pass/fail a script can assert — that is precisely why it is prose and not a `modules/` config. What *is* mechanically verified is that the prose itself is clean: every file here passes the repo's own markdown, spelling, editorconfig, and link-integrity lanes in CI, the same as any other markdown in the catalog. The standards dogfood themselves by being held to the standards.
