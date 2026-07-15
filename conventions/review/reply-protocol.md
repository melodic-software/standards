# Reply protocol

How a review-comment thread closes once its finding is addressed. Severity labels are defined in [README.md](README.md).

## Reply on the surface the finding was posted to

- **Threaded, same-surface reply** — an inline review comment gets an inline threaded reply (the review-comment API), never a detached top-level PR comment; an issue-level or review-body comment gets an issue-level reply. A reply on the wrong surface orphans the thread — the original comment still reads unaddressed to anyone re-checking it. **Important.**

## Cite the fix commit

- **`Fixed in <sha>`** — once the fix is committed and pushed, reply on that finding's own thread citing the commit that fixes it, in the form:

  > Fixed in `a1b2c3d`

  The SHA is the evidence: it lets the reviewer — human or bot — re-diff exactly the change that addresses the finding without re-reading the whole PR. Reply only after the fix commit is pushed and visible on the remote; a reply that promises a fix that has not landed yet is not this pattern. **Critical** when a finding is treated as addressed but no reply cites a commit — the thread still reads open from the reviewer's side even though the code shipped.

## Resolve conditionally, never on someone else's behalf

- **Bot threads only** — resolving the thread is a separate step from the reply, and only appropriate when a bot reviewer opened the thread and you addressed the finding. Never resolve a thread a human opened — the human resolves their own; never resolve a thread under another identity's authorship. **Important.**
