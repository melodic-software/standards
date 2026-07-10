# Use federated component distribution

- Status: accepted
- Date: 2026-07-10

## Context

Repository-quality policy had been copied among repositories and grouped in a
generic `modules/` hierarchy. Copies drifted, mixed unrelated capabilities, and
made it unclear whether policy, CI execution, GitHub governance, or a consuming
repository owned a change. A solution also had to work for local and cloud
agents without adding synchronization receipts or custom bookkeeping to every
consumer.

## Decision

Use a federated control plane with one normative owner per concern:

- `melodic-software/standards` owns shared policy and conventions.
- `melodic-software/ci-workflows` owns reusable GitHub Actions execution.
- the relevant `github-iac` repository owns organization and repository
  governance that the provider can express.
- each consuming repository owns its product behavior, project scope, and
  explicit local exceptions.

In this repository, organize policy as flat `components/<capability>/` source
slices. A component is the smallest capability adopted, updated, verified, and
removed as one unit. Its source slice co-locates contract tests, fixtures,
documentation, and package metadata; its exported payload contains only files a
consumer needs. Tool-mandated root configs remain the sole canonical copy at the
root and are documented and tested by their component slice.

Prefer delivery mechanisms in this order: platform control plane, native
package or reusable workflow/action, tool-native extension, then exact-file
synchronization by reviewed pull request. A consumer needing incompatible
policy opts out and owns the complete component locally. Managed payloads are
not edited downstream; a generally useful change is proposed upstream and then
propagated. Do not add receipts, lock files, generated headers, or a generic
templating/patch system to consumers.

## Consequences

Ownership and update direction are explicit, heterogeneous multi-file payloads
can move atomically, and component tests travel with the policy they prove.
Native package/reference mechanisms avoid copies where tools support them;
exact synchronization remains a simple fallback where they do not.

Consumers may briefly drift until reconciliation opens a pull request, and a
local exception sometimes requires whole-component ownership rather than a
partial merge. Repository and application access remain live external state
that adoption validation must query rather than duplicate in this catalog.
