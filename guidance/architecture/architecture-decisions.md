# Architecture decisions

## Design

- Prefer designs that make a choice cheap to reverse. Take the simple path for choices that can change cheaply; spend analysis before committing only on the ones that stay hard to reverse.
- Choose tools in this order: native platform features used as far as the official docs allow, then a popular existing tool you research, test and wrap, and custom building only where nothing fits. Pick by measured fitness, not fashion. When a vendor ships a feature that overlaps in-house tooling, decide per piece in a decision matrix whether to keep, go hybrid or migrate fully. Avoid depending on a single provider's terms or host: build fallbacks and make locations configurable.
- Adopt no tool, hyped or not, until its required use cases and edge cases pass your own tests, learned from fundamentals rather than hype. State definitively what it gets you. Make a trial's bar for failing as strict as its bar for passing, and record why a candidate failed. Default to the option with the best demonstrated output; keep a weaker one supported but not as the default.

## Design and review

- Base every decision on facts, measurements and the current consensus of authoritative sources, and state the basis. Treat claims from agents, experts and benchmarks as hypotheses. A fact about a product's own behavior or interface rests on its owner's current official source; a comparative, performance or self-serving claim from that owner needs independent corroboration. A design choice rests on the canonical source that defines the pattern and its recognized experts, with dissent noted; no source count is fixed. Prove choices on your own workloads. Merge overlapping approaches into one consensus design, and fold in the good parts of outside ideas rather than adopting them wholesale.
- Nothing is justified by existing. Reason the design out from the problem, not from the current implementation. Inventory the building blocks and data already available, and challenge incumbent structure, conventions, records and tools. Recheck incumbent tools on a schedule, including what the community uses most. Keep a convention unchanged when the only reason to change it is to suit another tool.

## Design and plan

- Add a mechanism, artifact or process only when a real consumer and evidence of value exist. Prefer the simpler option. Check designs for overengineering at interview and plan time, and weigh each proposal for the drift and maintenance it invites.
- Before building out, pin down the format and framework, poke holes in the design, measure it and run a small trial. For hard design or naming choices, generate at least three alternatives and have unbiased judges pick before a human approves. Keep a change only on evidence, and revert failures with a documented post-mortem.

## Design and build

- Reserve ADRs for decisions that are hard to change, with strict written criteria for what earns one. An ADR records the rejected alternatives, the reasoning the code cannot show and the upstream sources behind the decision. Title it so an agent can generalize the decision from the title alone. Once an accepted ADR's decision is implemented, it is not edited: a reversal gets a new ADR, and the old record stays, marked superseded with a link to the new one. Clarifications, link fixes and changes to a decision never implemented may be edited in place. Other docs change in the same change as the code they describe.
