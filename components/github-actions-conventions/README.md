# GitHub Actions naming and structure conventions

The one source for how Melodic Software names GitHub Actions workflow files,
workflow `name:` values, job ids, composite action directories, activities and
GitHub Apps. `naming-lint.mjs` checks a repository against it. Rules that
another component already owns are linked under
[Rules owned elsewhere](#rules-owned-elsewhere), not restated here.

| File | Role |
| --- | --- |
| [`vocabulary.json`](vocabulary.json) | Stages, function words per stage, verbs, tool and engine names, the activity grammar, exemptions and Apps |
| [`vocabulary.schema.json`](vocabulary.schema.json) | Draft 2020-12 schema for the vocabulary |
| [`rename-map.json`](rename-map.json) | Every workflow and composite action rename across the active repositories, with job id renames and couplings |
| [`rename-map.schema.json`](rename-map.schema.json) | Draft 2020-12 schema for the rename map |
| [`naming-lint.mjs`](naming-lint.mjs) | The analyzer |
| [`naming-lint.test.mjs`](naming-lint.test.mjs) | Behavioral tests, schema validation, and the check that this README's stage table matches the vocabulary |

The vocabulary holds names only. Which slots a pull request pipeline runs, and
in what order, belongs to the pipeline model, which refers to these names and
defines none.

## Workflow files

A workflow file is named `<stage>-<function>[-<modifier>].yml`, in kebab-case.

- **Stage** is one word from the fixed list below.
- **Function** is verb-first and literal: it says what the workflow does, with
  no metaphors (`check-managed-files`, not `managed-files-guard`). The allowed
  function words per stage are in `vocabulary.json` under `functions`; a word
  marked `reserved` belongs to a planned lane. A new function word is added to
  the vocabulary in the same change that introduces it.
- **Modifier** is optional and narrows the function (`pr-run-checks-go`,
  `release-deploy-tailscale-acl`).
- A workflow is named for its purpose, not the tool it runs
  (`pr-audit-workflows`, not `zizmor`).

<!-- stages:begin -->
| Stage | Purpose |
| --- | --- |
| `intake` | Classify and label incoming issues and requests. |
| `plan` | Turn accepted work into a plan before implementation starts. |
| `work` | Do the work outside a pull request, such as answering a mention. |
| `pr` | Run on a pull request until it merges. |
| `post-merge` | Check the default branch after a merge. |
| `release` | Tag, publish and deploy. |
| `maintenance` | Scheduled upkeep: sync, repin, audits and scans. |
| `upstream` | Track and take in changes from upstream sources. |
<!-- stages:end -->

The workflow's `name:` equals the file stem. A caller of a reusable workflow
takes the reusable's file name.

## Jobs and check names

GitHub names a check `<caller job name or id> / <called job name or id>`; the
workflow `name:` and file name never appear in it. So:

- A caller job id is the full slot name: the job calling `pr-review.yml` is
  `pr-review`.
- A job inside a reusable workflow is named for the engine or unit it runs:
  `claude`, `check-linux`. Checks then read `<slot> / <unit>`, for example
  `pr-review / claude`.
- Every other job id and every activity name is kebab-case and verb-first
  (`check-links`, `build-and-test`), and does not start with a stage word. Two
  exceptions: a job that runs exactly one tool keeps the tool's name
  (`shellcheck`), and a review-engine unit is named for the engine only
  (`claude`, `codex`, `bugbot`).
- An activity may carry one mode after `#`, from the pairs in
  `activityGrammar.modes` (`simplify#diff`, `fix-docs#report`).

`ci-status` is the only required check in every repository and keeps that name
everywhere. The gate workflow, `pr-require-checks.yml`, aggregates every lane
into it. Lanes are added or renamed behind it without touching a ruleset.

## Composite actions

- An action used by exactly one multi-unit lane lives at
  `.github/actions/<lane>/<unit>/`, where `<lane>` is the lane's slot name
  (`pr-require-checks/aggregate-results`).
- A single-unit lane action or an action shared by several lanes stays flat
  and verb-first (`check-managed-files`, `report-lane-outcome`).
- An action that wraps one tool keeps the tool's name (`markdownlint`,
  `psscriptanalyzer`).

## Settings a called workflow does not inherit

A reusable workflow is not configured by its caller's top-level settings. Set
these in each workflow that needs them:

- The called workflow's own top-level `concurrency` block applies when it is
  called. Put the concurrency block in the workflow that should own the group;
  a reusable that its callers run inside their own group carries none.
  [concurrency-policy](../concurrency-policy/README.md#what-it-checks) checks
  the caller's block and leaves reusable workflows out of its scope.
- The caller's `defaults.run.shell` does not reach the called workflow's
  steps. Set `defaults.run.shell` (or `shell:` per step) in the reusable
  itself.

Both were confirmed on github.com.

## Renaming a workflow, job or action

A rename is a change to every place that names the old path or id. Before
renaming, find each of these and change it in the same rollout:

1. **Required checks.** Renaming a required job (its caller id or the called
   job's `name:`) blocks every merge while all checks show green: GitHub
   reports no pending check, and the only API signal is
   `mergeStateStatus: BLOCKED`. Keeping `ci-status` the single required check
   makes file and lane renames safe; never rename `ci-status`.
2. **Runner policy.** The runner-policy contract approves reusable workflows by
   `path@SHA` and fails closed on an unknown path. A renamed reusable needs its
   new path approved before any consumer pins it.
3. **Synced files.** The standards sync never deletes a file. When a synced
   destination moves, the sync change for each target also deletes the old
   path, or both copies run.
4. **`workflow_run` triggers** are keyed on the triggering workflow's `name:`.
   Changing that `name:` silently stops them; update `workflows:` in the same
   change.
5. **Ghost runs.** A renamed file gets a new workflow id with empty history.
   The old id stays reachable through the API as `deleted` while it has runs;
   delete those runs once no branch or open pull request still carries the old
   file.

[`rename-map.json`](rename-map.json) records the approved renames and the
couplings each one touches. The tests check that every target passes the
lint. They cannot check that the map is complete, because the other
repositories are not available to them: run naming-lint in enforcing mode on
each repository, and every blocking finding must have an entry in the map.

## Lane configuration

Structured configuration for a lane or other concern lives in a dedicated YAML
file at `docs/conventions/<concern>.yaml`, validated against a JSON Schema,
next to its prose `docs/conventions/<concern>.md`. This supersedes
claude-code-plugins ADR 0044 for structured configuration.

## GitHub Apps

An organization GitHub App is named in literal, lowercase kebab-case that says
what it does. The Apps in use are listed under `apps` in `vocabulary.json`.

## Exemptions

The complete list is `exemptions` in `vocabulary.json`. It holds one entry:
github-iac's OIDC negative test, `release-deploy-oidc-negative-test.yml`,
whose `name:` is `release-deployx`: the deploy workflow's name plus one
character, so the identity policy that trusts `release-deploy` must reject it.
GitHub's dynamic workflows (Dependabot, CodeQL default setup, Pages) need no
entry: they have no file in `.github/workflows/`.

Any other exception is added to that list with its reason, scoped to one
repository where it applies to one.

## Rules owned elsewhere

| Rule | Owner |
| --- | --- |
| Runner labels and reusable workflow approval by `path@SHA` | [runner-policy](../runner-policy/README.md) |
| The top-level `concurrency` block of pull-request workflows | [concurrency-policy](../concurrency-policy/README.md) |
| The `# vX.Y.Z` comment on SHA-pinned `uses:` lines | [pin-comment-convention](../pin-comment-convention/README.md) |
| Dependabot configuration for Actions and package roots | [dependabot-policy](../dependabot-policy/README.md) |
| The `## Code Review Rules` section in `AGENTS.md` | [code-review-rules](../code-review-rules/README.md) |
| Synced Claude review lane callers | [claude-lanes](../claude-lanes/claude-review.yml), [claude-lanes-hosted](../claude-lanes-hosted/claude-review.yml) |
| Blocking hand edits to sync-managed files | [managed-files-guard](../managed-files-guard/README.md) |

## naming-lint

Read-only: it reports findings and sets the exit status. It never edits a
file.

```sh
npm ci --prefix components/github-actions-conventions
node components/github-actions-conventions/naming-lint.mjs --root . --mode advisory
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--root` | current directory | Repository to check |
| `--mode` | `advisory` | `advisory` reports every finding as a warning and exits 0; `enforcing` keeps errors as errors and exits 1 when any remains |
| `--format` | `github` when `GITHUB_ACTIONS=true`, else `text` | `github` prints workflow annotations; `json` prints `{ mode, ok, findings }` |
| `--repository` | `$GITHUB_REPOSITORY` | `owner/name`, used to apply repository-scoped exemptions |
| `--vocabulary` | the bundled `vocabulary.json` | Vocabulary file to check against |

Exit status 2 means bad arguments, or a missing or invalid vocabulary or
vocabulary schema.

It checks top-level `.github/workflows/*.yml` and `*.yaml` files and every
directory under `.github/actions/` that holds an `action.yml` or
`action.yaml`:

| Rule | Level | Fails when |
| --- | --- | --- |
| `workflow-filename` | error | the file stem is not `<stage>-<function>[-<modifier>]` with a known stage and function word |
| `workflow-name` | error | `name:` is missing or differs from the stem (or from a recorded exception) |
| `workflow-unparsable` | error | the file is not a YAML mapping |
| `gate-ci-status` | error | `pr-require-checks` has no `ci-status` job |
| `job-id-kebab` | error | a job id is not kebab-case |
| `job-id-stage-word` | warning | a job id starts with a stage word but is not a known slot name |
| `job-id-verb-first` | warning | a job id is not verb-first and is not a listed tool, engine or reserved id; whether a word is a verb cannot always be decided, so this never blocks |
| `action-directory` | error | an action directory is not kebab-case, not verb-first, an engine or a listed tool, or not a `<lane>/<unit>` pair under a slot name |

`checkActivityName` and `parseSlotName` are exported for tools that validate
activity and slot names outside workflow files.

### Rollout

The analyzer starts in advisory mode, following the
[enforcement rollout](../../docs/component-lifecycle.md#enforcement-rollout).
The standards CI runs it advisory over this repository and writes the findings
to the step summary. ci-workflows wraps it, in advisory mode until the renames
in `rename-map.json` land there, then enforcing. The switch to enforcing is
tracked in [#672](https://github.com/melodic-software/standards/issues/672),
due 2026-11-30. Baseline on ci-workflows at `7f03272` (2026-10-03): 49 findings,
31 of them blocking in enforcing mode.

### Ownership and operation

- **Owner:** the standards maintainers own the conventions, vocabulary and
  analyzer; each consumer owns its wrapper and its renames.
- **Outcome:** every workflow, job and action in a consumer passes
  `--mode enforcing`, so check names read `<slot> / <unit>` and `ci-status`
  stays the only required check.
- **Rollback:** switch the consumer's wrapper back to `--mode advisory`, or
  remove the wrapper job. Nothing else reads the analyzer's output.
- **Failure behavior:** read-only over `.github/`, no network or credentials,
  `contents: read` only. An unparsable workflow is a `workflow-unparsable`
  finding; bad arguments or a bad vocabulary exit 2.
