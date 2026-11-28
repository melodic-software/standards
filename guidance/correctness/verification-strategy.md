# Verification strategy

## Design and build

- Settle assumptions and tool behavior with prototypes, safe probes and real runs (fallbacks included), not by reasoning about them.
  - Use your own tools on your own work.
  - Test a tool against large real-world input.
  - Test a pipeline end to end with tiny, trivial items that pass through every stage.

## Build and review

- Verify on the real installed artifact in the target environment, with evidence, before reporting done. Defer work for a platform you cannot run or test.

## Review

- Before calling work done, check real state against the original intent and re-walk the source material for anything missed. Review all of the work, revert what is wrong, and leave a clean result that is not overengineered.
- Before merge, a separate verifier checks the acceptance criteria against recorded evidence.
  - Fit the evidence to what the change touches: browser checks, screenshots, demo video, before-and-after comparisons.
  - Confirm visual evidence is feasible before building for it.
  - Publish evidence only once it is validated, and keep interim evidence on a temporary branch that is cleaned up afterwards.
- Verify UI alignment by pixel-level comparison on every page and screen, not by eye.

## Review and operate

- Run only the tests and evals the change affects, with the full suite on the main branch. Choose checks from change history, tool version changes and the changed files' types, not by inspecting content. Within a checklist, skip a step only when its actual results show it does not apply.
- In CI, run deterministic tests first, and hand off to agent-driven browser end-to-end verification only when they pass.
- Apply and test configuration changes from the feature branch before merge, so verification does not wait on the merge.
