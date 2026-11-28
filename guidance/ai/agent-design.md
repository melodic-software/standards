# Agent design

## Design and build

- Use scripts, tools or fixed templates for every judgment-free step and spend model reasoning only where judgment is needed, but only when the script safely handles every foreseeable case. Prefer shipped, tested, fast helper scripts over improvised ones, and give scripts over changing input a drift check.

## Design and operate

- Scale orchestration to the work, yet fan out to as many parallel threads as it allows rather than an arbitrary limit. Keep the orchestrator slim, gather context top-down, then fan out with subagents returning only what is needed. Run code exploration and external research as separate concurrent lanes. Tools behave the same interactively, autonomously, in the cloud and in CI.

## Design and review

- Run an implement-verify loop in which a separate fresh-context verifier judges recorded evidence against criteria and intent, given the research behind the choices, not the author's reasoning. For contested decisions, have a few strong agents challenge the plan. Add a second-vendor AI reviewer beside the primary, and give every delegated harness the same tools.
- AI reviewers and observers must earn their spend. A model told to find problems always finds some, so adversarial or repeated review is configurable, leaning off by default and settled by eval. An observer surfaces what the working model cannot see, sends only departures from intent or standards, batched, tracks its own per-session overhead, and returns schema-validated output. A shipped reviewer's opinionated rules are suggestions the user opts into.

## Design and plan

- Route each role to a model and effort matched to its complexity: a lighter model for mechanical work, a stronger one for orchestration. Prefer a stronger model over maximum effort on a weaker one, default to high or higher effort, cap it at high or extra-high, and send the most expensive model to the tasks matching its measured strengths.
- Pick each role's model from measured evals. Until a role has one, it inherits the session model; mechanical work with a checkable output may route to a cheaper model. No source supports the smallest model at high effort as a general default.
- Pick model, vendor and effort per task by type and size from official model cards and docs, community consensus and independent benchmarks, discounting sponsored ones, and move work to a model only when its quality ties or beats the incumbent's. Name models by class, not version. Bind a subagent's tier in its definition, overridable, with no global force-override. Prefer a general subagent over per-persona definitions.

## Plan and operate

- Let parallel sessions on any machine discover and message each other directly through the harness's messaging, compactly, rather than through a human relay or a shared lock. Before a large or unattended multi-agent run, every session acknowledges the goal and agrees disjoint responsibilities. Split backlogs into disjoint groups with race-safe claims. Run sweeps once at the root, never from forks. One hub agent owns cross-session monitoring.
