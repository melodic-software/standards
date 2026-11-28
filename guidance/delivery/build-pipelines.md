# Build pipelines

## Any stage

- Never lower, loosen, reword, delete or skip a test, check, threshold or review to get a pass; on a stall, try another approach.

## Design and operate

- Run every change through one fixed pipeline shape built from a reusable, configurable skeleton that consumers extend rather than edit. Lanes are composable and in lifecycle order, and steps skip on metadata. Every code-changing step, including a simplification pass, runs before AI review, and final artifacts are produced only after checks pass. Cross-cutting concerns (resilience, credentials) go through one shared reusable workflow. Recurring local loops move into CI over time, and post-merge checks run when changes auto-merge.
- Build every CI job to handle a pull request of any size; when volume breaks a job, fix the pipeline's cause instead of splitting the change. Size runner capacity from historical throughput and scale it with load, give jobs pre-built environments with cached dependencies, and size automated work items to finish inside the job time limit.
- Keep git hooks few and under a 3-second ceiling. Pre-commit runs lint and format on staged files only, not in per-edit agent hooks. Be wary of pre-push hooks, and move anything over budget to CI. Prefer Lefthook over Husky. Choose between a git hook and a harness hook by a recorded rubric: git hooks cover humans and every agent, while harness hooks add noise to the model's context. Local and CI checks must not duplicate each other.

## Design and review

- Add a check or hook only when it earns its keep: fast, accurate, well tested, with no false positives and no failures on transient errors. Keep checks that depend on hosted-only runners or rate-limited AI review lanes non-required, and question any required check designed to fail in some state. When a rule becomes a check, and who makes it required, is as ai.prompting says.

## Build and operate

- Introduce a new lint rule without breaking anyone: fix existing violations first in a dedicated change, or ratchet the rule onto code as it changes. Lint gates run the rules from the change under review. Scope exclusions to specific files or occurrences, never a global allow. Prefer a much faster linter (Oxlint over ESLint) when it covers the needed rules.

## Operate

- Treat pull-request and CI throughput as a performance problem. Optimize median time to merge, aiming for any pull request to merge within about an hour whatever its size. Rank pull-request lane speed first, then post-merge main builds, then billed minutes. Treat a red main or a slow check as a defect to fix at once.
- Measure the pipeline end to end. Track which lanes fail and why, have automation route each failing pull request to the lane that owns it, and inspect runs (artifacts, annotations, review comments) instead of trusting a green status. Record non-fatal problems (rate limits, auth failures, transient link errors) visibly without failing the build.
