# .NET analysis

Strict first-party .NET analysis delivered as one atomic two-file component:

- `Directory.Build.props` enables nullable analysis, SDK analyzers,
  `AnalysisMode=All`, build-time code style, warnings-as-errors, and NuGet lock
  files.
- `dotnet.globalconfig` owns analyzer and code-style severities while leaving
  whitespace to `dotnet format`.

The props file references the sibling global config, so the pair is adopted,
updated, or removed together. They intentionally omit `TargetFramework` and
`LangVersion`; those are project/runtime decisions. The component uses only
analyzers included in the SDK and adds no analyzer package dependency.

The `dotnet-build` and `dotnet-format` actions in `ci-workflows` own execution.
Managed consumers do not edit the payload; a repository with an established
`Directory.Build.props` either imports the component intact or owns its complete
.NET analysis policy locally.

`fixtures/` and `dotnet-analysis.test.sh` prove code-quality, code-style, whitespace, and
System-first import ordering. Contract fixtures are not distributed.
