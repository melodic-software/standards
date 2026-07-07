# typescript module

TypeScript static analysis: linting + formatting via [Biome](https://biomejs.dev/)
and type-checking via the [TypeScript compiler](https://www.typescriptlang.org/)
(`tsc --noEmit`).

Both configs lean strict — findings are hard failures, in line with a
warnings-as-errors posture — and the two tools are split so they never
double-report: Biome owns lint, formatting, and import sorting (including
unused-symbol findings, which it can autofix), `tsc` owns type correctness.

## Contents

- `biome.json` — the lint + format ruleset, pinned to the Biome `$schema` it was
  authored against. Notable choices:
  - `recommended` is the baseline; the explicit rules add high-value checks that
    `recommended` leaves off (type-aware promise handling, `noConsole`, exhaustive
    switches, and others). Pair it with `biome ci --error-on-warnings` so any
    residual warning also fails.
  - `root: false` marks it as a shared, non-root config so it loads from a nested
    path (e.g. `modules/typescript/`) without a project-root config above it, and
    so a consumer can `extends` it from their own root `biome.json`. Biome 2.x
    rejects a nested `root: true` config.
  - It carries **no project scope** — which sources to check is
    consumer/project-scope (see adoption below). Biome has no CLI exclude and
    treats path arguments as literal, so narrow via `files.includes` (with `!`
    negation) or the action's `paths` input. The one `files.includes` entry it
    does ship is the universal generated-file exemption `!**/packages.lock.json`
    (NuGet's lock file — Biome
    [protects](https://biomejs.dev/guides/configure-biome/#specifying-files-to-process)
    the npm/yarn/composer lockfiles natively but not NuGet's); a consumer
    defining its own `files.includes` replaces the list wholesale and must
    carry that negation forward.
  - Several nursery / type-aware rules are named explicitly. Nursery rules are
    not under semver and graduate or get renamed between minors, so the Biome
    version is pinned and the rule set is re-audited on each bump.
- `tsconfig.json` — the portable type-checking ruleset only. Notable choices:
  - `strict` plus the strict-family escalations `recommended`/`strict` leaves off
    (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`,
    `noPropertyAccessFromIndexSignature`, `noImplicitReturns`, …) and modern
    interop posture (`verbatimModuleSyntax`, `isolatedModules`, `esModuleInterop`).
  - `noUnusedLocals` / `noUnusedParameters` are intentionally **omitted** so Biome
    is the single owner of unused-symbol findings.
  - `noEmit` is intentionally **omitted**: it lives on the CI command line, so the
    same base is usable for a consumer's build (which emits) and for type-check
    lanes (which pass `--noEmit`).
  - It carries **no project-scope keys** — see adoption below.

Neither tool ships a runner here; the CI lanes that install pinned engines and
run them live in the `ci-workflows` repo (execution) as the `biome` and `tsc`
composite actions. The `biome` action runs `biome ci --error-on-warnings` so
warnings fail the build; the `tsc` action runs `tsc --noEmit`.

## Engine

- Biome (any recent release; the repo dogfoods a pinned version in CI). The
  `$schema` and named rules track the pinned version.
- TypeScript / `tsc` (likewise pinned in CI).

`target`, `lib`, `module`, `moduleResolution`, and `types` are intentionally
omitted from `tsconfig.json`: each consuming repo's runtime floor and module
environment drive them, so the base stays correct for any consumer (the same
reason the Python overlay omits Ruff's `target-version`).

## Adopt in a repo

1. **Biome** — copy `biome.json` to the consuming repo (canonical home
   `modules/typescript/`). Either reference it directly from CI (the `biome`
   action's `config` input), or `extends` it from a root `biome.json` that adds
   project scope:
   - `files.includes` — the source globs to check, with `!`-prefixed exclusions
     (Biome's only exclude mechanism).
   - Per-directory `overrides` — the right place to relax a rule for one tree
     rather than weakening the global standard.
2. **TypeScript** — copy `tsconfig.json` to the consuming repo's root, then add
   the project-scope keys the base omits:
   - `target` / `lib` / `module` / `moduleResolution` — the runtime floor and
     module environment for this project.
   - `include` (and `files` / `exclude` / `references` as needed) — the source
     roots to type-check. Type-check tests too; excluding them is an anti-pattern.
   - `outDir` / `declaration` / build keys — only for a tsconfig that also emits.
   Reference the `ci-workflows` `tsc` action from CI, pointing its `project`
   input at this tsconfig.

## Test

`fixtures/typescript/{good,bad}` exercise both rulesets; `typescript.test.sh`
asserts the good fixture is clean and the bad fixture is flagged with specific
rule identifiers — proving the configs load, not just that the tools ran — via
the shell harness (`harness/shell/run-tests.sh`). Each fixture carries a small
`tsconfig.json` that extends the base and supplies `include`, because `tsc`
cannot mix `--project` with file arguments. The `bad` fixture is intentionally
non-conforming and is excluded from the repo's own self-lint.
