# managed-files-guard caller

Sync-managed caller for the `managed-files-guard` composite action in
`melodic-software/ci-workflows`
(`.github/actions/managed-files-guard`, ci-workflows#208). The action reads
this repository's `distribution/sync-manifest.yml` at a given ref, resolves
the calling repository's managed destination paths, and fails the pull
request when its diff touches one of them. That failing check is the signal
ADR-0007 assigned to a downstream hand-edit of a managed file
(`docs/adr/0007-keep-the-managed-file-seam-binary.md`): the seam stays
binary, the fix path is always a standards change, and the guard is what
makes a hand-edit visible before the next sync silently reverts it.

`managed-files-guard.yml` is the component's one file. The
`managed-files-guard-caller` manifest component materializes it at
`.github/workflows/managed-files-guard.yml` in every target that manages it.
It is the second recorded exception to the rule that workflow callers stay
consumer-owned (`distribution/README.md`), for the same reason as the Claude
review-lane callers: a fleet-wide guard is only a signal if every target runs
the same caller at the same pin, and the sync is the one mechanism that holds
that.

## Rollout: advisory first, hosted-only first

**Advisory soak.** The check is not aggregated into any target's `ci-status`
and is not a required context anywhere. It runs on every pull request,
reports, and blocks nothing. This follows the action's own contract
("advisory-first: wire into ci-status only after a clean soak") and the
enforcement-rollout steps in `docs/component-lifecycle.md`: observe against
the live consumers, classify every finding, then promote per target once the
baseline is understood. Promotion is a per-target decision, taken in that
target's own `ci-status` wiring after its soak is clean; nothing in this
component promotes. The soak and the promotion decisions are operator-owned
after the admitting pull request (standards#496); that issue is the record
until each target's promotion lands.

**Hosted-only first hop.** The caller runs on `ubuntu-24.04` directly, with
no `select-runner` indirection. `runner-policy` admits that shape on a public
repository and on a private repository not enrolled for local CI routing, so
one file serves both without a per-visibility variant. This hop is therefore
managed for exactly the hosted-only-eligible targets:

- `melodic-software/.github`, `account-rotation`, `agent-plugins`,
  `ci-runner`, `claude-code-plugins`, `codex-plugins`, `cursor-plugins`
  (public), and `claude-code-proxy` (private, not enrolled for selector
  routing).

`claude-code-plugins` is the one consumer here that also executes the
`runner-policy` gate; `components/runner-policy/runner-policy.test.mjs`
asserts this caller audits clean under a public hosted-only inventory so
the sync cannot red that target's `ci-status`.

**Excluded this hop: the selector-routed targets.** `dotfiles`,
`github-iac`, `medley`, and `provisioning` are private targets enrolled for
local CI routing (each manages `runner-policy` and a selector-routed Claude
lane caller). There, `runner-policy` requires every independently scheduled
read-only job to route through the governed selector, and a fixed
`runs-on: ubuntu-24.04` job fails the gate. A public-safe hosted caller
cannot be made selector-routed without becoming a different file, so those
four take a **selector-routed sibling component** in a second hop. Removal
trigger: that sibling landing; this component's target list does not grow to
include them. The contract test holds the boundary mechanically: no target
may manage this caller and a `components/claude-lanes/`-sourced caller at
once.

**Locally owned by `ci-workflows`.** ci-workflows hosts the action and
already runs the guard as a job of its own `ci.yml`, through a `./` action
reference that resolves to the commit under test. A synced caller pinned to
an older commit would run the guard twice per pull request, once at each
revision, so ci-workflows carries the component `locally-owned`. Removal
trigger: ci-workflows retiring its in-repo job in favor of the synced caller.

`standards` is the manifest source, not a target, and carries no caller.

## The two pins

**The action pin** is a full 40-character commit SHA of ci-workflows `main`,
under the `pin-comment-convention` (`components/pin-comment-convention/`).
The admitted pin is `3b2f4eab5b4bb58a150e400613350ede37742ee8`
(2026-08-30, ci-workflows#530), the commit that closed the guard's fail-open
on an unreadable diff: before it, an unfetched or bogus ref produced an empty
change list and the guard passed precisely when it could not see the diff.
No release carried that commit when this component was admitted (the newest,
v0.17.2, is 2026-08-21), so the comment takes the convention's fallback form
`# 3b2f4ea 2026-08-30` rather than a release tag.

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

The action pin rides the existing `claude-lanes-repin` cascade
(`.github/workflows/claude-lanes-repin.yml`, daily), which resolves the
newest full-SemVer ci-workflows release and rewrites every enumerated caller
to its SHA with a `# vX.Y.Z` comment. This file is enumerated in
`components/claude-lanes/repin-callers.sh`'s `EXTRA_CALLER_FILES` and in the
workflow's `add-paths`, so the same reviewed pull request that re-pins the
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
  moving this file from `3b2f4ea` (2026-08-30) back to v0.17.2 (2026-08-21),
  behind the fail-open fix. The pin advances to the tag form on the first
  release that contains it; until then the re-pin pull request names the
  file in its version note and moves the lane callers only. A failed
  compare is a hard failure, not a rewrite.
- **Not in `repin-policy-lockstep.mjs`'s `REPIN_TARGETS`.** Every `kind` that
  table expresses (`selector`, `lane`, `reusable`) copies a
  `components/runner-policy/policy.json` contract forward from the old SHA to
  the new one and diffs the reusable workflow's `workflow_call` surface.
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
- **Acceptance during soak:** across the seven live consumers, every finding
  is either a real downstream hand-edit of a managed destination (the check
  is doing its job) or a classified defect in the action or manifest; the
  `standards-sync` label / `melodic-standards-sync[bot]` actor exemption
  keeps sync pull requests green. A false red on a sync pull request, or a
  green on a hand-edit, is a defect to fix upstream before any promotion.
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
  a Dependabot bump of those workflows fails the `actionlint` lane until the
  component follows in the same change. That is the checkout advance path,
  and it is deliberate lockstep, not friction to remove. In a consumer, its
  own Dependabot will propose bumping `actions/checkout` inside the managed
  file; that pull request is precisely the hand-edit the guard reports, and
  the next sync reverts it. Expect that finding class during the soak, and
  classify it as structural rather than as a downstream defect. Before
  promotion, resolve it one of two ways: the action absorbs the consumer
  checkout (so the caller carries no third-party pin at all), or the fleet
  Dependabot posture for managed callers is settled in `github-iac`. Neither
  belongs to this hop.

## Verification

`managed-files-guard.test.sh` asserts, against the parsed YAML: the
`pull_request` trigger; `contents: read` as the whole grant; the canonical
`concurrency-policy` block and nothing else in it; one job on the literal
approved hosted label with a 10-minute timeout and no selector or reusable
call; a full-history, credential-free checkout pinned like the sibling
workflows; the action pinned by full SHA with a comment the
`pin-comment-convention` library accepts; and `standards-ref: main`. It then
checks the manifest wiring (destination path, hosted-only targets only,
ci-workflows `locally-owned`, every target accounted for) and materializes
each managing target through the real engine, asserting byte-identity at the
destination and, when `actionlint` is on PATH, a clean lint there.
`components/claude-lanes/repin-callers.test.sh` covers the cascade half,
including the ahead-of-release fence.
