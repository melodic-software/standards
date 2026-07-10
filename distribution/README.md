# Exact materialization

This slice owns the standards files that must physically exist in another
repository and cannot be consumed through a native package, reference, or
platform control plane.

`sync-manifest.yml` is the desired-state record. `sync-manifest.sh` is its
deterministic interpreter. The reusable workflow in `ci-workflows` supplies
GitHub authentication and opens one reviewed reconciliation pull request per
target.

## Ownership model

Each component has one or more fixed source-to-destination mappings. All files
in a component move together.

- `managed` means this repository owns the exact downstream bytes and Git mode.
- `locally-owned` records a deliberate repository-specific implementation or
  opt-out. The synchronizer never reads, changes, or deletes it.
- Omission means the component is irrelevant or has not been classified for
  that target.

There are no layouts, per-target paths, transforms, patches, profiles, receipts,
or generated downstream metadata. A component that needs a different
destination or partial ownership is the wrong component boundary and must be
split first.

Native adoption remains authoritative where it naturally lives:

- package and `extends` references in consumer manifests;
- actions and reusable workflows in consumer workflow files;
- repository governance in the relevant `github-iac` repository;
- repository reachability and App access in live GitHub state.

Those surfaces are joined only for an on-demand audit; no second inventory is
committed here.

## Lifecycle

| Change | Required order |
| --- | --- |
| Adopt | Add the component to `managed`, merge upstream, then review the generated materialization PR. |
| Update | Change the canonical source; reconciliation proposes the complete target delta. |
| Customize | Move `managed` to `locally-owned` upstream before editing downstream. The existing file is preserved. |
| Re-adopt | Move `locally-owned` to `managed`; reconciliation restores the canonical payload. |
| Retire | Remove upstream ownership first, then delete the obsolete downstream payload in a one-time PR. |
| Relocate | Change the destination and coordinate deletion of the old path in the downstream migration PR. |

Deselection never implies deletion. Without a downstream receipt, deletion and
ownership transfer are indistinguishable; guessing would eventually erase a
legitimate local file.

## Commands

All commands validate the complete manifest before doing any work.

```sh
distribution/sync-manifest.sh validate \
  --source-root . \
  --manifest distribution/sync-manifest.yml

distribution/sync-manifest.sh plan \
  --source-root . \
  --manifest distribution/sync-manifest.yml \
  --targets melodic-software/ci-workflows
```

`matrix` emits the JSON consumed by the reusable workflow. Source files must
match their indexed Git blobs exactly. `apply` operates on one clean, disposable
target checkout, validates every destination before the first write, and
reconciles bytes plus executable mode. It never commits, pushes, merges, or
deletes files.

## Adopting a new repository

1. Inspect the repository's actual tools and distinguish shared policy from
   repository-specific policy.
2. Add only exact materializations to this manifest. Record a deliberate
   exception as `locally-owned` only when it clarifies an otherwise relevant
   component.
3. Add native packages, local adapters, workflow callers, permissions, and the
   CI gateway in the consumer repository where those executable facts belong.
4. Review the generated materialization PR and verify CI.
5. Enable required CI in `github-iac` only after the gateway exists and passes.

The GitHub App installation is an authorization boundary, not an adoption
registry. A new target must also be granted App access before a real sync can
succeed.
