# Runner-policy threat model

This model covers the read-only analyzer in
[`runner-policy.mjs`](runner-policy.mjs), its central and repository schemas,
and the workflow and repository configuration it evaluates. The GitHub Actions
control plane, reusable-workflow implementations in `ci-workflows`, and the
self-hosted runner fleet are external systems. Their behavior is modeled where
it crosses this analyzer's boundary, but this component does not operate or
attest to them.

The model follows OWASP's maintained threat-modeling loop: describe the system,
identify what can go wrong, map concrete responses, and validate the result.

## Security objectives and assets

- Privileged, credential-bearing, containerized, and otherwise excluded work
  stays on an explicitly approved GitHub-hosted runner unless an exact
  reviewed admission, a reviewed runner-input contract boundary or a
  repository local-routing grant pinning the job's complete privilege
  surface, names it for a job that genuinely routes to the managed fleet.
  Containerized work is never admissible.
- Eligible private, read-only workloads reach the managed fleet only by naming
  a reviewed label from `approvedManagedRunnerLabels`.
- Workflow, reusable-workflow, permission, secret, and exception
  contracts cannot be widened through YAML ambiguity or local indirection.
- Repository visibility and declared repository identity use evidence that the
  checked-out repository cannot grant to itself.
- Policy findings fail the CI gate clearly without modifying the repository or
  workflow files.

The protected assets are repository and organization credentials, the
`GITHUB_TOKEN` permission boundary, deployment environments, self-hosted fleet
isolation, reviewed workflow identities, exception inventory, and CI
availability.

## Actors and trust boundaries

- A repository maintainer changes governed configuration and reviews findings.
- A pull-request contributor may control workflow YAML, local reusable
  workflows, action inputs, scripts, and checked-in repository inventory.
- A compromised action or reusable workflow may attempt to obtain credentials
  or move execution onto the managed fleet.
- Standards maintainers review central policy, schemas, and reusable-workflow
  contracts.
- GitHub supplies repository visibility and `GITHUB_REPOSITORY` identity and
  later evaluates the accepted workflow. Those facts cross an external control-
  plane boundary.
- `melodic-software/ci-workflows` maintainers change the first-party reusable
  workflows that callers at `@main` run on their next event. That repository's
  review and branch protection, not this analyzer, govern what main contains.

Checked-in `.github/runner-policy.json` and `.github/workflows/*.yml` are
untrusted subjects of the audit. The distributed central policy and schemas are
trusted only at their reviewed Git revision. Environment identity supplied by
GitHub is independent evidence; it must agree with checked-in inventory.

## Data flow

1. The caller selects a repository root, central policy, repository policy, and
   optional external visibility and repository-identity evidence.
2. The pinned YAML parser preflights raw central policy, repository policy, and
   both schema JSON files with unique object members required; `JSON.parse`
   remains the JSON syntax and runtime-value authority. Ajv then validates both
   policies against strict Draft 2020-12 schemas, and the runtime validates
   cross-record invariants that schema cannot express.
3. The analyzer indexes regular top-level workflow YAML files, rejects workflow
   symlinks, and parses with aliases and merge keys disabled, strict parsing,
   and unique keys required.
4. Each cross-repository reusable call is matched to the contract keyed by its
   workflow path. The ref must be `main` for a `melodic-software` workflow or a
   full 40-character commit SHA for any owner; any other ref is refused. The
   analyzer performs no network access.
5. It follows repository-local reusable calls, evaluates routing, permission
   flow, credentials, structural hosted requirements, external reusable
   contracts, and exact exception and local-routing-grant consumption.
6. Findings and the process exit status cross back to CI. No repository file,
   GitHub setting, runner, or remote workflow is changed.

## Threats, controls, and evidence

| Threat | Control | Executable evidence |
| --- | --- | --- |
| Checked-in inventory forges a private visibility or a different owner. | GitHub-supplied visibility must match inventory. Supplied `GITHUB_REPOSITORY` evidence must parse as an `owner/repository` name, and an owner mismatch against checked-in inventory fails configuration. | `GitHub visibility evidence must agree with governed inventory`, owner-evidence, and malformed-identity cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A shared `claude-review` / `claude-security-review` contract lists `standards-ref` or `STANDARDS_REVIEW_APP_*` while a public repository executes the gate, enabling a sensitive mount for every governed caller of that path. | Contracts for those workflow paths are scanned at audit time on their own `allowedInputs` / `allowedSecrets` listing. Denylisted surface requires `CI_REPOSITORY_VISIBILITY` and fails closed when absent; when present it must agree with inventory, and `public` inventory rejects the contract. | Visibility-scoped reusable-contract cases in [`runner-policy.test.mjs`](runner-policy.test.mjs); invariant in [`README.md`](README.md). |
| A privileged or credential-bearing job reaches a self-hosted runner. | A local route is a governed fleet label written as a literal on a repository enrolled for local routing, including a job reached through a repository-local `workflow_call` whose own `runs-on` names that label. Local routes require statically read-only permissions unless one reviewed runner-input reusable-workflow contract names an exact caller permission or secret boundary, or the repository's own local-routing grant pins the job's exact effective permission map, environment name, named-secret expressions, and credential actions. Each narrow admission still rejects permission drift and every credential surface outside its exact named terms. Deployment environments, credential-minting actions, job containers, and services remain hosted with an exact categorized exception absent such an admission, and containers are never admissible. | Permission, reusable-caller permission drift, secret-capable contract, local-routing-grant admission and exactness, credential-surface, environment, action, container, and service cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| An unreviewed label in the managed namespace is named as a literal and inherits the reviewed fleet label's trust, or a managed fleet label is named on a repository that may not route work there, or a repository enrolls itself by misdeclaring its own visibility. | Admission is exact membership in the reviewed `approvedManagedRunnerLabels` set, never a `managedLabelPatterns` match: those patterns are an unanchored detection surface whose job is to catch and refuse every label-shaped string, and using them to admit would invert that bias. Adding a fleet label is a reviewed policy-data change; an entry that carries whitespace, is a GitHub-hosted label, or does not read as a managed label fails configuration. A fleet literal is admitted only where `visibility` is `private` and `selfHostedCi` is `true`. Elsewhere it reports `public-self-hosted-routing` or `self-hosted-routing-disabled`, and `raw-self-hosted-label`, the one guard on `approvedManagedRunnerLabels`, still reports the pin. The repository-policy schema forces `selfHostedCi` false when `visibility` is `public`, and GitHub-supplied `CI_REPOSITORY_VISIBILITY` must agree with the checked-in value or analysis fails closed with a configuration error. | Fleet-literal admission, near-miss and adjacent-text refusal, `approvedManagedRunnerLabels` configuration-error, public-repository, non-enrolled, and visibility-evidence cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A moving reference or opaque wrapper changes reviewed execution. | External reusable workflows use path-keyed contracts; a caller may name only `@main` on a `melodic-software` workflow or a full 40-character SHA, so a tag, another branch, or a third-party `@main` is refused. A first-party `@main` deliberately moves with ci-workflows main (see residual risk). Local wrappers are recursively inspected; traversal, missing files, cycles, undeclared inputs or secrets, and `secrets: inherit` fail closed. | Reusable-contract ref-matching (`@main`, full SHA, tag, branch, third-party `@main`, `@` policy key), local-call traversal, recursion, input, secret, and wrapper cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| YAML ambiguity hides a different workflow graph. | The parser requires unique keys, disables aliases and merge keys, and records parse failures. Only regular top-level workflow files are indexed; symlinks are findings. | Duplicate-key and workflow-symlink cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| Duplicate JSON member names make a policy or schema interpretation-dependent. | Raw central policy, repository policy, and both schemas are preflighted with the pinned parser's strict unique-key mode before `JSON.parse`; diagnostics identify the affected path. This enforces the interoperability guidance in [RFC 8259 section 4](https://www.rfc-editor.org/rfc/rfc8259#section-4). | Top-level and nested duplicate-member cases for all four load classes in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| An exception becomes a blanket bypass or outlives its job. | Exceptions are keyed to one workflow and job, use allowlisted categories with justification, do not suppress runner-target rules, and fail on unused inventory. | Exception category, consumption, drift, and indirection cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A repository local-routing grant becomes a blanket privilege bypass or outlives its job. | Grants are keyed to one workflow and job, apply only while that job genuinely routes to the managed fleet (the governed fleet label as a literal on an enrolled private repository), never apply to a reusable-call job (caller permissions reaching an external workflow stay governed solely by the central `allowedCallerPermissions` contract review), pin the exact effective permission map, one literal environment name (expression-valued grant environments fail configuration), exact `${{ secrets.NAME }}` expressions, and full-SHA-pinned credential-action refs whose action names come from the central `localCredentialActions` list (a different ref of the same action stays privileged-hosted), cannot coexist with a hosted exception for the same key, must admit at least one privilege beyond the read-only boundary, never suppress structural container/service or runner-target rules, and fail on unused inventory: both a wholly unconsumed grant and any named secret or credential-action allowance the admitted job does not actually exercise. Everything outside the pinned surface keeps today's privileged-hosted behavior: transformed expressions, workflow-level env, conditions, `run:` interpolation, shorthand or drifted permissions. | Local-routing grant admission, exactness, structural, configuration-error, schema, and drift cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A consumer deletes a caller input that narrows a reusable-workflow gate while the shared contract still admits the input optionally, so CI stays green and the caller silently inherits a wider default. | `requiredReusableCallInputs` lets a repository pin presence-only mandatory inputs on the exact reusable-call job key. Every listed input must appear in the caller's `with:` mapping, must be admitted by the reviewed contract, and an unconsumed entry fails as inventory drift. Values are not pinned: widening still requires an explicit diff line, not an invisible deletion. | Required reusable-call input presence, presence-only value acceptance, contract-admission, and drift cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A policy or dependency change weakens validation unnoticed. | Central and repository schemas reject unknown shapes; component dependencies are exactly locked; CI runs behavioral tests and then audits this repository with external visibility evidence. | [`policy.schema.json`](policy.schema.json), [`repository-policy.schema.json`](repository-policy.schema.json), [`package-lock.json`](package-lock.json), and the `check-policies` CI job. |

The detailed operational contract and current approved references live in the
[component README](README.md) and [`policy.json`](policy.json); this model does
not duplicate those changing inventories.

## Residual and accepted risk

- Standards maintainers review a reusable workflow before its path gets its
  first `approvedReusableWorkflowContracts` entry, and again whenever its
  caller-facing surface changes. Between those reviews a first-party caller at
  `@main` runs whatever ci-workflows main holds: a change to a step body, a
  composite action, or a nested workflow inside ci-workflows reaches every such
  caller with no standards review, under the permissions and secrets its
  contract already admits. ci-workflows review and branch protection are the
  control for that content, accepted by the owner's decision to float
  first-party refs.
- A contract also admits any full 40-character SHA, which GitHub resolves from
  anywhere in the repository's fork network, so a caller could pin a fork-only
  commit of an approved path. This keeps SHA-pinned callers passing while
  first-party callers move to `@main`; the caller's own pull-request review is
  the control for which SHA it names.
- Credential detection is conservative static analysis, not shell or action
  semantic evaluation. A novel credential-minting action, obfuscated script, or
  GitHub feature may evade a specific pattern. Least `GITHUB_TOKEN` permissions,
  action review, code review, and updates to `localCredentialActions`
  remain necessary.
- A job that names the fleet label as a literal has no hosted recovery
  path. If no runner in the fleet is online it
  queues rather than skipping or falling back, and no rule here changes that.
  Availability is a separate control: fleet queue-depth alerting reports a
  managed-runner job that has waited too long, and a lane where queuing is
  unacceptable keeps a hosted literal and a named exception instead.
- The analyzer cannot establish that a self-hosted runner or its host is clean.
  Fleet hardening, ephemeral operation, network boundaries, and incident
  response remain outside this component.
- A local-routing grant or secret-capable runner-input contract deliberately
  moves a reviewed privileged workload onto the managed fleet, exposing its
  credentials and write authority to the runner host for that job's duration.
  Each admission pins the workflow-shape surface only; repository code review
  of the granted job's steps, GitHub deployment-environment protection rules,
  and the fleet controls above remain the compensating controls, exactly as
  for `allowedCallerPermissions` contracts.
- The analyzer has no event-type gate and no checkout or PR-head awareness. An
  enrolled private repository may name the fleet label on a job triggered by
  `issue_comment`, `pull_request_review`, `pull_request_review_comment`, or
  `issues`, and a permission-read-only job of that shape that checks out
  untrusted content places that content on the fleet with no static backstop.
  Step review of the routed job is the sole compensating control, exactly as a
  local-routing grant's job body is trusted. Every job-level control
  (statically-read-only-or-grant, privileged-hosted, container/service,
  runner-target) still applies unchanged, but each keys only on `GITHUB_TOKEN`
  write permissions, named secrets, and credential-minting actions.
- A pull request can change the analyzer, policy, and tests together. Required
  review, branch governance, pinned CI dependencies, and review of reduced
  negative coverage are repository controls outside the analyzer itself.
- GitHub Actions expression and reusable-workflow semantics can evolve after a
  passing audit. The policy proves only the modeled syntax and reviewed
  platform behavior, not all future control-plane interpretation.
- The governed reusable runner input's default label is bounded to
  `fallbackLabelAllowlist`, which admits fewer hosted labels than
  `approvedHostedRunnerLabels` does, so a caller that omits the input cannot
  land a costlier hosted tier. The bound is on the default a reviewed reusable
  workflow declares, not on what a caller may pass: an explicit caller value
  is still held to the ordinary runner-target rules.

No exception inside `.github/runner-policy.json` accepts these model-level
risks. A risk acceptance is recorded in the owning repository with scope,
owner, compensating controls, and a review trigger.

## Review triggers

Re-run this threat model when the analyzer accepts a new runner expression,
credential source, permission form, local-call shape, external contract type,
exception reason, YAML parser behavior, or repository-identity source. Also
review it when GitHub changes runner, token, expression, reusable-workflow, or
self-hosted security semantics; when a central schema version changes; or after
an incident crosses the hosted/self-hosted boundary.

Each review confirms the data flow, adds a negative test for every new failure
mode, and updates residual risk instead of merely changing the allowlist.

## External authorities

- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [NIST SP 800-218, Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final)
- [GitHub secure use of self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub reusable workflows](https://docs.github.com/en/actions/how-tos/sharing-automations/reuse-workflows)
- [GitHub `GITHUB_TOKEN` permissions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#setting-the-permissions-of-the-github_token-for-your-repository)
