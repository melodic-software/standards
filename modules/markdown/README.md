# Markdown module

GitHub Flavored Markdown linting via [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2).

## Contents

- `.markdownlint-cli2.jsonc` — the GFM ruleset: ATX headings, dash bullets, asterisk emphasis, fenced backtick code, GFM table rules. Schema-pinned to markdownlint-cli2 0.22.1.

## Engine

Requires Node (pinned per-repo via `.node-version`, provided by fnm) and `markdownlint-cli2` (pinned as an npm devDependency). It exits `0` when clean and `1` on findings.

## Adopt in a repo

Two ways to apply the ruleset:

- **By reference (no copy):** keep this file in the module and point the linter at it —

  ```bash
  npx markdownlint-cli2 --config modules/markdown/.markdownlint-cli2.jsonc "**/*.md"
  ```

- **Drop-in:** copy `.markdownlint-cli2.jsonc` to the consuming repo's root, where markdownlint-cli2 and the VS Code extension auto-discover it.

Pin `markdownlint-cli2` as a devDependency and Node via `.node-version` for reproducibility.

## Test

`fixtures/markdown/{good,bad}` exercise the ruleset; `markdown.test.sh` runs them on the shell harness.
