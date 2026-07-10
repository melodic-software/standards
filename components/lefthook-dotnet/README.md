# Lefthook .NET

Opt-in staged C# whitespace verification. `lefthook.yml` invokes `dotnet format
whitespace` for staged C# files. Analyzer builds remain in CI because they are
too broad and expensive for a per-file pre-commit lane. Compose this fragment
with `lefthook-base` for shared strict settings and glob matching.
