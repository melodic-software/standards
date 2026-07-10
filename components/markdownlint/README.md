# Markdownlint

GitHub Flavored Markdown policy for
[markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2). The
exported payload is the root-canonical
[`.markdownlint-cli2.jsonc`](../../.markdownlint-cli2.jsonc), where the CLI and
editor integrations auto-discover it.

The config pins its schema to the supported CLI version and owns rule choices,
not repository traversal scope. `fixtures/` and `markdownlint.test.sh` prove both
conforming Markdown and configured style failures.
