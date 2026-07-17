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
  reviewed admission — an immutable runner-input contract boundary or a
  repository local-routing grant pinning the job's complete privilege
  surface — names it for a genuinely selector-routed job. Containerized work
  is never admissible.
- Eligible private, read-only workloads reach the managed fleet only through a
  reviewed selector contract with a literal hosted recovery path.
- Workflow, selector, reusable-workflow, permission, secret, and exception
  contracts cannot be widened through YAML ambiguity or local indirection.
- Repository visibility and owner-scoped approvals use evidence that the
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
- Standards maintainers review central policy, schemas, and immutable workflow
  contracts.
- GitHub supplies repository visibility and `GITHUB_REPOSITORY` identity and
  later evaluates the accepted workflow. Those facts cross an external control-
  plane boundary.
- `raw.githubusercontent.com` supplies the previously reviewed and candidate
  workflow bytes used for auto-approval's structural diff. It is fetched at
  audit time, over HTTPS, by immutable commit SHA; it is trusted only to the
  extent of that structural comparison, never as a source of new,
  independently unreviewed contract terms.

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
4. Before per-job checks run, the analyzer looks for path@SHA references that
   share a workflow path with an already-reviewed contract but have no
   contract of their own (a Dependabot SHA bump). For each, it fetches the
   previously reviewed revision and the candidate revision from the source
   repository over HTTPS and structurally diffs `on.workflow_call` presence
   and validity, workflow- and effective job-level `permissions`,
   `on.workflow_call.inputs`/`secrets`, job routing and nested reusable calls,
   container/service/environment execution boundaries, and whether any called
   job trips the same privileged-control-plane credential detection enforced
   against every directly declared or repository-local job. A structurally
   identical surface auto-approves the candidate only after every reviewed
   revision for the workflow path has been fetched, parsed, and validated, and
   every surface-matching revision agrees on the same effective contract terms.
   Incomplete basis evidence, no matching basis, any surface change, or
   disagreement among matching contracts leaves it unapproved and folds the
   reason into the existing fail-closed diagnostic. A job whose
   routing-relevant fields reference the `needs` context in any form — an
   output, a job `result`, an object filter across every job's outputs, or
   any other property or index reachable off `needs`, in any letter case —
   on either the reviewed basis or the candidate, and any reviewed contract
   carrying `selectorResultInput` or a privileged caller-permission grant,
   all decline unconditionally regardless of surface match, because none of
   them can be proven unchanged by this structural diff alone. The `needs`
   check is intentionally an allowlist of provably `needs`-free routing
   fields rather than a blocklist of specific indirection syntaxes: earlier
   revisions matched only named `needs.<job-id>.outputs.<name>` accesses and
   their index-syntax equivalents, and each fix for one reported spelling
   (dot syntax, then bracket/index syntax) left another undetected, most
   recently an object-filter route
   (`needs.*.outputs.runner`/`join(needs.*.outputs.runner, '')`) that has no
   named job-id segment for a job-id-shaped pattern to match. This is the only
   network access the analyzer performs, and it never widens a contract's
   declared inputs, secrets, permissions, or routing — it only extends a
   structurally identical, unambiguous already-reviewed contract to a new
   SHA.
5. It follows repository-local reusable calls, evaluates routing, permission
   flow, credentials, structural hosted requirements, immutable external
   contracts, and exact exception and local-routing-grant consumption.
6. Findings and the process exit status cross back to CI. No repository file,
   GitHub setting, runner, or remote workflow is changed.

## Threats, controls, and evidence

| Threat | Control | Executable evidence |
| --- | --- | --- |
| Checked-in inventory forges a private visibility or approved owner. | GitHub-supplied visibility must match inventory. Owner-scoped approvals require valid `GITHUB_REPOSITORY` evidence, and an owner mismatch fails configuration. | `GitHub visibility evidence must agree with governed inventory`, owner-evidence, and malformed-identity cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A privileged or credential-bearing job reaches a self-hosted runner. | Local routes require statically read-only permissions unless one immutable runner-input reusable-workflow contract names an exact caller permission or secret boundary, or the repository's own local-routing grant pins the job's exact effective permission map, environment name, named-secret expressions, and credential actions. Each narrow admission still rejects permission drift and every credential surface outside its exact named terms. Deployment environments, credential-minting actions, job containers, and services remain hosted with an exact categorized exception absent such an admission, and containers are never admissible. | Permission, reusable-caller permission drift, secret-capable contract, local-routing-grant admission and exactness, credential-surface, environment, action, container, and service cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A moving reference or opaque wrapper changes reviewed execution. | Selector and external reusable workflows use exact path-at-40-character-SHA contracts. Local wrappers are recursively inspected; traversal, missing files, cycles, undeclared inputs or secrets, and `secrets: inherit` fail closed. | Selector-pin, reusable-contract, local-call traversal, recursion, input, secret, and wrapper cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| YAML ambiguity hides a different workflow graph. | The parser requires unique keys, disables aliases and merge keys, and records parse failures. Only regular top-level workflow files are indexed; symlinks are findings. | Duplicate-key and workflow-symlink cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| Duplicate JSON member names make a policy or schema interpretation-dependent. | Raw central policy, repository policy, and both schemas are preflighted with the pinned parser's strict unique-key mode before `JSON.parse`; diagnostics identify the affected path. This enforces the interoperability guidance in [RFC 8259 section 4](https://www.rfc-editor.org/rfc/rfc8259#section-4). | Top-level and nested duplicate-member cases for all four load classes in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| Selector failure silently drops required work or routes through an unvalidated variable. | Workloads require the exact selector dependency and a cancellation-safe condition. Ordinary routes use the governed literal hosted fallback; every required no-default local call requires the raw output plus exact self-hosted proof and exactly one same-workflow rejection sentinel paired to that selector. The zero-cost guard uses one reserved unmatched label only under the exact complement, including selector failure. Fail-closed reporting contracts forward the selector result exactly. | Selector recovery, cancellation, dependency identity, fallback, required-input, same-workflow sentinel pairing, sentinel shape, and result-reporting cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| An exception becomes a blanket bypass or outlives its job. | Exceptions are keyed to one workflow and job, use allowlisted categories with justification, do not suppress runner-target rules, and fail on unused inventory. | Exception category, consumption, drift, and indirection cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A repository local-routing grant becomes a blanket privilege bypass or outlives its job. | Grants are keyed to one workflow and job, apply only while that job genuinely consumes the approved selector output, never apply to a reusable-call job (caller permissions reaching an external workflow stay governed solely by the central `allowedCallerPermissions` contract review), pin the exact effective permission map, environment name, exact `${{ secrets.NAME }}` expressions, and credential actions drawn from the central `localCredentialActions` list, cannot coexist with a hosted exception for the same key, must admit at least one privilege beyond the read-only boundary, never suppress structural container/service or runner-target rules, and fail on unused inventory. Everything outside the pinned surface — transformed expressions, workflow-level env, conditions, `run:` interpolation, shorthand or drifted permissions — keeps today's privileged-hosted behavior. | Local-routing grant admission, exactness, structural, configuration-error, schema, and drift cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A policy or dependency change weakens validation unnoticed. | Central and repository schemas reject unknown shapes; component dependencies are exactly locked; CI runs behavioral tests and then audits this repository with external visibility evidence. | [`policy.schema.json`](policy.schema.json), [`repository-policy.schema.json`](repository-policy.schema.json), [`package-lock.json`](package-lock.json), and the `runner-policy` CI job. |
| A Dependabot SHA bump of an already-reviewed reusable workflow is auto-approved even though the bump silently removes callability, changes permissions/inputs/secrets/routing/boundaries, adds a called job's credential-minting action or unapproved credential expression, swaps an already-declared/allowed secret for a different secret in the identical position, repoints an already-declared credential-minting action at a different, unreviewed `@ref` while keeping the action name identical, or inherits a broader contract from one of several matching reviewed revisions by insertion order or partial fetch evidence. | Auto-approval requires a structurally identical match of `on.workflow_call` presence/validity, workflow- and effective job-level permissions, declared inputs/secrets, job routing/nested calls, container/service/environment declarations, the same privileged-control-plane credential detection enforced against every directly declared or repository-local job, and the exact credential-bearing values each job references — including a `localCredentialActions` step's full normalized `uses:` value, not just that detection's category or the bare action name — between reviewed revisions and the candidate, all fetched fresh from the source repository. Every reviewed revision for the path must fetch, parse, and validate before every surface-matching revision is compared for agreement on the effective input, secret, runner-input, and hosted-only contract; incomplete evidence, any diff, or ambiguity fails closed with a deterministic diagnostic. `disableAutoApproval`/`CI_RUNNER_POLICY_DISABLE_AUTO_APPROVAL=true` restores the pre-auto-approval behavior for any repository that wants no automatic extension at all. | Identical-surface and identical-contract, contract-ambiguity/permutation, partial-evidence fetch/parse failures, removed/malformed-callability, omitted/empty and widened-permissions, changed-inputs, changed-routing/boundaries, added-credential-action, changed-credential-reference, changed-credential-action-ref, and escape-hatch cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A Dependabot SHA bump keeps a job's literal `runs-on` (or other routing field) unchanged while a value it indirectly resolves through the `needs` context — a job output, a job `result`, an object-filter expression across every job's outputs (e.g. `needs.*.outputs.runner`, which has no named job-id segment for a job-id-shaped detector to enumerate), or any other property or index reachable off `needs`, in any letter case — changes the actual runner/container/environment boundary, or a bump silently stops honoring a `selectorResultInput` fail-closed contract's forwarded selector result while every compared field stays identical, and either is still auto-approved because the structural surface diff cannot observe the change. A detector that enumerates specific dangerous `needs` spellings will always have a next gap, because GitHub's expression grammar for context/property access is large and can grow (new index forms, new filters, new functions). | Any job on either the reviewed basis or the candidate whose routing-relevant fields reference `needs` in any form declines auto-approval unconditionally: the check is a coarse allowlist of provably `needs`-free routing fields, not an enumerated blocklist of indirection syntaxes, so it does not need to recognize the specific shape of the reference to decline it. Any reviewed contract carrying `selectorResultInput` declines auto-approval unconditionally regardless of surface match, because the fail-closed guarantee it is trusted for depends on the called workflow's own steps, which sit outside the compared surface. Both require a human to add a new contract entry. | Needs-reference indirection (candidate and basis; property dereference, index-syntax, object-filter, case-variant, and non-outputs `needs` property cases) and selector-result-contract cases in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A Dependabot SHA bump of a secret-capable runner-input workflow (a reviewed contract whose nonempty `allowedSecrets` mapping lets a statically read-only caller forward exact named secrets to a caller-chosen, potentially self-hosted runner) changes what the workflow's steps do with a forwarded secret while every compared field stays identical, silently extending the secret-forwarding trust to unreviewed executable content. | Any reviewed runner-input contract with a nonempty `allowedSecrets` mapping declines auto-approval unconditionally, for the same reason `selectorResultInput` and `allowedCallerPermissions` do: the trusted property depends on the called workflow's own steps, which sit outside the compared surface. A human must review the new SHA's content and add a new contract entry. Hosted-only contracts keep their existing eligibility because their secrets stay bound to the fixed hosted runner recorded in the reviewed contract. | `resolveAutoApprovedContracts`'s secret-capable decline in [`runner-policy.mjs`](runner-policy.mjs); secret-capable contract decline case in [`runner-policy.test.mjs`](runner-policy.test.mjs). |
| A Dependabot SHA bump of a workflow reviewed under a privileged `allowedCallerPermissions` grant (an exact caller permission and secret boundary that lets a job reach a self-hosted runner despite elevated permissions) changes what the workflow's steps do with that grant — for example exfiltrating an `id-token`-derived credential or misusing a `pull-requests: write` grant — while every field this diff compares (declared permissions, routing, and credential *references*) stays identical, because the diff never inspects step bodies for content. Auto-approval would then silently extend an already-reviewed privileged grant to unreviewed executable content. | Any reviewed contract carrying `allowedCallerPermissions` declines auto-approval unconditionally regardless of surface match, for the same reason `selectorResultInput` does: the property being trusted depends on the called workflow's own steps, which sit outside the compared surface, and here the trusted property is a privileged permission and self-hosted-reachability grant rather than a required-check result. A human must review the new SHA's content and add a new contract entry. | `resolveAutoApprovedContracts`'s unconditional `allowedCallerPermissions` decline in [`runner-policy.mjs`](runner-policy.mjs); allowedCallerPermissions-contract case in [`runner-policy.test.mjs`](runner-policy.test.mjs). |

The detailed operational contract and current approved references live in the
[component README](README.md) and [`policy.json`](policy.json); this model does
not duplicate those changing inventories.

## Residual and accepted risk

- Standards maintainers must independently review the bytes behind an
  external path-at-SHA before it becomes the first `approvedReusableWorkflowContracts`
  entry for that workflow path; a compromised remote repository or incorrect
  review remains a supply-chain risk. Auto-approval never substitutes for
  this initial review — it only extends an already-reviewed, structurally
  identical security surface to a later SHA of the same workflow path, and it fetches
  the diffed bytes fresh from the source repository at audit time rather than
  trusting a cached or asserted copy.
- The auto-approval fetch depends on `raw.githubusercontent.com` availability.
  A network outage or block does not approve an unreviewed candidate; the
  audit fails closed on the fetch error, the same as an unreviewed reference.
  Repositories that want zero audit-time network access can set
  `disableAutoApproval`/`CI_RUNNER_POLICY_DISABLE_AUTO_APPROVAL=true`.
- Credential detection is conservative static analysis, not shell or action
  semantic evaluation. A novel credential-minting action, obfuscated script, or
  GitHub feature may evade a specific pattern. Least `GITHUB_TOKEN` permissions,
  immutable action review, code review, and updates to `localCredentialActions`
  remain necessary.
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
- A pull request can change the analyzer, policy, and tests together. Required
  review, branch governance, pinned CI dependencies, and review of reduced
  negative coverage are repository controls outside the analyzer itself.
- GitHub Actions expression and reusable-workflow semantics can evolve after a
  passing audit. The policy proves only the modeled syntax and reviewed
  platform behavior, not all future control-plane interpretation.
- The literal hosted fallback preserves scheduling availability but spends
  hosted capacity and does not make a failed selector healthy. Operational
  monitoring must still surface selector failures.
- The zero-cost rejection sentinel intentionally delays terminal failure until
  GitHub's 24-hour unmatched self-hosted queue limit. Its safety also depends on
  the external runner inventory never assigning `ci-runner-selection-failed`;
  the one-minute timeout only bounds execution after an accidental assignment.

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
- [GitHub `GITHUB_TOKEN` permissions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#setting-the-permissions-of-the-github_token-for-a-repository)
