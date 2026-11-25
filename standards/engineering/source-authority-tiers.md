# Source authority tiers

Not every source that can be cited settles a question. A claim about how a tool
behaves, what a default is, or whether an option exists is only as strong as the
distance between the claim and the thing that decides it, and a citation alone
does not record that distance. This convention says what each kind of source is
worth and how many a claim needs before it is treated as settled.
[`documentation-and-citations.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/documentation-and-citations.md) owns *whether
and where* a citation appears once a claim is accepted; this owns *what the
source is worth* and *how many are needed*. Neither answers the other's
question.

This spans two of the tiers [`enforceability-tiers.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/enforceability-tiers.md)
defines. Counting sources is **deterministic** in nature, but the sources are
named in a session, not in a tracked artifact, so no tool has anything to count.
Deciding what kind of source something is, and whether two sources are
independent, is **reasoning-only** regardless: it turns on what the source owns
and where its content came from. The obligation stays with the author either
way.

## Four kinds of source

What a source is worth depends on how many hands the information passed through
to reach you, not on prestige or search ranking.

| Kind of source | Examples | What a claim can rest on it |
|---|---|---|
| The thing itself, answering now | command output, a file's contents, an API or query response, a live configuration value | first-hand; a claim may rest on it |
| The official source that defines or owns the thing, read at its current version | the specification, the vendor's own reference, the source code, the changelog, the registry entry | first-hand; a claim may rest on it |
| Someone else's account of either of those | a practitioner write-up, a community answer, a synthesis tool's response, a subagent's summary | supporting only; a claim may not rest on it alone |
| Memory, with no source behind it | recall, an assertion whose source cannot be named | not a source; find a first-hand source or drop the claim |

Someone else's account is not weak because it is wrong; it is weak because a
reader cannot tell whether it is wrong without reading the first-hand source it
paraphrases. Naming that source is its whole value, and it keeps that value only
while it does: a summary of a summary, or a report whose sources are gone, is
worth no more than memory, whatever it originally said.

## Official means owning the fact, not being reputable

A source is official for the facts it owns and someone else's account for
everything else. The same page changes kind with the question: a vendor's
reference is official for its own product's behavior and an outside account of a
competitor's; a specification is official for what it requires and an outside
account of whether any implementation conforms; a maintainer's post is official
for intent and an outside account of shipped behavior. Judge the source against
the claim, never against the domain's reputation.

Two consequences follow. Where a claim states a *runtime* fact, such as what a
version does, what a flag accepts, or what actually installed, the thing itself
outranks its official documentation: a release can ship ahead of the
documentation that describes it, so when the two disagree about behavior, the
running system decides. And a negative claim ("that option does not exist", "it
was removed", "nothing supports this") can only rest on the thing itself or its
official source, read for this claim: absence from someone else's account, or
from memory, is evidence of nothing.

## How many sources a claim needs

One first-hand source that owns the fact, read for this claim, is enough to rely
on. Independent sources that confirm it are worth adding where they exist,
especially when the claim enters durable content, gates an irreversible action,
or bears on security or identity; they are never required. A consumer may
require more in its own settings.

- Count independent sources, not citations. Two sources are one when they share
  an upstream source, an author or author network, a generating tool, or a
  single model's priors: three write-ups paraphrasing one release note are one
  source.
- Someone else's account never carries a claim alone, however many agree.
- For a high-stakes claim, a second first-hand source, such as checking the
  thing itself against its documentation, is worth more than further accounts.
  More accounts guard against one source being unrepresentative, not against
  every source being wrong.
- When sources disagree, the claim is not settled by any count. Settle it
  against the official source, or record the claim as open.

## A source must be re-read in the session that relies on it

What a source is worth depends on when it was read. A source read in an earlier
session is worth no more than memory: its content now comes from recall, and the
upstream may have moved. Re-read it before relying on it. This governs a
source's standing as evidence;
[`documentation-and-citations.md#time-bound-external-claims-need-a-recheck-trigger`](https://github.com/melodic-software/standards/blob/main/standards/engineering/documentation-and-citations.md#time-bound-external-claims-need-a-recheck-trigger)
governs the separate obligation attached to a time-bound fact once it is written
into durable content.

## Grounding a recommendation

A recommendation, option, or decision put in front of someone else rests on
sources read for it before it is presented, without waiting to be asked.
Ground it in both directions:

- **Locally**: read the code, configuration, or document the recommendation
  affects, and list who consumes it: callers, dependents, and other
  repositories that read it. That inventory is evidence from the thing itself;
  a recommendation that skips it is guessing at its own reach.
- **Externally**: for a tool, version, or API, the owner's current reference
  first. For a design pattern, the source that defines it (the Gang of Four
  catalog, Fowler's catalogs, *Enterprise Integration Patterns*, the
  domain-driven design books) and the recognized practitioners who build on
  it, with publication dates and any dissent noted. A pattern's definition
  does not weaken with age; a product default does.

Adoption is not authority. A pattern found in a template, a sample, or a
popular repository shows that people use it, not that it serves the principle
it claims to. Check it against that principle before recommending it, and say
so when a common pattern fails the check.

## Boundaries

- **vs [`documentation-and-citations.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/documentation-and-citations.md)**: that
  file owns whether a fact is cited rather than copied, where the link sits, and
  which footer it belongs to. This file owns how much the cited source is worth
  and how many are required.
- **vs [`reference-dont-duplicate.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/reference-dont-duplicate.md)**: that file
  owns one source of truth per fact inside the repository. This file ranks
  sources outside it, where there is no single owner to defer to.
- **vs [`deterministic-work-execution.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/deterministic-work-execution.md)**:
  that file owns whether an execution was honest enough for its output to count
  as evidence at all. This file owns what that output is worth beside other
  sources once it does. A first-hand source means a claim may rest on it; it
  does not mean the source answered the question that was asked.
- **vs [`enforceability-tiers.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/enforceability-tiers.md)**: that file
  classifies a *convention* by who can decide it. This file classifies a
  *source* by what it can establish. The two are unrelated; only the
  vocabulary for this document's own classification is borrowed.
- **vs [`session-time-agent-output-trust.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/session-time-agent-output-trust.md)**:
  that file governs an assertion an agent makes about its own work. An
  agent's assertion is worth what the source it names is worth, or no more
  than memory when it names none.
- Not a research procedure. How many queries to run, in what order, and when to
  stop are a consuming tool's or process's concern. This file supplies only the
  kinds of source and the sourcing rule those procedures resolve against.
