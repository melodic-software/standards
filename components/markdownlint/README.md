# Markdownlint

GitHub Flavored Markdown policy for
[markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2). This
directory backs two manifest components, both auto-discovered by the CLI and
editor integrations at the location they deploy to:

| Component | Payload | Deploys as |
| --- | --- | --- |
| `markdownlint` | root-canonical [`.markdownlint-cli2.jsonc`](../../.markdownlint-cli2.jsonc) | a repository's own `.markdownlint-cli2.jsonc` |
| `markdownlint-home` | [`home/.markdownlint-cli2.jsonc`](home/.markdownlint-cli2.jsonc) | `~/.markdownlint-cli2.jsonc`, via the dotfiles `dot_` source name |

Both configs pin their schema to the supported CLI version and own rule
choices. The root config additionally declares a repository traversal scope;
the home config declares its own, deliberately different one.

## Why the home payload is a sibling, not the same file

markdownlint-cli2 does not read a config from an *ancestor* of the working
directory, so a session rooted at the home directory resolves no config at all
and falls back to stock defaults. The home payload closes that gap without
touching repository-rooted runs, which keep using their own materialized copy.

The two `config` blocks are identical and must stay that way.
`markdownlint-home.test.sh` asserts the equality and fails the build on drift —
that gate is what makes the duplication safe. `config.extends` would express
the sharing directly, but the file it names has to exist beside the deployed
one, and only a single file deploys to the home directory.

The `ignores` blocks deliberately diverge. The root config excludes build and
cache trees (`bin/`, `obj/`) on the premise that the tree is a repository
checkout; under a home directory that premise fails, since `~/bin` holds
authored Markdown rather than build output. The home config therefore keeps
only the exclusions that hold anywhere — vendored `node_modules` and `.venv`.

## Verification

`fixtures/` is shared by both tests.

- `markdownlint.test.sh` proves the ruleset itself: conforming Markdown passes
  and configured style failures are flagged. It passes `--config` explicitly.
- `markdownlint-home.test.sh` proves the consumer path `--config` cannot reach:
  the manifest mapping, the `dot_` rename, auto-**discovery** by filename with
  no flag, that the discovered ruleset is this one rather than stock defaults,
  ruleset parity with the root config, and that authored Markdown under `bin/`
  is linted rather than silently excluded.
