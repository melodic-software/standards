# Persistence

## Design

- In vertical slice architecture, share infrastructure such as the database context across slices instead of duplicating it, and keep only the slice logic separate.

## Design and review

- Keep data access in infrastructure and inject it through a repository or a CQRS query side. An ORM data context injected straight into API endpoints is acceptable only in short-lived code; treat it as a red flag in long-lived code, and refactor toward CQRS once the code becomes long-lived.
