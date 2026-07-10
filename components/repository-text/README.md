# Repository text

Cross-platform text normalization for editors and Git.

The component exports the root [`.editorconfig`](../../.editorconfig) and
[`.gitattributes`](../../.gitattributes) as one atomic payload because the two
files jointly define whitespace, encoding, and line-ending behavior. Their
tool-mandated root locations are the canonical source; this directory contains
only the component documentation, not duplicate copies.

EditorConfig validation is a separate capability in
[`editorconfig-checker`](../editorconfig-checker/). Git index normalization is
enforced by the reusable `eol-renormalize` action in `ci-workflows`.
