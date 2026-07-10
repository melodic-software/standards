# Lefthook TypeScript

Opt-in staged JavaScript and TypeScript feedback. `lefthook.yml` runs the
consumer-pinned Biome engine for lint, format, and import sorting. TypeScript
type-checking stays in CI because it operates on a project graph. Compose this
fragment with `lefthook-base` for shared strict settings and glob matching. The
hook fails closed when Biome is not installed locally; it never downloads an
unpinned version during a commit.
