# Dependabot-policy threat model

This model covers the read-only analyzer in
[`dependabot-policy.mjs`](dependabot-policy.mjs), its central and repository
schemas, and the `dependabot.yml` and exception configuration it evaluates.
GitHub's Dependabot service and the package ecosystems it updates are external
systems. Their behavior is modeled where it crosses this analyzer's boundary,
but this component does not operate or attest to them.

The model follows OWASP's maintained threat-modeling loop: describe the system,
identify what can go wrong, map concrete responses, and validate the result.

## Security objectives and assets

- Every dependency-update entry batches related bumps, soaks new releases, and
  caps open pull requests, so bot-pull-request bursts cannot exhaust CI
  capacity.
- The soak (`cooldown`) is never silently dropped below the minimum, so a
  compromised or yanked release is caught before adoption while security
  updates still bypass it.
- The exception inventory cannot become a blanket bypass or outlive the
  condition it records.
- Findings fail the CI gate clearly without modifying `dependabot.yml`.

The protected assets are CI capacity and review throughput, the supply-chain
soak window, and the integrity of the exception inventory.

## Actors and trust boundaries

- A repository maintainer changes `.github/dependabot.yml` and the exception
  file and reviews findings.
- A pull-request contributor may control both files.
- Standards maintainers review the central policy values and both schemas,
  including the approved-reason and waivable-rule sets.
- GitHub's Dependabot service later reads the accepted `dependabot.yml`. That
  behavior crosses an external boundary.

Checked-in `.github/dependabot.yml` and `.github/dependabot-policy.json` are
untrusted subjects of the audit. The distributed `policy.json` and both schemas
are trusted only at their reviewed Git revision.

## Data flow

1. The caller selects a repository root, the central policy, and an optional
   exception file path.
2. The pinned YAML parser preflights the central policy, the exception file, and
   both schema JSON files with unique object members required; `JSON.parse`
   remains the JSON syntax authority. Ajv then validates the policy and the
   exception file against strict Draft 2020-12 schemas. A missing exception file
   yields an empty, most-strict exception set.
3. The analyzer parses `.github/dependabot.yml` with aliases and merge keys
   disabled, strict parsing, and unique keys required.
4. For each `updates` entry it checks the schedule interval, cooldown floor,
   groups requirement, and pull-request cap, and it confirms every declared
   exception is consumed by an entry that actually violates the waived rule.
5. Findings and the process exit status cross back to CI. No configuration file
   or Dependabot setting is changed.

## Threats, controls, and evidence

| Threat | Control | Executable evidence |
| --- | --- | --- |
| An update entry opens one pull request per dependency and floods review and CI. | Every entry must declare a groups block and keep the open-pull-request limit at or below the maximum. | The groups-missing and pr-limit-too-high cases in [`dependabot-policy.test.mjs`](dependabot-policy.test.mjs). |
| The supply-chain soak is dropped or shortened, so a compromised release is adopted immediately. | Each entry must set `cooldown.default-days` to at least the minimum; a missing or below-floor value is a finding. | The missing-cooldown and below-floor cases in [`dependabot-policy.test.mjs`](dependabot-policy.test.mjs). |
| A high-frequency schedule reintroduces the bot-burst the policy exists to prevent. | Each entry must schedule on the standard interval; a daily or absent interval is a finding unless a reasoned exception waives it. | The non-weekly-schedule and `tracks-upstream-release` exception cases in [`dependabot-policy.test.mjs`](dependabot-policy.test.mjs). |
| An exception becomes a blanket bypass or outlives its cause. | Exceptions are keyed to one entry, use an allowlisted reason with a justification, waive only named rules, and fail on an unused waiver or a missing entry. The pull-request cap is not waivable. | The exception-waive, unused-waiver, missing-entry, unknown-reason, unknown-waiver, and missing-justification cases in [`dependabot-policy.test.mjs`](dependabot-policy.test.mjs). |
| YAML or JSON ambiguity hides a different policy. | The parser requires unique keys and disables aliases and merge keys; duplicate JSON members are rejected before `JSON.parse`, per [RFC 8259 section 4](https://www.rfc-editor.org/rfc/rfc8259#section-4). A non-`version: 2` config is a finding. | The malformed-config, duplicate-member, and unsupported-version cases in [`dependabot-policy.test.mjs`](dependabot-policy.test.mjs). |
| A change weakens validation unnoticed. | The central and repository schemas reject unknown shapes and reasons; the runtime is exactly locked; CI runs the behavioral tests and then audits this repository. | [`policy.schema.json`](policy.schema.json), [`dependabot-policy.schema.json`](dependabot-policy.schema.json), [`package-lock.json`](package-lock.json), and the `dependabot-policy` CI job. |

## Residual and accepted risk

- The analyzer checks policy shape, not dependency safety. It does not evaluate
  whether a specific bump is malicious; the cooldown soak, security-update
  bypass, and human review of each pull request remain the controls for that.
- Dependabot options can change after a passing audit. The standard tracks the
  reviewed option set and values, not all future service behavior.
- Grouping and the pull-request cap bound bot-pull-request volume but not the
  cost of any single update's CI run. Workflow-level volume controls remain
  separate.
- A pull request can change the analyzer, policy, and tests together. Required
  review, branch governance, and pinned CI dependencies are repository controls
  outside the analyzer itself.

A risk acceptance is recorded in the owning repository with scope, owner,
compensating controls, and a review trigger; no exception file entry accepts
these model-level risks.

## Review triggers

Re-run this threat model when the analyzer accepts a new policy value, exception
reason, or waivable rule; when GitHub changes the `dependabot.yml` option set,
cooldown, or security-update semantics; when the schema version changes; or
after an incident where a dependency-update burst or an unsoaked release reached
CI.

Each review confirms the data flow, adds a negative test for every new failure
mode, and updates residual risk instead of merely widening the allowlist.

## External authorities

- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [Dependabot options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
- [Dependabot default package cooldown](https://github.blog/changelog/2026-07-14-dependabot-version-updates-introduce-default-package-cooldown/)
- [RFC 8259, The JavaScript Object Notation (JSON) Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
