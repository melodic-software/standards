#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

good='components/dotnet-analysis/fixtures/good/good.csproj'
bad='components/dotnet-analysis/fixtures/bad/bad.csproj'

command -v dotnet >/dev/null 2>&1 || skip_suite 'dotnet sdk not installed'

dotnet build "$good" --configuration Release --nologo >/dev/null 2>&1
assert_exit 'dotnet build: good fixture builds clean' 0 "$?"

out="$(dotnet build "$bad" --configuration Release --nologo 2>&1)"
assert_nonzero 'dotnet build: bad fixture exits non-zero' "$?"
assert_contains 'dotnet build: bad fixture enforces code-style (IDE0161)' "$out" 'IDE0161'
assert_contains 'dotnet build: bad fixture enforces code-quality (CA1051)' "$out" 'CA1051'

dotnet format whitespace "$good" --verify-no-changes >/dev/null 2>&1
assert_exit 'dotnet format: good fixture is already formatted' 0 "$?"

assert_command_fails 'dotnet format: bad fixture needs formatting' \
  dotnet format whitespace "$bad" --verify-no-changes

dotnet format style "$good" --diagnostics IDE0055 --verify-no-changes >/dev/null 2>&1
assert_exit 'dotnet format style: good fixture imports are organized' 0 "$?"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat >"$work/scratch.csproj" <<XML
<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="$root/components/dotnet-analysis/Directory.Build.props" />
  <PropertyGroup>
    <TargetFramework>net11.0</TargetFramework>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
  </PropertyGroup>
</Project>
XML
cat >"$work/Unsorted.cs" <<'CS'
using Microsoft.Win32.SafeHandles;
using System;

namespace Scratch;

public static class S
{
    public static string Go(SafeFileHandle? h) => h?.ToString() ?? string.Empty;
    public static int N() => Environment.ProcessId;
}
CS
cd "$work" || exit 1
assert_command_fails 'dotnet format style: System-first using order is enforced' \
  dotnet format style --diagnostics IDE0055 --verify-no-changes

[[ $FAILED -eq 0 ]] || exit 1
