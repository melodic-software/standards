#!/usr/bin/env bash
# Tests the dotnet module: the build (analyzers + code-style) owner and the format
# owners (whitespace, plus import organization via the IDE0055 OrganizeImports
# pass) pass the good fixture and flag violations. The suite skips cleanly when the
# .NET SDK is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

good='fixtures/dotnet/good/good.csproj'
bad='fixtures/dotnet/bad/bad.csproj'

command -v dotnet >/dev/null 2>&1 || skip_suite 'dotnet sdk not installed'

# --- build: owns code-quality (CAxxxx) + code-style (IDExxxx), warnings-as-errors
dotnet build "$good" --configuration Release --nologo >/dev/null 2>&1
assert_exit 'dotnet build: good fixture builds clean' 0 "$?"

out="$(dotnet build "$bad" --configuration Release --nologo 2>&1)"
assert_nonzero 'dotnet build: bad fixture exits non-zero' "$?"
# IDE rules are off-by-default and EnforceCodeStyleInBuild is off-by-default, so
# IDE0161 (file-scoped namespace) fires only because the props + globalconfig
# loaded — proving the code-style overlay, not a default.
assert_contains 'dotnet build: bad fixture enforces code-style (IDE0161)' "$out" 'IDE0161'
# CA1051 is off in the default analysis mode; it fires only because the overlay
# raises AnalysisMode — proving the strict code-quality posture loaded.
assert_contains 'dotnet build: bad fixture enforces code-quality (CA1051)' "$out" 'CA1051'

# --- format: owns whitespace/layout (no IDE/CA, so no double-report)
dotnet format whitespace "$good" --verify-no-changes >/dev/null 2>&1
assert_exit 'dotnet format: good fixture is already formatted' 0 "$?"

assert_command_fails 'dotnet format: bad fixture needs formatting' \
  dotnet format whitespace "$bad" --verify-no-changes

# --- format style (import organization): the IDE0055 OrganizeImports pass gates
# System-first using sort even though IDE0055 severity is none. The good fixture is
# already organized; an unsorted scratch project that imports the overlay's props
# must be flagged — proving dotnet_sort_system_directives_first is enforced, not
# inert. (--diagnostics IDE0055 scopes the lane to import order, so it never
# re-reports the whitespace/IDE/CA the other owners gate.)
dotnet format style "$good" --diagnostics IDE0055 --verify-no-changes >/dev/null 2>&1
assert_exit 'dotnet format style: good fixture imports are organized' 0 "$?"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat >"$work/scratch.csproj" <<XML
<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="$root/modules/dotnet/Directory.Build.props" />
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
  </PropertyGroup>
</Project>
XML
# All-resolvable usings, System.Text before System — only the import order is
# wrong, so only the organize-imports gate should fire.
cat >"$work/Unsorted.cs" <<'CS'
using System.Text;
using System;

namespace Scratch;

public static class S
{
    public static string Go() => new StringBuilder(string.Empty).ToString();
}
CS
cd "$work" || exit 1
dotnet format style --diagnostics IDE0055 --verify-no-changes >/dev/null 2>&1
assert_nonzero 'dotnet format style: unsorted usings are flagged' "$?"

[[ $FAILED -eq 0 ]] || exit 1
