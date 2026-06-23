# Research — check-jsonschema

JSON/YAML instance validator against JSON Schemas. PyPI package
`check-jsonschema`; upstream: <https://github.com/python-jsonschema/check-jsonschema>.

## Version

- Latest stable: **0.37.3**, published 2026-06-12 (agrees across the GitHub
  releases API `repos/python-jsonschema/check-jsonschema/releases/latest` and the
  PyPI JSON API `pypi.org/pypi/check-jsonschema/json`, verified 2026-06-23).
- `requires_python >=3.10`.

## Install + invocation

This repo runs Python tools through `uvx` (see the `ruff` and `pyright` actions),
not a checksum-pinned binary — check-jsonschema is a pure-Python wheel with no
single-binary release.

- The wheel's console-script entry point is `check-jsonschema = check_jsonschema:main`,
  so `uvx check-jsonschema@0.37.3 ...` runs it with no `--from`.
- Pin the exact version: the **built-in/vendored schemas are bundled per release**
  and drift across versions, so reproducibility requires an exact pin.

`medley` runs (lift-and-shift target) — four separate invocations in one job, one
schema per call:

```sh
check-jsonschema --builtin-schema vendor.dependabot      .github/dependabot.yml
check-jsonschema --schemafile tools/schemas/lefthook.schema.json  lefthook.yml
check-jsonschema --builtin-schema vendor.github-issue-forms  <form files…>
check-jsonschema --builtin-schema vendor.github-issue-config .github/ISSUE_TEMPLATE/config.yml
```

## Schema selection model — one schema + N files per call

A single invocation takes **exactly one** schema source and one-or-more target
files: `check-jsonschema <schema-source> file1 [file2 …]`. The three schema
sources are mutually exclusive per call:

- `--builtin-schema <name>` — a vendored schema bundled with check-jsonschema.
- `--schemafile <path-or-url>` — a caller-supplied schema file.
- `--check-metaschema` — validate the files as schemas themselves.

Built-in schema names in 0.37.3 (verified against the wheel's
`builtin_schemas/vendor/` directory, not just docs) — 26 `vendor.*` schemas:
`azure-pipelines`, `bamboo-spec`, `bitbucket-pipelines`, `buildkite`, `changie`,
`circle-ci`, `citation-file-format`, `cloudbuild`, `codecov`, `compose-spec`,
`dependabot`, `drone-ci`, `github-actions`, `github-discussion`,
`github-issue-config`, `github-issue-forms`, `github-workflows`, `gitlab-ci`,
`meltano`, `mergify`, `readthedocs`, `renovate`, `snapcraft`, `taskfile`,
`travis`, `woodpecker-ci` (each prefixed `vendor.`), plus one custom schema
`github-workflows-require-timeout` (no `vendor.` prefix).

## No config file — design implication

**Definitively config-light.** check-jsonschema reads **no** project config of its
own — no dotfile, no `pyproject.toml [tool.check-jsonschema]` table, no central
schema↔files mapping (verified against the 0.37.3 wheel source: no config-reading
code in `check_jsonschema/cli/`). The only places a schema↔files mapping lives as
"config" are a pre-commit hook list or the caller's own workflow. The schema for a
custom `--schemafile` (e.g. `medley`'s vendored `lefthook.schema.json`) is a
caller-owned file, not a `standards` module.

Consequence for the action: it models **one invocation** (one schema source +
target files via inputs); a caller that validates several schema groups (as
`medley` does) calls the action once per group. No `standards` module is created
for this tool.

## Other relevant flags (optional inputs / future backfill)

`--no-cache` (disable `$ref`/schema caching — sensible in CI), `-o/--output-format`
(`TEXT` default | `JSON`), `--traceback-mode` (`short` | `full`),
`--default-filetype` (`json` | `yaml` | `toml` | `json5`), `--force-filetype`,
`--color` (`always` | `never` | `auto`), `--data-transform`, `--fill-defaults`.

## Why uvx (not pip-install or a third-party action)

`medley` pip-installs a version pinned in `requirements.txt`. This repo's idiom for
ephemeral Python tooling is `uvx <tool>@<version>` provisioned by
`astral-sh/setup-uv` (see `ruff`, `pyright`): no virtualenv to manage, exact
version pin, self-contained.
