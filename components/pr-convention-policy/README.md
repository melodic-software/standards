# PR convention policy

Machine-readable policy and validator for fleet-wide pull-request conventions:
Conventional Commits titles, required body sections, and native closing
keywords (or an explicit no-issue marker). This is a standards-internal record
and self-test. It is not distributed to consumers
([ADR-0005](../../docs/adr/0005-retire-pr-convention-policy-distribution.md));
the gate consumers actually run is the `ci-workflows` `pr-issue-linkage.yml`
reusable, which each repository pins directly.

Run the validator locally:

```sh
node components/pr-convention-policy/pr-convention-policy.mjs \
  --title "feat(distribution): add pr-convention-policy component" \
  --body "$(cat components/pr-convention-policy/fixtures/good/pr-body.md)"
```

The component owns its own `package.json` and lockfile with an exact `ajv`
runtime pin. `policy.json` carries the canonical values; `policy.schema.json`
is the Draft 2020-12 structural authority.

## The standard

### PR titles

Titles follow [Conventional Commits](https://www.conventionalcommits.org/) with
the allowed types listed in [`policy.json`](policy.json). The fleet includes
`security` as an allowed type: three repositories reached for it independently,
and it is not a semver/changelog axis (that remains on PR titles that ship
release-impacting work under `feat`/`fix`).

### PR bodies

Every pull request carries:

- a native closing keyword (`Closes`, `Fixes`, or `Resolves` followed by an
  issue number), or the literal `No linked issue` / `No related issue` when
  nothing closes; and
- a non-empty section for each entry in `requiredSections`: `## Summary` (what
  changes and why), `## Fix` (the concrete change), `## Verification`
  (evidence the change works), and `## Related` (PRs, ADRs, or decision-log
  entries the PR does not close).

The `## Related` section is fleet-wide house style (reconciled in #247); this
component encodes the rule the `pr-issue-linkage` gate enforces. The
authoritative gate is the `ci-workflows` `pr-issue-linkage.yml` reusable,
which hardcodes its own copy of the section list (four sections as of
v0.14.2, `7107b34`). The two lists must change in lockstep; letting them
drift is exactly the failure #393 recorded. That lockstep is now enforced by
[`lockstep-drift.mjs`](lockstep-drift.mjs) (ADR-0008), which the
`pr-convention-lockstep` CI lane runs against the live gate source, the
source-control plugin's hook validator, the org PR template, the distributed
`.claude/rules/pr-body-contract.md` rule, and the contract of the reusable at
every caller's pinned SHA.

## Security

See [`THREAT-MODEL.md`](THREAT-MODEL.md).

## Follow-on

The thin-runner conversion this component once anticipated, `ci-workflows`
reusables reading a materialized policy copy, is retired with the
distribution ([ADR-0005](../../docs/adr/0005-retire-pr-convention-policy-distribution.md)).
A future consumer-side analyzer is a new adoption decision, not a revival of
the old entry.
