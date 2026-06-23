# Research — comment-hygiene

Cross-cutting repo-hygiene gate: code comments must not carry deferred-work
markers (`TODO`/`FIXME`/`HACK`/`XXX`) or issue-tracker references (`issue`/
`fixes`/`closes #N`, `PR #N`). Lifted from `medley`'s always-on `comment-hygiene`
job in `ci-status.yml`, which calls `tools/shared/comment-hygiene/scan-tree.sh`
and sources `comment-hygiene-patterns.sh`.

## Why it exists

Outstanding work tracked in a code comment rots silently — it is invisible to
the issue tracker and survives long after the context is gone. The gate pushes
that work to the tracker and keeps the source clean.

## Tool / pinning

**Pure shell + git — no external binary** to version-pin or checksum. Uses
`git grep -E`, `awk`, and bash regex. POSIX ERE only.

## Config boundary — the one Phase 3 tool that needs a standards module

The **pattern set is genuine policy** (what comment content is banned is a
choice that varies per org/repo), so per the program's config rule it lives
upstream in `standards` as `modules/comment-hygiene/comment-hygiene-patterns.sh`
and is vendored byte-identical into this repo for dogfooding (lockstep, like the
Phase 1 trio). The **execution** (`scan-tree.sh`) is a separate concern bundled
in the action via `$GITHUB_ACTION_PATH`.

### Generalized, not byte-identical to medley (deliberate)

medley's pattern library is deeply medley-coupled: hardcoded `melodic-software/
medley` internal-issue refs, `.work` phase-grammar carve-outs, an
encapsulation-audit exception, `cc-issue` tokens, and a long medley-specific
skip-path list. Importing those literals into an **org-wide** module would be
wrong for every other consumer. So the lifted module keeps the detection
*mechanism* (coarse `git grep` prefilter → authoritative per-line library
validation) but ships a **clean org-default policy**: the four warning markers
plus generic `issue|fixes|closes #N` / `PR #N` tracker refs, case-insensitive,
matched with token boundaries. medley keeps its richer rules as its own vendored
override when it cuts over (Phase 6).

This is the resolution of the open question raised at the start of Phase 3
(generalized org policy vs. byte-identical lift), decided in favor of a clean
org artifact.

### What medley's path/extension scoping became

medley's library also carried `chp::should_skip_path` / `is_scannable_extension`
(medley-specific paths and a fixed extension set). Those are **scan scoping**,
not detection policy, so they are not in the lifted library — they become the
action's `extensions` and `exclude` open-closed string inputs (D4).

## Behavior notes (faithful to the lifted mechanism)

- Only **full-line** comments are scanned (`^\s*(//|#)…`). Inline trailing
  comments (`code(); // TODO`) are intentionally not scanned — this is medley's
  behavior and avoids false positives on `//` inside URLs and string literals.
- The library matches markers case-insensitively and restores `nocasematch` so
  sourcing it never leaks shell state.
- `scan-tree.sh` fails **closed**: a coarse `git grep` exit other than 0 (match)
  or 1 (no match) is treated as a fatal error (`exit 2`), not a silent pass.

## Build decision

Bundled `scan-tree.sh` via `$GITHUB_ACTION_PATH` (D7); the policy library is a
caller-repo file referenced by the `patterns-file` input (default
`modules/comment-hygiene/comment-hygiene-patterns.sh`), mirroring how the
editorconfig/gitleaks actions point at their vendored configs.

## Dogfood note

The vendored library's own doc-comments contain the literal marker tokens, so
the ci-workflows dogfood passes
`exclude: ':(exclude).github/actions/comment-hygiene/** :(exclude)modules/comment-hygiene/**'`
to skip the action's own source and the module — exactly how medley excludes its
comment-hygiene tooling from its own scan.
