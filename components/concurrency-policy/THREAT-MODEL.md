# Concurrency-policy threat model

This model covers the read-only analyzer in
[`concurrency-policy.mjs`](concurrency-policy.mjs), its repository exception
schema, and the workflow and exception configuration it evaluates. The GitHub
Actions control plane and the runner fleet are external systems. Their behavior
is modeled where it crosses this analyzer's boundary, but this component does
not operate or attest to them.

The model follows OWASP's maintained threat-modeling loop: describe the system,
identify what can go wrong, map concrete responses, and validate the result.

## Security objectives and assets

- Every pull-request-triggered workflow supersedes its own in-flight run so a
  force-push or rapid re-push cannot fan out redundant runs that exhaust runner
  capacity.
- A push to the default branch or a scheduled run is never cancelled by another
  run of the same workflow.
- A concurrency group cannot be widened into a cross-pull-request or
  cross-fork collision through a fork-controllable branch name.
- The exception inventory cannot become a blanket bypass or outlive the
  condition it records.
- Findings fail the CI gate clearly without modifying any workflow or setting.

The protected assets are runner-fleet capacity and scheduling fairness,
default-branch and scheduled-run completion, and the integrity of the exception
inventory.

## Actors and trust boundaries

- A repository maintainer changes governed workflows and the exception file and
  reviews findings.
- A pull-request contributor may control workflow YAML, including the `on:`
  trigger set and any `concurrency` block, and — on `pull_request_target` — the
  head branch name.
- Standards maintainers review the analyzer and the exception schema, including
  the approved-reason set.
- GitHub later evaluates the accepted workflow and runs the concurrency control
  plane. That behavior crosses an external boundary.

Checked-in `.github/concurrency-policy.json` and `.github/workflows/*.yml` are
untrusted subjects of the audit. The analyzer and its schema are trusted only at
their reviewed Git revision.

## Data flow

1. The caller selects a repository root and an optional exception file path.
2. The pinned YAML parser preflights the exception JSON with unique object
   members required; `JSON.parse` remains the JSON syntax authority. Ajv then
   validates it against the strict Draft 2020-12 schema. A missing file yields
   an empty, most-strict exception set.
3. The analyzer indexes regular top-level workflow YAML files, rejects workflow
   symlinks, and parses with aliases and merge keys disabled, strict parsing,
   and unique keys required.
4. For each pull-request-triggered workflow it checks the top-level concurrency
   group and cancellation flag, and it confirms every declared exception is
   consumed by a workflow that actually needs it.
5. Findings and the process exit status cross back to CI. No workflow file,
   GitHub setting, or run is changed.

## Threats, controls, and evidence

| Threat | Control | Executable evidence |
| --- | --- | --- |
| A superseded pull-request run keeps a runner slot while a newer push queues behind it. | Pull-request-triggered workflows must carry the canonical group and `cancel-in-progress: true`; a missing block, drifted group, or absent cancellation is a finding. | Missing, group-drift, cancel-missing, and shorthand cases in [`concurrency-policy.test.mjs`](concurrency-policy.test.mjs). |
| A group keyed on `github.ref` cancels a default-branch or scheduled run. | The canonical group falls back to the unique `github.run_id` on non-pull-request events; a `github.ref` group is reported as drift. | The `github.ref` drift case over a push-and-pull-request workflow in [`concurrency-policy.test.mjs`](concurrency-policy.test.mjs). |
| A fork-controllable `head_ref` group collides across same-named branches, and one pull-request run cancels another. | The canonical group uses the unique, non-fork-controllable `github.event.pull_request.number`; the `head_ref` variant is reported as drift. | The `head_ref` drift case in [`concurrency-policy.test.mjs`](concurrency-policy.test.mjs). |
| A non-literal `cancel-in-progress` expression silently disables cancellation. | Only the literal boolean `true` passes; `false`, an omitted flag, and an expression string are findings rather than crashes. | The false, omitted, and expression `cancel-in-progress` cases in [`concurrency-policy.test.mjs`](concurrency-policy.test.mjs). |
| YAML ambiguity hides a different workflow graph. | The parser requires unique keys, disables aliases and merge keys, and records parse failures. Only regular top-level workflow files are indexed; symlinks are findings. | Duplicate-key and workflow-symlink cases in [`concurrency-policy.test.mjs`](concurrency-policy.test.mjs). |
| Duplicate JSON member names make the exception file interpretation-dependent. | The raw exception file is preflighted with the pinned parser's strict unique-key mode before `JSON.parse`, per the interoperability guidance in [RFC 8259 section 4](https://www.rfc-editor.org/rfc/rfc8259#section-4). | The duplicate-member case in [`concurrency-policy.test.mjs`](concurrency-policy.test.mjs). |
| An exception becomes a blanket bypass or outlives its cause. | Exceptions are keyed to one workflow, use an allowlisted reason with a justification, and fail on an unused, non-pull-request, or already-conformant target. | The unknown-reason, missing-justification, unknown-key, and inventory-drift cases in [`concurrency-policy.test.mjs`](concurrency-policy.test.mjs). |
| A change weakens validation unnoticed. | The schema rejects unknown shapes and reasons; the runtime is exactly locked; CI runs the behavioral tests and then audits this repository. | [`concurrency-policy.schema.json`](concurrency-policy.schema.json), [`package-lock.json`](package-lock.json), and the `concurrency-policy` CI job. |

## Residual and accepted risk

- The analyzer proves only the modeled workflow syntax. GitHub Actions
  concurrency semantics can change after a passing audit; the standard tracks
  reviewed platform behavior, not all future control-plane interpretation.
- Concurrency is one capacity control. It prevents redundant runs of the same
  workflow but does not bound the number of distinct workflows, jobs, or matrix
  legs a change triggers. Those remain separate volume controls.
- Job-level concurrency inside a reusable workflow is out of scope here; a
  `delegated-job-level` exception records that the enforcement lives in the
  called workflow, which is reviewed on its own.
- A pull request can change the analyzer, schema, and tests together. Required
  review, branch governance, and pinned CI dependencies are repository controls
  outside the analyzer itself.

A risk acceptance is recorded in the owning repository with scope, owner,
compensating controls, and a review trigger; no exception file entry accepts
these model-level risks.

## Review triggers

Re-run this threat model when the analyzer accepts a new concurrency expression
form, a new exception reason, or a new trigger classification; when GitHub
changes concurrency, `github` context, or reusable-workflow semantics; when the
schema version changes; or after an incident where a superseded or cancelled run
crossed the pull-request/default-branch boundary.

Each review confirms the data flow, adds a negative test for every new failure
mode, and updates residual risk instead of merely widening the allowlist.

## External authorities

- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [GitHub control of workflow concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
- [GitHub `github` context reference](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts)
- [RFC 8259, The JavaScript Object Notation (JSON) Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
