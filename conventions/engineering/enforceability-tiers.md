# Enforceability tiers

Some conventions a tool can decide alone; some need a tool to flag candidates and a human to judge; some are pure judgment no tool can make. Classifying a convention by which tier it belongs to is what keeps this catalog honest: a rule a tool *can* own should move into a component config and stop reaching reviewers, while a rule that is irreducibly judgment should stay in prose and not pretend to be automatable. Tool-enforceable rules belong to `components/` (or their root-canonical payload); reasoning-only rules live here in `conventions/`.

## The three tiers

| Tier | Who decides | When it applies |
|---|---|---|
| **Deterministic** | a linter, analyzer, or hook alone — pass/fail, no judgment | existence, format, syntax, exact match, count, path shape |
| **Detect-then-judge** | a tool flags candidates (advisory); a human or agent rules on each | a mechanical signal narrows the set, but the verdict needs meaning or context |
| **Reasoning-only** | a human or agent against written criteria — no tool can decide | meaning, intent, fit, abstraction quality, semantic equivalence |

Deterministic examples are the kind of thing executable components own: a banned symbol, a code-style rule at error severity, a secret pattern, a malformed file. Detect-then-judge covers things like a near-duplicate flagged for a human to decide whether to extract, or an unrecognized CLI flag flagged for the author to confirm against the tool's help. Reasoning-only covers "is this the right abstraction", "does this name track its responsibility", "does this comment explain *why* and not *what*".

## Rule of thumb

Existence, format, and syntax are **deterministic**. Meaning, intent, and fit are **reasoning-only**. **Detect-then-judge** is the middle: a cheap mechanical pass narrows the candidate set, then a human or agent rules on each survivor — never an auto-fix, because the deciding step is judgment and a confident false-positive fix is worse than a flag.

A finding can only climb to a tier its *nature* allows. No amount of cleverness makes "is this the right abstraction" deterministic; no review discipline is needed for "does this file parse" once a tool owns it.

## Routing a recurring finding

When review keeps catching the same issue, classify its tier and move it as far up the enforcement hierarchy as the tier permits:

- **Deterministic** → a linter, analyzer, or commit hook. The issue stops reaching review entirely.
- **Detect-then-judge** → a tool that flags (advisory) plus a human verdict. Keep it advisory.
- **Reasoning-only** → it stays in convention prose and review criteria. Not scriptable; do not pretend otherwise.

Tier classification answers *can* this be mechanized. Whether a candidate is *worth* mechanizing — given the false-positive rate, the maintenance cost, and how often it actually fires — is a separate decision, and the default answer is "not yet". Classify the tier first; justify the automation second.
