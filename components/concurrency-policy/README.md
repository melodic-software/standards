# Workflow concurrency policy

This module is the enforceable contract for GitHub Actions workflow
concurrency. It parses workflow YAML and checks that every
pull-request-triggered workflow carries an accepted top-level `concurrency`
block, so a superseding push to a pull request cancels the in-flight run before
it consumes a runner slot. Whether a push to the default branch or a scheduled
run can be superseded is the fallback term's job, and that term is a
per-repository decision the analyzer reports rather than dictates.

It is read-only: it reports findings and sets the process exit status. It never
edits a workflow, opens a pull request, or changes any GitHub setting.

In this source repository, run it from the repository root:

```sh
node components/concurrency-policy/concurrency-policy.mjs --root .
```

The distributed component lives at `.github/standards/concurrency-policy/` and
owns its own `package.json` and lockfile with exact `ajv` and `yaml` runtime
pins. `concurrency-policy.schema.json` is the Draft 2020-12 structural authority
for the repository exception file; Ajv compiles it in strict mode. Consumers
install and invoke that dependency root directly:

```sh
npm ci --prefix .github/standards/concurrency-policy
node .github/standards/concurrency-policy/concurrency-policy.mjs --root .
```

## The two accepted group forms

Every pull-request-triggered workflow (`on:` includes `pull_request` or
`pull_request_target`) must declare a top-level `concurrency` block whose
`group` is one of exactly two forms: the canonical form below, or the ci-perf
branched form in the section after it. `cancel-in-progress` is checked
independently of which form the `group` takes.

## The canonical block

The canonical form is:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: true
```

`github.workflow` keys the group per workflow. `github.event.pull_request.number`
supersedes an in-flight run of the same pull request, so a force-push or a rapid
second push cancels the prior run instead of queueing a second one. That number
is empty on `push` and `schedule` events, so those runs fall back to the unique
`github.run_id` and are never cancelled: a default-branch or scheduled run is
never superseded by another.

The pull-request number, not `github.head_ref`, is deliberate. Both satisfy the
"never cancel push or schedule" invariant, because `github.head_ref` is defined
only on `pull_request` and `pull_request_target` events and is empty otherwise.
But `head_ref` is a fork-controllable branch *name*: two pull requests from
different head repositories that share a branch name collide in the same
concurrency group, and one cancels the other. On `pull_request_target`, which
runs with the base repository's token, that collision is attacker-influenced.
The pull-request number is unique per repository and is not fork-controllable,
so it avoids the collision while keeping the identical push/schedule safety.
GitHub's own documentation presents the `head_ref || run_id` form as the general
example; this standard tightens it to the number for that reason.

Internal expression whitespace is tolerated in the `group` (`${{github.workflow}}`
and `${{ github.workflow }}` are equivalent), and YAML quoting is transparent
after parsing. The token order and identity are exact.

## The ci-perf branched group

The second accepted form branches the group on the contract-only predicate:

```yaml
concurrency:
  group: >-
    ${{ (github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base)))
        && format('ci-contract-{0}-{1}', github.event.pull_request.number, github.run_id)
        || format('{0}-{1}', github.workflow, github.event.pull_request.number || github.run_id) }}
  cancel-in-progress: true
```

Two runs of one required workflow on one head SHA otherwise share a single
concurrency group, and GitHub cancels a pending run in that group
unconditionally when a newer run arrives, whatever `cancel-in-progress` says. A
contract-only run evicted while pending starts no job, so its check suite never
receives the required check run and the pull request stops reporting until
someone re-runs that specific run. The branched group removes that: the
contract-only branch carries `github.run_id`, so every contract-only run has a
group of its own and can neither be evicted nor evict anything. It costs a burst
of one-job runs when labels flip repeatedly.

The full branch keeps the canonical shape, and its **fallback term is a
per-repository decision** rather than drift. Only two terms are admitted, and
they mean different things for `push` and `schedule` runs, where the
pull-request number is empty:

| Fallback term | Meaning |
| --- | --- |
| `github.ref` | Push-side burst collapse is kept: consecutive pushes to one ref land in one group, and with `cancel-in-progress: true` a newer push supersedes the in-flight run. |
| `github.run_id` | No push-side collapse: every push and scheduled run lands in its own group and is never superseded. |

Because both are legitimate, the analyzer reports the term it found as an
**informational** finding (`concurrency-group-fallback`, `level: "info"`) that
never fails the gate, so a fleet check can list which repositories keep push
collapse. The canonical form reports the same finding with `github.run_id`,
which is the fallback it carries by construction.

Whitespace is tolerated only at the two operator joins and inside the `${{ }}`
delimiters, which is exactly where the folded scalar above differs from the same
expression written on one line. Written as `group: >-` with the continuation
lines more-indented, the YAML parser preserves a newline and the continuation
indent at each join, so both spellings reach the analyzer as one string and both
are accepted. Everything else is exact: the predicate is compared byte for byte
against the same canonical string `cancel-in-progress` uses, the contract branch
must carry `github.run_id`, and a fallback term outside the two above is
`concurrency-group-drift`.

This form is the Phase 6b decision of the ci-perf program, tracked at
[melodic-software/github-iac#378](https://github.com/melodic-software/github-iac/issues/378).
It is admitted here before the consumer repositories adopt it, because this
component is the gate every one of those changes has to pass.

## The ci-perf contract-only shape

`cancel-in-progress` accepts one alternative to the literal `true`, and only
one:

```yaml
cancel-in-progress: ${{ !(github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))) }}
```

A workflow whose required check carries the pull-request contract also runs on
`edited`, `labeled` and `unlabeled` — events that change the contract answer
without a new commit. Those runs gate every lane off and carry the recorded lane
verdict forward instead of re-running the lanes, so such a run must never cancel
the full run it reads that verdict from: cancelling it means the verdict is
never recorded and the carry-forward can only fail. Expressed as
`!(<contract-only predicate>)`, cancellation stays on for every full-run event —
including `synchronize`, which still cancels everything on the superseded SHA —
and switches off only for the events that carry forward. On `push` the predicate
is false, so the value is `true` exactly as before.

The predicate is the `contract-only` default of the `ci-status` composite action
in `melodic-software/ci-workflows` at `.github/actions/ci-status`, tag `v0.20.0`.
The two must agree: if the workflow's copy drifted, the lanes would gate off
while the composite still resolved `contract-only` false and aggregated a set of
`skipped` results. Because agreement is the whole point, this value is compared
byte for byte — the whitespace tolerance the `group` enjoys does not apply, and
any other expression, including a reformatted or reordered copy of this one, is
`concurrency-cancel-missing` as before. The accepted set is exactly two values:
the literal `true` and the string above.

This text is kept for repositories that have not yet been reshaped onto the
branched group. A repository that has moves to a plain `cancel-in-progress: true`,
because the branched group already isolates every contract-only run and a
non-literal flag no longer buys anything. Both remain accepted, so the fleet can
migrate one repository at a time.

## What it checks

For each pull-request-triggered workflow that is not excepted:

- `concurrency-missing`: no top-level `concurrency` block.
- `concurrency-group-drift`: the `group` is neither the canonical expression nor
  the ci-perf branched form (for example `${{ github.workflow }}-${{ github.ref }}`,
  which lets two default-branch or scheduled runs cancel each other; the
  `head_ref` variant above; a branched group whose predicate differs from the
  canonical string by one byte; a fallback term other than `github.ref` or
  `github.run_id`; or a contract branch that omits `github.run_id`).
- `concurrency-group-fallback`: informational, never blocking. Names the group
  form and the fallback term the workflow carries, so a fleet check can list
  which repositories keep push-side burst collapse. It is the only `info`-level
  finding; the command line prints it on stdout and still exits `0`, and
  `--json` reports `"ok": true`.
- `concurrency-cancel-missing`: `cancel-in-progress` is neither the literal
  `true` nor the ci-perf contract-only expression above.
- `concurrency-malformed`: `concurrency` is neither a group string nor a
  mapping.
- `concurrency-extra-keys`: the block carries a key other than `group` and
  `cancel-in-progress` (for example `queue`), so it is not the exact canonical
  shape.

Reusable workflows (`on: workflow_call`) and workflows triggered only by
`push`, `schedule`, or `workflow_dispatch` are out of scope: a called workflow's
concurrency is the caller's concern, and a workflow that never runs on a pull
request has no superseding-pull-request run to cancel.

## Exceptions

A pull-request-triggered workflow that deliberately omits the top-level block
records the reason in a locally owned `.github/concurrency-policy.json`:

```json
{
  "schemaVersion": 1,
  "exceptions": {
    ".github/workflows/claude-review.yml": {
      "reason": "delegated-job-level",
      "justification": "The reusable it calls already supersedes in-flight runs at job level; a caller-level group of the same name would deadlock the called job."
    }
  }
}
```

The only approved `reason` is `delegated-job-level`: concurrency is enforced
inside a reusable workflow at job level, and a caller-level group would deadlock
the called job. Every exception carries a free-text `justification`. Unknown
reasons, unknown keys, and a missing justification fail closed at schema time. An
exception that names a workflow that does not exist, is not
pull-request-triggered, or already carries the canonical block is reported as
`exception-inventory-drift`, so the inventory cannot silently widen or rot.

The file is optional: a repository whose pull-request workflows are all
canonical needs no configuration, and its absence declares no exceptions,
the strictest stance.

## Enforcement gate

The gate installs the component's locked runtime and runs the analyzer against
the repository. In this repository the `concurrency-policy` CI job does exactly
that; a consumer adds the equivalent job in its own integration change:

```yaml
concurrency-policy:
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
        cache-dependency-path: .github/standards/concurrency-policy/package-lock.json
    - run: npm ci --prefix .github/standards/concurrency-policy
    - run: node .github/standards/concurrency-policy/concurrency-policy.mjs --root .
```

The security boundaries, fail-closed behavior, and review triggers are in the
[threat model](THREAT-MODEL.md).
