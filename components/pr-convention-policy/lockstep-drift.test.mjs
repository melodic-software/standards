import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  checkCopies,
  checkPinnedReusable,
  DriftError,
  GATE_CALLERS,
  parseCallerPin,
  parseGatePatterns,
  parseGateSections,
  parseMarkdownHeadings,
  parseValidatorSections,
} from "./lockstep-drift.mjs";
import { parseUniqueJson } from "./pr-convention-policy.mjs";

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const POLICY = parseUniqueJson(
  await readFile(path.join(MODULE_DIRECTORY, "policy.json"), "utf8"),
  "policy.json",
);

// Hermetic fixtures mirroring the narrowest parsed surface of each live copy.
const GOOD_GATE = `
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
const GOOD_VALIDATOR = [
  "KEYWORD_ERE='[^a-z0-9_](close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]*:?[[:space:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[^a-z0-9_]'",
  "NO_ISSUE_ERE='[^a-z0-9_]no (linked|related) issue[^a-z0-9_]'",
  "REQUIRED_SECTIONS=(Summary Fix Verification Related)",
  "",
].join("\n");
const GOOD_TEMPLATE =
  "Closes #\n\nOr `No related issue: <reason>` / `No linked issue`.\n\n## Summary\n\n## Fix\n\n## Verification\n\n## Related\n";
const GOOD_RULES = [
  "# PR body contract",
  "`Closes #<issue>` (`Fixes`/`Resolves`), or `No related issue: <reason>`.",
  "Sections: `## Summary`, `## Fix`, `## Verification`, `## Related`.",
].join("\n\n");

function goodTexts() {
  return {
    gate: GOOD_GATE,
    hookValidator: GOOD_VALIDATOR,
    orgTemplate: GOOD_TEMPLATE,
    rulesFile: GOOD_RULES,
  };
}

test("policy fixture agreement: every good fixture matches policy.json", () => {
  assert.deepEqual(checkCopies(POLICY, goodTexts()), []);
});

test("parsers extract the narrow surfaces", () => {
  assert.deepEqual(parseGateSections(GOOD_GATE, "gate"), POLICY.body.requiredSections);
  assert.deepEqual(
    parseValidatorSections(GOOD_VALIDATOR, "validator"),
    POLICY.body.requiredSections,
  );
  assert.deepEqual(parseMarkdownHeadings(GOOD_TEMPLATE), POLICY.body.requiredSections);
  assert.equal(
    parseCallerPin(
      "uses: melodic-software/ci-workflows/.github/workflows/pr-issue-linkage.yml@0f8176e87e0be518f382664779655011bf95784a # v0.17.2",
      "caller",
    ),
    "0f8176e87e0be518f382664779655011bf95784a",
  );
});

// Mutation probes: one mutated copy per source must produce exactly that
// source's drift finding (the acceptance criterion's red-under-mutation).
test("mutated gate section list is reported", () => {
  const texts = goodTexts();
  texts.gate = texts.gate.replace('"Fix"', '"Patch"');
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("gate reusable:")).length, 1);
});

test("mutated validator section list is reported", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator.replace(
    "REQUIRED_SECTIONS=(Summary Fix Verification Related)",
    "REQUIRED_SECTIONS=(Summary Related)",
  );
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("hook validator:")).length, 1);
});

test("template missing a policy heading is reported", () => {
  const texts = goodTexts();
  texts.orgTemplate = texts.orgTemplate.replace("## Verification\n\n", "");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("org PR template:")).length, 1);
});

test("rules file missing a section or keyword is reported", () => {
  const texts = goodTexts();
  texts.rulesFile = texts.rulesFile.replace("## Related", "## See also").replace("Resolves", "");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("rules file")).length, 2, errors.join("; "));
});

test("stale pin enforcing an older contract is reported", () => {
  const oldReusable = `
            const requiredSections = [
              { name: "Related", guidance: "r" },
            ];
`;
  // Two findings: the stale section list AND the missing enforcement-pattern
  // declarations (pre-pattern-era reusables lack the const declarations).
  const errors = checkPinnedReusable(POLICY, "codex-plugins", "c".repeat(40), oldReusable);
  assert.equal(errors.length, 2);
  assert.match(errors[0], /caller codex-plugins/);
  assert.match(errors[1], /caller codex-plugins/);
});

test("current pinned contract passes", () => {
  assert.deepEqual(checkPinnedReusable(POLICY, "dotfiles", "a".repeat(40), GOOD_GATE), []);
});

test("gate keyword/marker regressions are caught functionally, not by mention", () => {
  // Keyword stem removed from the DECLARED pattern while the word survives
  // in prose: a mention check would pass; the functional probe must not.
  const noResolve = goodTexts();
  noResolve.gate = noResolve.gate
    .replace("|resolve[sd]?", "")
    .concat("            // Resolves is still mentioned right here\n");
  assert.equal(
    checkCopies(POLICY, noResolve).filter((e) => e.includes("gate reusable (enforcement")).length,
    1,
  );
  const noMarker = goodTexts();
  noMarker.gate = noMarker.gate.replace("(?:linked|related)", "linked");
  assert.equal(
    checkCopies(POLICY, noMarker).filter((e) => e.includes('marker "No related issue"')).length,
    1,
  );
});

test("validator keyword/marker regressions are caught functionally", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator
    .replace("|resolve[sd]?", "")
    .replace("(linked|related)", "(linked)");
  const errors = checkCopies(POLICY, texts).filter((e) =>
    e.includes("hook validator (enforcement"),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /"Resolves"/);
  assert.match(errors[0], /"No related issue"/);
});

test("stale pin with current sections but stale keyword enforcement is drift", () => {
  const staleKeywords = GOOD_GATE.replace("|resolve[sd]?", "");
  const errors = checkPinnedReusable(POLICY, "dotfiles", "b".repeat(40), staleKeywords);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /rejects closing keyword "Resolves"/);
});

test("unparsable sources throw DriftError, never pass silently", () => {
  assert.throws(() => parseGateSections("jobs: {}", "gate"), DriftError);
  assert.throws(() => parseValidatorSections("echo hi", "validator"), DriftError);
  assert.throws(() => parseCallerPin("uses: something-else", "caller"), DriftError);
});

test("caller roster covers all ten gate repositories", () => {
  assert.equal(Object.keys(GATE_CALLERS).length, 10);
  assert.equal(GATE_CALLERS["ci-workflows"], ".github/workflows/pr-issue-linkage-self.yml");
});

// Regression: ci-workflows made CLOSING_KEYWORD global so every occurrence on a
// line can be classified. The parser pinned the declaration to a literal `/i;`,
// so a healthy gate reported "declarations not found" — a parse failure that
// reads as drift.
test("a global declaration parses and still probes", () => {
  const globalGate = GOOD_GATE.replaceAll("/i;", "/gi;");
  const patterns = parseGatePatterns(globalGate, "gate");
  assert.ok(patterns.keyword.test("Closes #12"), "keyword body still probes");
  assert.ok(patterns.marker.test("No linked issue"), "marker body still probes");
  assert.equal(patterns.keyword.global, false, "g is stripped so .test() is stateless");
  assert.deepEqual(
    parseGatePatterns(globalGate, "gate").keyword.source,
    parseGatePatterns(GOOD_GATE, "gate").keyword.source,
    "same body extracted regardless of declared flags",
  );
});

// Tolerating flags must not blind the check to losing one. Both declared bodies
// are lowercase and rely on `i` to accept the documented `Closes #12`, so a gate
// that dropped `i` would silently become case-sensitive. Probing with a
// hardcoded `i` would pass it; probing with the DECLARED flags catches it.
test("a gate that drops the i flag is enforcement drift, not a pass", () => {
  const caseSensitiveGate = GOOD_GATE.replaceAll("/i;", "/g;");
  const patterns = parseGatePatterns(caseSensitiveGate, "gate");
  assert.equal(patterns.keyword.ignoreCase, false, "declared flags are preserved");
  assert.equal(patterns.keyword.test("Closes #12"), false, "capitalised form now rejected");
  const texts = goodTexts();
  texts.gate = caseSensitiveGate;
  const errors = checkCopies(POLICY, texts).filter((e) => e.includes("gate reusable (enforcement"));
  assert.equal(errors.length, 1, "drift is reported");
  assert.match(errors[0], /closing keyword "Closes"/);
});

// `g`/`y` are stripped because they make .test() advance lastIndex, and
// assertPatternsEnforce probes each pattern once per policy keyword.
test("a global probe does not go stateful across repeated keyword probes", () => {
  const patterns = parseGatePatterns(GOOD_GATE.replaceAll("/i;", "/gi;"), "gate");
  for (const keyword of POLICY.body.closingKeywords) {
    assert.ok(patterns.keyword.test(` ${keyword} #12 `), `${keyword} probes on every call`);
  }
});
