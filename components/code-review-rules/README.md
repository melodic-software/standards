# Code Review Rules section

Codex reviews pull requests on every Melodic Software repository and takes its
review guidance from a `## Code Review Rules` section in the root `AGENTS.md`
([Codex GitHub docs](https://learn.chatgpt.com/docs/third-party/github),
fetched 2026-09-30). Every non-archived repository carries that section in the
shape below, so the Codex reviewer gets the same rules the Claude review lanes
read. Decided in `melodic-software/standards#656`; the pilot is
`melodic-software/claude-code-plugins#5966`.

## Shape

The section has two parts, in this order:

1. **The inherited block**, copied verbatim: the heading, one intro line, and
   one org-wide pointer to `REVIEW.md`.
2. **The per-repository slot**: zero or more pointer lines for rules the
   repository owns. A repository with none carries the inherited block alone.

Every line is a pointer. It opens with a short rule name, then links the file
that states the rule in full; it never copies the rule's text. List only
consequential, repository-specific rules that CI does not already enforce
mechanically. Codex follows a link to an in-repository file outside the diff:
a probe on the pilot repository raised a finding citing the linked file
(`melodic-software/standards#656`, one run per arm).

## The inherited block

Copy this block, with the one pointer line that matches how the repository
receives `REVIEW.md`: its `review-instructions` entry in
[`sync-manifest.yml`](../../distribution/sync-manifest.yml).

```markdown
## Code Review Rules

Each line names a rule CI does not enforce; the linked file states it in full.

- Org-wide criteria: [`REVIEW.md`](REVIEW.md), synced from `melodic-software/standards`.
```

That pointer line is the `managed` case. Any other case replaces it:

- `locally-owned`:

  ```markdown
  - Org-wide criteria: [`REVIEW.md`](REVIEW.md), a locally-owned copy reconciled with `melodic-software/standards`.
  ```

- absent, so the repository has no root `REVIEW.md`:

  ```markdown
  - Org-wide criteria: [`REVIEW.md`](https://github.com/melodic-software/standards/blob/main/REVIEW.md) in `melodic-software/standards`.
  ```

- `standards` itself, the canonical source:

  ```markdown
  - Org-wide criteria: [`REVIEW.md`](REVIEW.md), the canonical source the standards sync distributes.
  ```

The absent case links the canonical file by URL. The probe covered in-repository
links only, so whether the Codex reviewer fetches that URL is unverified;
adopting `review-instructions` gives such a repository the in-repository form.

`standards` owns no other org-wide review rule that belongs in the block:
`REVIEW.md` already points into [`conventions/review/`](../../conventions/review/README.md),
and the pull-request title, body and `do-not-merge` contract is checked by the
`ci-status` pull-request contract step, so it stays out.

## Per-repository slot

Add lines after the inherited pointer, each in this form:

```markdown
- <Short rule name>: [rule](<path to the file that owns it>).
```

Point at whichever file already states the rule: a `.claude/rules/` file, a
`CLAUDE.md` or `AGENTS.md` section, a Cursor rule, an ADR, or a convention
document. Keep the section short; when a rule needs more than one line, the
linked file holds the rest.

## Check

[`code-review-rules.sh`](code-review-rules.sh) checks the section: the heading
appears once, its section holds the intro line verbatim, and its `REVIEW.md`
pointer links `REVIEW.md` when the repository has a root `REVIEW.md` and the
canonical URL when it does not.

- `code-review-rules.sh file` checks one checkout. The `code-review-rules` lane
  in `ci.yml` runs it on this repository on every pull request, beside the
  contract test [`code-review-rules.test.sh`](code-review-rules.test.sh).
- `code-review-rules.sh fleet` checks repositories through the GitHub contents
  API. The scheduled
  [`code-review-rules-inventory`](../../.github/workflows/code-review-rules-inventory.yml)
  workflow runs it over the org's public repositories with the workflow token
  and over the standards-sync App installation's private repositories with a
  read-only App token, so a new repository is flagged once it is public or a
  sync target. A private repository outside the installation is not visible to
  either token.

The fleet run is report-only while `standards#656` rolls the section out: it
annotates each nonconforming repository with a warning and passes. Once every
repository conforms, set `REPORT_ONLY` in that workflow to `false` so drift
fails the run, as `lychee-private-inventory` does. Like that workflow, it opens
no issue.

## Ownership

- **Owner**: the `standards` maintainers.
- **Delivery boundary**: a check, not a synchronized file. Each repository's
  `AGENTS.md` is repository-owned content with a per-repository slot, and the
  distribution model has no partial-merge layer
  ([distribution contract](../../distribution/README.md)), so the section is
  copied once by a rollout pull request and held in place by the check.
- **Rollback**: delete the workflow and the `code-review-rules` lane; the
  sections already landed stay valid `AGENTS.md` content.
