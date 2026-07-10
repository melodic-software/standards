# Architecture and design

The structural defaults for production code. SOLID, fail-fast, and immutability are assumed as the baseline; this convention states the architecture-level choices a senior engineer makes by default. These are reasoning-only — analyzer components can enforce some boundary rules mechanically, but the design judgment behind them is yours. The diff-time review counterparts live in `../review/architecture.md`.

## Dependency direction

Dependencies point inward, toward the domain. A core layer depends on nothing; the domain depends only on core; the application layer depends on core and domain; infrastructure depends on all of the inner layers, and the inner layers never depend on infrastructure. The domain stays free of framework, persistence, and transport concerns. Where the toolchain can assert this (an analyzer, an architecture test), let it; the rule holds whether or not a tool watches it.

## Feature and vertical-slice organization

Organize by feature, not by technical bucket. A feature owns its request, handler, response, validation, and mapping together. Avoid top-level `Controllers/`, `Services/`, `Models/` folders that scatter one feature across the tree. Each module is one bounded context: cohesive inside, loosely coupled to its peers, exposing contracts rather than reaching into another module's internals.

## Composition over inheritance

Prefer interfaces, delegation, and decorators over deep class hierarchies. Keep inheritance shallow — roughly two levels beyond the language root — and reach for it only where it names a real relationship. Legitimate hierarchies exist (a shared template-method base across a family, framework base types, pattern roles); a hierarchy grown only to share scaffolding across three similar classes is better expressed as composition or a shared helper.

## Talk to immediate collaborators (Law of Demeter)

An object talks to its direct collaborators, not through them. Reaching-through chains that walk an object graph couple a caller to structure it should not know. This is acceptable within a single aggregate or a fluent builder; across module or layer boundaries it is a serious smell.

## Let the framework call you (Hollywood Principle)

Depend on abstractions and let the container, framework, or pipeline invoke your code — dependency injection, event handlers, middleware, decorator chains. Directly constructing services, chaining static calls, or pulling dependencies from a service locator inverts this. It is the runtime expression of the Dependency Inversion principle.

## Model expected failures as results, not exceptions

A failure the caller can reasonably anticipate — validation, a broken business rule, not-found, conflict — is a return value, not a thrown exception. Reserve exceptions for infrastructure failures and programmer bugs. Modeling operations as explicit success-or-failure tracks (railway-oriented programming, after [Wlaschin](https://fsharpforfunandprofit.com/rop/)) lets callers compose and short-circuit without a control-flow exception for an outcome that was always possible. Aggregate multiple failures (validation, for instance) rather than stopping at the first where it helps the caller. At the transport boundary, map each failure to its appropriate status.

## Command orchestration and consistency boundaries

- **A command does not call another command.** Nested handler invocation introduces coupling through the dispatch indirection. Shared logic belongs in a domain or application service, not in a second command.
- **Application services orchestrate; command handlers do one operation.** Multi-step work that spans aggregates — a batch import, a cross-aggregate workflow — belongs in an application service that injects domain services and repositories directly.
- **Batch work bypasses per-item handlers.** Importing a thousand records is not a thousand dispatched commands; it validates at the batch boundary, applies domain logic, and persists in bulk.
- **One transaction, one aggregate.** A command operates within a single aggregate's consistency boundary. Cross-aggregate coordination uses domain events in the same transaction, or integration events with an outbox for eventual consistency. Reach for a saga or process manager only when multi-step failure needs compensation.

## Configurable by default, within reason

Values that vary by environment, deployment, or operator preference belong in external configuration through the framework's own mechanism, not baked into source. Externalized settings ship with documented, safe defaults; secrets and machine-specific overrides stay out of tracked files. The counterweight is YAGNI: a single implementation with no realistic variance stays inline — a plugin framework or option bag for one value that never varies is over-engineering.

## Open for extension, closed for modification

When behavior varies along an axis you keep editing — a new provider, a new branch in shared dispatch — prefer adding through registration, strategy, or injection over editing the closed core each time. The tell is the *edit-to-extend* smell: a change that adds a variant by inserting another `if` or `case` into existing code. The counterweight, again, is YAGNI: do not build an extension point for a variation that does not yet exist.

## Testable by design

Structure code so meaningful tests are possible without heroic setup. Keep complex domain logic out of handlers and controllers that also do I/O — a humble-object or functional-core split lets the logic be unit-tested directly. Inject at volatile boundaries so substitutable behavior can be substituted. This is *not* "interface everything": abstractions exist for substitutability, not ceremony, and an in-process managed dependency often tests better against a real instance than a mock.

## Use design patterns when they solve a real problem

A pattern earns its place by solving a problem the code actually has. Before introducing one, ask whether the code has the specific problem the pattern addresses; "not yet, but it might" is YAGNI. Patterns are a vocabulary for problems you have, not a default for every class.

## Sources

- Evans, *Domain-Driven Design*; Vernon, *Implementing Domain-Driven Design* — aggregate and consistency boundaries
- Wlaschin — [Railway-Oriented Programming](https://fsharpforfunandprofit.com/rop/)
- Feathers, *Working Effectively with Legacy Code* — seams and the humble object
- Ousterhout, *A Philosophy of Software Design* ([PDF](https://milkov.tech/assets/psd.pdf)) — deep modules, configuration parameters
- Khorikov, *Unit Testing Principles, Practices, and Patterns* — testable architecture
