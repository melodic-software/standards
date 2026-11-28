# Readability

## Build

- Mark an interim, non-ideal choice with a brief comment that says it is not ideal and why, so someone can revisit it.
- Hold production code to the codebase's language and framework rules, set during design. Exempt prototypes and throwaway code.
- Keep registry lists in alphabetical order.

## Build and review

- Keep only the comments that are needed, apply that rule across the whole codebase, and have linting enforce it. Read "no comments" by meaning, not as a literal zero: keep comments that generate public API documentation, even under the strictest setting.

## Build and operate

- Do not let a formatter or linter auto-fix a whole repository until the team has agreed its rules. Committed lint and format config is a team convention, not a personal one.
