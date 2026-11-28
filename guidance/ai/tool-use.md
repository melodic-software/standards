# Tool use

## Design

- Prefer a browser-automation CLI paired with a skill over a browser MCP server for agent browser work.

## Design and build

- Give an agent one tool per job and route through the best one, because overlapping tools confuse it. Prefer a few consolidated skills with action paths over near-duplicate variants, extending an existing skill before creating one.
- Build custom deterministic tools only when they improve on the native ones (a more restrictive script that can miss cases is worse), and otherwise use the most token-efficient tool the project already has or present the top options to install.
- Pair a feature map (context) with a control CLI (action) so an agent can understand and drive an app. Let agents learn external CLIs from their built-in help, and check a dependency CLI's setup and version on a cadence, not on every use.

## Build

- Lean toward model-invocable skills: anything an agent or automation must run itself is model-invocable, user-only needs a reason, and a skill loads whenever the task matches its domain. Use a skill only for the work it is named for.
- Describe what a skill or tool does, not its method, in a short description (soft cap around 300 characters rather than a raised listing budget), with expressive trigger words plus a central map of what to run when, following the vendor's naming and metadata guidance.

## Review

- Whether a skill gets used or should exist is judged by an external audit, not the skill itself. A recommender considers the whole catalog, disabled and uninstalled items included, by default. Audit third-party integrations for real use and vault-sourced keys.
