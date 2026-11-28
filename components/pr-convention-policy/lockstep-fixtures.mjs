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
export const BACKTICKED_TEMPLATE = GOOD_TEMPLATE.replace(
  "No related issue: <reason>",
  "Use `No related issue: <reason>` or `No linked issue`.",
);
export function goodTexts() {
  return {
    gateRun: GOOD_COMPOSITE_RUN,
    gateAction: GOOD_COMPOSITE_ACTION,
    hookValidator: GOOD_VALIDATOR,
    orgTemplate: GOOD_TEMPLATE,
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
