# Pin-comment convention

Detection policy for the trailing comment on a `uses:` reference to a
`melodic-software/ci-workflows` reusable workflow or composite action pinned
by 40-character commit SHA. A bare SHA is not human-legible, so every such pin
carries a comment in exactly one of two forms — everything else, including no
comment at all, is drift:

1. **`# vX.Y.Z`** — primary form. The full-SemVer release tag the pinned SHA
   corresponds to.
2. **`# <short-sha> <date>[ <note>]`** — fallback form, for pinning a commit
   with no corresponding tag (legal but discouraged). `<short-sha>` is 7-40
   lowercase hex digits, `<date>` is ISO 8601 (`YYYY-MM-DD`), `<note>` is
   optional free text.

A single black-and-white rule (tag only) would break on a legitimately
untagged pin, so the fallback exists rather than forcing every pin to wait for
a release. See `melodic-software/standards#244` for the interview and
research that locked this dual-form shape, including the fleet pin-comment
census (six variants found pre-convention) in
`melodic-software/medley#1624`.

## Scope: form, not provenance

This policy checks **form** only — a comment is present and matches one of
the two shapes above. It does not check whether a fallback comment's
`<short-sha>` actually prefixes the pinned 40-character commit; that
provenance question is the runner-policy component's `pin-provenance-drift`
check (`components/runner-policy/README.md`). The two checks are
complementary: a comment can pass this form check and still fail
runner-policy's prefix match (a genuine, mismatched short SHA); the reverse
cannot happen — a comment that fails this form check never resembles a
short-SHA-plus-date claim in the first place. Neither check subsumes the
other, and this component does not re-implement runner-policy's prefix
comparison.

## Renovate: rejected as a pin-alignment mechanism

`melodic-software/standards#102` rejected Renovate for tracking these pins and
that rejection is reaffirmed, not reopened, by this convention — see the
reaffirmation comment on #102 for the updated rationale (GitHub's org SHA-pin
policy excludes reusable-workflow refs from its scope, immutable releases do
not soften SHA-pin guidance, Renovate's reusable-workflow-ref pinning is
undocumented, and Renovate is not installed anywhere in the fleet). Pin
alignment across consumers stays routed to the deferred mechanism in
`melodic-software/standards#197`.

## Library, driver, and what is deferred

`pin-comment-patterns.sh` exposes `pcc::scan_text`, which requires Mike
Farah's yq v4 on PATH (this repo's established YAML tool — see
`distribution/sync-manifest.sh`). Extraction walks the parsed YAML tree —
`explode(.) | .. | select(has("uses")) | .uses` — rather than matching text
line by line, so a plain, single-quoted, double-quoted, anchored, or aliased
`uses:` value is all scanned the same way, at any depth, and `uses:`-shaped
text inside a `run:` block body or a YAML `#` comment is never a candidate in
the first place because it is never a `uses:` node in the tree. A bare
scalar-value alias (`uses: *v`) shares only the referenced string, not the
anchor line's trailing comment, so the alias's own line still needs its own
comment — see the test cases in `pin-comment-convention.test.sh` for the
distinction from a whole aliased step, which does carry its comment along.
`scan-workflow-files.sh` in this directory is a minimal driver (file
enumeration, path handling, exit-code mapping) that this repository's own CI
runs against `.github/workflows/*.yml` and `*.yaml` as its live consumer,
after installing the same checksum-pinned yq release the `distribution` job
uses.

Full-tree execution for other repositories — the way the `comment-hygiene`
composite action in `ci-workflows` drives `comment-hygiene-patterns.sh` today
— is deferred: no `ci-workflows` composite action wraps this library yet. A
consumer that wants this check before that driver exists can invoke
`scan-workflow-files.sh` directly (with yq on PATH), the same way this
repository does.

`fixtures/` and `pin-comment-convention.test.sh` cover both forms (with and
without a fallback note), every documented drift shape (missing comment,
prose, partial SemVer, reversed fallback field order), the exclusion boundary
(a pin to any action or workflow outside `melodic-software/ci-workflows` is
out of scope regardless of its comment), quoted refs, anchored/aliased pins
(both the whole-step and bare-scalar-alias shapes), and the two run:-block /
YAML-comment false-positive guards. The test file skips (rather than fails)
when yq v4 is not installed, matching `distribution/sync-manifest.test.sh`'s
existing tool-availability guard.
