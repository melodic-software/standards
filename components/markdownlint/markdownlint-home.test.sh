#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

if [[ -x "$root/node_modules/.bin/markdownlint-cli2" ]]; then
  ml() { "$root/node_modules/.bin/markdownlint-cli2" "$@"; }
elif command -v markdownlint-cli2 >/dev/null 2>&1; then
  ml() { markdownlint-cli2 "$@"; }
else
  skip_suite 'markdownlint-cli2 not installed (run: npm ci)'
fi

manifest='distribution/sync-manifest.yml'
component='markdownlint-home'

manifest_files() {
  # SC2016: the single quotes are required — this is JavaScript, and its
  # `${...}` template literal must reach node unexpanded by the shell.
  # shellcheck disable=SC2016
  node -e '
    const YAML = require("yaml");
    const fs = require("fs");
    const doc = YAML.parse(fs.readFileSync(process.argv[1], "utf8"));
    const files = doc.components?.[process.argv[2]]?.files ?? {};
    const [source] = Object.keys(files);
    process.stdout.write(`${source ?? ""}\n${files[source] ?? ""}\n`);
  ' "$1" "$2"
}

mapfile -t mapping < <(manifest_files "$manifest" "$component")
source_path="${mapping[0]:-}"
dest_path="${mapping[1]:-}"

assert_eq 'component maps the home config' \
  'components/markdownlint/home/.markdownlint-cli2.jsonc' "$source_path"
assert_eq 'destination is the chezmoi dot_ source name' 'dot_markdownlint-cli2.jsonc' "$dest_path"
assert_file_exists 'the mapped source exists' "$source_path"

read_key() {
  node -e '
    const { parse } = require("jsonc-parser");
    const fs = require("fs");
    const doc = parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(JSON.stringify(doc[process.argv[2]]));
  ' "$1" "$2"
}

if ! node -e 'require("jsonc-parser")' 2>/dev/null; then
  skip_case 'ruleset-parity assertions require jsonc-parser (run: npm ci)'
else
  root_rules="$(read_key .markdownlint-cli2.jsonc config)"
  home_rules="$(read_key "$source_path" config)"
  assert_eq 'home ruleset is identical to the root ruleset' "$root_rules" "$home_rules"

  assert_contains 'root ruleset actually parsed' "$root_rules" 'MD013'

  home_ignores="$(read_key "$source_path" ignores)"
  assert_contains 'home config still excludes vendored node_modules' "$home_ignores" 'node_modules'
  assert_not_contains 'home config does not exclude bin/ as a build tree' "$home_ignores" '/bin/'
  assert_not_contains 'home config does not exclude obj/ as a build tree' "$home_ignores" '/obj/'
fi

case "$dest_path" in
  dot_*) pass 'destination carries the dot_ prefix chezmoi requires' ;;
  *) fail 'destination carries the dot_ prefix chezmoi requires' "got: $dest_path" ;;
esac

deployed_name=".${dest_path#dot_}"
assert_eq 'dot_ rename yields the discoverable filename' '.markdownlint-cli2.jsonc' "$deployed_name"

home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT

cp "$source_path" "$home/$deployed_name"
mkdir -p "$home/notes"
cp components/markdownlint/fixtures/good/Clean.md "$home/notes/Clean.md"
cp components/markdownlint/fixtures/bad/Violations.md.txt "$home/notes/Violations.md"

mkdir -p "$home/bin"
cp components/markdownlint/fixtures/bad/Violations.md.txt "$home/bin/Violations.md"

(cd "$home" && ml 'notes/Clean.md' >/dev/null 2>&1)
assert_exit 'auto-discovered config passes the good fixture' 0 "$?"

out="$(cd "$home" && ml 'notes/Violations.md' 2>&1)"
assert_exit 'auto-discovered config fails the bad fixture' 1 "$?"

assert_contains 'discovered ruleset flags list-bullet style (MD004)' "$out" 'MD004'
assert_contains 'discovered ruleset flags emphasis style (MD049)' "$out" 'MD049'
assert_not_contains 'discovered ruleset keeps MD013 disabled' "$out" 'MD013'

out="$(cd "$home" && ml 'bin/Violations.md' 2>&1)"
assert_not_contains 'authored markdown under bin/ is linted, not excluded' \
  "$out" 'Linting: 0 file(s)'

[[ $FAILED -eq 0 ]] || exit 1
