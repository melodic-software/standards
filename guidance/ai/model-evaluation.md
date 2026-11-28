# Model evaluation

## Design and review

- Before investing in curated agent guidance, establish whether agents honor it and whether it improves output; check every change a harness makes to itself for whether it helped later, and remove what did not.
- Treat a benchmark, a vendor's own above all, as one input checked against others for scores and per-task cost; coding-agent leaderboards measure tactical completion, not codebase health; trial a new model until proven, then stop re-trialing.
- When a person finds a defect by hand, check whether automated review would have caught it and improve it if not, and choose an agent artifact's format by evals on candidate shapes built from real past artifacts.

## Plan and review

- Weigh an eval run's usage against its benefit and run only the subset that matters.

## Build and review

- Before shortening or rewording text a model loads, compare old and new on representative cases, scaled to the stakes. A change to bytes the model never loads, or one a script proves mechanical, needs none. Hold an eval-driven fix to its full pass bar or at least a measured gain over baseline.

## Review

- Settle measurable claims, including an expert's, with an eval that isolates the variable and uses a proper sample or repeated trials.
- Test agent tooling by running it headless against real cases, and test handoffs against other agent harnesses too, before and after the change.

## Review and operate

- Unattended work may merge on its own with evals as the gate; a quality drop below a threshold blocks the merge.
