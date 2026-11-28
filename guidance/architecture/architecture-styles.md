# Architecture styles

## Design

- When shaping a system, always weigh event-driven architecture, a message bus, the monolith, and layered and clean architecture among the core candidates.
- Prefer vertical (feature) slice architecture where it fits, organizing by feature rather than technical layer. Use it alongside SOLID and coupling and cohesion as a lens to check each design item.
- Prefer hexagonal architecture. Put every external service, tracker, chat tool and even file format behind a port as an adapter, so the dependency is inverted and replaceable. Work natively by default and hardcode no external tool.
- Make the top-level structure show what the system does (Screaming Architecture).

## Build

- Detect a project's architecture style before generating structure for it, because the style changes how feature folders are laid out.
