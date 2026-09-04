# PR convention policy

Machine-readable policy and validator for fleet-wide pull-request conventions:
Conventional Commits titles, required body sections, and native closing
keywords (or an explicit no-issue marker). This is a standards-internal record
and self-test. It is not distributed to consumers
([ADR-0005](../../docs/adr/0005-retire-pr-convention-policy-distribution.md));
the gate consumers actually run is the `ci-workflows` `pr-contract` composite
(v0.20.0 onward, `449157aaa8e30f7b1457305d8048ebe6168e174a`), which each
repository pins directly as a step inside its `ci-status` job. Its predecessor
is the `pr-issue-linkage.yml` reusable, which every repository leaves during
Phase 3 of the ci-perf program (melodic-software/github-iac#396), one pull
request each; a repository runs one artifact or the other, never both.

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

The `pr-contract` composite's `types` input defaults to exactly these twelve,
`security` included, so the gate and `policy.json` now agree. The predecessor
`semantic-pr` reusable carried the action's eleven spec-aligned defaults and no
caller passed a `types:` value, which meant a `security:` title this policy
allows failed that gate. Adopting the composite ends that drift; the lockstep
check below reads the composite's default so it cannot reopen.

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
component encodes the rule the gate enforces. The authoritative gate is the
`ci-workflows` `pr-contract` composite, which hardcodes its own copy of the
contract: the section list as the `section_report("<name>")` calls in
[`run.sh`](https://github.com/melodic-software/ci-workflows/blob/main/.github/actions/pr-contract/run.sh),
the closing keywords and no-issue markers as the awk patterns beside them, and
the allowed title types as the `types` input default in `action.yml`. Those
copies must change in lockstep with `policy.json`; letting them drift is
exactly the failure #393 recorded. That lockstep is enforced by
[`lockstep-drift.mjs`](lockstep-drift.mjs) (ADR-0008), which the
`pr-convention-lockstep` CI lane runs against the live gate source, the
source-control plugin's hook validator, the org PR template, the distributed
`.claude/rules/pr-body-contract.md` rule, and the contract of the artifact each
consumer pins (the composite, or the reusable until that repository takes its
Phase 3 pull request) at that pinned SHA.

Only the title and the `do-not-merge` label fail the composite's step. A body
missing a closing keyword or a section is advisory: a warning, one upserted
comment, and the `needs-issue-linkage` label, with the step still exiting 0
(`linkage-mode: enforce` restores the hard gate per repository). The body
contract is still the standard; it is reported rather than gating so a body
edit never re-runs the file-lint lanes.

## Security

See [`THREAT-MODEL.md`](THREAT-MODEL.md).

## Follow-on

The thin-runner conversion this component once anticipated, `ci-workflows`
reusables reading a materialized policy copy, is retired with the
distribution ([ADR-0005](../../docs/adr/0005-retire-pr-convention-policy-distribution.md)).
A future consumer-side analyzer is a new adoption decision, not a revival of
the old entry.
