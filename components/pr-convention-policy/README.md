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
  issue number), a non-closing reference (`Refs: #N` or `Relates to: #N`, alone
  on its own line, from `nonClosingMarkers`) when the PR links an issue it must
  not close, or the literal `No linked issue` / `No related issue` when nothing
  is linked; and
- a non-empty section for each entry in `requiredSections`: `## Summary` (what
  changes and why), `## Fix` (the concrete change), `## Verification`
  (evidence the change works), and `## Related` (PRs, ADRs, or decision-log
  entries the PR does not close).

A negated closing reference (`does not close #N`) is an error even when valid
linkage appears elsewhere: GitHub's own parser ignores the disclaimer and
closes the issue on merge. `negatedClosers` records the rule: a closing
reference is negated when one of `triggerWords`, or a word ending in one of
`triggerSuffixes`, appears among the last `wordWindow` words between the
previous `.`, `!`, `?`, `;` or `,` and the keyword, unless it opens one of the
`affirmativePhrases` (`not only ... but` is affirmative).

`nonClosingMarkers` and `negatedClosers` are descriptive records of the rules
the composite and the hook validator implement. The local validator
(`pr-convention-policy.mjs`) is a self-test, not the evaluator of record, and
does not apply them: it still asks a body for a closing keyword or a no-issue
marker.

The `## Related` section is fleet-wide house style (reconciled in #247); this
component encodes the rule the gate enforces. The authoritative gate is the
`ci-workflows` `pr-contract` composite, which hardcodes its own copy of the
contract: the section list as the `section_report("<name>")` calls in
[`run.sh`](https://github.com/melodic-software/ci-workflows/blob/main/.github/actions/pr-contract/run.sh),
the closing keywords and no-issue markers as the awk patterns beside them, the
non-closing markers as the `rest ~ /^(refs|relates[ \t]+to):.../` test in
`scan_line`, the negation rule as `negation_trigger`, and the allowed title
types and the scope requirement as the `types` and `require-scope` input
defaults in `action.yml`. The hook validator transcribes the same linkage
rules as `CLOSING_ERE`, `NON_CLOSING_ERE`, `NO_ISSUE_ERE` and
`negation_trigger_to`; it is neither stricter nor looser than the composite on
either rule. Those copies must change in lockstep with `policy.json`; letting them drift is
exactly the failure #393 recorded. That lockstep is enforced by
[`lockstep-drift.mjs`](lockstep-drift.mjs) (ADR-0008), which the
`pr-convention-lockstep` CI lane runs against the live gate source, the
source-control plugin's hook validator, the org PR template, the distributed
`.claude/rules/pr-body-contract.md` rule, and the contract of the artifact each
consumer pins (the composite, or the reusable until that repository takes its
Phase 3 pull request) at that pinned SHA. The non-closing and negated-closer
rules are checked in the live composite, at every composite pin, and in the
hook; a reusable pin is checked for sections, keywords and markers only, since
that transition-only artifact gained the two rules late (ci-workflows#544);
ADR-0008's [2026-10-06 (#647) amendment](../../docs/adr/0008-distribute-pr-body-contract-rule.md#revisited-2026-10-06-647-rules-the-reusable-pins-predate)
records that exception to its every-pin consequence.

### Behavioral lockstep

Static parsing proves a copy declares the policy's data; it cannot prove the
copy acts on it, and each review round of #647 found one more way to break the
chain from declaration to verdict while every source regex still matched. So
the linkage rules are also checked by running each copy.
[`lockstep-behavior.mjs`](lockstep-behavior.mjs) generates a matrix of sample
bodies from `policy.json`, each followed by every `requiredSections` heading
with content. Each closing keyword appears in upper case, with a colon, with
no or a tab blank, after a list bullet or a quote, with a CRLF ending, and in
shapes that must not count (inside a longer word, before a longer reference, or
before an issue URL). Each non-closing marker appears on its own line,
indented, in upper case, with no blank or trailing blanks, mid-sentence, with
trailing text, without its colon, and after a bullet or a quote. Each no-issue
marker appears in upper case, mid-sentence and pluralized. For every closing
keyword, each trigger word and suffix appears at the window's edge and one word
beyond it, in upper and capitalized case, and with a typographic apostrophe.
The matrix also covers each clause delimiter, punctuation that is not one (`:`,
`-`, brackets, quotes and the like, which must leave the window open), each
affirmative phrase in any case, words that only contain a trigger, the
window's word count across hyphens, bare references and line breaks, and a
negated and a valid closer on one line, in both orders. For every closing
keyword, a negated closer sits on the line before and after a valid closer,
each non-closing marker and each no-issue marker, and a no-issue marker shares
its line in both orders, because no opt-out or other linkage excuses it. Every
two kinds of valid linkage also appear together in both orders. It also hides a
closing keyword, each non-closing marker, a negated closer for each closing
keyword and a no-issue marker inside each shape both copies mask before they
scan: an HTML comment (one line and several), a backtick fence, a tilde fence,
a space- and a tab-indented code block, and inline code. Each of those bodies
must read as missing linkage, and a masked negated closer beside a real
`Refs:` line must not be reported, so a copy that scanned the raw body would
fail. It runs the composite's `analyze_body` awk program (live and at every
composite pin) and the hook's `linkage::problems` on every body and fails on any
verdict the policy does not predict, naming the body. The static extractors
stay as the precise diff of declared lists. The bash in `run.sh` that reads the
analyzer's report calls the GitHub API and cannot run here, so its two
report-reading lines are the only part of the chain still checked as source.
The hermetic tests run the same path against verbatim copies of both sources in
[`fixtures/lockstep/`](fixtures/lockstep/).

The matrix leaves out one masking shape on purpose, because the two copies
disagree on it: a `<!--` inside code. The composite masks comments and code in
one pass, so a `<!--` inside a fence or an inline code span is code text and
opens no comment, as CommonMark renders it. The hook strips comments first and
masks code afterwards, so the same `<!--` opens a comment that swallows the rest
of the body, sections included. Text after a `-->` that closes a comment on a
line indented four or more spaces splits them the same way: the composite scans
it, the hook masks it as an indented code block. The hook is usually the
stricter copy there, but not always: a negated closer in that indented tail is
reported by the gate and passed by the hook. Aligning the hook is a `claude-code-plugins` change; the matrix gains these
shapes when the copies agree.

It leaves out Unicode spaces for the same reason. The hook turns a no-break
space and the other Unicode spaces into a plain space before it scans, so
`Closes<U+00A0>#12` closes and `No<U+00A0>linked issue` opts out. The composite
matches only a space or a tab, so neither counts as linkage.

`policy.json` spells three closing keywords and lists no inflections, but both
copies accept GitHub's nine forms (close, closes, closed, fix, fixes, fixed,
resolve, resolves, resolved), so the matrix probes every form as a plain closer
and as a negated one, from a GitHub-documented constant in
`lockstep-behavior.mjs`. The only divergence left is outside the matrix: the
reference validator in `pr-convention-policy.mjs` derives its own forms by trimming the listed
keyword, so for `Fixes` it accepts the non-word stem that drops only the final
`s`, which neither copy does, and rejects `Fix #12`, which both accept.

Executing fetched code is bounded as follows:

- Both sources come from org-owned repositories (`ci-workflows`,
  `claude-code-plugins`), fetched with the lane's read-only contents token, or
  from this repository's fixtures.
- The analyzer runs under `gawk --sandbox`, which refuses `system()`, command
  pipes, output redirection and extra input files, so it can only read the
  sample body on stdin and print. The lane installs `gawk` when the runner
  image lacks it; a missing `gawk` fails the check, never skips it.
- The hook runs as a sourced library in `bash --noprofile --norc` from a
  scratch copy, with an environment of `PATH=/usr/bin:/bin` and `LC_ALL` only
  (no token, no `HOME`) and a 10-second timeout. A hang is reported as drift.
  Unlike the analyzer, bash is not confined to stdin and stdout: this step
  trusts the hook as org-owned code and limits only what it can reach, so a
  change to the hook's trust (another owner, a third-party source) needs a
  stronger sandbox first.
- Neither process receives the GitHub token: Node passes an explicit
  environment instead of inheriting its own.

#### Rollout

The behavioral comparisons block in the existing `pr-convention-lockstep` lane
from their admission (#647), without a report-only period. They take the
[component lifecycle](../../docs/component-lifecycle.md#enforcement-rollout)'s
exception for a deterministic check, on this evidence from the live consumers:

- Before admission, the live sources ran clean: `checkCopies` against
  ci-workflows `main`, the `claude-code-plugins` hook validator and the org PR
  template, and `checkPinnedComposite` at composite pins `2531d56`, `cf316d1`
  and `fb56986`.
- On the PR head `145870d`, the lane's `verify-pr-convention-lockstep` job
  (Actions run 37465415796) passed: the hermetic tests, then the live run with
  the org App token, which fetched every source and pin and reported that all
  copies and consumer pins match `policy.json`.
- The Markdown-masking samples were added after that run. They were run
  locally against the same live sources (the composite's `run.sh` on `main`
  and at the three pins, the hook on `main`), and every body matched the
  policy's verdict.

No baseline period is needed because there is no baseline to learn. The check
is deterministic: the matrix is generated from `policy.json` and each copy's
verdict on a body is a pure function of its source, so a clean run over every
live source and pin is the complete baseline, with zero findings to classify.
It is not a new gate on any consumer: it re-verifies the same linkage rules the
lane already blocked on through the static parse, and it fails only when a copy
the lane already holds to those rules stops acting on them. A failure names the
copy, the sample body, and the expected and actual verdicts, so it is
actionable as it stands. No report-only path exists to remove.

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
