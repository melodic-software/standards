# Check placement

Where an automated check (formatter, linter, type check, test, scanner, guard) runs: in the
editor or agent session, in a git hook, or in CI. Place each check by three things: who it must
cover, what it costs, and what its output does to the person or agent reading it.

## The rules

1. **Cover every author with git hooks and CI.** An editor or agent-session hook sees only that
   tool's own edits. A check that must hold for humans, other agents and scripts alike runs in a
   git hook, and CI re-runs it.
2. **Use a session hook only to act before a change or to rewrite files.** A blocking guard that
   must stop a tool call, and a formatter that rewrites what the session just edited, belong in the
   session. A check that only reports does not.
3. **Never report findings per edit.** A report fired on every edit judges in-between states the
   author is about to change, and pulls an agent into fixes nobody asked for. Report at the commit.
4. **Choose the git hook by measured duration.** Measure each check; never guess. A check that fits
   the commit budget runs at `pre-commit`; a slower one at `pre-push`; one too slow for that runs in
   CI only. The budgets and measured durations live with the implementation, below.
5. **Block on what the change touched.** A local hook blocks only on findings in changed lines, so
   an old finding never stops an unrelated commit.
6. **Run each report-only check in one local place.** Formatters are the exception: they may
   rewrite in the session and are checked again at `pre-commit`. Whether a git hook may rewrite and
   re-stage is the hook manager's contract; the org's
   [lefthook fragment](https://github.com/melodic-software/standards/blob/main/components/lefthook-base/README.md)
   is check-only.
7. **CI never trusts a local pass.** A hook can be missing, skipped or stale on any machine, so CI
   re-runs every check on the change, and a scheduled full-tree run catches what change scoping
   misses.
8. **A skipped check says so.** A local skip names the check on stderr and relies on CI; an agent
   commit with a missing tool fails with the install command.

## Implementation

The Claude Code implementation, with the commit and push budgets, per-hook measured durations and
the git-hook registration contract:
[check-placement contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/README.md),
decided in
[ADR 0072](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0072-place-each-check-by-coverage-cost-and-model-facing-output.md).
