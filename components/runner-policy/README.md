# GitHub Actions runner policy

This module is the enforceable contract for local GitHub Actions routing. It
parses workflow YAML; it does not use text matching to infer job structure.

In this source repository, run it from the repository root:

```sh
node components/runner-policy/runner-policy.mjs --root .
```

The distributed component lives at `.github/standards/runner-policy/` and owns
its own `package.json` and lockfile with the exact `yaml@2.9.0` runtime pin.
Consumers install and invoke that dependency root directly:

```sh
npm ci --prefix .github/standards/runner-policy
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

Its `.github/runner-policy.json` entry therefore declares that job with a
`hosted-control-plane` exception. Set `CI_REPOSITORY_VISIBILITY` from the event
as shown so checked-in inventory cannot claim that a public repository is
private.

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
runtime switches. `repositoryOwner` is the reviewed ownership evidence used by
local analysis. In GitHub Actions, the analyzer prefers the immutable default
`GITHUB_REPOSITORY` context; when both sources are present, their owners must
match or analysis fails closed. Owner names are lowercase GitHub logins. A
missing owner does not change globally approved selector behavior, but it cannot
authorize an owner-scoped selector revision.

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
selector for adaptive policies. Four selector revisions remain approved for an
ordered consumer rollout. GitHub does not allow a reusable workflow to target a
self-hosted runner group owned by a different repository owner, so this revision
is approved only for `melodic-software`; `kyle-sexton` repositories cannot
select it. The three older revisions remain globally approved until compatible
consumers migrate.
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
trigger and `on.workflow_call.inputs.runner` is an optional string with the
governed `ubuntu-24.04` default. A `workflow_dispatch`, schedule, push, or other
co-trigger invalidates that routing contract because those entry points share
the workflow's `inputs` context.

The only other dynamic `runs-on` form is a configured hosted matrix expression
(`matrix.os` or `matrix.runner`) backed by a non-empty, static array containing
only approved hosted labels; `include` and `exclude` are rejected because they
can alter the runner target.

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

The policy also forbids `ubuntu-latest`, direct `self-hosted` use, managed scale
set labels, unknown literal labels, and arbitrary expression/variable
indirection. Hosted targets must come from the policy's explicit label
allowlist. A policy exception permits hosted execution; it does not suppress
the runner-target, selector-contract, or image-version rules.

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
