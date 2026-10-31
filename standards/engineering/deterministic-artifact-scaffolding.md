# Use deterministic artifact scaffolds

When an artifact repeats a stable structure, emit that structure with the
narrowest deterministic mechanism that fits: a platform-native form or
template, a schema-aware serializer, or a producer-owned template. A human or
model supplies only the values that require judgment. OpenAI's
[Structured Outputs guide](https://developers.openai.com/api/docs/guides/structured-outputs)
separates schema adherence from generation quality and recommends evals for
the latter; a scaffold owns the former, not the latter.

Choosing whether a shape is stable and reusable remains a reasoning-only
decision. [`enforceability-tiers.md`](enforceability-tiers.md)
owns that classification. A repeated heading or field can be deterministic
while the explanation, evidence, or decision placed beneath it still needs
human or agent judgment.

## Admit one artifact shape at a time

A scaffold needs a live producer and consumer, a repeated shape whose meaning
is stable, an accountable owner, and a measurable acceptance condition. Apply
the evidence and rollback requirements in
[`../../docs/component-lifecycle.md`](../../docs/component-lifecycle.md)
before promoting a producer-local experiment into shared policy. Do not build a
generic engine for anticipated artifact kinds or combine unrelated shapes
behind one placeholder language.

Prefer the artifact platform's native mechanism when it supplies the required
behavior. Otherwise, keep the template, schema, or serializer beside the
producer that understands the artifact. Anthropic's
[tool-design guidance](https://www.anthropic.com/engineering/writing-tools-for-agents)
likewise recommends choosing response structure through task-specific
evaluation rather than assuming one format fits every agent workflow.

The deterministic boundary must:

- define every required slot and reject missing or invalid required values;
- produce the same fixed structure for the same scaffold version and inputs;
- reject unresolved placeholders and output that fails its declared
  syntax or schema;
- avoid silently overwriting an existing artifact; and
- leave semantic correctness, evidence quality, and fitness for review to a
  human or agent.

## Ownership and delivery

| Artifact | Owner and delivery |
|---|---|
| Organization pull-request and issue-template bytes | `melodic-software/.github`, delivered through GitHub's native organization defaults. GitHub uses a public `.github` repository for defaults and gives repository-local templates precedence. For issue templates, any file in the local `.github/ISSUE_TEMPLATE` directory, including `config.yml`, prevents use of every file from the default repository's `ISSUE_TEMPLATE` directory ([GitHub default community-health files](https://docs.github.com/en/enterprise-cloud@latest/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)). |
| Repository settings, label definitions, and other provider-expressible governance | The relevant `github-iac` repository. It does not own the template file contents. |
| Repository-specific GitHub-template overrides | The consuming repository. The override is local behavior, not a partial merge with organization defaults. |
| Architecture-decision scaffold | The existing [`architecture-decisions` component](../../docs/adr/README.md) in this repository; each consumer continues to own its ADR contents and numbering. |
| Report, configuration, and skill scaffolds | The producer that understands the artifact. Admit each shared shape independently; do not create a catalog entry without a live consumer. Anthropic's current [Agent Skills specification](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) defines the required `SKILL.md` surface, but a repository-specific skill generator remains product behavior. |

The organization GitHub templates therefore do not belong in
`distribution/sync-manifest.yml`: GitHub already provides the native delivery
path, which precedes exact-file synchronization under
[`../../docs/adr/0001-federated-component-distribution.md`](../../docs/adr/0001-federated-component-distribution.md).
Configuration boilerplate already owned by a standards component stays in that
component; repository-specific adapters remain local.

A scaffold fixes structure; it does not copy editorial rules that another
convention owns. Link judgment-bearing slots to their authority, such as
[`concise-prose.md`](concise-prose.md), under the
[`reference-dont-duplicate.md`](reference-dont-duplicate.md) rule.

## Deferred policy and producer changes

This convention does not choose pull-request body headings or other
user-reserved fields. [`issue-tracker.md`](../process/issue-tracker.md) exposes
the current linkage rule;
[standards issue #173](https://github.com/melodic-software/standards/issues/173)
owns its reconciliation with the deployed gates and the future policy-as-data
boundary. Corrections to the current organization template bytes must land in
`melodic-software/.github` after that decision rather than being preempted here.

A skill-skeleton generator likewise remains deferred to its producer while
[claude-code-plugins pull request #293](https://github.com/melodic-software/claude-code-plugins/pull/293)
settles that repository's generation direction. Neither dependency blocks this
owner-selection convention.

## Make only measured efficiency claims

The acceptance claim for a scaffold is consistent structure and validated
required slots, not a universal token saving. Response structure affects agent
performance differently by task, and tokenization varies by model. Measure any
token or cost claim against the same representative workload, model, and
creation path, then record the actual usage metric and recheck trigger.
Anthropic's [token-counting documentation](https://platform.claude.com/docs/en/build-with-claude/token-counting)
explicitly requires counts to be taken with the model that will run the
workload and treats preflight counts as estimates.

## External authorities

- [GitHub, "Creating a default community health file"](https://docs.github.com/en/enterprise-cloud@latest/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)
- [GitHub, "About issue and pull request templates"](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/about-issue-and-pull-request-templates)
- [OpenAI, "Structured model outputs"](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Anthropic, "Writing effective tools for AI agents"](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Anthropic, "Agent Skills"](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Anthropic, "Token counting"](https://platform.claude.com/docs/en/build-with-claude/token-counting)
