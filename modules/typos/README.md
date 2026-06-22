# typos module

Catches spelling mistakes in source and prose with
[typos](https://github.com/crate-ci/typos), a source-code-aware spell checker
that understands identifiers, code, and `.gitignore`.

## Contents

- `_typos.toml` — the decoupled base config. typos already respects
  `.gitignore` and skips binary files, so the config carries only repo-agnostic
  ignores: inline ignore directives, braced GUID/UUID literals, and a minified-
  bundle path exclude. It ships **no** domain words — adopters add their own.

## Engine

[typos](https://github.com/crate-ci/typos) (`typos`). It exits `0` when clean,
`2` when typos are found, and `1` on error. It is identifier-aware, so it rarely
false-positives on code, hashes, or lockfiles.

## Inline ignore directives

The base config blesses a comment-based escape hatch for silencing a single
false positive without polluting the global allow-lists (typos has no built-in
pragma). Shell/JS (`#`, `//`) and Markdown/HTML comment forms:

```text
teh  # spellchecker:disable-line

# spellchecker:ignore-next-line
someMisspelledToken

# spellchecker:off
a whole block the checker ignores
# spellchecker:on
```

Prefer a directive for one-off false positives; promote a genuinely valid word
to `[default.extend-words]` only when it recurs.

## Adopt in a repo

Reference the config without copying:

```bash
typos --config modules/typos/_typos.toml .
```

or drop `_typos.toml` at the consuming repo's root, where typos auto-discovers
it. Extend it with repo-specific vocabulary and vendored paths (the block
directive below is this module dogfooding its own escape hatch — the example
words are deliberate near-misspellings that would otherwise flag self-lint):

<!-- spellchecker:off -->
```toml
[default.extend-words]
ASO = "ASO"          # domain acronym, not a typo

[default.extend-identifiers]
seeked = "seeked"    # whole-token identifier (a DOM event name)

[files]
extend-exclude = ["vendor/", "*.min.*"]
```
<!-- spellchecker:on -->

## Test

`fixtures/typos/{good,bad}` exercise the checker; `typos.test.sh` runs them on
the shell harness. CI additionally spell-checks the whole repo (excluding the
intentionally-misspelled bad fixtures).
