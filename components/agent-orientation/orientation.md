# AGENTS.md

## Synced standards are overwritten, not edited here

This repository's lint, formatting, and repository-hygiene configuration is
synchronized from `melodic-software/standards`. Any file that standards marks
as `managed` for this repository — including this file — is replaced on the
next sync, so a local edit to such a file is silently lost. When one of them
is wrong, fix the cause upstream in `melodic-software/standards` and let the
sync carry the correction back — never patch the materialized copy here.

To opt this repository out of a managed component, or to customize its copy,
propose a `melodic-software/standards` pull request moving the component from
`managed` to `locally-owned` for this repository in
`distribution/sync-manifest.yml`. The synchronizer never reads, changes, or
deletes a `locally-owned` file, so after that change lands this repository may
edit or delete its copy in an ordinary local pull request.

## New shebang files land in the index as non-executable

Git's executable-bit detection depends on the filesystem reporting the
permission accurately; where it can't (Windows, most commonly),
`core.filemode` is `false` and a newly staged file — including a new shebang
script — gets mode `100644` regardless of its intended use. The exec-bit gate
rejects any tracked file starting with `#!` that is staged `100644`, and that
failure only surfaces in CI, one round trip after the commit that caused it.

Stage the bit explicitly before committing a new shebang file:
`git update-index --chmod=+x -- <path>`.
