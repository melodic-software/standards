# Domain-driven design

Tactical patterns for modeling a domain in code, plus the shared language that keeps the model honest. Apply these where a module is rich enough to warrant a domain model; a generic or CRUD-shaped subdomain does not need them. These are reasoning-only modeling judgments. The structural placement of these types within the layering is governed by `architecture-and-design.md`.

## Tactical patterns

- **Entities** are identity-based and encapsulate behavior and invariants. An entity is never a bare property bag.
- **Value objects** are immutable and compared by value, not identity.
- **Aggregate roots** are the consistency boundary. Code outside an aggregate references it only by the root's identity, never by navigating into its internals.
- **Domain events** are raised inside an aggregate and dispatched after the change persists. Design their contracts to survive future asynchronous messaging — serializable, with a versionable shape.
- **Repositories** are one per aggregate root and return domain objects, not data-transfer shapes.
- **Specifications** encapsulate complex query and filtering logic as first-class, composable objects rather than scattering query predicates.
- **Persistence ignorance** — domain entities know nothing about how they are stored. No persistence-framework attributes, no data-context references in the domain layer.

## Ubiquitous language

The model is only as good as the shared vocabulary behind it. The same domain terms appear in conversations, the glossary, type names, and method names — `TransferFunds`, not `UpdateAccountBalance`. When a UI captures a task, name it for the intent a domain expert would use, not for the entity it happens to mutate; task-oriented operations align naturally with commands, where CRUD screens blur several intents into one. If an operation needs a domain expert to explain it beyond "you are editing field X", it deserves a named command in the ubiquitous language.

Keep the glossary current as the model evolves, and let a contradiction between the language and the code be a signal to fix one of them — drift between what the team says and what the code says is how a model rots.

## Sources

- Evans, *Domain-Driven Design: Tackling Complexity in the Heart of Software*
- Vernon, *Implementing Domain-Driven Design*
- Khorikov — domain model and the limits of DDD outside transactional operations
