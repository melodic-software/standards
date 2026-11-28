# Design patterns

## Design

- Use a named pattern only where it solves a real problem, and apply patterns to workflow and automation conventions too, not only to application code.
- Wrap an external access mechanism such as an HTTP client behind a Gateway (Fowler) or a simple facade, so callers depend on an interface the application owns and the implementation changes in one place.

## Design and build

- Add behavior and cross-cutting concerns by wrapping code in decorators, middleware or pipeline behaviors rather than editing it, with each concern as one composable step. This matters most for code you cannot modify.
