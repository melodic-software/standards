# Naming

## Design and build

- Settle naming, scope and boundary choices before shipping, by semantic accuracy backed by data and research, not taste. Couple other things to a stable identifier, qualifier or composite key, never to a display name. Never identify a resource or trigger behavior from a fragile signal, such as a host embedded in a name, a draft state or a line of text.
- Name an adopted tool by what it actually does when run; its author's name for it is not the spec. Look for the real-world thing that plays the same role, check that the name is available, and record the choice where the next worker will see it.

## Build

- Keep machine identifiers separate from display names. Use lower-kebab-case for machine ids and doc file names and Title Case for user-facing display names, each applied consistently.
- Define every name, label or code where it first appears and say where it applies. Qualify any term that could mean two things. Spell out an abbreviation unless it is widely understood, above all where it is overloaded.
- Prefer a fully qualified name when a sibling of the same category could appear later. Put the base term first and add modifiers as a suffix, and check that a grouping word fits every member it groups. Question any name containing "and", "or" or "in". Make a name explicit enough not to be overloaded, but not so bespoke that it cannot cover the next cases.
- For names that agents and terminals read: avoid words agents already read another way (such as "context"), and give agent skills imperative-verb names. Keep frequent commands from sharing a typing prefix, so tab completion does not pick the wrong one. Reserve "doctor" for a tool that inspects itself, and use "ready" or "health" for a check of a running app. Say "interactive", not "attended", for a session a person drives.

## Build and review

- Treat every change as the moment to check that each name is semantically accurate for its boundary and purpose. When a better term exists, rename now, despite the refactoring cost. Give one concept one label, and treat a term that is unclear on reading as the wrong term.
- A rename is complete only when no reference to the old name remains anywhere. Prefer a clean break over keeping aliases. Set explicit naming conventions for each repository and rename the existing stragglers, not only new names.
