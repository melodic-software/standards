# Testability

## Design

- Treat testability as a primary lever of code quality. An interface, abstraction or seam earns its place by making code testable, especially in legacy code (Feathers).

## Build

- Inject the clock instead of calling the current time directly, and default to UTC.
