# Reference, don't duplicate

Every fact has one source of truth. A consumer of that fact cites it; it never restates it. A one-line "summary" of someone else's rule is the cheapest thing to write and the most expensive to maintain — when the source changes, the copy silently drifts and readers can no longer tell which version is canonical. This is a reasoning-only discipline: a tool can flag candidate duplicates, but deciding whether two passages *mean* the same thing is a judgment.

## Two kinds of duplication

- **Literal** — a verbatim repeat of a value across files: a version pin, a port, a URL, a path, an identifier.
- **Semantic** — the same concept reworded: one rule explained three different ways across three files, one prerequisite described with different phrasing in four documents.

Literal duplication is easy to grep. Semantic duplication is the harder, equally costly smell — every update touches N sites, divergent phrasings produce silent contradictions, and readers cannot tell which is authoritative.

## Smell signals — any one triggers the rule

1. You edit the same idea in three or more files in a single change.
2. A search finds three or more near-matches saying almost-but-not-quite the same thing.
3. Two files assert the same rule with contradicting nuance.

## Classify a file's role before flagging

Each file plays one of three roles toward a given fact:

- **Describe** — the file *is* the source of truth and owns the value or concept. Keep the body here.
- **Use** — the file consumes the fact as a load-bearing reference (rules, conventions, internal docs). It must cite the source by a stable anchor rather than restate the content.
- **Expose** — the file surfaces the fact to humans for onboarding clarity (a README install command, an error message, a baseline snapshot). It *may* restate when onboarding clarity outweighs maintenance cost — and only when adjacent prose points back to the source so a future maintainer finds every copy.

## What stays inline versus what must be cited

**Stays inline (it is the contract surface, not duplication):** public names the source defines — severity tier names, label slugs, action verbs, command names, type identifiers. Naming a contract token is not copying it.

**Must be cited, never recapped:** definitions, criteria, "when to use" descriptions, mapping tables, examples, threshold numbers, and exception clauses — anything specific and subject to change. A one-line recap drifts when the source updates; the citation alone is sufficient.

## Cite stable anchors

Cite a source by something durable: a file's documented heading, a configuration key, a published symbol — an anchor the source intends to keep stable. Avoid citing line numbers, incidental phrasing, or internal structure that the source is free to change without notice. Prefer a link the reader can follow over a prose reference they must hunt for.

## The code and config equivalent

The same discipline holds outside prose. Deduplicate with the language's idiomatic mechanism — a shared constant, a build property and its reference, a YAML anchor and alias, a JSON `$ref`, an environment variable with a default — rather than copying a literal across call sites. A repeated literal is both the duplication and the missing name; the named constant deduplicates and documents in one move.

## Related

- Citing authorities *outside* the repo (vendor docs, framework references) — see `documentation-and-citations.md`.
- Resolving derivable external state instead of copying a snapshot of it — see `legacy-and-migration-debt.md` for the current-form-only posture.
