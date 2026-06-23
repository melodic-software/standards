# comment-hygiene module

Detection policy for the **comment-hygiene** gate: code comments must not carry
deferred-work markers (`TODO`/`FIXME`/`HACK`/`XXX`) or issue-tracker references
(`issue`/`fixes`/`closes #N`, `PR #N`). Outstanding work belongs in the issue
tracker, where it stays visible, not in a comment that rots silently in the
source.

## Why the split

This module is the **policy** (what comment content is banned) — the one piece
that varies per org/repo and is therefore configuration. The **execution** (the
full-tree scan driver) lives in the
[`comment-hygiene` composite action](https://github.com/melodic-software/ci-workflows)
and sources this library. Keeping them apart means a repo can tune the policy
without forking the scanner.

## Contents

- `comment-hygiene-patterns.sh` — a pure-bash library (sourced, never executed)
  exposing `chp::scan_text <content>`, which emits `lineno:kind:detail` per
  violation on comment lines and exits non-zero when any are found. POSIX ERE
  only, case-insensitive marker matching, and it restores `nocasematch` so
  sourcing it never leaks shell state.

This is the **org-default** policy. It is intentionally generic — the markers
plus generic tracker references — and carries no repo-specific carve-outs; a
consuming repo with stricter or looser needs vendors and edits its own copy.

## Adopt in a repo

Reference the `comment-hygiene` composite action and point it at this library:

```yaml
- uses: melodic-software/ci-workflows/.github/actions/comment-hygiene@<sha>
  with:
    patterns-file: modules/comment-hygiene/comment-hygiene-patterns.sh
```

`patterns-file` defaults to this path, so dropping the library at
`modules/comment-hygiene/comment-hygiene-patterns.sh` in the consuming repo needs
no override. Scope the scan with the action's `extensions` and `exclude` inputs.

## Test

`fixtures/comment-hygiene/{good,bad}` exercise the policy; `comment-hygiene.test.sh`
runs the library against them on the shell harness. CI additionally self-scans the
whole repo via the action.
