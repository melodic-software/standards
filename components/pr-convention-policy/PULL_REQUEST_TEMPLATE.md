Closes #

<!--
Complete the `Closes #` line above with the issue number to auto-close it on
merge, one closing keyword per issue (cross-repo:
`Closes <owner>/<repo>#<issue-number>`). Supported keywords are GitHub's:
https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue

If this PR closes no issue (an orphan PR: drift sweep, hotfix, refactor),
replace that line with the no-issue escape and its reason, as plain text:

No related issue: <reason>

The reason is required. Write the escape without backticks: the gate masks
inline code spans before matching, so a backticked escape is invisible to it
and the PR draws the advisory `needs-issue-linkage` label anyway. The linkage
rule is advisory: the `check-contract` step inside `CI Status` leaves a comment and
the `needs-issue-linkage` label instead of failing. That step's output reports
the exact rule it applied and is authoritative over this comment.

Every `##` section below must be filled with real content. HTML comments like
this one are stripped before validation, so an untouched template is reported
as missing every section rather than passing vacuously.
-->

## Summary

<!-- What changes and why, in a sentence or two of problem context. -->

## Fix

<!-- The concrete change and how it addresses the problem. -->

## Verification

<!-- How this was proven: the commands run and what they showed, or the manual check performed. -->

## Related

<!--
Issues, PRs, or decision records this change touches without closing
(one per line, e.g. `Refs: #<issue-number>`). This section must not be empty:
if nothing applies, say so in a sentence. The no-issue escape goes on the top
line of this template, not here.
-->
