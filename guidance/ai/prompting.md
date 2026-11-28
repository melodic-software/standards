# Prompting

## Design and build

- Scope each instruction to the narrowest surface. A convention one component reads lives in that component's config. A cross-cutting one goes in a dedicated doc pointed to from the global file. Instructions for every project go in user-level config. A correction for one skill never becomes a global rule. Classify new content by taxonomy, semantics and scope before placing it.
- Keep conventions in AGENTS.md as the cross-tool shared file, with each tool-specific file importing it and holding only what that tool needs. Instruction tooling targets whichever file the consumer uses and knows how each one loads.
- Give each skill one responsibility, linking related skills (named successor and related) rather than merging them. Ship stack-agnostic skills that discover the consumer's stack at run time and point to upstream docs, or a generator that writes repository-specific skills, with a per-repository place for learned gotchas. Keep bodies within the vendor's size guidance with progressive disclosure. Compare against Matt Pocock's published skills and explain large divergences.

## Build

- Keep agent guidance universal and model-agnostic. Take a source's process and general ideas, not its specific choices, and state intent rather than concrete examples, which constrain newer models.
- Write instructions as positively framed guidance with the reason why, not strict never/always prohibitions, and add no needless caution or opinion, which makes agents overcautious.
- Write skill text precisely. Give closing sections one consistent pattern, and state for each step whether it is automatic, its trade-off and its cost. Add no output that changes nothing downstream, and make required steps prominent. Define every qualifier ("important", "large") and parameterize repeated values at the top. A shorthand means exactly its phrase. Hook messages state actionable facts only when relevant. Attribution and origin notes stay out of agent-loaded text.

## Build and review

- With each model release, research current guidance, remove instructions the model no longer needs (proving no regression), keep guidance only for models in use, and revisit trigger words. Validate a rule against real use before setting a limit, and ship only guidance the curator understands and endorses.

## Build and operate

- Once a rule has earned its place on a recurring problem, not one person's slip, enforce it with an automated check if it needs no judgment. A blocking check must be actionable, near-zero false positives, and about correctness; an advisory check keeps few false positives and is retired when unhelpful. The rule's owners decide to make a check required. Rules that need judgment, and social rules, stay with people. Cut duplicate, contradictory and no-op lines. Mine corrections from sessions and review comments on a schedule.
