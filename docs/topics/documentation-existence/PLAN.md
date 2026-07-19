# documentation-existence

## Brief

**TLDR:** Add `conventions/engineering/documentation-existence.md` — the admission test governing whether a doc may exist at all — as the upstream gate of the documentation conventions family, with one-line seam updates in siblings.

**Goal:** Codify the existence test: a doc may exist only when its content's source of truth IS the doc — content code cannot express. Admitted categories: decisions and rejected alternatives (ADRs), domain language (glossary), navigation (one thin index with context-clue links to scenario-scoped files; shape owned by `progressive-disclosure.md`), and policy/wiring (owned by `documentation-and-citations.md`, cited not recapped). Refused: hand-written restatement of anything an agent can derive from code by search — a second source of truth, drift by construction. Sanctioned exceptions: the Expose role (`reference-dont-duplicate.md`) and automated derivation (generated docs with an automated regeneration path only).

**Constraints:**

- Single-concern doc alongside the family; no file merges. Siblings get one-line ownership-map seam updates; existence-ish claims that leaked into siblings are trimmed (moved, not duplicated).
- Reasoning-only tier, declared in the opening paragraph per family pattern. Seam notes only: navigation-map link validity is deterministic; doc-recaps-code candidates are detect-then-judge.
- Convention stays tool-agnostic. Motivation (second source of truth, drift by construction, recurring token cost) woven into the opening paragraph; research provenance in a sources footer.
- Cite sibling seams; never recap their content (`reference-dont-duplicate.md` discipline applies to this doc itself).

**Acceptance criteria:**

- `conventions/engineering/documentation-existence.md` exists, states the test ("could an agent with repo search derive this from code? yes → the doc may not exist"), the four admitted categories, the refusal, and both exceptions — each seam by citation.
- Every sibling whose ownership map should reference existence (`concise-prose.md` at minimum) carries the one-line seam update.
- Any existence-scoped claim found in siblings is relocated into the new doc, not duplicated.
- `conventions/engineering/README.md` (if it indexes the family) lists the new doc.
- Doc passes the repo's own conventions: concise prose, progressive disclosure, no duplication, tier declared.

**Captured assumptions:**

- Remediation of existing repo docs is opportunistic (Boy Scout, maintenance cycles, on-demand audits) — no mandated fleet sweep; a sweep remains available as a later explicit decision.
- Tooling charter-sharpening (`doc-drift-detector`, `docs-hygiene:declutter` gain the admission test as a pre-check; failed admission routes to deletion, not update) is a separate follow-up change in `claude-code-plugins`.

**Out-of-scope:**

- Fleet-wide audit of existing docs.
- Plugin/tooling changes (separate follow-up).
- Shareability machinery — resolved as already-solved: `standards` and `claude-code-plugins` are public; `follow-our-standards` binds via consuming-project declaration; day-job portability = marketplace install + declared standards source.

**Deferred questions:**

- Matt Pocock citation for the sources footer — RESOLVED: user-supplied X post shipped in the footer and verified live (author `@mattpocockuk`, quoted text matches).
- Whether `sync-manifest.yml` should distribute any part of this convention as a managed component — `/architect`.
- Tooling follow-up design (plugins repo): whether the admission test ships as the portable-baseline default in `doc-drift-detector` / `docs-hygiene:declutter` — consuming org's declared conventions always win via the `follow-our-standards` resolution ladder; plugins never hard-code `melodic-software/standards` (verified: zero runtime references) — decided in that follow-up, not here.

## Plan

Intentionally deferred — no `/architect` pass was run; this single-concern documentation change shipped directly from the Brief above. The one open architecture decision it surfaced (managed-component distribution) is tracked in #207.
