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
exclusions are additive command inputs (`-exclude`) supplied by execution.
`fixtures/` and `editorconfig-checker.test.sh` prove both conforming and failing inputs.
