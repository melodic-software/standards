# Harness configuration

## Design

- Sessions run on the harness's own default model and effort rather than pinned choices that fall behind, letting callers override; subagent roles follow ai.agent-design. A silent fallback to a weaker model when usage runs out degrades work, so make it visible or stop instead.

## Design and review

- Judge the stock harness first and keep a record of what a fresh install contains, so every customization is measured against it. Adopt a native feature the way the vendor recommends, only where it helps agents. Enable a new feature by default only after an experiment on real sessions measures its value and cost, with an easy on/off switch. Retire workaround add-ons as models improve.

## Design and build

- Ground every harness decision in the vendor's current official docs and changelog, read fresh. Model a new extension on the platform's shipped built-in equivalent. When a built-in companion serves a different purpose, build a purpose-specific one beside it and let users run either.
- A harness hook returns early and cheaply when its condition is absent and can never break a session. What hooks feed the model stays visible to the person without spam, in the fewest high-signal tokens. When your own guard blocks legitimate work, fix the guard rather than filing defects against built-in behavior.

## Design and operate

- Safe, read-only and already-approved operations run without prompts or denials, and any such friction is a defect. Write permission rules generically, reusable across repositories in the existing syntax, and classifier rules as the smallest unambiguous generalized expression.
- Keep tools installed but enable only what a phase, folder or user needs through layered, user-curatable profiles. General-purpose plugins are on by default, niche skills only where needed, and unused tools are off. Core workflow tools and safety guardrails stay enabled. Prefer plugin-bundled MCP servers, and decide user versus project scope by precedence.

## Operate

- Launch headless sessions with the harness's native options (names, modes) set consistently, and give every session a descriptive name, spawned ones included.
