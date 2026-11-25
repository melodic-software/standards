# Markdownlint

GitHub Flavored Markdown policy for
[markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2). This
directory documents two configs:

| Config | Reaches its readers as |
| --- | --- |
| root-canonical [`.markdownlint-cli2.jsonc`](../../.markdownlint-cli2.jsonc) | fetched from this repository at run time (not synced), as below |
| [`home/.markdownlint-cli2.jsonc`](home/.markdownlint-cli2.jsonc) | the `markdownlint-home` manifest component: `~/.markdownlint-cli2.jsonc`, via the dotfiles `dot_` source name, auto-discovered by the CLI and editor integrations |

Both configs own their rule choices, and both point their `$schema` URL at
markdownlint-cli2's `main` branch schema. The CLI never reads `$schema`; only
editors use it, so the URL names no version and a dependency bump leaves it
alone. The root config additionally declares a repository traversal scope; the home config
declares its own, deliberately different one.

## Defaults, extensions and overrides

The ci-workflows `markdownlint` composite and the melodic-software/claude-code-plugins lefthook remote (for a repository whose `docs/conventions/source-control.yaml` names `standards_repository`) read this file at run time. markdownlint-cli2 applies a `--config` file as the base and merges the repository's own `.markdownlint-cli2.jsonc` (and nested configs) over it rule by rule ([README](https://github.com/DavidAnson/markdownlint-cli2/blob/main/README.md), checked with markdownlint-cli2 0.24.1).

| Mode | What the repository commits | Result |
| --- | --- | --- |
| Default | nothing | this file alone |
| Extension | root `.markdownlint-cli2.jsonc` with only the rules it adds | both apply |
| Partial override | root `.markdownlint-cli2.jsonc` with only the rules it changes | the repository's value wins per rule; a top-level option such as `ignores` it sets replaces this file's whole |
| Complete override | a config that sets every rule this file sets, or (CI) a config at another path passed as the composite's `config` input | that file's rules |

## Why the home payload is a sibling, not the same file

markdownlint-cli2 does not read a config from an *ancestor* of the working
directory, so a session rooted at the home directory resolves no config at all
and falls back to stock defaults. The home payload closes that gap without
touching repository-rooted runs, which keep using the root config.

The two `config` blocks are identical and must stay that way.
`markdownlint-home.test.sh` asserts the equality and fails the build on drift.
That gate is what makes the duplication safe. `config.extends` would express
the sharing directly, but the file it names has to exist beside the deployed
one, and only a single file deploys to the home directory.

The `ignores` blocks deliberately diverge. The root config excludes build and
cache trees (`bin/`, `obj/`) on the premise that the tree is a repository
checkout; under a home directory that premise fails, since `~/bin` holds
authored Markdown rather than build output. The home config therefore keeps
only the exclusions that hold anywhere: vendored `node_modules` and `.venv`.

## Verification

`fixtures/` is shared by both tests.

- `markdownlint.test.sh` proves the ruleset itself: conforming Markdown passes
  and configured style failures are flagged. It passes `--config` explicitly.
- `markdownlint-home.test.sh` proves the consumer path `--config` cannot reach:
  the manifest mapping, the `dot_` rename, auto-**discovery** by filename with
  no flag, that the discovered ruleset is this one rather than stock defaults,
  ruleset parity with the root config, and that authored Markdown under `bin/`
  is linted rather than silently excluded.
