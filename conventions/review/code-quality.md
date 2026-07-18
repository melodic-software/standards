# Code quality review criteria

Diff-time checks for local design, parameter and model shape, style, and authoring hygiene — the quality bars automated tooling cannot fully decide. Cross-unit design judgment — cohesion, coupling, abstraction fit, substitutability, and pattern use — is owned by [code-design.md](code-design.md). Severity labels (Critical / Important / Suggestion) are defined in [README.md](README.md). Where a check restates a principle owned by an engineering convention, it points there rather than re-explaining it; where a component mechanically enforces a check, it points to that component instead of duplicating the rule.

## Local design

- **Magic literals** — bare numeric, string, or boolean *policy* values that recur or whose meaning is not self-evident, where a named constant belongs. A status string (`"active"`), a protocol keyword, or a boolean policy flag counts, not only numbers. Carve-outs: universal arithmetic idioms, values already named via a lookup, one-off literals obvious in context. Usually Suggestion; Important when the literal is a tunable threshold duplicated across sites.
- **Constants placement** — prefer a module-local named constant; promote to a shared location only when two or more consumers share the value or it is cross-cutting protocol. Avoid premature shared constant god-files bundling unrelated values.
- **Principle of least astonishment** — names, signatures, and behavior that would surprise a competent newcomer to the codebase.
- **Fail-slow patterns** — errors deferred, swallowed, or hidden instead of failing fast at the entry point.
- **Deep nesting** — prefer early returns and guard clauses over nested conditional ladders.
- **Exceptions for expected failures** — a thrown exception where the failure was anticipable and should be an explicit result; see `../engineering/architecture-and-design.md`.

## Parameter and model shape

Review owns parameter shape: where a stack toolchain enforces an arity ceiling, the universal tiers below apply well below it — and they apply in full where no such ceiling exists.

- **Parameter-object default** — when a method or type takes two or more inputs describing one operation, start with a single named input object rather than a growing flat list, even below the linter's arity limit. Name it by role.
- **Flat arity tiers** — zero to three independent parameters are unremarkable; two to three *co-traveling related* primitives are a data clump worth grouping even at low arity; four to six flat unrelated parameters are Important (introduce a parameter object, or apply Fowler's preceding refactors first); seven or more is Important at minimum, Critical at a public boundary.
- **Easily swappable parameters** — two or more adjacent parameters of the same (or implicitly convertible) type where order is semantically meaningful and a wrong order still compiles. Fix with distinct types, then a parameter object with named fields. Typed identities fix `OrderId` versus `UserId` but not `Transfer(UserId, UserId)`.
- **Primitive obsession** — a primitive carrying domain identity or a constrained concept on an entity or model field, where a typed identity or value object belongs. Distinct from the swappable-parameter check on signatures.
- **Fat flat shapes** — a wide property-only type mixing unrelated concerns. Passing it as a single parameter does not fix the smell; review the type. Do not split fields that form one domain concept.
- **Context object versus Law of Demeter** — grouping parameters into one object does not license reaching through its nested properties. Consumers call the context or its direct collaborators only.
- **File / type density** — multiple unrelated type definitions in one file usually means too many responsibilities; default to one primary concern per file. A genuinely small vertical slice co-locating request, handler, and response is the narrow exception, not a shared `types` barrel.

## Style

- **Naming** — abbreviations, scope-baked names, and vague role-suffixes are governed by `../engineering/naming.md`; flag diffs that violate it.
- **No conjunctions in function names** — `record_and_exit`, `validate_or_throw` hide two concerns; split them. Exception: a genuinely atomic operation (`compare_and_swap`).
- **No sequence numbers in file names** — name by content, not position.
- **No noise comments** — documentation comments on self-explanatory members add clutter; reserve comments for non-obvious intent or constraints.
- **Comments explain why, not what** — code reads without commentary; comments capture the non-obvious *why*. The [`comment-hygiene`](../../components/comment-hygiene/) component mechanically catches actionable debt markers and tracker provenance; review covers judgments the patterns cannot, such as a comment that restates code; a comment left stating a false current fact belongs to the stale-descriptor bar under Authoring hygiene.
- **No layer-leaking in comments** — do not mention transport status codes in domain types or storage columns in domain entities.
- **Alphabetical by default for order-independent sets** — an enumerable set whose order carries no meaning (config keys, list entries, table rows, imports no tool sorts) defaults to alphabetical order, so additions have one obvious place and diffs stay minimal; the Google style guides prescribe the same default for their own order-independent lists ([C++ include order](https://google.github.io/styleguide/cppguide.html#Names_and_Order_of_Includes), [Java imports in ASCII sort order](https://google.github.io/styleguide/javaguide.html#s3.3.3-import-ordering-and-spacing)). Semantic ordering wins wherever order carries meaning, and a community- or framework-prescribed order is respected. A tool-sortable surface belongs to its owning component per `../engineering/enforceability-tiers.md`; an unsorted tool-sortable surface with no tool configured is an escalation candidate under the [enforcement-escalation path](README.md#enforcement-escalation). Suggestion.

## Authoring hygiene

- **Version qualifiers in identifiers** — `v1`/`v2`, `phase-6`, `methodology-v2` in names, files, headings, or test names. One canonical version, implied; when something changes, rewrite rather than append a new suffix. Carve-out: a qualifier is legitimate only where the surface carries External contract or Production obligation exposure per the classifier in `../engineering/legacy-and-migration-debt.md` — a versioned public API or a published message contract qualifies (contract evolution itself stays owned by `messaging.md` and `architecture.md`). Internal surfaces are never versioned — no `v2` alongside `v1`; the change replaces the surface (`../engineering/code-organization.md`). An internal `V2` identifier is tolerated only as transient mid-migration state inside an expand-and-contract rollout of an external contract, and is still flagged — Important when it carries no recorded reasoning or removal path. Mechanism preference (Suggestion, non-prescriptive): version negotiation is metadata, so prefer headers or media type over URL paths — URL versioning remains acceptable as a widely-adopted convention (the mechanism landscape — URI, query string, header, media type — is catalogued in [Microsoft's API design guidance](https://learn.microsoft.com/azure/architecture/best-practices/api-design)).
- **Removal drift markers** — tombstones in code comments narrating what was removed; the surrounding code should read as if the removed thing never existed. See `../engineering/legacy-and-migration-debt.md` for the full posture and its exceptions.
- **Stale descriptors after a behavior change** — a change that alters behavior but leaves comments, docs, names, or examples still describing the old behavior. The change is not complete until every descriptor it invalidates is updated. Suggestion for an inline comment; Important where the stale descriptor is user-facing or operator documentation.
- **Lint exclusions instead of fixes** — default to fixing. Never add a suppression to bypass a pre-existing error; a justified exclusion lives in the tool's config with a recorded reason, never inline as a silencer.
- **Embedded cross-language scripts** — a multi-line script of one language inlined inside another (a shell heredoc of another language, say) belongs in its own co-located file.
- **Self-executing importable modules** — an entry script that other modules import needs a main guard so its CLI body does not run on import.
- **PR-title format** — deterministic; tool-owned by the `pr-title` gate (`ci-workflows/.github/workflows/semantic-pr.yml`, wired into each consumer as `.github/workflows/pr-title.yml`), not review prose. See `../engineering/enforceability-tiers.md`.

## Sources

- Fowler & Beck, *Refactoring* — [Introduce Parameter Object](https://martinfowler.com/refactoring/catalog/introduceParameterObject.html), [Data Clump](https://martinfowler.com/bliki/DataClump.html), [Primitive Obsession](https://www.informit.com/articles/article.aspx?p=2952392&seqNum=11)
- Martin, *Clean Code* — Ch. 3 (function arguments), Ch. 4 (comments, including stale and misleading ones), Ch. 10 (classes)
- Ousterhout, *A Philosophy of Software Design* ([PDF](https://milkov.tech/assets/psd.pdf)) — configuration parameters, shallow wrappers
- Google style guides — [C++ include ordering](https://google.github.io/styleguide/cppguide.html#Names_and_Order_of_Includes), [Java import ordering](https://google.github.io/styleguide/javaguide.html#s3.3.3-import-ordering-and-spacing)
- [Best practices for RESTful web API design](https://learn.microsoft.com/azure/architecture/best-practices/api-design) — versioning mechanisms
