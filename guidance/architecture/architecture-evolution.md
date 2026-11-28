# Architecture evolution

## Plan and build

- Document the target state and a route to it, then reach it incrementally through normal changes rather than fixing everything at once.

## Plan and review

- A port, replacement or wrapper of an existing component ships only with full behavioral parity, meaning every feature and acceptance criterion of what it replaces, and with a way to stay in sync.

## Build and review

- Enforce architecture rules with static analyzers, custom ones included, so agents cannot violate boundaries unnoticed.
