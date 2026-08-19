# Escape hatches

The sanctioned ways a consuming repository steps outside a synced default.
This document is the consumer-facing index; the [Lifecycle](README.md#lifecycle)
table in the distribution README records the same moves from the manifest's
perspective. Further exception surfaces (engine target filters, hook bypass
shapes, agent deny-rule reconciliation) are consolidated here by the
component-cleanup phase of the standards sync audit
(docs/topics/standards-sync-audit/).

## Opting a repository out of a managed component

Any file this manifest marks `managed` for a repository is replaced on the
next sync, so a local edit to such a file is silently lost. When a managed
copy is wrong, fix the cause upstream in `melodic-software/standards` and let
the sync carry the correction back — never patch the materialized copy
downstream.

To opt a repository out of a managed component, or to customize its copy,
propose a `melodic-software/standards` pull request moving the component from
`managed` to `locally-owned` for that repository in
[`distribution/sync-manifest.yml`](sync-manifest.yml). The synchronizer never
reads, changes, or deletes a `locally-owned` file, so after that change lands
the repository may edit or delete its copy in an ordinary local pull request.
The manifest PR is where the exception is recorded and reviewed — one visible
decision upstream instead of a fight against the sync bot downstream.
