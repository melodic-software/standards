#!/usr/bin/env bash
# Guards the fact both .markdownlint-cli2.jsonc configs' $schema URL claims: that
# it documents THIS repo's own markdownlint-cli2 devDependency pin, not any
# consumer's. The pin is hand-maintained (a comment plus a release-pinned URL,
# not read from package.json — no such indirection exists in a static JSONC
# schema reference), so nothing stops it drifting from the dependency it
# describes the moment one is bumped without the other. This is the visibility
# gate for that pair: fail loudly on drift instead of letting the comment keep
# claiming a version it no longer matches.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

if [[ ! -d node_modules ]]; then
  skip_suite 'dependencies not installed (run: npm ci)'
fi

# jsonc-parser is a direct devDependency, so an install that succeeded has it.
# Skipping on its absence would report a green build at exactly the upgrade
# boundary this guard exists to police — the drift would land unwatched while
# the suite claimed to be watching.
if ! node -e 'require("jsonc-parser")' 2>/dev/null; then
  fail 'jsonc-parser resolves from the installed dependencies' \
    'declared in package.json devDependencies but not resolvable; re-run npm ci'
  exit 1
fi

pinned_version="$(node -e '
  const fs = require("fs");
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  process.stdout.write(pkg.devDependencies?.["markdownlint-cli2"] ?? "");
')"

if [[ -z "$pinned_version" ]]; then
  fail 'package.json pins markdownlint-cli2 as a devDependency' 'no version found'
  exit 1
fi

expected_schema="https://raw.githubusercontent.com/DavidAnson/markdownlint-cli2/v${pinned_version}/schema/markdownlint-cli2-config-schema.json"

read_schema() {
  # SC2016: the single quotes are required — this is JavaScript, and the
  # literal "$schema" property key must reach node unexpanded by the shell.
  # shellcheck disable=SC2016
  node -e '
    const { parse } = require("jsonc-parser");
    const fs = require("fs");
    const doc = parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(doc["$schema"] ?? "");
  ' "$1"
}

for config in .markdownlint-cli2.jsonc components/markdownlint/home/.markdownlint-cli2.jsonc; do
  actual_schema="$(read_schema "$config")"
  assert_eq "$config \$schema matches package.json's markdownlint-cli2 pin (v$pinned_version)" \
    "$expected_schema" "$actual_schema"
done

[[ $FAILED -eq 0 ]] || exit 1
