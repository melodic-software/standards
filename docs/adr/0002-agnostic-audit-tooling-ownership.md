# Own agnostic audit tooling in the capability-distribution home

- Status: accepted
- Date: 2026-08-03

## Context

[`0001-federated-component-distribution.md`](0001-federated-component-distribution.md)
established one normative owner per concern and enumerated four: this
repository, `ci-workflows`, the relevant `github-iac` repository, and each
consuming repository. That enumeration predates the capability-distribution
home becoming an owner in its own right rather than a delivery detail.

The rest of the repository already reflects the fifth owner.
[`../../conventions/process/autonomy-binding.md`](../../conventions/process/autonomy-binding.md)
binds the capability-distribution home role to the `claude-code-plugins`
marketplace, and [`../../conventions/README.md`](../../conventions/README.md)
records the `review` plugin resolving this repository's criteria at review
time. Only the ownership summary lagged, leaving a reader to conclude that
every quality-policy surface is an org policy choice owned here.

The forcing question is where a rule belongs when any consumer could adopt it
unchanged. Keeping such a rule here either imposes a Melodic Software policy
choice on repositories we do not control, or forces the rule to be duplicated
into every consumer that wants it without the policy.

## Decision

Recognize agnostic audit tooling as a distinct federated concern and name
[`melodic-software/claude-code-plugins`](https://github.com/melodic-software/claude-code-plugins)
its normative owner, alongside the four owners ADR-0001 enumerates. Nothing in
ADR-0001 is reversed: the federated control plane, the
`components/<capability>/` source organization, and the delivery-preference
ordering all stand.

The discriminating axis is who the rule binds:

- a rule binding Melodic Software repositories — one it would be wrong to
  impose on a repository we do not control — is an org policy choice and stays
  in this repository;
- a rule any consumer could adopt unchanged, whose default yields to that
  consumer's own declared policy where one exists, is agnostic and belongs to
  the capability-distribution home.

The deference clause is what makes the two layers compose rather than
partition: the `review` plugin's severity vocabulary is the neutral baseline,
and this repository's [`../../REVIEW.md`](../../REVIEW.md) is the org choice
that overrides it.

Agnostic audit tooling ships by marketplace version bump. That is ADR-0001's
tool-native extension tier rather than a new mechanism, so it precedes
exact-file synchronization and adds no entry to
[`../../distribution/sync-manifest.yml`](../../distribution/sync-manifest.yml).

## Consequences

A repository outside this organization can adopt an audit surface without
inheriting Melodic Software policy, and this repository stops accreting rules
it has no standing to impose. Marketplace-owned surfaces leave the
synchronization loop entirely, so their currency depends on a version bump
rather than a reviewed sync pull request, and a consumer of both layers now
tracks two update paths instead of one.

The axis has to be applied per rule at authoring time, and a misplacement
surfaces only when a consumer trips over an org-specific default. A rule that
starts org-specific and later generalizes moves repositories rather than
directories.
