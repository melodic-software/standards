// Shared fixtures for the lockstep-*.test.mjs files, which node --test runs
// in parallel.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { checkCopies } from "./lockstep-drift.mjs";
import { parseUniqueJson } from "./pr-convention-policy.mjs";

export const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
export const POLICY = parseUniqueJson(
  await readFile(path.join(MODULE_DIRECTORY, "policy.json"), "utf8"),
  "policy.json",
);

// The two executable copies are vendored, because the behavioral layer runs
// them. Each matches its upstream commit except the message prefix and the
// comment marker, which carry the composite's name `check-contract`: the
// composite's run.sh from ci-workflows
// 8b3cc4bf282b30e51dd0eef31e2997b978770cea (ci-workflows#733, the
// `issue-ref-pattern` shape, plus one `spellchecker:ignore-next-line` awk
// comment for this repository's typos lane), the same run.sh from ci-workflows
// a932d486c5a4d0a959c42e60ff015f50cf2103f3 (the inline `#N` shape older pins
// still run), the same run.sh from ci-workflows
// cc7613fbf8bacca72700d6498c32145c05fe1f09 (ci-workflows#815, the gsub
// keyword pass and bounded backward negation scan, with the same awk
// comment), the same run.sh from ci-workflows
// cb6945d4906ef5e6c6d6281d98c96e79a45349f5 (ci-workflows#1129, one report loop
// with a case per kind, with the same awk comment), and the hook validator from
// claude-code-plugins 53d5c6a09dfb5890b9767b447a28ca10ba922173. The `.txt`
// suffix keeps the shell lint lanes off code this repository does not own.
// Refresh them when either upstream changes shape the tests depend on.
const readFixture = (name) =>
  readFile(path.join(MODULE_DIRECTORY, "fixtures", "lockstep", name), "utf8");
export const GOOD_COMPOSITE_RUN = await readFixture("check-contract-run.sh.txt");
export const LITERAL_REF_COMPOSITE_RUN = await readFixture("check-contract-run-literal-ref.sh.txt");
export const BOUNDED_SCAN_COMPOSITE_RUN = await readFixture(
  "check-contract-run-bounded-scan.sh.txt",
);
export const SINGLE_LOOP_COMPOSITE_RUN = await readFixture("check-contract-run-1129.sh.txt");
export const GOOD_VALIDATOR = await readFixture("pr-linkage-validator.sh.txt");
export const BOUNDED_SCAN_VALIDATOR = await readFixture("pr-linkage-validator-bounded-scan.sh.txt");

export const GOOD_COMPOSITE_ACTION = [
  "name: Check Contract",
  "inputs:",
  "  require-scope:",
  "    description: Require a scope to always be present in the title.",
  "    default: 'false'",
  "  types:",
  "    description: >-",
  "      Comma-separated allowed Conventional Commits types. The default is the",
  "      twelve types policy.json declares.",
  "    default: build,chore,ci,docs,feat,fix,perf,refactor,revert,security,style,test",
  "  issue-ref-pattern:",
  "    description: POSIX extended regex for the issue reference.",
  "    default: '([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+'",
  "runs:",
  "  using: composite",
  "",
].join("\n");

// The predecessor reusable. Still live at every consumer that has not taken
// its Phase 3 pull request yet, so its extractor keeps its own coverage.
export const GOOD_GATE = `
      - name: Validate
        with:
          script: |
            const requiredSections = [
              { name: "Summary", guidance: "s" },
              { name: "Fix", guidance: "f" },
              { name: "Verification", guidance: "v" },
              { name: "Related", guidance: "r" },
            ];
            const CLOSING_KEYWORD =
              /\\b(close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\s*:?\\s*(?:[\\w.-]+\\/[\\w.-]+)?#\\d+\\b/i;
            const NO_ISSUE_MARKER = /\\bno (?:linked|related) issue\\b/i;
`;
// The live org template's shape since .github#135: one escape, plain text, on
// its own line inside the guidance comment an author reads and deletes. The
// comment placement is load-bearing — masking it the way the composite masks a
// PR body would leave the live template with no marker at all.
export const GOOD_TEMPLATE = [
  "Closes #",
  "",
  "<!--",
  "Complete the `Closes #` line above with the issue number. If this PR closes",
  "no issue, replace that line with the escape and its reason, as plain text:",
  "",
  "No related issue: <reason>",
  "",
  "Write it without backticks: the gate masks inline code spans before matching.",
  "-->",
  "",
  "## Summary",
  "",
  "## Fix",
  "",
  "## Verification",
  "",
  "## Related",
  "",
].join("\n");
// The pre-#135 shape: both escapes present, but only ever inside inline code
// spans, so the composite sees neither.
export const BACKTICKED_TEMPLATE = GOOD_TEMPLATE.replace(
  "No related issue: <reason>",
  "Use `No related issue: <reason>` or `No linked issue`.",
);
const GOOD_RULES = [
  "# PR body contract",
  "`Closes #<issue>` (`Fixes`/`Resolves`), a `Refs: #<issue>` line, or `No related issue: <reason>`.",
  "Sections: `## Summary`, `## Fix`, `## Verification`, `## Related`.",
].join("\n\n");

export function goodTexts() {
  return {
    gateRun: GOOD_COMPOSITE_RUN,
    gateAction: GOOD_COMPOSITE_ACTION,
    hookValidator: GOOD_VALIDATOR,
    orgTemplate: GOOD_TEMPLATE,
    rulesFile: GOOD_RULES,
  };
}

const NEGATION_DATA_FIELDS = [
  "triggerWords",
  "triggerSuffixes",
  "affirmativePhrases",
  "wordWindow",
];
export const negationData = (negatedClosers) =>
  Object.fromEntries(NEGATION_DATA_FIELDS.map((field) => [field, negatedClosers[field]]));

// Mutate one copy and return its findings, asserting the text really changed.
export function mutate(copy, from, to) {
  const texts = goodTexts();
  texts[copy] = texts[copy].replace(from, to);
  assert.notEqual(texts[copy], goodTexts()[copy], `mutation did not apply: ${from}`);
  return checkCopies(POLICY, texts);
}

export const LOCATION = { gateRun: "gate composite", hookValidator: "hook validator" };

export function assertOnlyBehavior(errors, copy, expected) {
  assert.equal(errors.length, 1, errors.join("; "));
  assert.ok(errors[0].startsWith(`${LOCATION[copy]} (behavior): `), errors[0]);
  assert.match(errors[0], expected);
}
