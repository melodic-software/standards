# Research — eol-renormalize

Cross-cutting repo-hygiene gate: detect index-level line-ending drift. Lifted
from `medley`'s `eol-renormalize` job in `editorconfig-ci.yml` (a blocking
gateway check via the `editorconfig` slot in `ci-status.yml`).

## Why it exists

With `.gitattributes` `* text=auto`, git's clean filter normalizes every text
blob to LF-in-repo on a normal `git add`, so commit-content EOL corruption is
structurally impossible through the happy path. The one gap it cannot self-heal:
a blob committed **before** its `eol` rule existed, or staged via a bypassed
hook — stale EOL then persists in the index until renormalized. Working-tree
fixers (editor, pre-commit) cannot see what already lives in history; this gate
can.

## Approach (authoritative)

`git add --renormalize <paths>` — per the official docs, "Apply the 'clean'
process freshly to all tracked files to forcibly add them again to the index …
useful after changing `core.autocrlf` configuration or the `text` attribute in
order to correct files added with wrong CRLF/LF line endings" (verified at
<https://git-scm.com/docs/git-add>, 2026-06-23). A resulting staged diff is
exactly the stale-index drift.

The gate is therefore:

```sh
git add --renormalize -- <paths>
git diff --cached --quiet   # clean ⇒ index already matches EOL policy
git reset --quiet           # read-only: restore the index either way
```

A non-empty `git diff --cached` lists the drifted files and fails the gate with
the local fix (`git add --renormalize . && git commit`).

## Tool / pinning

**Pure git — no external binary** to version-pin or checksum.

## Config

**Config-light** — driven entirely by the **caller's own `.gitattributes`**,
which is a repo-local file every repo already owns, **not** a `standards`
module. The only optional input is `paths` (default `.`), an open-closed string
default (D4).

## Build decision

Inline `run:` in `action.yml` rather than a bundled script: the whole gate is a
three-command git sequence, short enough that an inline block reads clearer than
a separate file. (exec-bit and machine-specific-paths bundle their scripts
because their logic is long and intricate; this one is not.)

## Dogfood note

A clean checkout has `index == HEAD`; `--renormalize` only re-stages tracked
files, so on an already-normalized repo the index stays equal to HEAD and the
gate passes. ci-workflows' `.gitattributes` is `* text=auto eol=lf`, and all
tracked blobs are already LF, so the dogfood is clean.
