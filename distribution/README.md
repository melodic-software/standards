# Exact materialization

This slice owns the standards files that must physically exist in another
repository and cannot be consumed through a native package, reference, or
platform control plane.

`sync-manifest.yml` is the desired-state record. `sync-manifest.mjs` is its
deterministic interpreter, a Node engine with one exact-locked production
dependency (the `yaml` parser), and `sync-manifest.sh` is the stable
exec-wrapper entrypoint every caller invokes. The reusable workflow in
`ci-workflows` supplies GitHub authentication and opens one reviewed
reconciliation pull request per target.

Standards authoring CI independently converts fixture YAML with `yq` and
checks the Draft 2020-12 JSON Schema in `sync-manifest.schema.json` with
pinned Node dependencies (`validate-sync-manifest.mjs`). This is a genuinely
independent parse: yq's Go parser reads the schema-path input while the
engine's `yaml` parser reads the engine-path input. That schema is an
overlapping structural subset of the engine's rules: it expresses shape,
naming, and typing constraints the engine also enforces, but not Git-index
state, tracked-file contracts, path-safety beyond the schema, dependency
closure, or apply-time checks. Where both validators apply on a fixture
manifest, the contract suite in `sync-manifest.test.sh` requires them to
agree; the engine alone gates `distribution/sync-manifest.yml` in CI
(`sync-manifest.sh validate`). The engine retains equivalent structural
checks plus the repository path, Git-index, ownership, dependency-graph,
target-identity, and apply safety checks that JSON Schema cannot express.

The distribution [threat model](THREAT-MODEL.md) records trust boundaries,
fail-closed guarantees, residual risks, and security review triggers for the
reconciliation engine itself. The
[native-reference review credential](REVIEW-CREDENTIAL.md) classifies the
separate, read-only credential a private calling repo's review job uses to
mount `conventions/review` by native reference, and its republication
limits. The [governance process](governance-process.md) records the
copy-adoption back-link and drift-check requirement and the cross-doc
reconciliation step for normative-doc changes, all three outside this
manifest's automated reconciliation loop.

## Ownership model

Each component has one or more fixed source-to-destination mappings. All files
in a component move together.

- `managed` means this repository owns the exact downstream bytes and Git mode.
- `locally-owned` records a deliberate repository-specific implementation or
  opt-out. The synchronizer never reads, changes, or deletes it.
- Omission means the component is irrelevant or has not been classified for
  that target.

A target may also set `automerge: false` to opt that repository out of
auto-merge arming; the key is policy-as-data read by the `ci-workflows`
reusable that opens sync PRs. Omitting the key defaults to `true` (armed), so the fleet
default stays terse; only a deliberate opt-out needs an explicit entry.

This repository's own root files (`README.md`, `REVIEW.md`, `AGENTS.md`,
`CLAUDE.md`) are neither `managed` nor `locally-owned` here: those labels
describe a *downstream* copy's relationship to an upstream source. In
`standards` itself a file is simply the canonical source: no ownership label,
because there is no synchronization to record. Note the canonical source of a
component is not always the same-named root file: `review-instructions`
exports root `REVIEW.md`, while a component may equally export a file that
lives only under `components/` (the root `AGENTS.md` and `CLAUDE.md` here back
no component: `CLAUDE.md` is an empty placeholder, and `AGENTS.md` holds only
this repository's own `## Code Review Rules` section, whose shape
[`components/code-review-rules/`](../components/code-review-rules/README.md)
defines and checks rather than syncs). Wherever the source lives, the
downstream copy is what carries the `managed` label; this repository's own
originals never carry an ownership label themselves.

There are no layouts, per-target paths, transforms, patches, profiles, receipts,
or generated downstream metadata. A component that needs a different
destination or partial ownership is the wrong component boundary and must be
split first. Per-target Claude Code `enabledPlugins` follows that rule:
each consumer has its own exact source file under
`components/claude-settings/targets/<repo>/settings.json` (first consumer:
github-iac via `claude-settings-github-iac`). Shared marketplace registration
and the SessionStart bootstrap hook are asserted against
`components/claude-settings/base/settings.json` by
[`check-claude-settings-targets.sh`](check-claude-settings-targets.sh):
authoring-time conformance, not an apply-time merge. Apply copies the
target file byte-exact. `.claude/settings.local.json` and
managed-settings-only keys (`strictKnownMarketplaces`) stay repo-owned.

Native adoption remains authoritative where it naturally lives:

- package and `extends` references in consumer manifests;
- actions and reusable workflows in consumer workflow files, with the
  Claude review-lane callers and the managed-files-guard caller as the
  recorded exceptions (see
  [Claude review-lane caller components](#claude-review-lane-caller-components)
  and [managed-files-guard caller component](#managed-files-guard-caller-component));
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
| Opt out | Same manifest move as Customize. `locally-owned` is the sanctioned per-repository exclusion, recorded and reviewed here rather than fought out against the sync bot downstream. Once it lands, the consuming repository edits or deletes its copy in its own PR; the synchronizer never touches a `locally-owned` file. |
| Re-adopt | Move `locally-owned` to `managed`; reconciliation restores the canonical payload. |
| Retire | Remove upstream ownership first, then delete the obsolete downstream payload in a one-time PR. |
| Relocate | Change the destination and coordinate deletion of the old path in the downstream migration PR. |
| Reconcile | For a `locally-owned` target whose file predates and diverges from the canonical shape, a periodic check confirms the canonical minimum content is still present, not a byte diff. Drift opens a review; it is never auto-overwritten. |

The consumer-facing index of these moves and the other sanctioned exception
surfaces lives in [ESCAPE-HATCHES.md](ESCAPE-HATCHES.md).

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
deletes files. The single-target commands (`mappings`, `dest-paths`, `apply`)
take `--target OWNER/REPO`, and `apply` additionally takes `--target-root DIR`
for the disposable checkout. The consumer-facing summary of every target
filter lives in [ESCAPE-HATCHES.md](ESCAPE-HATCHES.md).

### Cloud plugin baseline

Every cloud snapshot installs each plugin in the melodic-software marketplace
catalog whose entry leaves `defaultEnabled` unset or sets it `true` (see the
[cloud-environment component](../components/cloud-environment/README.md#plugin-install)).
Each repository's checked-in `.claude/settings.json` carries only its deltas
from that set: `false` to opt out of a plugin, `true` to opt in to an
off-by-default one. Cloud sessions install the catalog-derived list, then the
repo file's `true` entries. `cloud-bootstrap.sh` also prints an inventory line
naming catalog plugins that neither source enables, reading the marketplace
clone already on disk.

To change a materialized target's deltas, edit that repo's file under
`components/claude-settings/targets/` in this repository; sync delivers exact
bytes. Targets not yet materialized still use ordinary per-repo pull requests.

## Adopting a new repository

1. Inspect the repository's actual tools and distinguish shared policy from
   repository-specific policy.
2. Add only exact materializations to this manifest. Record a deliberate
   exception as `locally-owned` only when it clarifies an otherwise relevant
   component.
3. Add native packages, local adapters, workflow callers (other than the
   sync-managed
   [Claude review-lane callers](#claude-review-lane-caller-components) and
   [managed-files-guard caller](#managed-files-guard-caller-component)),
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
`.github/standards/runner-policy/` in exactly these enrolled targets, an
adoption list rather than a visibility class; note `claude-code-plugins` is
public (see [`REVIEW-CREDENTIAL.md`](REVIEW-CREDENTIAL.md)):

- `melodic-software/claude-code-account-rotation`
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
   fixed approved hosted targets need no exception and the analyzer rejects
   every unconsumed entry as
   `exception-inventory-drift` (grants likewise fail as
   `local-routing-grant-drift`).
2. A CI job that runs
   `npm ci --prefix .github/standards/runner-policy`, then invokes
   `node .github/standards/runner-policy/runner-policy.mjs --root .` with
   `CI_REPOSITORY_VISIBILITY: ${{ github.event.repository.visibility }}`. A
   private consumer with `selfHostedCi: true` names the governed fleet label
   `melodic-ubuntu-24.04-x64` directly, which the analyzer admits under its
   `managed-literal` routing kind; a hosted-only consumer runs it as a fixed
   `ubuntu-24.04` hosted job with no exception. The
   analyzer consumes GitHub's default `GITHUB_REPOSITORY` environment variable
   as trusted owner evidence; `.github/runner-policy.json#repositoryOwner` is
   only inventory and a mismatch tripwire.
3. Workflow routing, exception, and grant inventory that pass the gate at the
   reviewed reusable-workflow SHA in the distributed `policy.json`.
   Do not add a consumer npm Dependabot entry for
   `/.github/standards/runner-policy`: that lockfile is byte-exact
   sync-managed, so a downstream bump is drift the next sync reverts.
   Alerts still report the nested lockfile without a consumer entry.

**The selector recovery contract is retired.** ci-perf Phase 7 deleted the
`select-runner` reusable workflow (ci-workflows#569, merged as
`541ee4e90d12d77a90a3ddd72a3af9bc78634ea7`, released as v0.23.0) and
standards#556 (merged as `771a796628f325c3c418c7b397d09fb7211e2972`) removed its
grammar from this component, taking `schemaVersion` from 3 to 4. No consumer
writes a `needs.<selector>.outputs.runner` fallback expression any more, and
nothing reads `vars.CI_HOSTED_RUNNER`. github-iac's Phase 7 step 5 apply
(2026-09-08) deleted that organization variable and every other variable the
selector consumed. The
`ci-runner-selection-failed` marker is not a shape a consumer may write either,
though it survives in `policy.json` and `policy.schema.json` as a
`failureSentinelMarker` the analyzer validates stays outside every hosted and
managed runner label set; a job naming it as a runner is refused.

A direct job or a reusable caller now names its runner as a literal. A private
enrolled consumer names `melodic-ubuntu-24.04-x64` as the direct `runs-on` value
or the canonical `with.runner` input, and the analyzer admits it under the
`managed-literal` routing kind; a public or hosted-only consumer names an
approved hosted label such as `ubuntu-24.04`. A job that needs hosted capacity
inside an enrolled private repository declares an entry under `exceptions` in
that repository's `.github/runner-policy.json`, keyed `<workflow path>#<jobId>`
and carrying a `reason` drawn from `policy.json`'s closed `hostedExceptionReasons`
set plus a free-text `justification`; `hosted-exception-required` is the finding
the analyzer raises when that entry is missing, not a key a consumer writes. The
key carries the literal `.github/workflows/` prefix, as in
`.github/workflows/ci.yml#windows`, and a wrong `reason` fails with the full
valid set printed in the analyzer's own error. The decision is recorded in
melodic-software/github-iac#466, which adds
`docs/adr/0014-fleet-first-ci-for-private-repositories.md`.

The synchronizer deliberately does not invent those files: workflow shape,
exceptions, and dependency-update configuration are executable facts owned by
each consumer. The
[Claude review-lane callers](#claude-review-lane-caller-components) and the
[managed-files-guard caller](#managed-files-guard-caller-component) are the
two recorded exceptions to that workflow-shape rule. A materialization PR is
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
`.github/workflows/pr-review.yml` and
`.github/workflows/pr-review-security.yml`. They are the recorded
exception to the rule that workflow callers stay consumer-owned. Hand-written
lane callers empirically drifted: a missing `reopened` trigger in medley,
divergent `skip-actors` lists, and reusable-pin skew (v0.6.1 ↔ e295107).
That is exactly the fleet-normalization problem managed materialization
exists to solve. The reusable workflows themselves remain native references
in `ci-workflows`; only the caller files are managed bytes.

What stays consumer-owned:

- The `CLAUDE_CODE_OAUTH_TOKEN` secret and the observer key, per the
  runner-policy consumer handoff above. The `CI_RUNNER_*` selector variables
  are gone: the selector that read them was deleted (ci-workflows#569), and
  github-iac's Phase 7 step 5 apply (2026-09-08) deleted the variables and
  their Pulumi declarations. `CI_RUNNER_OBSERVER_CLIENT_ID` matches that glob
  but was never one of them; it is the observer key named above and it stays.

The security lane has no path gating from ci-workflows v0.29.0: it reviews every
non-draft same-repository PR whose actor is not a bot, and a target's `.github/claude-security-paths` file is
no longer read. The manifest never managed that file.

The two callers deliberately carry different concurrency values (per-PR
cancel on the code-review caller; cancel disabled and
no queue on the security caller, whose check may be a required
execution-evidence context). The component sources record the rationale
inline. Do not normalize the two.

Both components name the governed review-tier fleet label
`melodic-review-ubuntu-24.04-x64` directly (`claude-review.yml` and
`claude-security-review.yml`), and `runner-policy` admits that literal, like
every entry in `approvedManagedRunnerLabels`, only for a private self-hosted
consumer. The ban consults neither `exceptions` nor
`localRoutingGrants`, so a PUBLIC target has no configuration escape and would
fail its own `runner-policy` lane (and with it `ci-status`) the moment the
caller synced in. These components are therefore private-only, which resolves
differently for each lane:

- Both components are `managed` for the private targets claude-code-proxy,
  dotfiles, github-iac, medley and provisioning, so every PR there gets both
  advisory lanes. Public repos, `claude-code-plugins` and `ci-workflows`
  among them, remain ineligible for the fleet-routed shape.

Public targets take a hosted pair instead, as an interim (#622):
`claude-review-hosted-caller` and `claude-security-review-hosted-caller`,
sourced from `components/claude-lanes-hosted/` and materialized at
`.github/workflows/pr-review-hosted.yml` and
`.github/workflows/pr-review-security-hosted.yml`. Each file equals its
fleet sibling except for comments, `runner: ubuntu-24.04` and the workflow
`name:`, which equals each file's stem; the job ids match, so the check
contexts do too. The destinations differ because
a destination has one owning component. They are `managed` for agent-plugins,
ci-runner, claude-code-account-rotation, claude-code-plugins, codex-plugins
and cursor-plugins.
`.github` stays exempt (near-zero PR traffic).

- On a public repository the lanes review only pull requests from
  same-repository branches. Fork and Dependabot pull requests get no secrets,
  so they get no review.
- The sync never deletes a file. A target that moves between the hosted and
  fleet variants must delete the old caller in a repo-local pull request, or
  both run.
- Removal trigger: the one-shape work below landing, after which the hosted
  pair retires.

Three tests in `components/runner-policy/runner-policy.test.mjs` hold the
constraint, now stated over the fleet literal rather than the retired selector:
"fleet-routed claude lane callers are not managed for a public sync target",
"claude lane caller components pass runner policy for a private self-hosted
consumer", and "a fleet-routed claude lane caller is rejected outright on a
public consumer". Three more hold the hosted pair: it equals its fleet sibling
except for comments, `runner` and the `-hosted` name, every target managing it is public and
audits clean, and no target manages both variants of one lane.

Public/shared-shape removal trigger: moving the runner indirection inside the
`ci-workflows` reusable is necessary but not sufficient for one managed
component across both visibilities (#377). That path also needs a cross-repo
reusable routing kind in runner-policy and a deliberate narrowing of the blanket
public-target test for `components/claude-lanes/`.

## managed-files-guard caller component

Two components materialize a thin caller for the `ci-workflows`
`check-managed-files` composite action: `managed-files-guard-caller` at
`.github/workflows/pr-check-managed-files-hosted.yml` (hosted) and
`managed-files-guard-fleet-caller` at
`.github/workflows/pr-check-managed-files.yml` (fleet-routed). The action
fails a consumer pull
request that hand-edits one of that repository's managed destinations, which
is the signal ADR-0007 assigned to a downstream edit of a managed file. It is
the second recorded exception to the consumer-owned-caller rule, on the same
grounds as the first: the guard is a fleet signal only if every target runs
the same caller at the same pin.

Both call `.github/actions/check-managed-files` at the same pin. The two files
differ only in `runs-on`, comments and the workflow `name:`, which equals each
destination stem (`pr-check-managed-files-hosted` and
`pr-check-managed-files`). They share the job id and job name
`pr-check-managed-files`, so the check context is `pr-check-managed-files`
on every target, hosted or fleet-routed. The hosted caller
runs on `ubuntu-24.04` and is `managed` for the public targets. The
fleet-routed caller runs on `melodic-ubuntu-24.04-x64` and is `managed` for
the fleet-enrolled private targets (`claude-code-proxy`, `dotfiles`,
`github-iac`, `medley`, `provisioning`), where runner-policy requires the
fleet literal for every read-only job. claude-code-proxy is fleet-enrolled in
github-iac and its `ci.yml` runs on the fleet label, though it has no
`.github/runner-policy.json`. No target manages both.
`ci-workflows` is `locally-owned`: it hosts the action and
already runs the guard from its own tree. The check is advisory (not in any
`ci-status`) during its soak, and the caller passes `standards-ref: main`
until the soak completes. Rationale, pins, the advance path through the
`claude-lanes-repin` cascade, and the promotion record live in
[`components/managed-files-guard/README.md`](../components/managed-files-guard/README.md).

## Review-instructions reconciliation (medley)

`review-instructions` is `locally-owned` in `melodic-software/medley`, not
`managed`: medley's own `REVIEW.md` predates this manifest, is load-bearing
for medley's own `/quality-gate` automation (a severity vocabulary, a
tracker-priority axis, and a confidence axis this manifest does not model),
and is cited from dozens of files. A whole-file managed sync would clobber
content the `managed`/`locally-owned` split exists to protect. (Medley's
bespoke `AGENTS.md` enjoys the same protection simply by not being any
component's destination: the former agent-orientation component was retired
by the standards sync audit.)

The `Reconcile` lifecycle row above is what keeps this from silently
blinding medley to canonical drift: when the canonical `REVIEW.md` gains a
criterion, medley's own copy is checked for the equivalent content (not a
byte match) and updated by a repository-specific PR in medley, same as the
initial reconciliation pattern (`melodic-software/medley#1541`). This is a
periodic self-review obligation, not an automated reconciliation PR the
synchronizer opens: `locally-owned` means exactly that the synchronizer
never reads, changes, or deletes the file.
