import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  ConfigurationError,
  parseArguments,
  parseUniqueJson,
  validateBody,
  validatePolicy,
  validatePullRequest,
  validateTitle,
} from "./pr-convention-policy.mjs";

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const POLICY = validatePolicy(
  parseUniqueJson(
    await readFile(path.join(MODULE_DIRECTORY, "policy.json"), "utf8"),
    "policy.json",
  ),
);

function rules(findings) {
  return findings.map((item) => `${item.field}:${item.rule}`).sort();
}

test("policy schema accepts the canonical policy and rejects drift", () => {
  assert.deepEqual(POLICY.title.allowedTypes.includes("security"), true);
  assert.throws(
    () =>
      validatePolicy({ schemaVersion: 1, title: { allowedTypes: ["feat"], requireScope: false } }),
    ConfigurationError,
  );
  // A version-1 policy, with no non-closing or negated-closer record, no
  // longer validates.
  const { nonClosingMarkers, negatedClosers, ...versionOneBody } = POLICY.body;
  assert.ok(nonClosingMarkers.length > 0 && negatedClosers.wordWindow > 0);
  assert.throws(
    () => validatePolicy({ ...POLICY, schemaVersion: 1, body: versionOneBody }),
    ConfigurationError,
  );
  assert.throws(
    () => validatePolicy({ ...POLICY, body: versionOneBody }),
    /body must have required property 'nonClosingMarkers'/,
  );
  // The linkage copies implement exactly one affirmative exception and one
  // trigger suffix, which is all the lockstep extractors can read.
  for (const [field, values] of [
    ["affirmativePhrases", [[], ["not only", "not just"]]],
    ["triggerSuffixes", [[], ["n't", "nt"]]],
  ]) {
    for (const value of values) {
      const body = { ...POLICY.body, negatedClosers: { ...negatedClosers, [field]: value } };
      assert.throws(
        () => validatePolicy({ ...POLICY, body }),
        new RegExp(`${field} must NOT have`),
      );
    }
  }
});

test("canonical requiredSections mirror the enforced pr-issue-linkage contract", () => {
  // Lockstep pin against the authoritative gate: ci-workflows'
  // pr-issue-linkage.yml reusable (v0.14.2, 7107b34) enforces exactly these
  // four sections. When the reusable's list changes, this policy changes with
  // it (standards#393).
  assert.deepEqual(POLICY.body.requiredSections, ["Summary", "Fix", "Verification", "Related"]);
});

test("command-line parsing requires a title", () => {
  assert.deepEqual(parseArguments(["--title", "feat: add policy", "--json"]), {
    title: "feat: add policy",
    body: "",
    policyPath: path.join(MODULE_DIRECTORY, "policy.json"),
    json: true,
  });
  assert.throws(() => parseArguments(["--json"]), ConfigurationError);
});

test("title validation accepts conventional commits with allowed types", () => {
  assert.deepEqual(rules(validateTitle("feat(scope): add policy", POLICY)), []);
  assert.deepEqual(rules(validateTitle("security: pin dependency", POLICY)), []);
  assert.deepEqual(rules(validateTitle("fix!: break api", POLICY)), []);
});

test("title validation rejects empty and non-conforming titles", () => {
  assert.deepEqual(rules(validateTitle("", POLICY)), ["title:title-empty"]);
  assert.deepEqual(rules(validateTitle("feature: wrong type token", POLICY)), [
    "title:title-not-conventional",
  ]);
});

const FULL_SECTIONS = `## Summary
Aligns the policy with the enforced contract.

## Fix
Update the section list.

## Verification
node --test passes.

## Related
- standards#171`;

test("body validation requires every policy section and a closing keyword", () => {
  const good = `Closes #173

${FULL_SECTIONS}`;
  assert.deepEqual(rules(validateBody(good, POLICY)), []);

  const noIssue = `No linked issue

${FULL_SECTIONS}`;
  assert.deepEqual(rules(validateBody(noIssue, POLICY)), []);

  const missingAllSections = "Closes #173";
  assert.deepEqual(rules(validateBody(missingAllSections, POLICY)), [
    "body:section-missing",
    "body:section-missing",
    "body:section-missing",
    "body:section-missing",
  ]);

  const missingRelated = `Closes #173

## Summary
Aligns the policy.

## Fix
Update the list.

## Verification
node --test passes.`;
  assert.deepEqual(rules(validateBody(missingRelated, POLICY)), ["body:section-missing"]);

  const emptyRelated = `Closes #173

${FULL_SECTIONS.replace("- standards#171", "")}`;
  assert.deepEqual(rules(validateBody(emptyRelated, POLICY)), ["body:section-empty"]);

  const missingKeyword = FULL_SECTIONS;
  assert.deepEqual(rules(validateBody(missingKeyword, POLICY)), ["body:closing-keyword-missing"]);
});

test("body validation ignores instructional text inside rendered HTML comments", () => {
  const body = `<!-- Template: Closes #123 -->

No linked issue

${FULL_SECTIONS.replace("- standards#171", "- standards#173")}`;
  assert.deepEqual(rules(validateBody(body, POLICY)), []);
});

test("validatePullRequest aggregates title and body findings", () => {
  const findings = validatePullRequest(
    {
      title: "feat: land policy",
      body: `Closes #173

${FULL_SECTIONS.replace("- standards#171", "- ci-workflows thin-runner follow-on")}`,
    },
    POLICY,
  );
  assert.deepEqual(findings, []);
});

test("duplicate JSON object members fail closed", () => {
  assert.throws(
    () => parseUniqueJson('{"schemaVersion":1,"schemaVersion":1}', "policy at /tmp/policy.json"),
    (error) =>
      error instanceof ConfigurationError &&
      error.message.includes("policy at /tmp/policy.json") &&
      error.message.includes("duplicate"),
  );
});

test("closing keyword validation follows policy-authored keywords", () => {
  const customPolicy = validatePolicy({
    schemaVersion: 2,
    title: { allowedTypes: ["docs"], requireScope: false },
    body: {
      requiredSections: ["Related"],
      closingKeywords: ["Completes"],
      noIssueMarkers: ["No linked issue"],
      nonClosingMarkers: POLICY.body.nonClosingMarkers,
      negatedClosers: POLICY.body.negatedClosers,
    },
  });
  const accepted = `Completes #42

## Related
- standards#171`;
  assert.deepEqual(rules(validateBody(accepted, customPolicy)), []);

  const rejected = `Closes #42

## Related
- standards#171`;
  assert.deepEqual(rules(validateBody(rejected, customPolicy)), ["body:closing-keyword-missing"]);
});

test("title validation follows policy-authored allowed types", () => {
  const customPolicy = validatePolicy({
    schemaVersion: 2,
    title: { allowedTypes: ["docs"], requireScope: false },
    body: {
      requiredSections: ["Related"],
      closingKeywords: ["Closes"],
      noIssueMarkers: ["No linked issue"],
      nonClosingMarkers: POLICY.body.nonClosingMarkers,
      negatedClosers: POLICY.body.negatedClosers,
    },
  });
  assert.deepEqual(rules(validateTitle("docs: update readme", customPolicy)), []);
  assert.deepEqual(rules(validateTitle("feat: add feature", customPolicy)), [
    "title:title-not-conventional",
  ]);
});
