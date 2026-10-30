# GitHub Actions runner policy

This module is the enforceable contract for local GitHub Actions routing. It
parses workflow YAML; it does not use text matching to infer job structure.

In this source repository, run it from the repository root with explicit local
repository identity evidence:

```sh
GITHUB_REPOSITORY=melodic-software/standards \
  node components/runner-policy/runner-policy.mjs --root .
```

PowerShell equivalent:

```powershell
$env:GITHUB_REPOSITORY = "melodic-software/standards"
node components/runner-policy/runner-policy.mjs --root .
```

The distributed component lives at `.github/standards/runner-policy/` and owns
its own `package.json` and lockfile with exact `ajv@8.20.0` and `yaml@2.9.0`
runtime pins. `policy.schema.json` (central policy, `schemaVersion` 4) and
`repository-policy.schema.json` are the
Draft 2020-12 structural authorities. Ajv compiles them in strict mode; the
runtime retains only cross-record semantics and workflow/path checks that JSON
Schema cannot express.

The security boundaries, fail-closed behavior, and required review triggers are
documented in the component [threat model](THREAT-MODEL.md).

Consumers install and invoke that dependency root directly, supplying their own
`owner/repository` identity for local analysis:

```sh
npm ci --prefix .github/standards/runner-policy
GITHUB_REPOSITORY=owner/repository \
  node .github/standards/runner-policy/runner-policy.mjs --root .
```

In a hosted-only repository the policy gate stays on an explicit
GitHub-hosted image so the enforcement path neither depends on nor exercises
any self-hosted fleet:

```yaml
runner-policy:
  runs-on: ubuntu-24.04
  permissions:
    contents: read
  steps:
    - uses: actions/checkout@<REVIEWED_40_CHARACTER_SHA>
      with:
        persist-credentials: false
    - uses: actions/setup-node@<REVIEWED_40_CHARACTER_SHA>
      with:
        node-version-file: .node-version
        cache: npm
        cache-dependency-path: .github/standards/runner-policy/package-lock.json
    - run: npm ci --prefix .github/standards/runner-policy
    - run: node .github/standards/runner-policy/runner-policy.mjs --root .
      env:
        CI_REPOSITORY_VISIBILITY: ${{ github.event.repository.visibility }}
```

In a private repository with `selfHostedCi: true`, the gate job instead names a
label from `approvedManagedRunnerLabels` like any other eligible read-only job.
No dedicated category pins read-only work to hosted infrastructure: the remaining reasons
describe structural constraints (Windows, containers, Docker socket access),
and while the analyzer consumes any allowlisted reason for an eligible
read-only fixed-hosted job without validating that constraint, declaring a
structural reason the job does not exercise is a review-time inventory
defect, not an admitted route. A hosted-only repository sets
`selfHostedCi: false` and keeps `exceptions` empty: local routing is disabled,
fixed approved hosted targets need no exception, and any unconsumed exception
fails as `exception-inventory-drift`. macOS labels are public-only: a private
repository that names one in `runs-on`, a matrix or a reusable `with:` value
gets `private-macos-runner`, whatever its `selfHostedCi` or exceptions, since
macOS minutes bill on private repositories. Set `CI_REPOSITORY_VISIBILITY` from the
event as shown so checked-in inventory cannot claim that a public repository is
private. GitHub Actions supplies the default `GITHUB_REPOSITORY` environment
variable independently of the checked-out repository, so the owner-mismatch
tripwire reads identity that no workflow-controlled input can forge.

Consumers must not add an npm Dependabot entry for
`/.github/standards/runner-policy`. That lockfile is byte-exact sync-managed
from `/components/runner-policy`; a downstream version bump is drift the next
sync reverts (and can silently downgrade). Coverage rides the source
repository's `/components/runner-policy` Dependabot entry plus standards-sync.
Dependabot directory entries drive version updates only; security alerts still
report the nested lockfile without a consumer entry.

Each adopting repository carries `.github/runner-policy.json`:

```json
{
  "schemaVersion": 1,
  "repositoryOwner": "melodic-software",
  "visibility": "private",
  "selfHostedCi": true,
  "exceptions": {
    ".github/workflows/ci.yml#windows": {
      "reason": "windows",
      "justification": "The Linux x64 Docker fleet cannot execute Windows Pester."
    }
  }
}
```

`repositoryOwner`, `visibility`, and `selfHostedCi` are governed inventory, not
runtime switches. `repositoryOwner` is inventory and a mismatch tripwire only;
it authorizes nothing. When it and the externally supplied `GITHUB_REPOSITORY`
context are both present, their owners must match or analysis fails closed.
Owner names are lowercase GitHub logins.

## Naming the managed fleet label directly

An enrolled private repository reaches the fleet exactly one way: write one of
the labels in `approvedManagedRunnerLabels` as a plain literal, either directly
in `runs-on:` or as the `runner` input of a reviewed reusable call. The analyzer
classifies that target as `managed-literal`. The
`localRoutingGrants` inventory admits a write-capable token on it, the
`allowedCallerPermissions` waiver admits a reviewed reusable call whose
`runner` input carries the label, and the explicit-read-only floor applies
so an omitted or non-explicit permission mapping is still a finding.

The literal is admitted only where routing is enabled, that is a repository
whose inventory says `visibility: private` and `selfHostedCi: true`. On a
public repository it reports `public-self-hosted-routing`, and on a private
repository with `selfHostedCi: false` it reports `self-hosted-routing-disabled`.
A repository cannot enroll itself by misdeclaring its own visibility:
`CI_REPOSITORY_VISIBILITY` from the event is compared against the checked-in
value and a disagreement is a configuration error, not a finding.

Admission is exact membership in `approvedManagedRunnerLabels`, a reviewed set
mirroring `approvedHostedRunnerLabels`, and deliberately not a
`managedLabelPatterns` match. Those patterns are a DETECTION surface: unanchored
and unbounded on purpose, so `rawManagedLabel` catches every label-shaped string
and refuses it. Admission needs the opposite bias. Reusing the detection pattern
as the gate would give an unreviewed near-miss such as
`melodic-anything-ubuntu-24.04-x64`, or label-shaped text sitting next to other
characters, the same trust as the real fleet label, including the
`allowedCallerPermissions` waiver and the grant treatment. Adding a label to the
fleet is therefore a reviewed, data-only policy change, exactly like adding an
approved hosted label. Configuration fails closed when an entry carries
surrounding whitespace, is a known GitHub-hosted label, or does not itself read
as a managed label.

`raw-self-hosted-label` catches every case it must: any string containing
`self-hosted`, an unreviewed label in the managed namespace, and a reviewed
managed label on any repository that is not an enrolled private consumer. Its
message is `raw managed runner target "<value>" is forbidden; name a label from
policy.approvedManagedRunnerLabels`. Only the exact
label a routing-enabled job resolves to is skipped, in `runs-on` and in an
approved reusable call's `runner` input alike. It is the one guard standing on
`approvedManagedRunnerLabels`, which is why it is a rule of its own.

The literal has no hosted recovery path: if no runner in the fleet is online,
the job queues instead of skipping or falling back, and no rule in this
component changes that. The controls that answer it are elsewhere: the fleet's
queue-depth alerting reports a managed-runner job that has waited too long, and
bringing a second host online is an operational task, not a policy one. A job
that must not fail hard on fleet unavailability names a hosted label or takes a
reviewed exception instead.

Reusable calls are not opaque exceptions. Every cross-repository reusable
workflow must have an entry in `policy.json`'s
`approvedReusableWorkflowContracts`, keyed by its bare path
(`owner/repo/.github/workflows/<file>.yml`, no `@ref`). A call matches that
contract at `@main` when the owner is `melodic-software`, or at a full
40-character commit SHA listed in that contract's `approvedShas`; an unlisted
SHA, a tag, another branch, or `@main` on a third-party workflow is refused.
`approvedShas` holds the SHAs earlier policy versions approved for the path,
so callers still SHA-pinned pass while they move to `@main`. It is migration
data: delete a path's list once no consumer pins that path to a SHA, and add
no SHA a reviewer has not traced to the workflow repository's main branch,
because GitHub serves a commit pushed to any fork under the parent
repository's path. A first-party call at `@main` runs the
workflow's current main, so the contract holds for whatever main declares and
a ci-workflows change needs no standards sync unless it changes the contract
surface (see [Contract revision lockstep](#contract-revision-lockstep)). Its contract names the
complete set of reviewed caller input names, an exact secret-name-to-expression
map (which may be empty), and one of two routing modes. Every
reusable call rejects `secrets: inherit`, omitted required secret mappings,
unknown secret names, and alternate expressions:

- `runner-input` names the one canonical runner input. Unknown workflows,
  unapproved refs, omitted runner inputs, and extra inputs fail closed.
  A contract may additionally name one exact `allowedCallerPermissions`
  mapping when an independently reviewed workflow needs a narrowly
  scoped write-capable caller token. The caller's effective job permissions
  must match every scope and access level exactly; missing scopes, additional
  scopes, `write-all`, and access drift fail closed. Omitting this field keeps
  the ordinary read-only local-workload boundary. This waiver applies only
  while the call's runner input carries the managed fleet label; a caller that
  instead pins a fixed hosted runner literal through the same input gets no
  permission waiver and still needs proven hosted execution under the
  `privileged-control-plane` exception category like any other write- or
  `id-token`-capable job, or `publication` when the caller's only write
  scope is `packages` and it carries no other privileged surface, per the
  packages-only rule below.
  A contract may separately name a `minimumCallerPermissions` mapping: the
  floor a caller must clear, where `allowedCallerPermissions` is the ceiling it
  must not exceed. The two answer different questions and neither implies the
  other. `allowedCallerPermissions` waives the ordinary read-only caller
  boundary so a reviewed workflow may hold a privileged grant, which is why the
  validator refuses it unless it carries at least one `write`;
  `minimumCallerPermissions` grants nothing and waives nothing. It records what
  the called workflow's own `permissions:` block requests, because a called
  workflow can only narrow the caller's `GITHUB_TOKEN` and never widen it, so a
  caller granting less than the callee asks for cannot do the work the contract
  was reviewed for. That obligation is most often entirely read, the case no
  write-requiring waiver can express at all, so the two fields are separate
  rather than one field doing both jobs. **A floor may only require `read`,**
  and the validator rejects any other value: GitHub downgrades a caller's
  write grants to read (and write-only scopes to none) on forked and
  Dependabot pull requests unless repository settings permit otherwise, so a
  caller's declared `write` is not the access the callee receives, and a write
  floor checked against the declaration would admit exactly the callers it
  exists to catch. A write obligation belongs in `allowedCallerPermissions`,
  which is reviewed against the calling job rather than inferred from it. The
  restriction is on what a contract may *require*, not on how grants compare:
  access stays ordered (`none` < `read` < `write`) and the check stays a
  floor, not a match, so a caller granting `write` where the contract requires
  `read` passes, extra scopes the contract does not name pass, and `read-all`
  or `write-all` clears a read floor: each of those still clears the floor
  after an event-time downgrade lands at `read`. A scope the caller does not
  name is granted nothing and fails, and a caller whose effective job
  permissions are omitted fails closed: omitted permissions resolve to
  repository- or organization-defined defaults this policy cannot read, so
  they can never prove the floor. A contract naming both fields must be
  satisfiable: because the waiver is the only mapping such a caller may
  present, a waiver falling short of the floor is rejected when the policy
  loads. Because the floor waives nothing, a `write-all` caller that clears it
  still meets the ordinary `privileged-control-plane` rules below.
  A runner-input contract whose reviewed `allowedSecrets` mapping is nonempty
  is secret-capable on its own: a statically read-only caller may forward
  exactly that named secret mapping while the call routes to the managed fleet,
  because the reviewed contract, not the caller, owns the secret boundary, the
  same way a hosted-only contract's mapping does. The caller's permissions keep
  the ordinary explicit read-only requirement unless the contract also names
  `allowedCallerPermissions`.
  A contract with `allowedCallerPermissions` maps each secret to its own name
  (`NAME: ${{ secrets.NAME }}`). A contract that also declares a funding
  `role` (lower kebab, and `role` must be in `allowedInputs`) may instead map
  it to that role's prefixed name, `NAME: ${{ secrets.<ROLE>_NAME }}`, with
  `<ROLE>` upper-snake (`issue-lane` is `ISSUE_LANE`), and its caller must pass
  `role:` as that exact literal. Role-named secrets let several funding roles
  share one repository; the role stays a reviewed literal, never an
  expression, and every other rename is still refused.
- `hosted-only` has no runner input. It records the GitHub-hosted labels found
  in the called workflow and rejects any caller-added input that was
  not part of the review.

`requiredReusableCallInputs` is the repository-local complement to that shared
contract surface. It is keyed by `<workflow path>#<job id>` on the caller job
that invokes a cross-repository reusable workflow, requires a non-empty
`justification`, and names one or more input keys in `requiredInputs`. The
check is presence-only: every listed input must appear in the caller's `with:`
mapping, but its value is not pinned. That lets a consumer require an explicit
`skip-actors` line, so deleting it becomes a visible diff and policy failure
rather than a silent re-widening to the reusable's default, without binding
every fleet consumer of the same pin to one consumer-specific value. Each named
input must still be admitted by the job's reviewed `allowedInputs` contract;
value pinning belongs in the caller workflow itself, not in this inventory.
An unconsumed entry fails as `required-reusable-call-input-drift`, exactly like
exception and local-routing grant inventory drift.

Repository-local calls use only the canonical
`./.github/workflows/<file>.yml` form. The policy resolves the regular checked-in
file directly: traversal, subdirectories, symlinks, missing files, parse
failures, recursion, undeclared/required inputs, undeclared/required secrets,
and `secrets: inherit` fail closed. A local runner-input workflow has the same
exclusive `workflow_call`, optional `runner`, and hosted-default contract as a
cross-repository runner-input workflow. Fixed-hosted and internally routed
local workflows are inspected at each called job, so structural and privileged
exceptions live on the actual called job instead of becoming a blanket caller
exception.

The `maintenance-sync-standards` reusable mints a per-target App token that
may write `.github/workflows/` and arms squash auto-merge on every sync PR the
manifest marks `automerge: true`. Read the two together before adding the
first manifest mapping under `.github/workflows/`: with targets whose `base`
ruleset requires zero approving reviews, one merged standards PR could write
workflow content into every target and have it self-merge. `ci-workflows`,
which hosts the engine, is itself a target.

The policy records each path, fixed runner label, caller-input allowlist, and
exact secret map; changing any field requires another review.

## Visibility-scoped reusable contracts (Claude lanes)

`approvedReusableWorkflowContracts` entries are keyed by workflow path and are
**shared by every governed consumer repository**. The schema has no way to scope
a contract to a repository or to a visibility class: listing an input or secret
in `allowedInputs` or `allowedSecrets` enables **every** governed caller of that
path to pass it; omitting it forbids every caller.

Two public repositories execute this gate today: `standards` and
`claude-code-plugins`. (`ci-workflows` is public but does not manage the
`runner-policy` component, so the gate never evaluates it there.)

The gate scopes these review reusables by path: `claude-review.yml` and
`claude-security-review.yml`, and their renamed paths `pr-review.yml` and
`pr-review-security.yml`. No consumer pins an old path; the old paths stay
listed because the historical fixture the tests read still holds entries for
them.

> **Invariant:** No `claude-review` or `claude-security-review` contract may list
> `standards-ref` or the `STANDARDS_REVIEW_APP_*` secrets while **any**
> repository that executes the runner-policy gate is public, unless the
> contract schema first grows repository- or visibility-scoped entries.

The gate enforces this invariant at audit time by scanning each reviewed
`claude-review` / `claude-security-review` contract's own `allowedInputs` and
`allowedSecrets` listing (not merely what a caller's `with:` block passes).
When such a contract lists a denylisted surface, the audit requires
`CI_REPOSITORY_VISIBILITY` and fails closed if it is absent; when present, it
must agree with `.github/runner-policy.json`'s `visibility`, and a `public`
inventory rejects the contract. Private repositories may carry the surface once
visibility evidence is supplied. This closes the gap where a well-intentioned
`policy.json` edit could enable a sensitive mount for private consumers while
simultaneously enabling it for public ones.

## Contract revision lockstep

A ci-workflows change that leaves a reusable's caller-facing surface alone
(`on.workflow_call` inputs and secrets, the permissions a caller must grant,
routing) needs no change here: first-party callers at `@main` run it on their
next event. A change to that surface is ordered so no caller is refused:

1. A new input: add it to the path's contract in `policy.json` and distribute
   it through the normal component sync before any caller passes it.
2. A removed or renamed input: remove it from every caller, found with an
   org-wide code search rather than a remembered list, then from the contract,
   then from the reusable.
3. A secret or `allowedCallerPermissions` change: every caller must send exactly
   the contract's secret map and caller permissions, so the contract change and
   every caller's change take effect together; callers on either side of the
   sync fail until both land.
4. A new reusable path gets its own contract entry before its first caller
   lands.

A caller still pinned to an approved SHA is checked against the same path
contract, so it too must send the current secret map and caller permissions.

A production fleet relabel is the same class of event plus its own sites:
`approvedManagedRunnerLabels` and `managedLabelPatterns` in `policy.json`,
every `runs-on:` and reviewed `runner` input naming the old label, and each
host's scale-set labels in `provisioning`. Live-state drift between those
layers is not detected by any repository check and shows up as an admitted job
queuing against a label no host answers to.

The analyzer also reports `pin-provenance-drift`: when the trailing comment on
a 40-character `uses:` pin contains a token that reads as a short commit SHA
(mixed hex digits and letters, or a full 40-character SHA), it must be a
prefix of the pinned commit. Version tags, prose, dates, and hex-only English
words are not treated as SHA claims. Update the comment in the same change as
the pin. A `@main` reference carries no pin and no such comment. The
`maintenance-repin-ci-workflows` job writes the `# vX.Y.Z` form when it moves
a first-party action pin, which this check accepts.

For a reusable workflow call, name the target through its canonical `runner`
input:

```yaml
  test:
    uses: ./.github/workflows/test.yml
    with:
      runner: melodic-ubuntu-24.04-x64
```

The exact contract applies equally to cross-repository and repository-local
reusable callers. Reusable workflow definitions may use
`runs-on: ${{ inputs.runner }}` only when `workflow_call` is the file's exclusive
trigger. The runner input must be either an optional string with the governed
`ubuntu-24.04` default, or `required: true` with no `default`; the required
form obliges every caller to name its own target. That governed default must
itself appear in `fallbackLabelAllowlist`, which admits fewer hosted labels
than `approvedHostedRunnerLabels` does and additionally admits the managed
fleet label: a label may be an approved explicit `runs-on`
target and still be barred from becoming the label a caller lands on by
omission, so a costlier hosted tier cannot slip in silently. Configuration
fails closed when the default is absent from the allowlist, and when an
allowlist entry is neither an approved hosted label nor a managed-label
match. A
`workflow_dispatch`, schedule, push, or other co-trigger invalidates either
routing contract because those entry points share the workflow's `inputs`
context. GitHub documents required reusable-workflow inputs; separately, an
optional string without a default becomes `""`, which is why the required form
is spelled `required: true` rather than merely omitting `default`.[9]

The only other dynamic `runs-on` form is a configured hosted matrix expression
(`matrix.os` or `matrix.runner`) backed by a non-empty, static array containing
only approved hosted labels; `include` and `exclude` are rejected because they
can alter the runner target. Set the required `hostedMatrixExpressions` policy
field to `[]` to explicitly disable matrix routing fail closed while continuing
to permit approved literal hosted labels. The [JSON Schema Draft 2020-12
specification][8] defines an omitted `minItems` as zero; keeping the field
required distinguishes that deliberate empty policy from a missing
configuration.

An exception is keyed by `<workflow path>#<job id>` and requires both an
allowlisted machine-readable `reason` and a non-empty `justification`. Extra,
renamed, and deleted exception entries fail as inventory drift. The centrally
allowlisted reasons deliberately cover Windows, job/service containers, Docker
socket access, privileged control planes, publication, and Dependabot. A
hosted job whose only write scope is `packages`
belongs to the `publication` category, not `privileged-control-plane`:
`packages: write` is registry-publication authority rather than repository or
organization state, and keeping it in the durable category lets published
artifacts retain hosted provenance after the control-plane reasons retire.
Any additional write scope, or any other privileged surface on the job, such
as a deployment environment, a credential expression, or a credential-minting
action, keeps the job privileged. The one admission is the exact
GitHub-provided token expression (the common registry-authentication step
env), which carries only the packages-only permission map the exception
already reviews.

A job declaring `container` must use a proven hosted target and an exception
whose reason is `job-container`. A job declaring `services` without a job
container similarly requires `service-container`. When both are present,
`job-container` is the governing category. An exception records why the job is
hosted; it never authorizes a fleet label or a reusable `inputs.runner` value
for these structurally excluded jobs.

`localRoutingGrants` is the reviewed inventory for the opposite direction: it
admits one directly declared job that reaches the managed fleet by naming the
fleet label,
while that job holds an exactly pinned privilege surface that would otherwise
require hosted execution. A grant is keyed by
`<workflow path>#<job id>`, requires a non-empty `justification`, and names:

- `permissions`: the complete effective `GITHUB_TOKEN` mapping the job must
  declare, compared exactly per scope and access level. Shorthands
  (`read-all`, `write-all`), omitted declarations, missing scopes, extra
  scopes, and access drift all fail closed. Pinning the map also admits the
  exact GitHub-provided `${{ secrets.GITHUB_TOKEN }}` or `${{ github.token }}`
  expression as a complete job- or step-level `env`/`with` value, which the
  ordinary boundary reserves for statically read-only jobs.
- `environment` (optional): one exact deployment environment name the job
  must declare in plain string form. A differing name, a mapping-form or
  expression-valued environment, and an environment the grant does not name
  all stay privileged-hosted; an expression-valued grant name itself fails
  configuration, because GitHub evaluates environment expressions (`vars`,
  `needs`, `matrix`) and the protected environment could then change without
  a grant-inventory diff.
- `secrets` (optional): repository or organization secret names the job may
  reference, each only as the exact complete `${{ secrets.NAME }}` value of a
  job-level `env` or step `env`/`with` entry. `GITHUB_TOKEN` cannot be named
  here; transformed expressions, workflow-level env values, `run:`
  interpolation, and conditions stay privileged-hosted.
- `credentialActions` (optional): full `owner/action@<40-hex-SHA>`
  references the job's steps may invoke, whose action name must be a central
  `localCredentialActions` entry (for example
  `actions/create-github-app-token@<reviewed SHA>`). The grant pins the exact
  ref because a different ref of the same action is different
  credential-minting code; a tag, branch, or other SHA stays
  privileged-hosted, and actions outside the central list cannot be granted.

A grant applies only while the job genuinely routes to the managed fleet, that
is while it names the fleet
label as a literal on a repository enrolled for local routing. A fixed hosted
target keeps the ordinary privileged exception inventory, and job/service
containers remain structurally hosted regardless.
A reusable-call (`uses:`) job never takes the grant path: its caller
permissions flow into an external workflow whose behavior only the central
contract review sees, so `allowedCallerPermissions` remains
the sole write-capable waiver for callers and a grant keyed to such a job
fails as `local-routing-grant-drift`.
One key cannot carry both an exception and a grant, a grant that admits
nothing beyond the ordinary read-only boundary fails configuration, and an
unconsumed grant fails as `local-routing-grant-drift`, exactly like exception
inventory drift. The same drift rule reports a consumed grant whose named
secret or credential-action allowances the job does not actually exercise:
an unexercised allowance is latent pre-approval a later workflow-only change
could start consuming without any grant-inventory diff, so the admitted
surface and the reviewed inventory must stay exactly equal.

For an enrolled private repository, effective `GITHUB_TOKEN` permissions follow
GitHub's workflow-then-job precedence: a job-level declaration replaces the
workflow declaration, and omitted permissions in a mapping become `none`.
Omitting both the workflow and direct workload declaration is different:
GitHub derives that token from repository or organization defaults, so the
policy cannot prove it read-only. Every directly fleet-routed workload must
therefore resolve explicitly to `read-all`, `{}`, or a mapping containing only
`read`/`none`. A wholly omitted declaration, `write-all`, any individual
`write`, and `id-token: write` require proven hosted execution plus a precise
`privileged-control-plane` exception, or `publication` when the only write
scope is `packages` per the packages-only rule above, unless the repository
pins that job's exact effective mapping in a `localRoutingGrants` entry as
described above. A full-SHA action does not weaken this rule because an action
can obtain `github.token` implicitly.

For repository-local reusable calls, GitHub passes the caller's permission
grant into the called workflow and nested calls can only keep or reduce it. The
policy follows that chain recursively. Every dynamic/local called job must
declare an effective read-only job or workflow mapping when a caller can pass
write; omission fails because the caller grant would flow through. A fixed
hosted called job may inherit write only with its own
`privileged-control-plane` exception, or `publication` when the called job
declares its own packages-only write map with no other privileged surface,
per the packages-only rule above. A local reusable caller's write grant is
therefore not rejected wholesale when every potentially local called job
provably narrows it.

Local-routable workload jobs also reject deployment environments, explicit
credential expressions, and credential-minting actions listed in
`localCredentialActions`, unless the repository's `localRoutingGrants` entry
for that exact job names them as described above. Absent a grant, the only
workload credential exception is the exact
GitHub-provided `${{ secrets.GITHUB_TOKEN }}` or functionally equivalent
`${{ github.token }}` as a complete step-level `env`/`with` value under
statically read-only effective permissions, or under a packages-only write
map, where the token carries exactly the `publication`-categorized authority
per the packages-only rule above. Workflow/job environment values,
run-script interpolation, bracket aliases, case variants, transformations, and
user secrets remain privileged-hosted.
Exact hosted-only reusable secret mappings remain governed by their
`approvedReusableWorkflowContracts` entry. GitHub notes that actions
can access `github.token` implicitly, so full-SHA action policy and least token
permissions remain the actual boundary; banning only one equivalent spelling
would add no isolation.

Any approved fleet-routed runner-input call may carry only its exact
reviewed named `secrets` mapping, with or without `allowedCallerPermissions`.
After that mapping passes the reusable-workflow contract, the generic
credential scan omits only the caller's `secrets` property; the caller's own
permissions still require the explicit read-only boundary unless the contract
names `allowedCallerPermissions`. Secret expressions in `with`, `if`,
workflow or job environment values, or any other caller field remain forbidden,
as do transformed secret expressions and `secrets: inherit`. Deployment
environments, credential-minting actions, job containers, and services retain
their existing hosted-only rules.

The policy also forbids `ubuntu-latest`, direct `self-hosted` use, unreviewed
labels in the managed namespace (including tiered forms), unknown literal
labels, and arbitrary expression/variable indirection. Hosted targets must come
from the policy's explicit label allowlist, and managed targets from
`approvedManagedRunnerLabels`. A policy exception permits hosted
execution; it does not suppress the runner-target, reusable-contract, or
image-version rules.

The contract follows GitHub's documentation for [choosing runners for jobs][1],
[reusing workflows and passing secrets explicitly][2], [secure use of
self-hosted runners][3], [GitHub token contexts][4], and [permission flow across
reusable workflows][5], [job status-check functions][6], and [repository-level
default `GITHUB_TOKEN` permissions][7].

[1]: https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job
[2]: https://docs.github.com/en/actions/how-tos/sharing-automations/reuse-workflows
[3]: https://docs.github.com/en/actions/reference/security/secure-use
[4]: https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#github-context
[5]: https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations#supported-keywords-for-jobs-that-call-a-reusable-workflow
[6]: https://docs.github.com/en/actions/reference/evaluate-expressions-in-workflows-and-actions#status-check-functions
[7]: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#setting-the-permissions-of-the-github_token-for-your-repository
[8]: https://json-schema.org/draft/2020-12/json-schema-validation#section-6.4.2
[9]: https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow
