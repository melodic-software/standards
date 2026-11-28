# Module boundaries

## Design

- Give each unit, stage and step one responsibility. Keep distinct concerns (review versus fixing, linting versus formatting) in separate units that never duplicate each other. Package a coherent practice as its own module rather than overloading a general-purpose one; a tool that grows into a product gets its own repository.
- Size a package as a well-named, generic, data-driven domain with smaller encapsulated units inside. Choose granularity and layout by the repository's existing conventions, and default to flat folders over deep nesting.
- Keep a process separate from its inputs and output targets, and wire outputs in as adapters behind ports. For swappable providers, ship one default or a few common adapters plus a generic custom-command adapter. Leave tool picks such as a boundary-lint tool to the consumer. Mark dependencies between components explicitly.

## Design and review

- Apply coupling, cohesion and "what changes together lives together" to processes, documents and file layout as well as code. Review designs through fixed lenses: coupling and cohesion, assumptions and ambiguities, configurability and extensibility.
- In a vertical-slice layout, a shared folder holds only what two or more slices actually use, stays minimal and gets extra scrutiny on every change. Where no clean mechanism exists to share something, keep the parts separate rather than join them with a hack.
- A shipped package must not couple to files a consumer repository may or may not generate. When one feature ships on several surfaces, the variants read the same settings while neither depends on the other. Components move within or across repositories without renames or cascading breakage.

## Design and build

- Express layering rules once, repository-wide, keyed on consistent project and namespace naming, so they stay DRY and fail the build everywhere.

## Design and plan

- When code is known to be generalized later, isolate it now so it can be ported. Before changing shared infrastructure or a contract, map every dependent consumer, check the effect on each and update them in the same change.
