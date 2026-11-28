# Coding agents

## Any stage

- Keep humans on planning and intent and delegate the rest. Align intent up front into an agent-ready work-item contract, then let an autonomous pipeline carry it to merge and beyond, stopping for a human only on a departure from intent or a serious security risk.

## Interview and plan

- Start from intent captured exactly, confirming understanding and asking whether to rethink a prescribed solution. Run explore, research, plan, implement and verify with the available skills, discovery covering code, history and outside sources. Choose the workflow with the fewest turns, tokens and wall time that still gives an accurate signal, and flag when implementation proves the plan wrong.

## Design and operate

- Keep only the human-in-the-loop stages (discovery, requirements, design, planning, writing work items) in interactive local sessions. Hand implementation, testing, review and shipping to unattended CI automation, which routes problems back as needs-human, unless a step needs a local dependency.
- Widen autonomy iteratively behind guardrails, and remove the human only where reliable verification exists. Classify each mechanism as a brake or an accelerator and balance them, since agents produce fast work with a maintenance cost. Oversight interjects before work that would have to be reverted, not after.

## Build and review

- Fence an agent to its assigned scope and stop when the asked work is done, while still investigating adjacent options in the area. An audit or cleanup covers every file in scope, never a sample. Fix a blocking or serious defect now; handle any other found defect, including one in its own tools, as team.work-item-flow says.

## Operate

- In unattended runs, no permission prompt can block: an unexpected prompt is a signal to fail early. Use single shell invocations, not loops or chained commands, and reference only invocable commands. On an item needing a human, stop, push the work, post why, keep the branch, and apply a needs-human marker that blocks merge. Durably record every decision taken on a human's behalf and every gate relaxed, with how to undo it.
- An unattended lane never edits its shared checkout and never skips hooks; its workspace persists until whoever merges removes it. A scripted precheck stops it without spending tokens when there is nothing to do, and it checks remaining quota first. With nothing left, it stops outright, leaving no watchers burning tokens.
- An orchestrator inventories its agents and loops, confirms each finished, retries failures with a fresh worker before naming the human action needed, and resumes every interrupted agent after a crash. It caps concurrent work by host CPU and memory and sizes limits to the task, not fixed turn or time caps. Long efforts run under a goal whose done condition is proven by command output, and an automated kill is reported and easy to resume.
