# Source control

## Design and operate

- Find high-churn files and adopt conventions such as changelog fragments so merge conflicts on them do not become a bottleneck.

## Plan and operate

- Avoid long-lived release branches: consumers track main, and work merges promptly instead of continuing on a stale feature branch.

## Build

- Require Conventional Commits for commit and pull request titles, with explicit narrow exclusions, and put the ticket number in commits so blame links code to its rationale.
- Commit and push often at checkpoints. Before each push, fetch main, rebase if it moved, combine conflicting changes from both sides, and verify again. Record a progress step as a pull request update, not an empty commit.
- Force-push only as a lease pinned to the full remote SHA on a feature branch. Never force-push a branch that several agents commit to; each later finisher merges in the others' changes instead.

## Build and operate

- Do each effort in its own worktree on a feature branch, keep the canonical checkout parked on the default branch and current, and land every change through a merged pull request, never a direct push to the default branch.

## Review and operate

- Merge only with green CI and finished reviews at the pinned current head, no unresolved threads, no hold label and no wait request, after a preflight against the current rulesets, required checks and open comments; an automated worker turns auto-merge off before it pushes to a pull request.

## Operate

- Whoever created a merged, stale or unneeded branch or worktree deletes it, locally and remotely; a branch tied to an open work item lives until that item closes; prototypes and discovery artifacts go on short-lived branches linked from the work item.
