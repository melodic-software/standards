# Distribute a PR-body contract rule and automate convention lockstep

- Status: accepted
- Date: 2026-09-01

## Context

First pull requests kept failing the fleet's required `pr-issue-linkage` check
because drafting-side copies of the PR-body convention drifted from the gate:
consumer `.claude/source-control.md` keys lagged the four-section contract
(ci-workflows#514, claude-code-plugins#3205), and codex-plugins pinned a
v0.9.1 gate enforcing an older contract entirely. The convention already has a
canonical machine-readable record here (`components/pr-convention-policy/policy.json`,
ADR-0003), but lockstep between it and the other copies — the ci-workflows
reusable, the source-control plugin's PreToolUse validator, the org `.github`
PR template — was documented discipline only (failure #393), and sessions
running without the plugin fleet ("unhobbled") had no repo-tracked signal at
all: skills, hooks, and templates never reach a bare `gh pr create`.

ADR-0005 retired distributing the pr-convention-policy component because the
vendored copies had zero readers, and reserved any future consumer-side need
for a new adoption decision. This is that decision — with a reader this time:
the always-loaded `.claude/rules/` layer, the one surface every Claude session
in a gate repo loads regardless of installed plugins.

## Decision

1. Distribute a small always-loaded rule, `.claude/rules/pr-body-contract.md`,
   through `sync-manifest.yml` to all nine non-standards gate callers; this
   repository's own copy is the component source (the actionlint
   source-doubles-as-live-config pattern).
2. Automate lockstep: `components/pr-convention-policy/lockstep-drift.mjs`
   runs in its own CI lane (`pr-convention-lockstep`), diffing the section
   lists, closing keywords, and no-issue markers of the gate reusable, the
   plugin hook validator, the org PR template, and the rules file against
   `policy.json` — and dereferencing every gate caller's pinned SHA to
   validate the contract of the reusable at that pin, the drift class no
   source-copy diff can see. Fetch failures fail the lane; nothing skips.
3. The gate reusable stays hardcoded and SHA-pinned; enforcement never reads
   remote policy at runtime (a policy edit must not mutate any repository's
   merge gate without an explicit pin bump).

## Consequences

- A convention change is now one edit to `policy.json` plus the lockstep lane
  turning red until every copy and every caller pin catches up — drift is loud
  instead of discovered by failing first PRs.
- Sessions with no plugins installed still see the contract before creating a
  PR.
- The lockstep lane is deliberately non-hermetic (live fetches of public
  repos); it lives in its own job so the hermetic component lane stays
  hermetic, and a network outage reads as a distinct `fetch-error`, never a
  silent pass.
- Per-repo `pr_body_required_sections` values are not fleet-checked: a single
  repository's re-drift surfaces immediately as that repository's own next
  first-PR failure and is cheap to fix, while caller pins — where divergence
  hid for months — are checked on every run.
