# Code design review criteria

Diff-time checks for design judgment on a unit of code — cohesion, coupling, responsibility assignment, abstraction fit, substitutability, and pattern application. This is the tier between [architecture.md](architecture.md) (structure across units — boundaries, dependency direction, contracts) and [code-quality.md](code-quality.md) (surface hygiene — shape, style, readability). Severity labels (Critical / Important / Suggestion) are defined in [README.md](README.md).

Several of these read the whole changed unit or the whole diff, not a single hunk: a scattered-edit smell or a responsibility drift is only visible once the change is seen in full. Where a check restates a principle owned by an engineering convention, it points there rather than re-explaining it.

## Responsibility and cohesion

- **God class / large type** — a type or file mixing unrelated reasons to change (I/O plus business rules plus registration in one unit). Remediation: extract by responsibility. Suggestion by default; Important at a public, shared, or contract surface. Carve-outs: composition roots, declarative config-only files, generated code, legitimate template-method bases.
- **Divergent change** — one class edited for reasons unrelated to why it was last edited; the change-history dual of the god class. When a single type keeps accruing unrelated responsibilities, split it by axis of change. Suggestion; Important once two or more unrelated responsibilities already share the type.
- **Shotgun surgery** — one conceptual change forces the same *logic* edit across many files because a responsibility was never centralized: a business rule, a format, or a dispatch case duplicated so that changing it means editing every copy. The diff itself is the tell. Important. Carve-out: the boundary representations one change legitimately needs — a new field appearing in its entity, DTO, mapper, migration, and API contract — are necessary layered propagation, not this smell. Flag scattered *duplicated logic*, never required per-layer plumbing.
- **Feature envy** — a method reads several fields or getters of one other object and little of its own state — a calculation living on the wrong type, pulled off the type that owns the data. Suggestion; Important when it drags domain logic out of the entity or aggregate that owns the data. Carve-out: an intentional separation via a Strategy or Visitor.
- **Data class / anemic domain object** — a type that is only fields and accessors while the behavior operating on it lives elsewhere. Suggestion by default; Important when the type is a domain entity or aggregate that should enforce its own invariants but delegates them out; see `../engineering/domain-driven-design.md`. Carve-outs: DTOs, request/response records, configuration objects, value objects, and ORM projections at a boundary are not this smell.

## Coupling and encapsulation

- **Law of Demeter and the Hollywood Principle** — reach-through chains and service-locator pulls are flagged at module and layer boundaries (Critical there); see `../engineering/architecture-and-design.md`.
- **Insider trading (inappropriate intimacy)** — two types reach into each other's internals bidirectionally, a new mutual dependency on non-public surface. Important; Critical across a module boundary, where it is the module-to-module coupling `architecture.md` already flags.
- **Middle man** — a type or method whose members almost all forward to a single collaborator, adding no behavior of their own. Suggestion. Carve-out: a decorator, adapter, facade, anti-corruption layer, or port that delegates on purpose is legitimate under the Hollywood Principle — the smell is delegation that buys nothing.
- **Temporary field** — a mutable field set and used only during one operation and empty otherwise, a shortcut for passing state between private methods. Prefer a parameter or an extracted method-object.

## Inheritance and substitutability

- **Refused bequest** — a subtype overrides inherited members to throw, no-op, or return null, or ignores most of the parent's interface — inheritance taken for reuse without a genuine is-a. Important. Prefer composition; see `../engineering/architecture-and-design.md`.
- **Liskov substitutability** — an override that strengthens a precondition (rejects input the base accepts), weakens a postcondition, or throws where the base returns a value, so the subtype is not safely substitutable for its base. Important; Critical on a widely substituted base.

## Abstraction fit

- **Missing abstractions** — third-party libraries, infrastructure, or volatile dependencies referenced directly from domain or application code instead of behind an owned interface.
- **Duplicated structure, not just duplicated lines** — repeated field/property/method scaffolding across three or more classes signals a missing base or helper. A new class in an established family should extend it, not re-implement it. (Rule of three; see `../engineering/simpler-code.md`.)
- **Speculative generality** — an abstraction added with no current second consumer: an interface with one implementation, an unused generic parameter, an extension hook nothing varies, or a config knob no code reads. Suggestion; Important when the indirection sits on a hot path or a public API.
- **Needless indirection** — a wrapper, layer, or interface that adds a call hop without adding an abstraction: a pass-through whose surface is identical to its single implementation.
- **Interface segregation** — an interface bundles members no single client uses together, forcing consumers to depend on or implement methods they do not use. Suggestion; Important at a public contract surface.

**Abstraction earns its place.** *Missing abstractions* pushes toward more interfaces; *speculative generality* and *needless indirection* push toward fewer — they resolve on need, not count. An abstraction is warranted at a volatile or substitutable boundary with a real substitution need (a third-party dependency, infrastructure, transport). It is needless indirection when it wraps a stable in-process dependency, exposes a surface identical to its one implementation, or exists for a future that has not arrived — consistent with this repo's posture that not everything needs an interface, and that an in-process managed dependency often tests better against a real instance than a mock (`../engineering/architecture-and-design.md`).

## Pattern application

- **Premature patternization** — a design pattern (factory, strategy, abstract factory, visitor) introduced for a single concrete case with no second variant in sight; pattern vocabulary applied to a problem the code does not yet have. Overlaps speculative generality. Suggestion. A pattern earns its place by solving a real, present problem; see `../engineering/architecture-and-design.md`.
- **Singleton as global state** — a singleton or static mutable holder used to smuggle state across unrelated call sites instead of injecting it. Important, for the hidden coupling and the testability cost; Critical when it holds mutable shared state under concurrency (see `concurrency.md`).
- **Open for extension, closed for modification** — a change that adds a variant by inserting another branch into a dispatch already switching on a type code, especially where the same switch is duplicated across sites. Suggestion; Important when the switch is duplicated. Prefer polymorphism or a lookup; see `../engineering/architecture-and-design.md`.

## Sources

- Fowler & Beck, *Refactoring* (2nd ed) — code smells: [Feature Envy](https://refactoring.guru/smells/feature-envy), [Shotgun Surgery](https://refactoring.guru/smells/shotgun-surgery), [Divergent Change](https://refactoring.guru/smells/divergent-change), [Inappropriate Intimacy / Insider Trading](https://refactoring.guru/smells/inappropriate-intimacy), [Refused Bequest](https://refactoring.guru/smells/refused-bequest), [Speculative Generality](https://refactoring.guru/smells/speculative-generality), [Middle Man](https://refactoring.guru/smells/middle-man), [Temporary Field](https://refactoring.guru/smells/temporary-field), [Repeated Switches](https://refactoring.guru/smells/switch-statements); [2nd-edition catalog changes](https://martinfowler.com/articles/refactoring-2nd-changes.html)
- Fowler — [Anemic Domain Model](https://martinfowler.com/bliki/AnemicDomainModel.html)
- Martin, *Agile Software Development: Principles, Patterns, and Practices* — SOLID
- Gamma, Helm, Johnson, Vlissides, *Design Patterns* (GoF); [Singleton drawbacks](https://refactoring.guru/design-patterns/singleton)
- Ousterhout, *A Philosophy of Software Design* ([PDF](https://milkov.tech/assets/psd.pdf)) — deep versus shallow modules, pass-through methods
