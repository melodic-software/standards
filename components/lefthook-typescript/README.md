# Lefthook TypeScript

Opt-in staged JavaScript and TypeScript feedback. `lefthook.yml` runs the
consumer-pinned Biome engine for lint, format, and import sorting. TypeScript
type-checking stays in CI because it operates on a project graph. The
consumer's root `lefthook.yml` sets the strict settings and
`glob_matcher: doublestar` itself (see
[lefthook-base](../lefthook-base/README.md#remote-form)). The
hook fails closed when Biome is not installed locally; it never downloads an
unpinned version during a commit.

`lefthook-typescript.test.sh` builds a temporary consumer and checks that the
biome lane passes a clean file, fails a lint finding, and passes a commit that
stages only files the consumer's Biome config ignores.
