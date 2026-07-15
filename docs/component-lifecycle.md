# Shared component lifecycle

A shared component exists to satisfy a demonstrated consumer need with one
maintained policy boundary. It is not a catalog entry for a tool that might be
useful later. This lifecycle applies to packages, exact materializations,
reusable configuration, analyzers, hooks, and their supporting conventions.

The repository's existing surfaces remain the inventory: component directories
and package manifests describe what exists, the
[`sync-manifest.yml`](../distribution/sync-manifest.yml) records exact
materialization, and native references remain in their consumer repositories.
Do not create a second component or adoption registry. Join those surfaces only
through the on-demand audit described by the
[distribution contract](../distribution/README.md).

## Admission evidence

The admitting pull request must supply all of the following evidence. Missing
evidence means the component remains a consumer-local experiment.

- **Live consumer** — identify at least one current repository and the exact
  workflow, manifest, configuration, or code path that will consume the
  component. Anticipated use and an ecosystem's general popularity are not
  adoption evidence.
- **Owner and outcome** — name the accountable maintainer, the problem being
  solved, the measurable acceptance condition, and the rollback path. Durable
  ownership and operating instructions live beside the component; consumer
  lists stay in their authoritative surfaces.
- **Delivery boundary** — choose the natural authority: a native package or
  reference, a reusable workflow in `ci-workflows`, an organization setting in
  GitHub IaC, or exact materialization through this repository. Explain why the
  selected boundary preserves one source of truth.
- **Alternatives and overlap** — compare the platform's official facility and
  credible maintained alternatives against the requirement. Identify overlap
  with existing components and explain why composition will not duplicate
  findings or create competing configuration authorities.
- **Operational fit** — exercise the real consumer and report signal quality,
  false positives, runtime, resource use, supported operating systems and
  architectures, required privileges, data or credential access, and failure
  behavior. A documentation-only comparison is not sufficient.
- **Upstream health** — cite official documentation and releases; inspect
  project governance, active maintainers, security reporting, unresolved
  advisories, release and issue response, documented adopters, and archival or
  end-of-support status. Popularity is corroborating evidence, never a
  substitute for fitness or maintenance.
- **Legal and security fit** — record the upstream license with its SPDX
  identifier or expression, compatibility with the organization's applicable
  policy, artifact provenance and integrity mechanism, dependency and network
  boundary, and the review required by
  [security criteria](../conventions/review/security.md).
- **Update path** — enable the repository's supported dependency updater for
  every independent dependency root. If automation cannot cover a tool, record
  the owner, exact upstream release source, review procedure, and recurring
  check trigger beside the component.
- **Verification** — add behavioral tests for the policy boundary, fixtures for
  expected pass and fail cases, deterministic installation, and CI that runs
  the same entrypoint consumers will use. Structural validation is not
  behavioral proof.

[OpenSSF Scorecard](https://github.com/ossf/scorecard#project-non-goals) may
inform upstream due diligence through its individual probes. Its aggregate
score is not an admission threshold: the project explicitly describes the
checks as opinionated heuristics with false positives and false negatives.

## Enforcement rollout

Every new behavioral gate has an explicit rollout recorded in its admission
change:

1. Run it against the live consumer in observation or report-only mode.
2. Classify every finding as a defect, a narrowly justified exception, or tool
   noise; change shared defaults only when the evidence generalizes.
3. Promote it to blocking after the baseline is understood, the failure output
   is actionable, and a clean run proves the configured boundary.
4. Remove the report-only path or attach it to a named completion issue with an
   owner and deadline. Indefinite advisory enforcement is not adoption.

A deterministic check may begin blocking only when the admission PR already
contains equivalent observation evidence from the live consumer and explains
why no baseline period is needed. Exceptions are precise, owned, time-bounded
where the risk can change, and tested so they cannot silently widen.

## Operation and re-audit

The component owner keeps documentation, locks, fixtures, and updater coverage
aligned with the supported release line. Re-run the admission assessment when:

- an upstream major release, license change, ownership transfer, archival, or
  end-of-support notice changes the trust decision;
- a security advisory, integrity failure, material false-positive increase, or
  platform incompatibility challenges the accepted boundary;
- the abandonment signals in the
  [security criteria](../conventions/review/security.md) appear;
- the delivery mechanism, privilege, credential, network, or data boundary
  changes; or
- the recurring review owned by the component comes due.

The re-audit records current evidence and a decision to retain, replace,
restrict, or retire. It does not copy upstream release catalogs into this
repository. NIST SSDF practice PW.4 calls for maintained component selection,
vulnerability monitoring, integrity verification, and plans for components
that become unsupported; this lifecycle makes those decisions reviewable
without pretending activity metrics alone prove safety.

## Retirement

Retirement requires a fresh on-demand adoption audit with zero consumers. The
audit covers the materialization manifest, native package and configuration
references, reusable-workflow callers, consumer workflow wiring, and relevant
live repository state. A `locally-owned` manifest entry is not consumption of
the shared bytes, but it must be reviewed before removing the capability's
classification.

The retirement pull request links the audit result, names the owner, and states
the migration or removal impact. Remove upstream ownership before coordinated
downstream deletion, following the distribution lifecycle; never infer deletion
from deselection. Remove obsolete updater entries, locks, CI, documentation,
and exceptions with the component. If any consumer remains, replacement and
consumer migration precede retirement.

This deliberate, evidence-first decision follows the CNCF's project-archiving
principle: automated health signals may trigger review, but adoption, security
posture, maintainer response, and consumer impact require human evaluation.

## External authorities

- [NIST SP 800-218, Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final)
- [OpenSSF Scorecard goals and non-goals](https://github.com/ossf/scorecard#project-non-goals)
- [OpenSSF Scorecard check documentation](https://github.com/ossf/scorecard/blob/main/docs/checks.md)
- [CNCF project lifecycle](https://github.com/cncf/toc/tree/main/process)
- [CNCF project archiving process](https://github.com/cncf/toc/blob/main/process/archiving.md)
- [SPDX license list](https://spdx.org/licenses/)
