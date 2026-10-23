# Commit convention

The org commit-subject convention, as one file:
[`commit-convention.yml`](commit-convention.yml). The `commit-convention`
component in [`distribution/sync-manifest.yml`](../../distribution/sync-manifest.yml)
materializes it to `docs/conventions/source-control/commit-convention.yml` in
every sync target, which is the well-known path the guardrails resolver and
the source-control plugin read
([seam contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/commit-convention/README.md)).
A repository therefore needs no `## subject_pattern` section in its
`.claude/source-control.md`; when the tracked file is present, its keys win
over that section.

## What reads it

- The guardrails `commit-msg-convention` git hook, through
  `resolve-convention-pattern.sh`: a local commit whose subject does not match
  `subject_pattern` is rejected. The file counts only when it is git-tracked.
- The guardrails Claude Code guard and the source-control plugin's drafting,
  through the same resolver and the same path.

The CI pull-request title gate (the ci-workflows `check-contract` action) does
not read this file. It takes its types from its `types` input, whose default
is [`policy.json`](../pr-convention-policy/policy.json) `title.allowedTypes`.

## The value

`subject_pattern` is POSIX ERE: the twelve `title.allowedTypes`, an optional
scope (`requireScope: false`), an optional `!`, then a colon, a space and a description;
or a subject git writes itself (`Merge ...`, `Revert "..."`). The value is
single-quoted and contains no single quote, because the resolver strips one
quote pair and does no escape processing. `pr_title_pattern` defers to
`subject_pattern`.

## Changing it

Edit [`commit-convention.yml`](commit-convention.yml) and copy it byte for
byte to this repository's `docs/conventions/source-control/commit-convention.yml`;
standards is the manifest source, not a sync target, so that copy is what its
own hook reads. A type change also changes `policy.json` and the ci-workflows
`check-contract` `types` default, in that order.
[`commit-convention.test.sh`](commit-convention.test.sh) fails when the three
disagree, when the copy differs, when the resolver does not print the pattern
from a tracked file, or when the hook accepts or rejects the wrong subjects.

A repository that needs a different convention moves the component to
`locally-owned` in its manifest target block and tracks its own file at the
same path.

Rollback: remove the component from the targets and the manifest. The sync
never deletes a file, so each target then deletes its copy in a repository
pull request; until it does, the copy keeps enforcing.
