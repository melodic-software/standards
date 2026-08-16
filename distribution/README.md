# Exact materialization

This slice owns the standards files that must physically exist in another
repository and cannot be consumed through a native package, reference, or
platform control plane.

`sync-manifest.yml` is the desired-state record. `sync-manifest.sh` is its
deterministic interpreter. The reusable workflow in `ci-workflows` supplies
GitHub authentication and opens one reviewed reconciliation pull request per
target.

The production Bash entrypoint uses Mike Farah `yq` v4 and requires no Node
runtime. Standards authoring CI independently converts fixture YAML and checks
the Draft 2020-12 JSON Schema in `sync-manifest.schema.json` with pinned Node
dependencies (`validate-sync-manifest.mjs`). That schema is an overlapping
structural subset of the engine's rules: it expresses shape, naming, and
typing constraints the engine also enforces, but not Git-index state, tracked-file
contracts, path-safety beyond the schema, dependency closure, or apply-time
checks. Where both validators apply on a fixture manifest, the contract suite
in `sync-manifest.test.sh` requires them to agree; the Bash engine alone gates
`distribution/sync-manifest.yml` in CI (`sync-manifest.sh validate`). The Bash
path retains equivalent structural checks plus the repository path, Git-index,
ownership, dependency-graph, target-identity, and apply safety checks that JSON
Schema cannot express.

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

A target may also set `automerge: false` — policy-as-data read by the
`ci-workflows` reusable that opens sync PRs — to opt that repository out of
auto-merge arming. Omitting the key defaults to `true` (armed), so the fleet
default stays terse; only a deliberate opt-out needs an explicit entry.

This repository's own root files — currently just `README.md` — are neither
`managed` nor `locally-owned` here — those labels describe a *downstream*
copy's relationship to an upstream source. In `standards` itself a root file
is simply the canonical source: no manifest entry, because there is no
synchronization to record. The same holds for any root file `standards`
adds later, such as `AGENTS.md` or `CLAUDE.md`. Once a downstream target
gains a manifest component for a root file — for example a future
`REVIEW.md` or `AGENTS.md` component — that downstream copy is what carries
the `managed` label; this repository's own originals never carry an
ownership label themselves.

There are no layouts, per-target paths, transforms, patches, profiles, receipts,
or generated downstream metadata. A component that needs a different
destination or partial ownership is the wrong component boundary and must be
split first.

Native adoption remains authoritative where it naturally lives:

- package and `extends` references in consumer manifests;
- actions and reusable workflows in consumer workflow files — with the
  Claude review-lane callers as the recorded exception (see
  [Claude review-lane caller components](#claude-review-lane-caller-components));
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
| Opt out | Same manifest move as Customize — `locally-owned` is the sanctioned per-repository exclusion, recorded and reviewed here rather than fought out against the sync bot downstream. Once it lands, the consuming repository edits or deletes its copy in its own PR; the synchronizer never touches a `locally-owned` file. |
| Re-adopt | Move `locally-owned` to `managed`; reconciliation restores the canonical payload. |
| Retire | Remove upstream ownership first, then delete the obsolete downstream payload in a one-time PR. |
| Relocate | Change the destination and coordinate deletion of the old path in the downstream migration PR. |
| Reconcile | For a `locally-owned` target whose file predates and diverges from the canonical shape, a periodic check confirms the canonical minimum content is still present — not a byte diff. Drift opens a review; it is never auto-overwritten. |

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

### Plugin-catalog drift report

Each repository's checked-in `.claude/settings.json` is the source of truth
for the plugins its sessions load (cloud sessions install exactly what it
declares). This repository's own settings file doubles as the fleet baseline,
and [`check-plugin-baseline.sh`](check-plugin-baseline.sh) makes divergence
visible — report-only, never an edit, because a repo may diverge on purpose:

```sh
distribution/check-plugin-baseline.sh                  # every manifest target
distribution/check-plugin-baseline.sh owner/repo ...   # specific repositories
```

Fleet mode fetches each target's settings via `gh api`, so it reads private
repositories with the caller's own auth. To propagate a baseline change, edit
the diverging repos' `enabledPlugins` in ordinary per-repo pull requests —
the report tells you exactly which entries moved.

## Adopting a new repository

1. Inspect the repository's actual tools and distinguish shared policy from
   repository-specific policy.
2. Add only exact materializations to this manifest. Record a deliberate
   exception as `locally-owned` only when it clarifies an otherwise relevant
   component.
3. Add native packages, local adapters, workflow callers (other than the
   sync-managed
   [Claude review-lane callers](#claude-review-lane-caller-components)),
   permissions, and the CI gateway in the consumer repository where those
   executable facts belong.
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
`.github/standards/runner-policy/` in exactly these enrolled targets — the set
is an adoption list, not a visibility class, and `claude-code-plugins` is
public (see [`REVIEW-CREDENTIAL.md`](REVIEW-CREDENTIAL.md)):

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
   enrollment, and exact job exception and local-routing-grant inventory. A
   hosted-only consumer uses `selfHostedCi: false` and `exceptions: {}`;
   because selector routing is disabled, fixed approved hosted targets need no
   exception and the analyzer rejects every unconsumed entry as
   `exception-inventory-drift` (grants likewise fail as
   `local-routing-grant-drift`).
2. A CI job that runs
   `npm ci --prefix .github/standards/runner-policy`, then invokes
   `node .github/standards/runner-policy/runner-policy.mjs --root .` with
   `CI_REPOSITORY_VISIBILITY: ${{ github.event.repository.visibility }}`. A
   private consumer with `selfHostedCi: true` routes this job through the
   governed selector with the approved hosted fallback; a hosted-only consumer
   runs it as a fixed `ubuntu-24.04` hosted job with no exception. The
   analyzer consumes GitHub's default `GITHUB_REPOSITORY` environment variable
   as trusted owner evidence; `.github/runner-policy.json#repositoryOwner` is
   only inventory and a mismatch tripwire.
3. An npm Dependabot entry with
   `directory: /.github/standards/runner-policy` for the distributed lockfile.
4. Workflow routing, exception, and grant inventory that pass the gate at the
   reviewed selector/reusable-workflow SHA in the distributed `policy.json`.

Selector-dependent direct jobs and ordinary reusable callers use the recovery
contract: `if: ${{ !cancelled() }}` (safely conjoined with any existing
predicate) and `${{ needs.<selector>.outputs.runner || 'ubuntu-24.04' }}` as the
direct `runs-on` value or canonical `with.runner` input. The fallback never
reads `vars.CI_HOSTED_RUNNER`, because selector failure means that value was not
validated by the selector.

A repository-local reusable workflow may instead require its runner input with
no default. That zero-hosted-fallback form passes the raw selector output only
behind the exact successful self-hosted-route proof. The reserved
`ci-runner-selection-failed` marker step is accepted solely for the narrowly
shaped hosted rejection guard documented by the runner-policy component; it is
not a general workload runner or fallback. During migration the legacy unroutable
`runs-on: ci-runner-selection-failed` shape remains accepted.

The synchronizer deliberately does not invent those files: workflow shape,
exceptions, and dependency-update configuration are executable facts owned by
each consumer — the
[Claude review-lane callers](#claude-review-lane-caller-components) are the
one recorded exception to that workflow-shape rule. A materialization PR is
not an adoption completion signal until its corresponding integration PR
supplies this wiring and CI passes.

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

## Claude review-lane caller components

`claude-review-caller` and `claude-security-review-caller` materialize the
thin workflow callers for the `ci-workflows` reusable Claude review lanes at
`.github/workflows/claude-review.yml` and
`.github/workflows/claude-security-review.yml`. They are the recorded
exception to the rule that workflow callers stay consumer-owned: hand-written
lane callers empirically drifted — a missing `reopened` trigger in medley,
divergent `skip-actors` lists, and reusable-pin skew (v0.6.1 ↔ e295107) —
which is exactly the fleet-normalization problem managed materialization
exists to solve. The reusable workflows themselves remain native references
in `ci-workflows`; only the caller files are managed bytes.

What stays consumer-owned:

- `.github/claude-security-paths` — the security lane's pattern file naming
  the repo's security-sensitive surfaces, read by the reusable from the PR's
  base branch. It is repo-specific tuning, so it is deliberately not a
  managed file; an absent file fails open (every PR is security-reviewed).
  The manifest has no seed-once mechanism, so a new adopter commits its
  starter list in a repo-local PR alongside (or before) its caller
  materialization PR.
- The `CLAUDE_CODE_OAUTH_TOKEN` secret and the optional `CI_RUNNER_*`
  selector variables and observer key, per the runner-policy consumer
  handoff above.

The two callers deliberately carry different concurrency values (per-PR
cancel plus a repo-wide queue on the code-review caller; cancel disabled and
no queue on the security caller, whose check may be a required
execution-evidence context). The component sources record the rationale
inline — do not normalize the two.

Both components resolve the runner through the governed `select-runner`
indirection, and `runner-policy` admits that selector only for a private
self-hosted consumer — the ban consults neither `exceptions` nor
`localRoutingGrants`, so a PUBLIC target has no configuration escape and would
fail its own `runner-policy` lane (and with it `ci-status`) the moment the
caller synced in. These components are therefore private-only, which resolves
differently for each lane:

- `claude-review-caller` is `managed` for the four private targets that run
  the code-review lane (dotfiles, github-iac, medley, provisioning).
- `claude-security-review-caller` is `managed` for private adopters
  (`provisioning` first). Public repos running a security lane today —
  `claude-code-plugins` and `ci-workflows` — remain ineligible for the
  selector-routed shape.

`melodic-software/claude-code-plugins`, the org's one public caller target and
the only repo whose ruleset requires `security-review / security-review`, is
`locally-owned` for both components and keeps its hand-written hosted-only
callers that pass `runner: ubuntu-24.04` directly. Consequence to accept
knowingly: that repo stays outside this normalization and re-pins by hand at
each `ci-workflows` release.

Three tests in `components/runner-policy/runner-policy.test.mjs` hold the
constraint: a selector-routed caller component may not be `managed` for a
public target, every caller component must audit clean for a private
self-hosted consumer, and a selector-routed caller is expected to be rejected
outright on a public one.

Public/shared-shape removal trigger: moving the runner indirection inside the
`ci-workflows` reusable is necessary but not sufficient for one managed
component across both visibilities (#377). That path also needs a cross-repo
reusable routing kind in runner-policy, a deliberate narrowing of the blanket
public-target test for `components/claude-lanes/`, and either absorbing
claude-code-plugins' repo-owned `security-review-evidence` guard into the
reusable or accepting that caller stays `locally-owned`.

## Review-instructions reconciliation (medley)

`agent-orientation` and `review-instructions` are `locally-owned` in
`melodic-software/medley`, not `managed`: medley's own `REVIEW.md` and
`AGENTS.md` predate this manifest, are load-bearing for medley's own
`/quality-gate` automation (a severity vocabulary, a tracker-priority axis,
and a confidence axis this manifest does not model), and are cited from
dozens of files — a whole-file managed sync would clobber content the
`managed`/`locally-owned` split exists to protect.

The `Reconcile` lifecycle row above is what keeps this from silently
blinding medley to canonical drift: when `standards`' `REVIEW.md` or
`AGENTS.md` gains a criterion, medley's own copy is checked for the
equivalent content (not a byte match) and updated by a repository-specific
PR in medley, same as the initial reconciliation pattern
(`melodic-software/medley#1541`). This is a periodic self-review obligation, not an
automated reconciliation PR the synchronizer opens — `locally-owned` means
exactly that the synchronizer never reads, changes, or deletes the file.
