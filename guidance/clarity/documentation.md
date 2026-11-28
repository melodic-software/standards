# Documentation

## Build

- Date the records tied to a moment: research, experiment results, decision records, changelogs. Keep time-anchored wording out of reference and instruction prose, except a value copied or measured from upstream, which carries its as-of date and recheck trigger beside it. When a rendered docs page needs a currency signal, its owner and review date go in metadata the platform shows. Detect moved or broken links mechanically: use references that need no upkeep, such as stable record ids, and run a link checker in CI.
- Record durably what experiments on unclear upstream behavior found (how to keep those records current is still open). Keep digested external content raw in a knowledge corpus, and mine takeaways from it separately.
- Write succinct, scannable prose with the bottom line first, free of AI-writing tells and em dashes, in American English enforced by a linter. Fix genuine misspellings in text you own; exempt only real aliases or copied text.
- Keep established, current industry terms and product names instead of simplifying them away, and never reword in a way that risks semantic accuracy or obscures intent. When migrating content, carry source sentences over verbatim unless a written rule requires a change. When adopting an upstream approach, represent it accurately and add nothing it does not support.
- A technical design gives implementers an ordered roadmap for shaping the code and points at existing conventions as guardrails. Research output leads with a short summary, with the full report beneath it.

## Build and review

- Docs state current truth only. Working code is the source of truth: fix or delete docs that drift from it, and prune dead, superseded or bloated content. Leave history to version control and decision records, and keep ephemeral specs and plans out of the codebase.

## Build and operate

- Any markdown kept in the code that must be maintained (generated maps, feature docs) needs a known trigger for its upkeep. Update it in the same change that touches the feature, and give every lesson learned a defined home.
