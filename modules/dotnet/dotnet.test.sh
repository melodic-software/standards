#!/usr/bin/env bash
# Tests the dotnet module: the build (analyzers + code-style) and format
# (whitespace) owners pass the good fixture and flag the bad fixture. The suite
# skips cleanly when the .NET SDK is absent.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1

good='fixtures/dotnet/good/good.csproj'
bad='fixtures/dotnet/bad/bad.csproj'

have_dotnet=0
command -v dotnet >/dev/null 2>&1 && have_dotnet=1
if [[ $have_dotnet -eq 0 ]]; then
  skip_suite 'dotnet sdk not installed'
fi

FAILED=0
CASE_NUM=0

# --- build: owns code-quality (CAxxxx) + code-style (IDExxxx), warnings-as-errors
dotnet build "$good" --configuration Release --nologo >/dev/null 2>&1
assert_exit 'dotnet build: good fixture builds clean' 0 "$?"

out="$(dotnet build "$bad" --configuration Release --nologo 2>&1)"
rc=$?
assert_exit 'dotnet build: bad fixture exits non-zero' 1 "$((rc != 0 ? 1 : 0))"
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

dotnet format whitespace "$bad" --verify-no-changes >/dev/null 2>&1
rc=$?
assert_exit 'dotnet format: bad fixture needs formatting' 1 "$((rc != 0 ? 1 : 0))"

[[ $FAILED -eq 0 ]] || exit 1
