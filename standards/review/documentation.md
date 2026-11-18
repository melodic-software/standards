# Documentation review criteria

Diff-time checks for tracked prose: docs, READMEs, conventions, and the instruction files and skills an agent loads. The authoring rules live in the engineering conventions this file cites; these bars flag a change that breaks them. Code comments are owned by [code-quality.md](code-quality.md), and copied external state such as an issue title or a `file:line` reference by [architecture.md](architecture.md#contract-evolution). Severity labels are defined in [README.md](README.md).

## Single source of truth

- **Restated source of truth**: a consuming file restates content whose canonical home is another file: definition prose, criteria, a mapping table, a threshold, or an exception clause, recapped instead of cited, even in one line. Tells: the chunk recaps more than a sentence of the source, or a value change would force editing both. Naming a contract token (a tier name, a label, a command) is not duplication, and an onboarding surface may restate when adjacent prose points back to the source. A double pin, citing both a source of truth and that source's own upstream, is the same defect: drop the upstream pin. Classify the file's role before flagging, per `../engineering/reference-dont-duplicate.md`, "Classify a file's role before flagging". Important.
- **Unresolvable citation**: a cited path, heading, or anchor that does not resolve in the repository, or a tracked file that cites a per-user file outside it (a local settings override, a personal instruction file, per-user memory) as authority. Important when the citation is load-bearing; Suggestion when illustrative.

## Upstream content

- **Upstream content recapped or its links scattered**: vendor or framework content (defaults, catalogs, schemas, flag inventories, pricing) recapped in tracked prose instead of linked, upstream links repeated across sections instead of placed at the sentence that defers to them, or research provenance credited in body prose ("per X's talk") instead of a sources footer. See `../engineering/documentation-and-citations.md`.

## Current state only

- **Narration and tombstones in prose**: prose that narrates a rename, refactor, or removal when the current form suffices ("superseded", "formerly", "was renamed to", "removed in …"). State the current path, name, or rule only. Decision-record status blocks, changelogs, and the other exceptions in `../engineering/legacy-and-migration-debt.md` are exempt; the code-comment form is `code-quality.md`'s removal-drift bar.

## Agent instructions

- **Instruction on the wrong surface**: content added to an always-loaded instruction surface that applies only to some files or tasks, deep reference detail added to a path- or task-scoped rule, a scoped rule whose path patterns match files it does not help, one rule file mixing concerns for disjoint file sets, or a convention placed where its readers cannot load it (agent-agnostic content only in one agent's private file). See `../engineering/progressive-disclosure.md`. Suggestion when the move is cosmetic; Important when the misplacement costs every session context or hides the rule from the reader who acts on it.
- **Repeatable procedure left as prose**: a numbered procedure in instructions or a skill that produces facts without judgment (an inventory, a validation, a count) and recurs, where a script would run it deterministically. Do not flag judgment-heavy steps. See `../engineering/deterministic-work-execution.md`. Suggestion.

## Prose edits

- **Meaning lost in compression**: a change that shortens prose and drops part of its contract: directive force weakened ("must" to "has"), a concrete example or literal token, one half of an "X, not Y" pair, a scope qualifier or threshold, a rule-specific rationale, a cross-reference, an exception clause, or an enumeration item. See `../engineering/concise-prose.md`, "Preserve the whole contract".
