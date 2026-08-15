# PR convention policy

Machine-readable policy and validator for fleet-wide pull-request conventions:
Conventional Commits titles, required body sections, and native closing
keywords (or an explicit no-issue marker). The policy file is the single
source of truth; `ci-workflows` thin runners and the source-control plugin read
the materialized copy from `.github/standards/pr-convention-policy/`.

Run the validator locally:

```sh
node components/pr-convention-policy/pr-convention-policy.mjs \
  --title "feat(distribution): add pr-convention-policy component" \
  --body "$(cat <<'EOF'
Closes #173

## Related
- melodic-software/ci-workflows#138
EOF
)"
```

The distributed component lives at `.github/standards/pr-convention-policy/` and
owns its own `package.json` and lockfile with an exact `ajv` runtime pin.
`policy.json` carries the canonical values; `policy.schema.json` is the Draft
2020-12 structural authority.

## The standard

### PR titles

Titles follow [Conventional Commits](https://www.conventionalcommits.org/) with
the allowed types listed in [`policy.json`](policy.json). The fleet includes
`security` as an allowed type — three repositories reached for it independently,
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
component encodes the rule the `pr-issue-linkage` gate enforces. Until the
thin-runner conversion below lands, the authoritative gate is the
`ci-workflows` `pr-issue-linkage.yml` reusable, which hardcodes its own copy
of the section list (four sections as of v0.14.2, `7107b34`). The two lists
must change in lockstep; letting them drift is exactly the failure #393
recorded.

## Security

`pull_request_target` callers execute the base-ref copy of this policy only.
See [`THREAT-MODEL.md`](THREAT-MODEL.md).

## Follow-on

`ci-workflows` `semantic-pr` and `pr-issue-linkage` reusables become thin
runners that read the materialized policy instead of embedding the rules inline.
That conversion is tracked in the same program (#173) and is intentionally out
of scope for the standards-owned slice.
