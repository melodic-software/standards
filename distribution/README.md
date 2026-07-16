# Exact materialization

This slice owns the standards files that must physically exist in another
repository and cannot be consumed through a native package, reference, or
platform control plane.

`sync-manifest.yml` is the desired-state record. `sync-manifest.sh` is its
deterministic interpreter. The reusable workflow in `ci-workflows` supplies
GitHub authentication and opens one reviewed reconciliation pull request per
target.

The production Bash entrypoint uses Mike Farah `yq` v4 and requires no Node
runtime. Standards authoring CI independently converts the YAML and checks the
Draft 2020-12 JSON Schema in `sync-manifest.schema.json` with pinned Node
dependencies. The Bash path retains equivalent structural checks plus the
repository path, Git-index, ownership, dependency-graph, target-identity, and
apply safety checks that JSON Schema cannot express.

The distribution [threat model](THREAT-MODEL.md) records trust boundaries,
fail-closed guarantees, residual risks, and security review triggers for the
reconciliation engine itself. The
[native-reference review credential](REVIEW-CREDENTIAL.md) classifies the
separate, read-only credential a private calling repo's review job uses to
mount `conventions/review` by native reference, and its republication
limits. The [governance process](governance-process.md) records the
copy-adoption back-link and drift-check requirement and the cross-doc
reconciliation step for normative-doc changes — all three outside this
manifest's automated reconciliation loop.

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

Every real sync derives the expected access set from the complete, unfiltered
manifest. Before any target-specific write token, checkout, materialization, or
pull-request mutation, it verifies the expected active organization App
installation is in selected-repository mode and requires two consecutive,
fully paginated snapshots to equal that set exactly. Missing, excess, malformed,
or changing access fails the whole run. The optional `targets` input limits
reconciliation only; it never narrows access attestation.

Adding, removing, transferring, or renaming a manifest target therefore
requires an organization owner to coordinate the App's selected access and
record the approval, actor and time, before/after repository sets, and the
successful attested sync. Managed bytes must wait for that authoritative sync;
they are never hand-copied around a failed access check.

## Runner-policy consumer handoff

The `runner-policy` component materializes one atomic runtime at
`.github/standards/runner-policy/` in exactly these enrolled private targets:

- `melodic-software/claude-code-plugins`
- `melodic-software/dotfiles`
- `melodic-software/github-iac`
- `melodic-software/medley`
- `melodic-software/provisioning`

It includes `runner-policy.mjs`, `policy.json`, both Draft 2020-12 policy schema
files, and the component-local npm manifest and lockfile. The component requires
`node-runtime`, so `.node-version` is part of each target's managed
materialization as well. The runtime loads both schemas directly; omitting them
would make the supposedly atomic payload fail on a clean consumer checkout.

Repository-specific adoption remains a separate consumer change. Each target
must add all of the following in the same integration PR:

1. A locally owned `.github/runner-policy.json` with correct visibility,
   enrollment, and exact job exceptions. A hosted-only consumer uses
   `selfHostedCi: false` and `exceptions: {}`; because selector routing is
   disabled, fixed approved hosted targets need no exception and the analyzer
   rejects every unconsumed entry as `exception-inventory-drift`.
2. A fixed `ubuntu-24.04` hosted CI job that runs
   `npm ci --prefix .github/standards/runner-policy`, then invokes
   `node .github/standards/runner-policy/runner-policy.mjs --root .` with
   `CI_REPOSITORY_VISIBILITY: ${{ github.event.repository.visibility }}`. In a
   private consumer with `selfHostedCi: true`, this fixed hosted job uses the
   `hosted-control-plane` exception; a hosted-only consumer does not. The
   analyzer consumes GitHub's default `GITHUB_REPOSITORY` environment variable
   as trusted owner evidence; `.github/runner-policy.json#repositoryOwner` is
   only inventory and a mismatch tripwire.
3. An npm Dependabot entry with
   `directory: /.github/standards/runner-policy` for the distributed lockfile.
4. Workflow routing and exception inventory that pass the gate at the reviewed
   selector/reusable-workflow SHA in the distributed `policy.json`.

Selector-dependent direct jobs and ordinary reusable callers use the recovery
contract: `if: ${{ !cancelled() }}` (safely conjoined with any existing
predicate) and `${{ needs.<selector>.outputs.runner || 'ubuntu-24.04' }}` as the
direct `runs-on` value or canonical `with.runner` input. The fallback never
reads `vars.CI_HOSTED_RUNNER`, because selector failure means that value was not
validated by the selector.

A repository-local reusable workflow may instead require its runner input with
no default. That zero-hosted-fallback form passes the raw selector output only
behind the exact successful self-hosted-route proof. The reserved
`ci-runner-selection-failed` literal is accepted solely for the narrowly shaped
scheduled rejection guard documented by the runner-policy component; it is not
a general workload runner or fallback.

The synchronizer deliberately does not invent those files: workflow shape,
exceptions, and dependency-update configuration are executable facts owned by
each consumer. A materialization PR is not an adoption completion signal until
its corresponding integration PR supplies this wiring and CI passes.

## Go-analysis consumer handoff

The `go-analysis` component materializes the root `.golangci.yml` in
`melodic-software/ci-runner`. The file is exact managed policy: consumers do not
change the enabled set, suppression rules, or config version downstream.

Analyzer execution remains a separate native workflow adoption. The consumer
calls the merged `ci-workflows` Go quality workflow by a full commit SHA, passes
the exact `.golangci.yml` path, runs native Linux and Windows analysis, and
includes its stable local gateway job in required `ci-status`. The workflow
owns golangci-lint v2.12.2 and govulncheck v1.6.0 installation and integrity
checks; this materialization component owns only analyzer policy bytes.

The `lefthook-dotnet` component has a similar explicit consumer value. A target
that selects it receives `.lefthook/dotnet.yml` and
`.lefthook/dotnet-format-staged.mjs`, while the consumer owns only
`.lefthook/dotnet-format.json`. That strict file contains `schemaVersion: 1` and
one repository-relative `.sln`, `.slnx`, or `.csproj` `workspace`. The complete
managed named job remains the sole owner of `run`, `glob`, and `fail_text`; the
workspace never enters its shell command. The wrapper rejects missing,
malformed, unknown-version, unknown-key, out-of-repository, and unsupported
workspace configurations before spawning `dotnet`. Implicit MSBuild workspace
discovery is not an accepted default.
