# Authentication

## Design

- Treat an AI agent's identity as a bot (a non-human actor), and give automation its own identity, separate from the interactive one.
- Prefer app-issued tokens over personal access tokens, unless a personal token is the established best practice for the case.
- Reuse and consolidate bot apps rather than adding one per lane or repository, balanced against least privilege. Before reusing one, check how each candidate is used across its consumers.
- Recognize a returning user across browsers, so reopening a shared link never creates a duplicate participant.
