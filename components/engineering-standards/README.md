# Engineering standards

The team layer of the standards contract: eight `conventions/engineering/`
files, plus the index in [`standards-index.md`](standards-index.md), synced into
`docs/standards/` of each target. Planning and review skills in
`melodic-software/claude-code-plugins` resolve that directory through the
contract (`docs/conventions/standards/` there, version 1.0.2) and load only the
files whose `Applies when` row matches the task, so work is built to the same
criteria it is reviewed against.

The eight files stay in `conventions/engineering/`, their canonical location;
this directory holds only the index and this record. The file list is the
`engineering-standards` entry in
[`sync-manifest.yml`](../../distribution/sync-manifest.yml), and its targets are
the ones that list it under `managed`.

## Admission evidence

Per [component lifecycle](../../docs/component-lifecycle.md#admission-evidence).

- **Live consumer**: the `planning` and `review` plugin skills in
  `claude-code-plugins` (their `setup` skills and the binding copy
  `reference/standards-contract.md`) read `<standards_dir>/README.md`, default
  `docs/standards/`. The targets are every repository that takes
  `pr-body-contract-rule`; none has `docs/standards/` on its default branch,
  so the sync adds the directory and overwrites nothing.
- **Delivery boundary**: exact materialization through this repository. The
  contract requires the files to sit in the consuming repository, and the
  sync is the one channel that writes text files there from a single source.
  A link to this repository instead would leave the contract's team layer
  empty, and skills do not fetch remote standards.
- **Alternatives and overlap**: a per-repository copy would drift with no
  owner. `code-review-rules` and `REVIEW.md` carry review criteria; this
  component carries working conventions and links into them rather than
  restating them. `managed-files-guard` lists the eight destinations, so a
  local edit to a synced file is caught as drift instead of competing with the
  source.
- **Operational fit**: `sync-manifest.sh plan` for a target lists exactly the
  eight files; the payload is markdown with absolute links, checked by lychee
  offline with no errors. No runtime cost in the target: nothing executes, and
  dotfiles' `.chezmoiignore` already ignores `docs`, so nothing renders into a
  home directory. Failure behavior is the sync engine's: a target that cannot
  take the files fails its sync run without touching other targets.
- **Upstream health**: no third-party dependency.
- **Legal and security fit**: first-party prose under the repository's
  license; no code, credential or network boundary beyond the existing
  standards-sync App.
- **Update path**: no dependency root. A change to a synced file reaches the
  targets on the next sync run; a change to the index's `standards-contract`
  version follows the contract's `CHANGELOG.md` in `claude-code-plugins`.
- **Verification**: `distribution/sync-manifest.test.sh` and
  `sync-manifest.sh validate` cover the manifest entry, and
  `managed-files-guard.test.sh` covers the guarded destinations.

## Ownership

- **Owner**: the `standards` maintainers.
- **Acceptance**: each target's sync pull request adds the eight files under
  `docs/standards/`, and a planning or review skill run there names a
  `docs/standards/` file from the index.
- **Customization**: a target relocates the team layer through
  `.claude/standards.yaml` `standards_dir`, or moves the component to
  `locally-owned` in the manifest. The index is `managed` because the engine
  has no seed-once mode.
- **Rollback**: remove the component from the targets' `managed` lists and
  delete its manifest entry and `managed-files-guard` paths. The files already
  synced stay as ordinary repository docs until each target deletes them.
