# GitHub Actions runner policy

This module is the enforceable contract for local GitHub Actions routing. It
parses workflow YAML; it does not use text matching to infer job structure.

Run it from a repository root:

```sh
node components/runner-policy/runner-policy.mjs --root .
```

The only runtime dependency is the exact `yaml@2.9.0` pin. In GitHub Actions,
set `CI_REPOSITORY_VISIBILITY` from `${{ github.event.repository.visibility }}`
so the checked-in inventory cannot claim that a public repository is private.

Each adopting repository carries `.github/runner-policy.json`:

```json
{
  "schemaVersion": 1,
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

`visibility` and `selfHostedCi` are governed inventory, not runtime switches.
Public repositories and repositories not enrolled for local CI cannot call the
selector. Enrolled private repositories must route each independently scheduled
job through a selector whose complete workflow path and 40-character commit SHA
appear in `policy.json`'s `approvedSelectorReferences`. That allowlist is empty
until the independently reviewed selector is committed. This deliberately fails
closed across the publication dependency gate; adding the reviewed path@SHA is a
data-only policy change.

An approved selector call has an exact contract. Alternate variables, literals,
extra inputs, extra secrets, and `secrets: inherit` are rejected:

```yaml
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
    runs-on: ${{ needs.select-runner.outputs.runner }}
```

Personal-repository callers may additionally pass
`self-hosted-labels-json: ${{ vars.CI_SELF_HOSTED_LABELS_JSON }}`. No other
selector input is allowed by the policy.

Reusable calls are not opaque exceptions. Every reusable workflow must have an
exact path@40-character-SHA entry in
`policy.json`'s `approvedReusableWorkflowContracts`. Its contract names the
complete set of reviewed caller input names and one of two routing modes:

- `runner-input` names the one canonical runner input. Unknown workflows,
  obsolete SHAs, omitted runner inputs, and extra inputs fail closed.
- `hosted-only` has no runner input. It records the GitHub-hosted labels found
  in the immutable called workflow and rejects any caller-added input that was
  not part of the review.

Runner-controlled contracts remain absent until their new reusable commits have
completed independent review. That publication gate is distinct from the six
existing `hosted-only` contracts: their exact pinned git objects at
`1d3762c2ace413db0f347048307946c46850161c` were inspected, every job has a
literal `runs-on: ubuntu-latest`, and no input participates in runner selection.
The policy records each complete path@SHA, fixed runner label, and caller-input
allowlist; changing any of those fields requires another review.

For an approved reusable workflow call, pass the selector output through its
canonical `runner` input. Reusable workflow definitions may use
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

The policy also forbids `ubuntu-latest`, direct `self-hosted` use, managed scale
set labels, unknown literal labels, and arbitrary expression/variable
indirection. Hosted targets must come from the policy's explicit label
allowlist. A policy exception permits hosted execution; it does not suppress
the runner-target, selector-contract, or image-version rules.

The contract follows GitHub's documentation for [choosing runners for jobs][1],
[reusing workflows and passing secrets explicitly][2], and [secure use of
self-hosted runners][3].

[1]: https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job
[2]: https://docs.github.com/en/actions/how-tos/sharing-automations/reuse-workflows
[3]: https://docs.github.com/en/actions/reference/security/secure-use
