# Session-time agent-output trust

An agent's output is not all destined for a diff. A status report, a summary, a
diagnosis, a count, a "done", a recommendation, an answer to a direct question —
each is consumed the moment it appears, and each becomes the basis for the next
decision without passing any gate. A committed change at least reaches a
reviewer; a mid-session claim reaches only whoever acted on it. This convention
states what the consumer of such a claim owes before acting, and what the
producer owes to make the claim usable.

The complementary diff-time criteria are in
[`../review/ai-generated-code.md`](../review/ai-generated-code.md), whose
[Why the extra scrutiny](../review/ai-generated-code.md#why-the-extra-scrutiny)
section carries the measured basis and is not restated here. Those criteria
judge the artifact. This file judges the claim made about it, which no review
sees.

These are **reasoning-only** judgments in the sense
[`enforceability-tiers.md`](enforceability-tiers.md) uses the word: whether a
report's scope matches the request, and whether stated confidence matches the
evidence behind it, turn on meaning. One half is deterministic in nature —
whether a report cites an invocation and its output at all is an existence check
— but a session transcript is not a tracked artifact, so no tool has anything to
gate. The obligation stays with the reader.

## Classify the claim before acting on it

What a claim needs is decided by what could verify it. The axis is where a check
can run — not who decides the verdict, which is the axis
[`enforceability-tiers.md`](enforceability-tiers.md) sorts on:

- **Verifiable now** — a mechanical check exists in this session: a count, a
  file's contents, an exit status, whether a symbol or package exists, whether a
  command succeeded. Run the check. Do not accept the assertion in its place,
  and do not accept a description of a check as the check.
- **Verifiable elsewhere** — the check needs a run, an environment, or an
  authority not present here. Carry the claim as a hypothesis with its check
  named, never as a settled fact, and hand the check forward with it.
- **Judgment** — a design opinion, a fit assessment, a severity call, a
  tradeoff. No check exists. Weigh the stated reasoning; where reasoning is
  absent, there is nothing to weigh and nothing to accept.

Misclassification runs one way: a **verifiable now** claim accepted as
**judgment** because it arrived phrased as a conclusion. How a claim is phrased
carries no information about whether a check was available.

## Claim shapes that do not survive contact

- **A completion report with no artifact** — "done", "fixed", "all tests pass",
  "every call site migrated", with no invocation, no output, and no path list.
  The evidence for work is the work's own trace; a report without it is a
  prediction in the past tense. Ask for the invocation and its material output.
- **Silent scope narrowing** — the report answers a smaller question than the
  one asked: three of nine call sites, one ecosystem of four, the happy path
  only. The tell is a scope word present in the request and absent from the
  report. Silence about coverage is not a claim of full coverage, and must not
  be read as one.
- **Uniform confidence** — every claim delivered at one certainty regardless of
  how it was obtained, so the reader cannot separate what was run from what was
  inferred. A report that flattens that distinction has destroyed the
  information the reader needed most.
- **A conclusion whose provenance is gone** — a summary of a summary, a
  subagent's return, or a recollection of earlier session work, presented as
  findings. The conclusion survived; the evidence did not. The rung it now holds
  is set by
  [`source-authority-tiers.md#the-four-rungs`](source-authority-tiers.md#the-four-rungs).
- **Agreement mistaken for corroboration** — several agents, or several passes
  of one agent, converging on an answer. The tell is a count of agreeing reports
  offered where independent sources were needed;
  [`source-authority-tiers.md#independence-is-what-corroboration-counts`](source-authority-tiers.md#independence-is-what-corroboration-counts)
  decides what such a count is worth.
- **A constraint that quietly stopped being mentioned** — a late claim that
  contravenes a limit set early: a directory that was out of bounds, a step that
  required approval, a tool that was excluded. The tell is a stated constraint
  that no recent output references — a goal is restated on every turn, a
  constraint set once is not.
- **An answer more confident than its retrieval** — an authority-shaped
  assertion about an external fact with no source named. Route it through
  [`source-authority-tiers.md#the-four-rungs`](source-authority-tiers.md#the-four-rungs)
  rather than judging it on how well it reads.

## What a usable report carries

The reciprocal obligation, and the cheapest way to make a claim actionable
instead of re-verifiable:

- The scope actually covered, stated against the scope requested, including what
  was deliberately left out and why.
- For anything executed, the record required by
  [`deterministic-work-execution.md#make-the-execution-honest`](deterministic-work-execution.md#make-the-execution-honest).
- For any external fact, the source and its rung.
- An explicit statement of what was *not* verified. This is the load-bearing
  item: a reader can act on a bounded claim, but cannot act safely on a claim
  whose boundary is unstated.

Confidence is reported as it was earned. Downgrading a claim costs one clause;
a reader discovering the downgrade later has already acted on it.

## Boundaries

- **vs [`deterministic-work-execution.md`](deterministic-work-execution.md)** —
  that file owns the producer's side: run the mechanical operation rather than
  predict its result, and record the invocation and input scope that make the run
  repeatable. This file owns the consumer's side — what is owed before acting on
  the report, whether or not anything was executed.
- **vs [`../review/ai-generated-code.md`](../review/ai-generated-code.md)** —
  that file owns the committed artifact at diff time: generation smells,
  hallucinated APIs and packages, injection surface, and confidently-wrong code.
  This file owns the confidently-wrong *claim about* the code, which no review
  sees. The confidence failure is split along that line, not stated twice
  across it.
- **vs [`source-authority-tiers.md`](source-authority-tiers.md)** — that file
  ranks an external source. This file governs an agent's assertion about its own
  work, which carries no rung until a source is named.
- **vs [`../review/testing.md#verification-honesty`](../review/testing.md#verification-honesty)** —
  that file owns which kind of proof a change's verification claim rests on,
  reviewed against the change. This file owns whether a session-time claim
  carries any proof at all.
- Not a harness or protocol specification. Which artifacts an agent writes, how
  a handoff is structured, and how a tool enforces any of this are a consuming
  system's concern.
