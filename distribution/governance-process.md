# Governance process

Two standing process requirements this repository enforces outside the
automated `sync-manifest.yml` reconciliation loop: keeping a manually copied
file honest after it leaves this repository, and keeping the prose catalog
internally consistent as it changes.

## Copy-adoption integrity

[`conventions/README.md`](../conventions/README.md) documents two adoption
paths for reasoning-only prose: a consumer either copies the files it adopts
into its own tree, or points its contributor and review guides at this
repository. The copy path stays available — prose has no runtime coupling to
enforce reconciliation the way `sync-manifest.yml` does for exact
materializations — but a copy with no way back to its source and no way to
notice drift is indistinguishable from an orphaned, silently stale file. Two
requirements close that gap:

- **Back-link.** Every copied file carries a visible citation of its exact
  canonical source — repository and path, and, where the destination format
  honors comments, an inline header — so a reader can find the original and
  confirm currency. This follows the stable-anchor citation discipline in
  [`../conventions/engineering/reference-dont-duplicate.md`](../conventions/engineering/reference-dont-duplicate.md);
  a copy is the "Expose" role that file describes, and exposure still requires
  adjacent prose pointing back to the source.
- **Drift-check.** The adopting repository owns a periodic check that diffs
  its copy against the current canonical source and surfaces the result — a
  scheduled workflow, a recurring task, or an equivalent recurring review. The
  check's cadence is the adopting repository's choice, but its owner and
  trigger must be named at the copy site, the same recheck-trigger discipline
  [`../conventions/engineering/documentation-and-citations.md`](../conventions/engineering/documentation-and-citations.md)
  already requires for a time-bound external claim: a copy with no recheck
  trigger is drift waiting to happen.

This is deliberately distinct from a `managed` component under
[`sync-manifest.yml`](sync-manifest.yml): a managed component already
reconciles automatically through a reviewed pull request and, per the
ownership model in [`README.md`](README.md), carries no downstream receipt or
header bookkeeping because the manifest itself is the single source of truth.
The back-link and drift-check requirement applies only to the manual copy
path, where nothing else keeps the copy current. A copy that stabilizes and
outgrows manual upkeep is a candidate to graduate into a tracked component
under the [adopt lifecycle row](README.md#lifecycle) instead of continuing to
carry its own drift-check.

## Cross-doc reconciliation before a normative-doc change merges

A normative doc is any file in `conventions/` — or elsewhere in this
repository — that states a rule another doc cites or assumes:
[`naming.md`](../conventions/engineering/naming.md),
[`process/issue-tracker.md`](../conventions/process/issue-tracker.md), and
[`review/code-quality.md`](../conventions/review/code-quality.md) are
representative examples, not an exhaustive list.

Before a change to a normative doc merges, a cross-reference check confirms no
other doc in the catalog now contradicts the changed text: search the
repository for other files touching the same concept, and either reconcile
the wording or record the exception as an explicit cross-link. `naming.md`'s
general long-form-value rule and `issue-tracker.md`'s commit-type-versus-label-vocabulary
carve-out are exactly the shape of gap this check exists to catch — two
normative docs stating related rules without a cross-link between them — and
closing that specific gap is tracked separately. A change that narrows or
restates a rule without this check risks the exact silent-contradiction
failure mode
[`reference-dont-duplicate.md`](../conventions/engineering/reference-dont-duplicate.md)
names as a duplication smell.

**Ownership.** This organization keeps `required_approving_review_count` at
`0` everywhere, including this repository — a deliberate, recorded choice
against a mandatory second reviewer for a single-maintainer org. The
cross-reference check is therefore a self-review checklist item the author
performs before merging, not a delegated reviewer gate: the author runs the
check and states in the pull request that no other normative doc was left
contradicting the change. Until an automated check exists, this is the sole
control — treat it as required, not optional, precisely because nothing else
backstops it.

**Automation path.** Once the periodic cross-plugin-source consistency check
adopted for `claude-code-plugins` is running, extend the same pattern to this
repository's own normative docs so the check stops depending solely on
author diligence at merge time. That extension is future work; this document
records the requirement and its interim owner so the gap is a tracked
decision, not an unaddressed one.

## Review-criterion graduation and retirement

[`../conventions/engineering/enforceability-tiers.md`](../conventions/engineering/enforceability-tiers.md)
already says a finding climbs from reasoning-only prose toward mechanical
enforcement as far as its nature allows. This section is the missing other
half: what happens to the *prose bullet itself*, in `REVIEW.md` or a
`conventions/review/` criterion, once the mechanization it describes
actually exists downstream.

Retiring the prose line is a **self-review checklist item the author
performs when landing the mechanization**, not a bespoke CI job — the same
shape as the cross-doc reconciliation check above, and for the same
underlying reason: `required_approving_review_count` is `0` here, so nothing
else backstops it. Before removing a criterion bullet because a linter,
analyzer, or hook now covers it, the author confirms in the pull request
that the automated check:

- actually covers the same cases the prose bullet described, not a narrower
  subset that would silently regress coverage;
- is already landed and enforcing in every consumer the criterion currently
  reaches — removing the prose line before the automation exists downstream
  leaves those consumers with neither the check nor the reasoning that used
  to stand in for it, a real coverage gap, not a paperwork one.

**Ordering, not just presence.** A retirement is safe only after the
automated component has propagated to every consumer that still reads the
prose line — for a `managed` sync-manifest component that means the
materialization PR is merged in each enrolled target, not merely opened; for
a native-reference criterion it means the mechanized check is live in the
consuming repo's own CI. Retiring the prose line first, and trusting the
automation to catch up, creates exactly the propagation-lag window this
checklist item exists to close: a period where a consumer has neither the
reasoning-only bar nor its mechanical replacement.

**Not yet automatable.** A currency check (is a graduated criterion's
mechanization still enforcing what the retired prose described) and a
graduation-candidate scan (which criteria are ready to climb) both need a
stable per-criterion tag or ID to key off — none exists yet, so neither is a
CI job today. This is the same precondition the root `REVIEW.md`'s
`blocking` escalation tag already names for tag-selective enforcement: the
tagging groundwork comes first.

**Feedback loop.** What actually justifies a graduation-candidate scan
existing at all is a live signal that a criterion is (or isn't) worth its
prose: managed Code Review's own reaction counts and the self-hosted
`bughunter-severity` check-run JSON both carry a real per-finding usefulness
signal today, but nothing routes either back into revising `REVIEW.md` or a
`conventions/review/` criterion — a criterion that fires constantly as a
false positive, or one that never fires at all, currently gets no different
treatment than one earning its keep. Closing this loop is itself gated on
the same per-criterion tag/ID scheme above (the signal has to attach to a
specific criterion to be actionable), so it stays recorded here as a
precondition, not built.

## Related

- [`README.md`](README.md) — the managed/locally-owned ownership model and
  lifecycle this copy path deliberately sits outside of.
- [`../conventions/README.md`](../conventions/README.md) — the copy-or-pointer
  adoption model this document adds requirements to.
- [`../docs/component-lifecycle.md`](../docs/component-lifecycle.md) — the
  admission evidence a copy needs before it can graduate to a managed
  component.
- [`../conventions/engineering/enforceability-tiers.md`](../conventions/engineering/enforceability-tiers.md) —
  the climb this section's retirement half completes.
