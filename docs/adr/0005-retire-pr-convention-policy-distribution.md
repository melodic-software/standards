# Retire pr-convention-policy distribution

- Status: accepted
- Date: 2026-08-19
- Supersedes: [ADR-0003](0003-pr-convention-policy-as-data.md)

## Context

ADR-0003 made `components/pr-convention-policy/` the standards-owned
policy-as-data slice and distributed it through `distribution/sync-manifest.yml`
to `.github/standards/pr-convention-policy/` in five consuming repositories.
The standards sync audit verified the fleet-wide result: no consumer ever
invoked the vendored analyzer. No workflow, hook, script, or doc referenced
it beyond each repository's Dependabot entry for its npm lockfile. The live
enforcement consumers actually run is the ci-workflows `pr-issue-linkage`
reusable, which each repository pins directly. The distributed copies were
payloads plus a per-repository Dependabot maintenance root with zero readers.

## Decision

Stop distributing the component: its manifest entry and the five `managed`
rows are removed, and the consuming repositories delete their materialized
`.github/standards/pr-convention-policy/` payloads and Dependabot roots in
one-time PRs per the distribution Retire lifecycle.

`components/pr-convention-policy/` itself stays in this repository as the
standards-internal record and self-test of the PR convention: `policy.json`
remains the machine-readable convention source
(`conventions/process/issue-tracker.md` cites it), and the analyzer still runs
against its fixtures in this repository's CI. Enforcement remains where it
already lives: the ci-workflows reusable that consumers pin.

## Consequences

- One authoritative, testable policy record remains, without a second
  distributed inventory nobody executes.
- Consumers carry five fewer synced files and one fewer Dependabot npm root
  each.
- A future consumer-side analyzer need is a new adoption decision (and a new
  ADR), not a revival of this entry.
