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
runtime pins. `policy.schema.json` and `repository-policy.schema.json` are the
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

The policy gate itself stays on an explicit GitHub-hosted image so the
enforcement path neither depends on nor exercises the fleet it audits:

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

In a private repository with `selfHostedCi: true`, its
`.github/runner-policy.json` entry declares that fixed hosted job with a
`hosted-control-plane` exception. A hosted-only repository sets
`selfHostedCi: false` and keeps `exceptions` empty: selector routing is disabled,
fixed approved hosted targets need no exception, and any unconsumed exception
fails as `exception-inventory-drift`. Set `CI_REPOSITORY_VISIBILITY` from the
event as shown so checked-in inventory cannot claim that a public repository is
private. GitHub Actions supplies the default `GITHUB_REPOSITORY` environment
variable independently of the checked-out repository, so owner-scoped selector
approval remains available without another workflow-controlled input.

Because the distributed lockfile is an independent dependency root, every
consumer must add an npm Dependabot entry whose `directory` is exactly
`/.github/standards/runner-policy`. The source repository maintains the
corresponding `/components/runner-policy` entry. Adding or relocating this
component without both entries is incomplete dependency coverage.

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
it never authorizes an owner-scoped selector revision. Authorization evidence
must come from the externally supplied `GITHUB_REPOSITORY` context. When both
sources are present, their owners must match or analysis fails closed. Owner
names are lowercase GitHub logins. Missing external owner evidence does not
change globally approved selector behavior, but it cannot authorize an
owner-scoped selector revision even when checked-in inventory declares an owner.

Public repositories and repositories not enrolled for local CI cannot call the
selector. Enrolled private repositories must route each independently scheduled
job through a selector whose complete workflow path and 40-character commit SHA
appear in policy schema v3's global `approvedSelectorReferences` or in the
current owner entry under `approvedSelectorReferencesByRepositoryOwner`. The
allowlists contain only independently reviewed production selector commits.
Owner-scoped entries cannot also be globally approved, and malformed owners,
malformed refs, or ownership mismatches fail closed. Updating a path@SHA or its
owner scope remains a reviewed, data-only policy change.

Workloads with the same selector inputs and secret mapping may share one
selector job in the same workflow. Each workload still follows the direct
dependency, runner-output, and cancellation-safe condition contract below.

An approved selector call has an exact contract. Alternate variables, literals,
extra inputs, extra secrets, and `secrets: inherit` are rejected:

```yaml
permissions: read-all

jobs:
  select-runner:
    uses: melodic-software/ci-workflows/.github/workflows/select-runner.yml@<APPROVED_40_CHARACTER_SHA>
    secrets:
      observer-private-key: ${{ secrets.CI_RUNNER_OBSERVER_PRIVATE_KEY }}
    with:
      policy: ${{ vars.CI_RUNNER_POLICY }}
      self-hosted-label: ${{ vars.CI_SELF_HOSTED_LABEL }}
      hosted-runner: ${{ vars.CI_HOSTED_RUNNER }}
      scope: ${{ vars.CI_RUNNER_SCOPE }}
      managed-runner-prefix: ${{ vars.CI_MANAGED_RUNNER_PREFIX }}
      observer-client-id: ${{ vars.CI_RUNNER_OBSERVER_CLIENT_ID }}

  test:
    needs: select-runner
    if: ${{ !cancelled() }}
    runs-on: ${{ needs.select-runner.outputs.runner || 'ubuntu-24.04' }}
```

The workload contract deliberately has two parts. Its target is exactly
`${{ needs.<selector-job>.outputs.runner || 'ubuntu-24.04' }}`, and the same
selector job ID must appear in `needs`. Its job condition is exactly
`${{ !cancelled() }}`, or begins with that status check as the first top-level
`&&` operand when the workload already has a condition. A nested disjunction is
safe only when the outer expression remains cancellation-gated. Missing status
checks, `always()`, top-level `||`, a different selector dependency, a different
hosted literal, and arbitrary target expressions fail closed.

This explicit literal is the recovery path if the selector itself fails before
producing an output. It must not use `vars.CI_HOSTED_RUNNER`: on selector
failure, that operational value has not passed the selector's approved-hosted-
label validation. The selector still receives `CI_HOSTED_RUNNER` as its normal
validated input; only the caller's failure fallback is frozen to
`ubuntu-24.04`.

Personal-repository callers may additionally pass
`self-hosted-labels-json: ${{ vars.CI_SELF_HOSTED_LABELS_JSON }}`. No other
selector input is allowed by the policy.

Reusable calls are not opaque exceptions. Every cross-repository reusable
workflow must have an exact path@40-character-SHA entry in
`policy.json`'s `approvedReusableWorkflowContracts`. Its contract names the
complete set of reviewed caller input names, an exact secret-name-to-expression
map (which may be empty), and one of two routing modes. Every
reusable call rejects `secrets: inherit`, omitted required secret mappings,
unknown secret names, and alternate expressions:

- `runner-input` names the one canonical runner input. Unknown workflows,
  obsolete SHAs, omitted runner inputs, and extra inputs fail closed.
  A reviewed `selectorResultInput` additionally requires exact `if: ${{ always() }}`
  and the matching `${{ needs.<selector>.result }}` mapping so a required gate
  can report every selector outcome without authorizing general workloads to
  run after cancellation. Repository-local reusable workflows cannot wrap this
  contract; the selector-owning workflow must call the reviewed immutable
  workflow directly so no wrapper can default or forge the result.
- `hosted-only` has no runner input. It records the GitHub-hosted labels found
  in the immutable called workflow and rejects any caller-added input that was
  not part of the review.

A path@SHA with no `approvedReusableWorkflowContracts` entry is not
automatically rejected if the same workflow path already has a reviewed
contract at a different SHA: this is the common Dependabot-bump case. Before
the per-job checks run, the policy fetches both the previously reviewed
revision and the candidate revision from the source repository and
structurally diffs their security-relevant surface — the presence and validity
of `on.workflow_call`, workflow- and effective job-level `permissions`,
`on.workflow_call.inputs` and `on.workflow_call.secrets`, plus each job's
runner-routing declarations (`runs-on`, `strategy`, and nested reusable calls)
and execution boundaries (`container`, `services`, and `environment`). A
structural match on that surface auto-approves the candidate under the
previously reviewed contract,
stamped with `autoApproved: { basisSha, approvedAt }`
provenance; anything else (a fetch failure, a parse failure, or any change to
that surface) fails closed exactly as an unreviewed reference does, with the
declined reason folded into the diagnostic. This is a deterministic structural
comparison, not a judgment call, and it grants no blanket trust to a source
repository. Changes outside that bounded runner-contract surface may be
auto-approved; any change to the surface itself requires a human to add a new
contract entry.
Set `disableAutoApproval: true` (or `CI_RUNNER_POLICY_DISABLE_AUTO_APPROVAL=true`
in CI) to restore today's behavior and require an explicit contract for every
SHA.

The comparison preserves GitHub's documented distinctions: a reusable workflow
must declare [`on.workflow_call`][12], and omitted `permissions` inherit the
configured default while an explicit empty mapping disables all token
permissions.[13]

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

The approved production contracts at
`99ac2f8c5b09dbb785d4eaf18465cbd96c30290c` and the label-less scale-set
selector fix at `029a1c37a9b86f8200ef03f6f0c54fb1e7e6cdb1` were independently
reviewed. The self-hosted-only selector at
`3cb83c9502da0b210c335785e250023508c4b8e3` was independently reviewed as
well. The strict-selector scheduling fix at
`de50a08b6093d231519ee7a4c9371db76c0a7e1e` keeps the selector control-plane
job on the managed fleet for `self-hosted-only` while preserving the hosted
selector for adaptive policies. The liveness-routing revision at
`3415de3ff2fafee40e4d087eb6073d2f6952b595` routes to the managed fleet
whenever a matching runner is online — busy runners queue instead of falling
back to hosted — removes the rerun-to-hosted branch so a re-run keeps its
original route, and reports `online-runner-count`. The revision at
`f2d5e06757201f2fce187096a2c6fa805836c3d2` carries that selector
byte-identical; it is approved so consumer pins adopting the repository's
non-shallow Gitleaks scan fix keep a reviewed selector reference. The
Dependabot-routing revision at `3931f91ccba9bfe97500196091ae2cc039672952`
retires the Dependabot hosted-only guard with the owner's named approval:
same-repository Dependabot runs route like pushes, sourcing the observer key
from the organization's Dependabot secrets store, while fork and public guards
are unchanged and the key stays confined to the selector job. Until
`CI_RUNNER_OBSERVER_PRIVATE_KEY` is mirrored in that store, Dependabot runs
keep falling back hosted (`missing-secret`), so rollout is fail-safe.
Seven selector revisions remain approved for an ordered consumer rollout.
GitHub does not allow a reusable workflow to target a self-hosted runner group
owned by a different repository owner, so these four strict-scheduling
revisions are approved only for `melodic-software`; `kyle-sexton` repositories
cannot select them. The three older revisions remain globally approved until
compatible consumers migrate.
The Zizmor contract at `de50a08b6093d231519ee7a4c9371db76c0a7e1e`
uses its reviewed `runner` input and checksum-verified native Linux binary, so
strict consumers may route that advisory lane through the approved selector
without Docker-socket access.
The fail-closed required-check revision of `semantic-pr` at
`51012e2c7b8bf74bc26e08c6446b488254a8770f` was independently reviewed. Its
contract permits only the governed `runner` input plus `prerequisite-result`,
which lets a caller report selector failure without making the required check
disappear. A fail-closed caller must declare the selector as its only `needs`
prerequisite so the forwarded result covers every dependency outcome. The
selector and `semantic-pr` workflow expose only the governed
runner contract; Windows Pester, Docker-dependent scans, and privileged
control-plane workflows
such as the Pulumi version-drift monitor remain fixed to explicit GitHub-hosted
images. The production Claude review
contract permits its general `skip-actors` string input without constraining the
caller-owned value; every other input name remains denied by default. The
earlier hosted-only contracts
at `1d3762c2ace413db0f347048307946c46850161c` are compatibility-only entries for
the dependency-ordered consumer PRs; they do not authorize new adoption. Each
consumer must move every reusable call to the reviewed production SHA in the
same integration that enables its policy gate, and the legacy entries are
removed after the six consumer migrations. The policy records each complete
path@SHA, fixed runner label, caller-input allowlist, and exact secret map;
changing any field requires another review.

## Selector revision lockstep

A selector or approved-contract revision is never a one-repository change.
Shipping one requires every step below in order; skipping any of them is a
known failure mode, not a shortcut:

1. Land the reviewed change in `melodic-software/ci-workflows` and take the
   **merged main commit SHA**. A PR-branch head becomes unreachable after a
   squash merge; GitHub then refuses reusable-workflow resolution at that SHA,
   the pin passes review and sync, and the break surfaces only as a
   `startup_failure` on the first live dispatch.
2. Append the new `path@SHA` to the correct allowlist scope in `policy.json`
   (owner-scoped for strict-scheduling revisions, global otherwise), record
   its review note above, and distribute through the normal component sync.
3. Repin **every** consumer caller. Enumerate them with an org-wide code
   search for the previous SHA rather than trusting a remembered list, and
   remember that a single repository can fetch the pin in more than one
   workflow (for example a CI lane and a conformance lane); a missed
   pin-fetch step stays hidden while the PR ref keeps the old commit
   reachable and fails only after merge.
4. Remove superseded allowlist entries once every consumer has migrated, so
   the allowlist keeps expressing only what production may run.

A production fleet relabel is the same class of event plus its own sites: the
selector's label constant and strict-policy `runs-on` (gated red by the
`ci-workflows` fleet-label-agreement tests), the `CI_SELF_HOSTED_LABEL`
organization variable in `github-iac`, and each host's scale-set labels in
`provisioning`. Changing the selector constant mints a new selector revision,
so a relabel always implies the full lockstep above; live-state drift between
those layers is not detected by any repository check and shows up as the
selector routing hosted (adaptive policies) or refusing the label
(`self-hosted-only`) while runner inventory looks healthy.

The analyzer also reports `pin-provenance-drift`: when the trailing comment on
a 40-character `uses:` pin contains a token that reads as a short commit SHA
(mixed hex digits and letters, or a full 40-character SHA), it must be a
prefix of the pinned commit. An automated or manual repin that leaves the old
short SHA behind turns the comment into misinformation for the next reviewer;
version tags, prose, dates, and hex-only English words are not treated as SHA
claims. Update the provenance comment in the same change as the pin.

For an approved reusable workflow call, pass the same cancellation-safe,
literal-fallback expression through its canonical `runner` input:

```yaml
  test:
    needs: select-runner
    if: ${{ !cancelled() }}
    uses: ./.github/workflows/test.yml
    with:
      runner: ${{ needs.select-runner.outputs.runner || 'ubuntu-24.04' }}
```

The exact contract applies equally to cross-repository and repository-local
reusable callers. Reusable workflow definitions may use
`runs-on: ${{ inputs.runner }}` only when `workflow_call` is the file's exclusive
trigger. The runner input must be either an optional string with the governed
`ubuntu-24.04` default, or `required: true` with no `default`. The required form
accepts only the raw selector output and requires the caller condition to prove
selector success, the `self-hosted` route, a non-empty runner, and equality with
`vars.CI_SELF_HOSTED_LABEL`. The same caller workflow must also contain exactly
one approved unroutable failure sentinel for that selector; one sentinel may
cover multiple required calls sharing the selector, but a sentinel in another
workflow or for another selector does not satisfy the contract. Optional calls
with the governed hosted fallback do not require this guard. A
`workflow_dispatch`, schedule, push, or other co-trigger invalidates either
routing contract because those entry points share the workflow's `inputs`
context. GitHub documents required reusable-workflow inputs; separately, an
optional string without a default becomes `""`, which is why the no-fallback
form is required rather than merely omitting `default`.[9]

One exact literal, `ci-runner-selection-failed`, is reserved as an unroutable
failure sentinel. It is not a general runner target or fallback. The analyzer
accepts it only for a selector-dependent rejection job with one selector in
`needs`, the exact complement of a successful governed self-hosted route
(including an explicit selector-failure arm),
`timeout-minutes: 1`, `permissions: {}`, no environment, secrets, action, or
other executable surface, and one static error annotation followed by `exit 1`.
GitHub leaves a self-hosted-labelled job queued when no matching runner exists
and fails it after 24 hours,[10] so this exceptional guard fails a scheduled run
without consuming a hosted minute. The one-minute execution timeout does not
shorten that queue period; it limits execution only if a runner is mistakenly
given the reserved label. The guard exists because a condition-skipped job
reports Success and cannot by itself make a required check fail.[11]

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
socket access, privileged control planes, publication, Dependabot, and narrow
hosted control-plane work.

A job declaring `container` must use a proven hosted target and an exception
whose reason is `job-container`. A job declaring `services` without a job
container similarly requires `service-container`. When both are present,
`job-container` is the governing category. An exception records why the job is
hosted; it never authorizes selector output or a reusable `inputs.runner` value
for these structurally excluded jobs.

For an enrolled private repository, effective `GITHUB_TOKEN` permissions follow
GitHub's workflow-then-job precedence: a job-level declaration replaces the
workflow declaration, and omitted permissions in a mapping become `none`.
Omitting both the workflow and direct workload declaration is different:
GitHub derives that token from repository or organization defaults, so the
policy cannot prove it read-only. Every directly selector-routed workload must
therefore resolve explicitly to `read-all`, `{}`, or a mapping containing only
`read`/`none`. A wholly omitted declaration, `write-all`, any individual
`write`, and `id-token: write` require proven hosted execution plus a precise
`privileged-control-plane` exception. A full-SHA action does not weaken this
rule because an action can obtain `github.token` implicitly.

For repository-local reusable calls, GitHub passes the caller's permission
grant into the called workflow and nested calls can only keep or reduce it. The
policy follows that chain recursively. Every dynamic/local called job must
declare an effective read-only job or workflow mapping when a caller can pass
write; omission fails because the caller grant would flow through. A fixed
hosted called job may inherit write only with its own
`privileged-control-plane` exception. A local reusable caller's write grant is
therefore not rejected wholesale when every potentially local called job
provably narrows it.

Local-routable workload jobs also reject deployment environments, explicit
credential expressions, and credential-minting actions listed in
`localCredentialActions`. The only workload credential exception is the exact
GitHub-provided `${{ secrets.GITHUB_TOKEN }}` or functionally equivalent
`${{ github.token }}` as a complete step-level `env`/`with` value under
statically read-only effective permissions. Workflow/job environment values,
run-script interpolation, bracket aliases, case variants, transformations, and
user secrets remain privileged-hosted. The selector's one exact observer-secret
mapping remains allowed because the selector is a reviewed hosted reusable
workflow. Exact hosted-only reusable secret mappings remain governed by their
immutable `approvedReusableWorkflowContracts` entry. GitHub notes that actions
can access `github.token` implicitly, so full-SHA action policy and least token
permissions remain the actual boundary; banning only one equivalent spelling
would add no isolation.

The policy also forbids `ubuntu-latest`, direct `self-hosted` use, owner-prefixed
managed scale-set labels (including tiered and canary forms), unknown literal
labels, and arbitrary expression/variable indirection. Hosted targets must come
from the policy's explicit label allowlist. A policy exception permits hosted
execution; it does not suppress the runner-target, selector-contract, or
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
[10]: https://docs.github.com/en/actions/reference/runners/self-hosted-runners#routing-precedence-for-self-hosted-runners
[11]: https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions
[12]: https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#creating-a-reusable-workflow
[13]: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions
