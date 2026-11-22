#!/usr/bin/env node

// Generates the three prose copies of the PR and issue contracts from their records: the org PR
// template, the always-loaded `.claude/rules/pr-body-contract.md` rule, and the harness-neutral
// filing guide the filing-guide component syncs to every target's `docs/standards/`. `check` (the
// default) fails when a committed copy differs from what the records generate; `write`
// regenerates them. The sync materializes the committed copies byte-exact, so each is changed in
// policy.json or contract.json, or in this generator's wording, and nowhere else.

import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, "..", "..");
export const POLICY_PATH = path.join(HERE, "policy.json");
export const CONTRACT_PATH = path.join(ROOT, "components", "issue-body-contract", "contract.json");
export const OUTPUTS = {
  template: "components/pr-convention-policy/PULL_REQUEST_TEMPLATE.md",
  rule: ".claude/rules/pr-body-contract.md",
  guide: "standards/process/filing-prs-and-issues.md",
};

// The one marker of each kind the prose steers an author to. policy.json keeps the full accepted
// set for the copies that enforce it; naming one gives the author no choice the gate never asked
// for (lockstep-drift.mjs holds the rule file and template to "at least one").
export const NO_ISSUE_MARKER = "No related issue";
export const NON_CLOSING_MARKER = "Refs";

const STANDARDS_BLOB = "https://github.com/melodic-software/standards/blob/main";
const LOOP_LANE =
  "https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/loop-lane/README.md";

export function validateInputs(policy, contract) {
  const errors = [];
  const { body } = policy;
  const guidance = Object.keys(body.sectionGuidance ?? {});
  if (JSON.stringify(guidance) !== JSON.stringify(body.requiredSections)) {
    errors.push(
      `policy.json body.sectionGuidance keys [${guidance.join(", ")}] must equal body.requiredSections [${body.requiredSections.join(", ")}] in order`,
    );
  }
  if (!body.noIssueMarkers.includes(NO_ISSUE_MARKER)) {
    errors.push(`policy.json body.noIssueMarkers no longer accepts "${NO_ISSUE_MARKER}"`);
  }
  if (!body.nonClosingMarkers.includes(NON_CLOSING_MARKER)) {
    errors.push(`policy.json body.nonClosingMarkers no longer accepts "${NON_CLOSING_MARKER}"`);
  }
  if (!Array.isArray(contract.floorLabels) || contract.floorLabels.length === 0) {
    errors.push("contract.json floorLabels must be a non-empty array");
  }
  return errors;
}

function oxfordList(items) {
  if (items.length < 3) return items.join(" and ");
  return `${items.slice(0, -1).join(", ")}, and ${items.at(-1)}`;
}

function htmlComment(text) {
  return text.includes("\n") ? `<!--\n${text}\n-->` : `<!-- ${text} -->`;
}

export function renderTemplate(policy) {
  const sections = policy.body.requiredSections
    .map((name) => `## ${name}\n\n${htmlComment(policy.body.sectionGuidance[name])}\n`)
    .join("\n");
  return `${policy.body.closingKeywords[0]} #

<!--
Complete the \`${policy.body.closingKeywords[0]} #\` line above with the issue number to auto-close it on
merge, one closing keyword per issue (cross-repo:
\`${policy.body.closingKeywords[0]} <owner>/<repo>#<issue-number>\`). Supported keywords are GitHub's:
https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue

If this PR closes no issue (an orphan PR: drift sweep, hotfix, refactor),
replace that line with the no-issue escape and its reason, as plain text:

${NO_ISSUE_MARKER}: <reason>

The reason is required. Write the escape without backticks: the gate masks
inline code spans before matching, so a backticked escape is invisible to it
and the PR draws the advisory \`needs-issue-linkage\` label anyway. The linkage
rule is advisory: the \`check-contract\` step inside \`CI Status\` leaves a comment and
the \`needs-issue-linkage\` label instead of failing. That step's output reports
the exact rule it applied and is authoritative over this comment.

Every \`##\` section below must be filled with real content. HTML comments like
this one are stripped before validation, so an untouched template is reported
as missing every section rather than passing vacuously.
-->

${sections}`;
}

export function renderRule(policy) {
  const [first, ...others] = policy.body.closingKeywords;
  const sections = oxfordList(policy.body.requiredSections.map((name) => `\`## ${name}\``));
  return `# PR body contract

The \`check-contract\` step inside \`CI Status\` fails a pull request on a
non-Conventional-Commits title or a \`do-not-merge\` label. In repositories that
enable it, a separate \`CI Status\` check fails a body line that would start with
the word \`committer\` after the 72-column squash wrap, which breaks the squash
commit's signature: reword that line. The body contract is advisory, reported
by comment and the \`needs-issue-linkage\` label, but expected: open with
\`${first} #<issue>\` (or
${others.map((keyword) => `\`${keyword}\``).join("/")}), a \`${NON_CLOSING_MARKER}: #<issue>\` line to link without closing (never
"does not close", which still closes), or \`${NO_ISSUE_MARKER}: <reason>\`, then
fill ${sections}. Draft from
the repo's PR template (else the \`melodic-software/.github\` default);
canonical record of the title and body contract:
\`components/pr-convention-policy/policy.json\` in
\`melodic-software/standards\`.
`;
}

function codeList(items, separator = ", ") {
  return items.map((item) => `\`${item}\``).join(separator);
}

function renderIssueType(type) {
  const fields = type.fields
    .map(
      (field) =>
        `- \`${field.heading}\` (${field.required ? "required" : "optional"}): ${field.description}`,
    )
    .join("\n");
  const form = type.form === null ? "" : ` Form: \`${type.form}\`.`;
  return `### ${type.name}\n\n${type.description}${form}\n\n${fields}\n`;
}

function renderTypeRow(type) {
  let flag = `\`--type ${type.nativeType}\``;
  if (type.form === null) flag = "set by its publisher";
  else if (type.nativeType === null) flag = "no `--type`: triage sets it";
  return `| ${type.name} | ${flag} | ${type.form === null ? "none" : `\`${type.form}\``} |`;
}

export function renderGuide(policy, contract) {
  const { title, body } = policy;
  const [first, ...others] = body.closingKeywords;
  const types = Object.values(contract.types);
  const floor = codeList(contract.floorLabels, " and ");
  const levels = contract.headingLevels.map((level) => `\`${"#".repeat(level)} <heading>\``);
  const sections = body.requiredSections
    .map((name) => `### ${name}\n\n${body.sectionGuidance[name].replaceAll("\n", " ")}\n`)
    .join("\n");
  return `# Filing pull requests and issues

<!-- Generated by components/pr-convention-policy/contract-docs.mjs from components/pr-convention-policy/policy.json and components/issue-body-contract/contract.json in melodic-software/standards. Edit those, run \`node components/pr-convention-policy/contract-docs.mjs write\`, and commit the result. -->

What a pull request and an issue in an organization repository must carry, for any agent or person
writing one, whatever tool, harness or model writes it. The rules are generated from the two
records that the gates and forms read:
[\`policy.json\`](${STANDARDS_BLOB}/components/pr-convention-policy/policy.json) for pull requests
and [\`contract.json\`](${STANDARDS_BLOB}/components/issue-body-contract/contract.json) for issues.
How labels, fields and triage work is the
[issue-tracker playbook](${STANDARDS_BLOB}/standards/process/issue-tracker.md)'s.

This guide is the organization default. Where a repository's own PR template, issue forms or
\`AGENTS.md\` differ from it, the repository's own wins, as GitHub already prefers a repository's
own template and forms over the organization's.

## Pull request title

Conventional Commits: \`<type>[(<scope>)]: <subject>\`, with \`!\` before the colon for a breaking
change. The type is one of ${codeList(title.allowedTypes)}. A scope is ${title.requireScope ? "required" : "optional"}. The
\`check-contract\` step inside the required \`CI Status\` check fails any other title, and fails a
pull request that carries the \`do-not-merge\` label.

## Pull request body

Open the body with one linkage line, written as plain text, never in backticks (the gate ignores
code spans):

- \`${first} #<issue>\` (or ${codeList(others, " or ")}) closes the issue on merge. Use one keyword
  per issue; across repositories, \`${first} <owner>/<repo>#<issue>\`.
- \`${NON_CLOSING_MARKER}: #<issue>\` links an issue without closing it. Never write a disclaimer such
  as "does not close #12": GitHub closes the issue anyway, and the gate reports it.
- \`${NO_ISSUE_MARKER}: <reason>\` when no issue applies. The reason is required.

Then fill these sections, as \`## <name>\` headings in this order, each with real content. Their
guidance is the org PR template's:

${sections}
The body contract is advisory: a miss draws a comment and the \`needs-issue-linkage\` label instead
of a failed check, but it is expected. Draft from the repository's PR template, else the
\`melodic-software/.github\` default; \`gh pr create --body\` skips the template.

## Issues

Title an issue as a plain summary, starting with a verb when it is work to do, with no \`X:\` or
\`[X]\` prefix. Set the Issue Type at filing: \`gh issue create --type <Type>\`.

| Kind | \`gh issue create\` | Issue form |
|---|---|---|
${types.map(renderTypeRow).join("\n")}

A new issue opens with the floor label ${floor}: a form applies it, and the floor workflow adds it
to an issue filed without a triage-status label. Never apply a role label such as \`agent-ready\`
at filing; triage grants it.

Write each field as a heading (${levels.join(" or ")}) followed by its answer. A required heading
is never left empty or answered \`${contract.emptyAnswer}\`.

${types.map(renderIssueType).join("\n")}
## Routing labels

In repositories the automation lanes serve, three labels take an issue off the unattended path,
and each means one thing ([loop-lane convention](${LOOP_LANE}#when-work-stops-for-the-owner)):

- \`session-owned\`: a local session works the issue itself, so the lanes skip it. Apply it when
  you will do the work in your own session. It says who works the item, not whether a person is
  present.
- \`attended\`: the owner must be present for a manual step on external state an agent cannot
  safely run or test, such as a DNS change, a new key or secret, or an elevated pass. It asks no
  decision, and only the owner removes it.
- \`needs-human\`: an owner decision is needed. Never use it for ownership or a manual step.

Otherwise leave the issue to the automation lanes: file it with the fields above and no routing
label, and intake triage takes it from there.
`;
}

export function renderAll(policy, contract) {
  return {
    [OUTPUTS.template]: renderTemplate(policy),
    [OUTPUTS.rule]: renderRule(policy),
    [OUTPUTS.guide]: renderGuide(policy, contract),
  };
}

export async function loadInputs() {
  return {
    policy: JSON.parse(await readFile(POLICY_PATH, "utf8")),
    contract: JSON.parse(await readFile(CONTRACT_PATH, "utf8")),
  };
}

export async function diffOutputs(expected, root = ROOT) {
  const drift = [];
  for (const [relative, text] of Object.entries(expected)) {
    let committed;
    try {
      committed = await readFile(path.join(root, relative), "utf8");
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
      drift.push(`${relative}: missing`);
      continue;
    }
    if (committed !== text) drift.push(`${relative}: differs from what the records generate`);
  }
  return drift;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const mode = process.argv[2] ?? "check";
  const say = (stream, line) => stream.write(`${line}\n`);
  const { policy, contract } = await loadInputs();
  const errors = validateInputs(policy, contract);
  if (errors.length > 0) {
    for (const error of errors) say(process.stderr, `contract-docs: ${error}`);
    process.exit(1);
  }
  const outputs = renderAll(policy, contract);
  if (mode === "write") {
    for (const [relative, text] of Object.entries(outputs)) {
      await writeFile(path.join(ROOT, relative), text);
    }
    say(process.stdout, `contract-docs: wrote ${Object.keys(outputs).length} files`);
  } else if (mode === "check") {
    const drift = await diffOutputs(outputs);
    if (drift.length > 0) {
      for (const line of drift) say(process.stderr, `drift: ${line}`);
      say(
        process.stderr,
        "Run `node components/pr-convention-policy/contract-docs.mjs write` and commit the result.",
      );
      process.exit(1);
    }
    say(process.stdout, "contract-docs: committed copies match policy.json and contract.json");
  } else {
    say(process.stderr, `usage: contract-docs.mjs [check|write], got ${mode}`);
    process.exit(2);
  }
}
