# Naming

Names are read far more often than they are written. The few extra characters of a clear name are paid once; ambiguity is paid on every read. These are reasoning-only rules — a linter can cap line length or flag a banned word, but it cannot tell whether a name describes what the thing does.

## Default to verbose, behavior-naming identifiers

Name an artifact for what it does, so a reader understands it without surrounding context. Prefer `dependency-hygiene` over `dep-hygiene`, `vulnerability-warning` over `vuln-warning`. This applies to every reader-facing identifier: file names, scripts, environment variables, configuration keys, log labels, task names.

Three escape hatches keep verbosity reasonable:

- **Narrow scope earns a specific name.** A step that only packages one ecosystem's artifacts is named for that ecosystem, not given a broad generic name it does not earn.
- **Keep a short form only when it is industry-standard and instantly recognized** — `HTTP`, `JSON`, `URL`, `API`, `CI`, `CVE`, `OS`, `ID`. Project-local shorthand is not industry-standard; expand it.
- **Repeated inline markers** (opt-out tokens, annotations appearing many times in body text) may use a terse form derived from the verbose name.

## Name by current behavior, not current scope

Pick a name that tracks what the artifact does today, not an assumption about how widely it is used. When a scope assumption ("this only checks one file") is baked into the name, later expansion forces a rename. Name by behavior; rename when behavior changes.

## Name by responsibility, not a vague role-suffix

A type — and therefore its file, where the language ties the two — should be named for the one responsibility it owns, not a generic suffix that names what it vaguely *manages*. The recurring offenders, worst first: the noise-word suffixes (`Helper`, `Util`/`Utils`, `Processor`, `Coordinator`, `Engine`, and the bare nouns `Info` / `Data` / `Object`), then `Service` used as a catch-all, then `Manager`. These name a slot, not a job.

The tell is that the name survives unchanged as unrelated responsibilities accrete: a `UserManager` that creates users, queries users, and sends registration emails keeps its name through every addition, because the name never claimed a single responsibility to disprove. This is distinct from curing an *under-qualified* name — adding a domain prefix fixes ambiguity, but a well-qualified `UserManager` still fails this rule because the **suffix** hides the responsibility.

Fix by naming the verb: split the type into the operations it performs (a `CreateUser` handler plus a `RegistrationEmailSender`), or rename it to the single thing it does. A suffix that genuinely states the responsibility (`OrderPriceCalculator`) is exactly what this rule asks for.

A suffix dictated by a pattern or framework contract is not the smell — it names a defined role:

| Legitimate suffix | Why it is not the smell |
|---|---|
| `Handler` (CQRS command/query) | names one operation; one handler per file |
| Domain / application `Service` (DDD) | a first-class building block that orchestrates a defined workflow |
| Framework base subclass (e.g. a hosted background service) | inherited framework type name |
| `Provider` · `Factory` · `Builder` · `Dispatcher` · `ViewModel` | dependency-injection / design-pattern name for a defined role |

`Manager` has no such idiom — treat it strictest. `Service` is legitimate only as a domain/application service or a framework-interface implementation, never as a generic dumping ground.

## Disambiguate overloaded terms

Words like *service*, *tool*, *context*, *provider*, *handler*, *manager*, *client*, *host*, and *module* mean different things in different domains. When they appear in a public API, registration code, or documentation, qualify them with a domain prefix: an `AddTools()` extension is ambiguous (AI tools? CLI tools?); `AddAiToolDiscovery()` is explicit.

## Branch names: type prefix, then a behavior-naming slug

A branch name states two things: the kind of change, and what changed.

```
<type>/<short-description>
```

The type is the Conventional Commits vocabulary — the same eleven types (`feat`, `fix`, `refactor`, `perf`, `style`, `docs`, `test`, `build`, `ci`, `chore`, `revert`) the [Conventional Commits spec](https://www.conventionalcommits.org/en/v1.0.0/) recommends and [`@commitlint/config-conventional`](https://github.com/conventional-changelog/commitlint/tree/master/%40commitlint/config-conventional) codifies — kept to one vocabulary rather than a second, branch-specific one. The description is a kebab-case, lowercase slug that follows the rules above: verbose enough to name what changed (3-5 words is a reasonable aim), not an assumption about scope.

A branch a cloud coding agent (Claude Code, Codex, Cursor, Copilot) or a bot (e.g. Dependabot) generates on its own carries that tool's prefix instead of a type (`claude/`, `codex/`, `cursor/`, `copilot/`, `dependabot/`). Renaming it can orphan the agent's task-designated session or break the tool's own PR-creation path — leave a generated prefix as generated rather than forcing it into the type grammar.

The `<type>/` and tool prefixes are a fixed, exact-match set — deterministic, in the sense `enforceability-tiers.md` uses the word, so a repo may gate the pattern with a commit hook the same way it gates any other exact-match rule. Choosing a slug that actually names the change stays reasoning-only, same as every other rule in this document. Branch name is cosmetic once a PR merges through a squash workflow — the PR title becomes the default-branch history, which is why enforcing the Conventional Commits vocabulary at PR-title time (see `../review/code-quality.md`) matters more for history hygiene than the branch name does; the branch grammar exists to keep local development and in-flight PRs legible in the meantime.

## Rename across all coupled edges

A rename is only complete when every coupled edge moves with it in the same change: configuration entries, environment-variable prefixes, kill-switch keys, log/output labels, paired test files, task definitions, opt-out markers, and any documentation that cites the name. A partial rename leaves a name that lies.

**Exception: the label-governance seam.** A repository rename's alias in `github-iac`'s `GovernedRepositorySpec.PreviousNames`, and a label rename in `github-iac`'s `Labels.cs` taxonomy (applied through the authoritative `Github.IssueLabels` resource), are not coupled edges that must move in the same change as the rename that motivates them. Both propagate through a separate, reviewed Pulumi deployment on its own cadence, and neither can be forced to apply atomically with the originating change. A repository or label identifier may lag briefly during that propagation without the rename being partial.

## Sources

- Martin, *Clean Code* (Prentice Hall, 2008), Ch. 2 "Meaningful Names" — noise words add no meaning — [book page](https://www.informit.com/store/clean-code-a-handbook-of-agile-software-craftsmanship-9780132350884)
- Ottinger — Rules for Variable and Class Naming (`DeviceManager` vs `ProtocolController`; `Info`/`Data` as noise) — [mirror](https://exelearning.org/wiki/OttingersNaming/)
- Yegge — "Execution in the Kingdom of Nouns" (2006) — the Noun-Verber anti-pattern — [post](http://steve-yegge.blogspot.com/2006/03/execution-in-kingdom-of-nouns.html)
- Fowler & Beck, *Refactoring* — Large Class / God Class smell — [refactoring.guru](https://refactoring.guru/smells/large-class)
