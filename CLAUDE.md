@AGENTS.md

## Claude Code

<!--
Provisional shape: root CLAUDE.md = @AGENTS.md import + this delta section,
per code.claude.com/docs/en/memory's own documented pattern for repos that
already have an AGENTS.md.

Open question this repository has not fully closed: whether managed Code
Review's CLAUDE.md consumption expands @import the same way normal session
loading does. code.claude.com/docs/en/memory describes CLAUDE.md @import
expansion as unconditional ("Imported files are expanded and loaded into
context at launch") with no carve-out for Code Review. By contrast,
code.claude.com/docs/en/code-review explicitly calls out REVIEW.md, and only
REVIEW.md, as NOT expanding @import ("pasted verbatim... referenced files
are not read into the prompt"). The absence of a similar carve-out for
CLAUDE.md is documentation-level evidence that CLAUDE.md's @AGENTS.md import
IS expanded for Code Review too — but it is not an explicit statement to
that effect, and it is not empirically verified on a live repo (Code Review
is Team/Enterprise-only; untestable on a Max-plan subscription). Re-verify
empirically, or get Anthropic support confirmation, before relying on a
mostly-@AGENTS.md CLAUDE.md for managed Code Review's nit-level checks on a
Team-plan rollout. Trigger: this repository or any consumer gains
Team/Enterprise Code Review access.
-->

Review-specific guidance belongs in [`REVIEW.md`](REVIEW.md), not here.
Managed Code Review reads `CLAUDE.md` as general project context (nit-level
findings only) and `REVIEW.md` as review-only, highest-priority instructions
— duplicating review rules into this file would create two sources of truth
for the same behavior.
