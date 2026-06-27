# dotnet module

.NET static analysis: code-quality + code-style via the
[Roslyn analyzers](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/overview)
enforced during `dotnet build`, and whitespace/layout via
[`dotnet format`](https://learn.microsoft.com/dotnet/core/tools/dotnet-format).

Both configs lean strict — findings are hard failures, in line with a
warnings-as-errors posture — and the two owners are split so they never
double-report: the build owns code-quality (CAxxxx), code-style (IDExxxx), and
nullable/compiler correctness; `dotnet format whitespace` owns whitespace, the
one thing the build does not enforce by default.

## Contents

- `Directory.Build.props` — the strict MSBuild posture: the switches that turn
  the analyzers and code-style rules into build errors. Self-documents its
  rationale inline. Notable choices:
  - `AnalysisMode=All` is the strictest code-quality preset (nearly every CA rule
    on as a warning — a few legacy CA and code-metrics rules stay opt-in even
    under `All`); `EnforceCodeStyleInBuild` runs the IDExxxx rules on build;
    `TreatWarningsAsErrors` escalates compiler **and** analyzer warnings to
    errors. `Nullable` is on.
  - It carries **no `TargetFramework` and no `LangVersion`** — the runtime floor
    is consumer-supplied (see adoption). Pinning either would couple the ruleset
    to one runtime, and Microsoft discourages `LangVersion=latest`.
  - It wires the severity ruleset via `GlobalAnalyzerConfigFiles`, so the two
    files must travel together.
- `dotnet.globalconfig` — the analyzer/code-style severities, as a global
  AnalyzerConfig (path-independent, no directory section). Notable choices:
  - Code-quality (CAxxxx) is turned on wholesale by `AnalysisMode`, so CA rules
    are not enumerated here; the file escalates the high-value **code-style**
    (IDExxxx) rules that `AnalysisMode` does not touch, and pins the matching
    style preferences.
  - `IDE0055` (formatting) is set to `none` so the build does not report
    whitespace — `dotnet format` is its single owner. The CI format lane still
    gates using-directive organization (`dotnet format style --diagnostics
    IDE0055`): that pass runs regardless of the `none` severity, so System-first
    import sorting is enforced without the build re-reporting whitespace.
  - Editor keys (`indent_size`, `trim_trailing_whitespace`, …) cannot live in a
    global config; they stay in the repo-root `.editorconfig`, which already
    covers C# via its language-agnostic defaults.

Neither tool ships a runner here; the CI lanes that install the pinned SDK and
run them live in the `ci-workflows` repo (execution) as the `dotnet-build` and
`dotnet-format` composite actions. `dotnet-build` builds with warnings-as-errors;
`dotnet-format` runs `dotnet format whitespace --verify-no-changes` and
`dotnet format style --diagnostics IDE0055 --verify-no-changes` (import ordering).

## Engine

- The .NET SDK (any recent release; the repo dogfoods a pinned version in CI).
  Analysis is **first-party only** — the code-quality and code-style analyzers
  ship inside the SDK, so the overlay adds no analyzer `PackageReference`s and
  has no NuGet manifest to track.

`TargetFramework` and `LangVersion` are intentionally omitted: each consuming
repo's runtime floor drives them, so the base stays correct for any consumer (the
same reason the Python overlay omits Ruff's `target-version` and the TypeScript
overlay omits `target`).

## Adopt in a repo

1. **Build posture** — copy `Directory.Build.props` to the consuming repo's root
   (or `Import` its `PropertyGroup`/`ItemGroup` into an existing one), keeping
   `dotnet.globalconfig` beside it so `GlobalAnalyzerConfigFiles` resolves it.
   Then add the project scope the base omits — `TargetFramework`, package
   versions, source layout. Relax a context-specific rule (for example `CA2007`,
   `CA1062`, `CA1303`) in your **own** `.globalconfig` / `.editorconfig` for one
   tree rather than weakening this base. Reference the `ci-workflows`
   `dotnet-build` action from CI, pointing its `project` input at your solution.
2. **Formatting** — reference the `ci-workflows` `dotnet-format` action from CI.
   Locally, `dotnet format` (no subcommand) auto-fixes whitespace, code-style, and
   import ordering; CI gates on the build (style + quality), `dotnet format
   whitespace`, and `dotnet format style --diagnostics IDE0055` (import ordering).

## Test

`fixtures/dotnet/{good,bad}` exercise both owners; `dotnet.test.sh` asserts the
good fixture builds and formats clean and the bad fixture is flagged with
specific rule identifiers (`IDE0161` for code-style, `CA1051` for code-quality)
— proving the configs load, not just that the tools ran — via the shell harness
(`harness/shell/run-tests.sh`). Each fixture imports the base props with a
relative path, because the base ships no project scope. The `bad` fixture is
intentionally non-conforming and is excluded from the repo's own self-lint.
