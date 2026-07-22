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

## Scope: the tag form is format-only; the fallback form is provenance-checked

The tag form (`# vX.Y.Z`) checks **format** only — whether the named release
actually corresponds to the pinned SHA is GitHub tag data a static scan
cannot verify without a network call, so it is out of scope here.

The fallback form (`# <short-sha> <date>[ <note>]`) is **provenance-checked**,
not just format-checked: `<short-sha>` must case-insensitively prefix the
pinned 40-character SHA on the *same line*. At this position the token is an
unambiguous SHA claim about that exact pin, so there is no ambiguity to defer
to a heuristic for — unlike the runner-policy component's
`pin-provenance-drift` check (`components/runner-policy/README.md`), which
scans free-form comments across the whole repository and needs an `isShaClaim`
heuristic (mixed digits/letters, or exactly 40 characters) to decide whether a
token is a SHA claim at all before checking it. That heuristic would reject a
legitimate all-digit or all-`a`-`f` abbreviated SHA outright — a real, if less
common, git prefix — so this component does not align its accepted subset to
it; it checks the actual pin directly instead. The two checks now overlap for
a ci-workflows fallback comment specifically: this check is authoritative
there, and `pin-provenance-drift` remains the sole check for every other
SHA-pin comment shape this convention does not govern.

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
`explode(.)` first to resolve anchors and aliases, then only
`jobs.<id>.uses` and `jobs.<id>.steps[*].uses`, the two positions GitHub
Actions actually executes a `uses:` value from — rather than matching text
line by line or walking every node in the document. A plain, single-quoted,
double-quoted, anchored, or aliased `uses:` value is all scanned the same
way; `uses:`-shaped text inside a `run:` block body or a YAML `#` comment is
never a candidate because it is never a `uses:` node in the tree; and a
same-named "uses" key that is only data — a `strategy.matrix.include` entry,
a step's own `with:` input — is never a candidate either, because it is
never at one of the two scanned positions. A bare scalar-value alias
(`uses: *v`) shares only the referenced string, not the anchor line's
trailing comment, so the alias's own line still needs its own comment — see
the test cases in `pin-comment-convention.test.sh` for the distinction from
a whole aliased step, which does carry its comment along. `scan-workflow-files.sh`
in this directory is a minimal driver (file enumeration, path handling,
exit-code mapping) that this repository's own CI runs against
`.github/workflows/*.yml` and `*.yaml` as its live consumer, after
installing the same checksum-pinned yq release the `distribution` job uses.

The pinned 40-character SHA in the `uses:...@<sha>` value is matched
case-insensitively — it names the same git object regardless of hex letter
case, matching how the runner-policy provenance scanner already treats it.
The fallback comment's own short-SHA and the release-tag form's leading `v`
both stay case-sensitive by deliberate design, not oversight: a fallback
short-SHA is an authored documentation string the two-form policy fixes a
canonical spelling for, and a tag's case is part of its identity as a git
ref (this repo has never cut an uppercase-`V` tag, so an uppercase comment
would name a tag that does not exist). The org/repo segment
(`melodic-software/ci-workflows`) also stays case-sensitive: GitHub's own
routing is case-insensitive there, but nothing in this fleet has ever
spelled it any other way, and matching it case-insensitively would require
widening the `.github/(workflows|actions)/` directory segment along with
it — those *are* case-sensitive git tree paths — for a shape with no known
real occurrence; considered and deliberately left as-is.

Full-tree execution for other repositories — the way the `comment-hygiene`
composite action in `ci-workflows` drives `comment-hygiene-patterns.sh` today
— is deferred: no `ci-workflows` composite action wraps this library yet. A
consumer that wants this check before that driver exists can invoke
`scan-workflow-files.sh` directly (with yq on PATH), the same way this
repository does.

`fixtures/` and `pin-comment-convention.test.sh` cover both forms (with and
without a fallback note), every documented drift shape (missing comment,
prose, partial SemVer, reversed fallback field order, a fallback short-sha
that does not prefix its pin, a short-sha under 7 characters), an all-digit
short-sha that genuinely prefixes its pin, the exclusion boundary (a pin to
any action or workflow outside `melodic-software/ci-workflows` is out of
scope regardless of its comment), quoted refs, anchored/aliased pins (both
the whole-step and bare-scalar-alias shapes), the two run:-block /
YAML-comment false-positive guards, the two data-field-named-"uses"
false-positive guards (matrix and `with:`), an uppercase pinned SHA (clean
and flagged), and a document with no `jobs:` key at all (clean, not a parse
failure). The test file skips (rather than fails) when yq v4 is not
installed, matching `distribution/sync-manifest.test.sh`'s existing
tool-availability guard.
