# EditorConfig checker

Validation of repository text policy with
[editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker).

The exported payload is the root-canonical
[`.editorconfig-checker.json`](../../.editorconfig-checker.json). It configures
the checker but does not own formatting policy: `.editorconfig` and
`.gitattributes` are the separate, atomic `repository-text` component.
End-of-line validation is disabled here because `.gitattributes` is the byte
normalization authority; indent width and line length remain formatter-owned.

Managed consumers do not edit the root config. Repository-specific path
exclusions are additive command inputs (`-exclude`) supplied by execution; any
other change [opts out](../../distribution/ESCAPE-HATCHES.md#opting-a-repository-out-of-a-managed-component).
`fixtures/` and `editorconfig-checker.test.sh` prove both conforming and failing inputs.

## Defaults, extensions and overrides

The ci-workflows `editorconfig-checker` composite and this repository's lefthook remote (`components/lefthook-base/lefthook-remote.yml`) read this file at run time. editorconfig-checker reads one config and has no include or extends, so a repository's own file replaces this one whole; with none, the readers pass this file (`-config`).

| Mode | What the repository commits | Result |
| --- | --- | --- |
| Default | nothing | this file alone |
| Extension | per-finding suppressions: the composite's additive `exclude` input | this file plus the suppressions |
| Complete override | its own root `.editorconfig-checker.json` | that file alone; nothing here applies |

A partial override has no native mechanism; a repository that needs one copies this file and edits it.
