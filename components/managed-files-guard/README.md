# managed-files-guard caller

Sync-managed caller for the `check-managed-files` composite action in
`melodic-software/ci-workflows`
(`.github/actions/check-managed-files`, ci-workflows#208). The action reads
this repository's `distribution/sync-manifest.yml` at a given ref, resolves
the calling repository's managed destination paths, and fails the pull
request when its diff touches one of them. That failing check is the signal
ADR-0007 assigned to a downstream hand-edit of a managed file
(`docs/adr/0007-keep-the-managed-file-seam-binary.md`): the seam stays
binary, the fix path is always a standards change, and the guard is what
makes a hand-edit visible before the next sync silently reverts it.

Two files, one per `runner-policy` inventory, identical except for `runs-on`,
the workflow `name:` (each equals its destination stem) and their headers:

| Manifest component | Source | Destination | `runs-on` |
| --- | --- | --- | --- |
| `managed-files-guard-caller` | `managed-files-guard.yml` | `.github/workflows/pr-check-managed-files-hosted.yml` | `ubuntu-24.04` |
| `managed-files-guard-fleet-caller` | `managed-files-guard-fleet.yml` | `.github/workflows/pr-check-managed-files.yml` | `melodic-ubuntu-24.04-x64` |

Both carry the same action pin and the same job name, so the check context is
`pr-check-managed-files` on every target. The destinations differ because the
manifest requires each destination to have one owning component.
The guard caller is the second recorded exception to the rule that workflow callers stay
consumer-owned (`distribution/README.md`), for the same reason as the Claude
review-lane callers: a fleet-wide guard is only a signal if every target runs
the same caller at the same pin, and the sync is the one mechanism that holds
that.

## Rollout: advisory first, one caller per runner inventory

**Advisory soak.** The check is not aggregated into any target's `ci-status`
and is not a required context anywhere. It runs on every pull request that
touches a managed path (see "Path filter" below), reports, and blocks nothing. This follows the action's own contract
("advisory-first: wire into ci-status only after a clean soak") and the
enforcement-rollout steps in `docs/component-lifecycle.md`: observe against
the live consumers, classify every finding, then promote per target once the
baseline is understood. Promotion is a per-target decision, taken in that
target's own `ci-status` wiring after its soak is clean; nothing in this
component promotes. The soak and the promotion decisions are operator-owned
after the admitting pull request (standards#496); that issue is the record
until each target's promotion lands. Promotion must also decide whether the
action's `dependabot[bot]` actor skip stays: under it, a Dependabot pull
request that edits a managed destination passes the guard rather than reds
it, and the next sync reverts the edit; the durable fix is the action
absorbing the consumer
checkout, which needs a ci-workflows release.

**Hosted caller.** `managed-files-guard.yml` runs on `ubuntu-24.04`
directly. `runner-policy` admits that shape on a public repository and on a
private repository not enrolled for local CI routing. It is managed for
`melodic-software/.github`, `agent-plugins`, `ci-runner`,
`claude-code-account-rotation`, `claude-code-plugins`, `codex-plugins`, and
`cursor-plugins`, all public. `claude-code-plugins` is the one consumer here
that also executes the `runner-policy` gate;
`components/runner-policy/runner-policy.test.mjs` asserts this caller audits
clean under a public hosted-only inventory so the sync cannot red that
target's `ci-status`.

**Fleet-routed caller.** `managed-files-guard-fleet.yml` runs on the managed
fleet label `melodic-ubuntu-24.04-x64`. It is managed for the private targets
enrolled for local CI routing: `claude-code-proxy`, `dotfiles`, `github-iac`,
`medley`, and `provisioning`. On a routing-enrolled repository,
`runner-policy` requires every eligible read-only job either to name the
managed fleet label or to carry a reviewed hosted exception, so a fixed
`runs-on: ubuntu-24.04` job fails the gate there, and the fleet label is
refused on a public repository. `runner-policy.test.mjs` asserts the sibling
audits clean on each managing target and is refused on a public consumer.
`claude-code-proxy` runs no `runner-policy` gate today, but it is
fleet-enrolled in github-iac and its CI already runs on the fleet label.

The contract test holds the boundary mechanically: a target that manages a
`components/claude-lanes/`-sourced caller must manage the fleet-routed guard
and not the hosted one, and no target manages both.

The sync never deletes a file. `claude-code-proxy` managed the hosted caller
before the fleet-routed one existed, so its old
`.github/workflows/managed-files-guard.yml` stays until a one-time
claude-code-proxy pull request deletes it. Until then both workflows there
share the name `managed-files-guard` and so one concurrency group, and each
pull request event cancels one of the two runs.

**Locally owned by `ci-workflows`.** ci-workflows hosts the action and
already runs the guard as a job of its own `ci.yml`, through a `./` action
reference that resolves to the commit under test. A synced caller pinned to
an older commit would run the guard twice per pull request, once at each
revision, so ci-workflows carries the component `locally-owned`. Removal
trigger: ci-workflows retiring its in-repo job in favor of the synced caller.

`standards` is the manifest source, not a target, and carries no caller.

## Path filter

The action fails only when the diff touches an exact managed destination
path (`run.sh` in the action: `git diff --name-only` checked against the
engine's `dest-paths` set). Each caller therefore carries
`on.pull_request.paths` set to the sorted union of the `dest-paths` of every
target that receives that caller, its own destination included, so a pull
request that touches no managed path starts no job. The hosted caller lists
only hosted targets' destinations and the fleet-routed caller only
fleet-routed targets', so neither names the other's workflow files
(standards#698). The list is a union, not a per-target set, because one file
ships byte-identical to every target that receives it; on a target that does
not manage a listed path, a match runs the guard and it passes. `types` restates GitHub's documented default (`opened`,
`synchronize`, `reopened`).

The contract test computes the union through the engine and requires the
list to equal it, so a manifest change that adds, moves or drops a
destination fails CI here until both callers follow in the same pull
request; the next sync then delivers the new list together with the new
file. A required check could not take this filter (a workflow skipped by
`paths` leaves its check pending), which is one more thing promotion has to
decide; today only `ci-status` is required on any target.

Known gaps, both fail-open on an advisory check: GitHub skips a filtered
workflow when the diff exceeds 3,000 files and no match is among the first
3,000
([workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#git-diff-comparisons));
and between a standards merge that adds a destination and that target's sync,
the consumer's caller still carries the old list.

## The two pins

**The action pin** is a full 40-character commit SHA of ci-workflows `main`,
under the `pin-comment-convention` (`components/pin-comment-convention/`).
Both files pin `.github/actions/check-managed-files` at
`cf316d12b4a14fbdb96a339b7ad00ce935a8cad4` (v0.38.2) today. v0.34.0
(`7446b51`) gave the action that path; the pins below name its old path,
`.github/actions/managed-files-guard`. The pin moves with each ci-workflows release through the cascade below.
The earlier pins are recorded because of what they fixed:
`2c1de45aa0e1b1489afb8edfebc12cb3a4fa6ac3` (v0.24.0) superseded
`5776760254f8b63cba44e896f51604cb755350d9` (v0.22.2), which in turn
superseded `3b2f4eab5b4bb58a150e400613350ede37742ee8` (2026-08-30,
ci-workflows#530), the commit that closed the guard's fail-open on an
unreadable diff: before it, an unfetched or bogus ref produced an empty change
list and the guard passed precisely when it could not see the diff. No release
carried that commit when this component was admitted (the newest, v0.17.2, is
2026-08-21), so the comment took the convention's short-SHA fallback form until
a release contained it; v0.22.2 was the first release that did, and the pin has
carried the release-tag comment form since. Between v0.22.2 and v0.24.0
`.github/actions/managed-files-guard/action.yml` changed once (verified through
the compare API), in ci-workflows `3c23f69e4248700c3636cabd49f1d5c888284444`
(ci-workflows#568). It adds a `'dependabot[bot]'|dependabot` arm to the actor
`case`, so both the bracketed login and the bare name now skip the hand-edit
check; a Dependabot bump that edits a pinned action inside a standards-managed
file reds the guard without it. It also **quotes** the existing
`melodic-standards-sync[bot]` pattern, which is a behavior change, not
cosmetics: unquoted, bash parsed `[bot]` as a glob character class matching a
single `b`, `o` or `t`, so that arm never matched the bot login at all. It was
masked by the sibling `standards-sync` label check, which skipped sync-bot PRs
through the label path; quoting turns a dead arm live. Nothing else the guard
executes moved. v0.30.1 (ci-workflows#634) installs the standards tree's
`.node-version` with SHA-pinned `actions/setup-node` before `npm ci`: the fleet
caller's self-hosted runners ship no Node, so the guard failed there with
`npm: command not found`.

**`standards-ref: main`** for the soak, per the action's input contract
("Pin to a full SHA in callers once soak completes"). The guard must read the
manifest that is live for the calling repository: a fixed standards SHA would
stop tracking target-roster and component changes the moment it landed, and
every sync after it would move destinations the guard no longer knew about.
`standards-ref` is a workflow input naming a ref of a different repository,
not a `uses:` reference, so the ci-workflows pin-comment convention does not
apply to it. Moving it to a SHA is a post-soak decision that then needs its
own advance path (the sync engine's `dest-paths` contract at that SHA is what
the guard executes); do not pin it in this hop.

## Pin-advance path

The action pin rides the existing `maintenance-repin-ci-workflows` cascade
(`.github/workflows/maintenance-repin-ci-workflows.yml`, daily), which resolves the
newest full-SemVer ci-workflows release and rewrites every enumerated caller
to its SHA with a `# vX.Y.Z` comment. Both files are enumerated in
`components/claude-lanes/repin-callers.sh`'s `EXTRA_CALLER_FILES`, and the
workflow's `add-paths` covers the whole `components/managed-files-guard`
directory, so the same reviewed pull request that re-pins the
lane callers re-pins the guard and the sync fans it out.

Two properties of that ride are deliberate:

- **A pin ahead of the release is left alone.** `apply` asks GitHub's
  compare API whether the pinned SHA is an ancestor of the release SHA
  ([compare two commits](https://docs.github.com/en/rest/commits/commits#compare-two-commits)).
  Status `ahead` or `diverged` leaves the file untouched; `behind` or
  `identical` lets the rewrite proceed. Day-level pin-comment dates are not
  consulted: a pin landed later on the same UTC day as the release, or on
  another line of history, cannot be proven contained by a `YYYY-MM-DD`
  string. Without that fence the very next scheduled run would have proposed
  moving this file from `3b2f4eab5b4bb58a150e400613350ede37742ee8`
  (2026-08-30) back to v0.17.2 (2026-08-21),
  behind the fail-open fix. The pin advances to the tag form on the first
  release that contains it, and the file now sits on that tag form, so the
  fence has released it and it re-pins with the lane callers on every later
  release. A failed compare is a hard failure, not a rewrite.
- **Not in `repin-policy-lockstep.mjs`'s `REPIN_TARGETS`.** Every `kind` that
  table expresses and that still has a contract to copy (`lane`, `reusable`)
  copies a `components/runner-policy/policy.json` contract forward from the old
  SHA to the new one and diffs the reusable workflow's `workflow_call` surface.
  Composite actions are not SHA-allowlisted by runner-policy
  (`components/runner-policy/README.md`), so there is no contract to copy and
  no `workflow_call` surface to diff; an entry would either invent a kind the
  policy does not have or force the lockstep to `manual` on every release.
  The guard caller therefore takes the pin rewrite only, which is the whole
  of what it needs. runner-policy governs the caller as an ordinary hosted
  job (fixed approved label, read-only token, full-SHA action pin), not
  through `approvedReusableWorkflowContracts`; a bogus reusable-workflow
  contract for a composite action would be exactly the misuse that README
  warns against.

## Ownership and operation

- **Owner:** the standards repository maintainers (the manifest and the
  Claude lane callers share the same owner); the ci-workflows maintainers own
  the action itself.
- **Acceptance during soak:** across the live consumers, every finding
  is either a real downstream hand-edit of a managed destination (the check
  is doing its job) or a classified defect in the action or manifest; the
  `melodic-standards-sync[bot]` author plus `standards-sync` label exemption
  keeps sync pull requests green, and the action's `dependabot[bot]` actor
  skip passes a Dependabot pull request that edits a managed destination
  (see above). A false red on a sync pull request, or a green on any other
  hand-edit, is a defect to fix upstream before any promotion.
- **Rollback:** move the component to `locally-owned` for a target (the
  next sync stops writing it; the target deletes its copy in its own pull
  request), or remove the component from the manifest to withdraw it
  fleet-wide. Nothing else references the file.
- **Failure behavior:** the action fails closed on an unreadable diff or an
  unresolvable manifest, no-ops when the repository is not a manifest target,
  and needs only `contents: read` (standards is public; the checkout of it
  uses the job's ambient token with `persist-credentials: false`).
- **The `actions/checkout` pin.** Unlike the Claude lane callers, this file
  carries a third-party action pin, and two consequences follow. In this
  repository, Dependabot's `github-actions` ecosystem scans
  `.github/workflows/` only, so the component's checkout pin never moves on
  its own; the contract test asserts it equals the sibling workflows' pin, so
  a Dependabot bump of those workflows fails the `check-github-actions` job until the
  component follows in the same change. That is the checkout advance path,
  and it is deliberate lockstep, not friction to remove. In a consumer, its
  own Dependabot will propose bumping `actions/checkout` inside the managed
  file. From ci-workflows v0.23.0 the action skips the `dependabot[bot]`
  actor, so that pull request passes the guard rather than reds it, and the
  next sync reverts the edit; the pin therefore moves only by a hand edit to
  this standards component, not by a consumer's Dependabot. Before
  promotion, resolve it one of two ways: the action absorbs the consumer
  checkout (so the caller carries no third-party pin at all), or the fleet
  Dependabot posture for managed callers is settled in `github-iac`. Neither
  belongs to this hop.

## Verification

`managed-files-guard.test.sh` asserts, against the parsed YAML of each file:
the `pull_request` trigger with the default `types` and a `paths` list equal
to the managed union of the targets that receive that file, free of glob
metacharacters; `contents: read` as the whole grant; the
canonical `concurrency-policy` block and nothing else in it; one job on its
literal label with a 10-minute timeout, calling no reusable workflow; a
full-history, credential-free checkout pinned like the sibling workflows; the
action pinned by full SHA with a comment the `pin-comment-convention` library
accepts; and `standards-ref: main`. It asserts the two files carry the same
action pin and differ only in comments, the workflow name, `paths` and `runs-on`. It then checks the
manifest wiring (destination paths, fleet-routed targets on the fleet-routed
caller only, no target on both, ci-workflows `locally-owned`, every target
accounted for) and materializes each managing target through the real engine, asserting byte-identity at the
destination and, when `actionlint` is on PATH, a clean lint there.
`components/claude-lanes/repin-callers.test.sh` covers the cascade half,
including the ahead-of-release fence.
