# Context engineering

## Design and build

- Keep always-loaded context to what every session needs and load the rest on demand by concern as the conversation evolves. A convention must load from an always-present surface, not depend on a skill being invoked. Load surface-specific instructions only where they work, detected at run time. Place context by audience (personal stores versus a shared home).
- Put detailed agent instructions in a failing check's error message so they load only when needed, feed long documents section by section, and prefer a question-keyed summary cache for large docs pages.
- Enforce rate limits, spend and turn caps in the harness. Show the agent a budget it can plan against, such as tool calls or a task budget; withhold raw rate-limit or plan-usage figures it cannot act on. Where context figures are shown, pair them with the continuation mechanism and a reminder not to stop early. Guards state facts and never push an agent to stop early, run fewer agents or pick weaker models. Agents get the current date and time.

## Design and operate

- Prefer one reliably searchable append-only log that agents query over layered progressive disclosure, given retention and a path to aggregate across machines. Shared agent memory must work on every machine and in the cloud. Store a person's ruling on a finding so later runs never re-flag it. Keep discovery, specs and plans in the central tracker.
- A forked subagent is cheap only while the prompt cache is warm; design so a cold cache does not silently multiply cost.

## Plan and operate

- Keep a session under about 60 percent of its context window (80 at most), sizing tasks to fit and handing sizable side work to a separate session or subagent. At a phase boundary, choose between handing off and continuing by how much context remains.

## Operate

- Prefer a targeted save of state, split into always-load and load-later, over lossy compaction. A handoff carries and restarts the prior session's running loops, watchers and scripts, and the resuming session catches up on what happened since. Prove handoff flows before relying on them. No automatic handoff fires while a completion goal is active, and a manual one clears the goal.
- Before retrying a failed agent run, stop everything and clear stale files and context so they do not mislead the retry.
