# Code review

## Design and review

- Let the pull request, with CI and automated review, be the review step and the single gate for what ships. Review lanes never queue or block merges and fail fast when usage limits hit. Remove approval gates and holds that guard no real exposure, and flag sensitive changes (workflows, trust gates, secret handling) for approval rather than blocking them.

## Plan

- Ship small, self-contained pull requests merged to trunk at least daily, with unfinished work behind release toggles removed within weeks. This depends on fast review; slow review is the bottleneck to fix first. Split for reviewability, never by dropping content. Small changes get faster review; do not promise a shorter total time to merge from splitting alone.

## Build and review

- Give draft and ready one defined meaning each: a draft is an unrestricted checkpoint that reviewers skip, and ready is the handover that starts review automation. A push that only merges the base and bumps versions and changelog may reuse an earlier passing review if the gates pass on the new head. Keep the body and evidence edited in place, structured and collapsed, with reviewer media labeled apart from agent evidence.

## Review

- Block a merge only on a critical or severe finding fixable in the same change. Turn nits into agent-ready follow-up items that carry the review detail and depend on the original change merging.
- Give every pull request both a code review and a security review, each review type (standards, spec, security) run separately with its own context. Review against documented standards and the originating spec, looking for implementer shortcuts. Point an AI reviewer's instruction file at the team's conventions instead of copying them.
- Never accept findings blindly: validate each one, fix only the valid ones, and reply to every finding with a cited verdict. Automated review fixes what it finds, hands humans only the items it is unsure about, and says on the pull request whether a human decision is needed. Feed every human comment back into automated review so it never has to be left twice.

## Review and operate

- Let reasoned risk decide which changes auto-merge (two-way door, small blast radius, no data migration). Send mechanical pull requests straight to merge, hold big or heavy changes for fuller review, and make review configurable between post-merge sampling and blocking pre-merge review.
- Make automated review time grow sublinearly with diff size: skip hunks proven comment-only (failing closed) and review the remaining chunks in parallel. Bound review rounds and judge whether leftovers are real defects, because stacked or repeated reviewers always find something.
