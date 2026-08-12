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

test("body validation requires Related content and a closing keyword", () => {
  const good = `Closes #173

## Related
- standards#171`;
  assert.deepEqual(rules(validateBody(good, POLICY)), []);

  const noIssue = `No linked issue

## Related
- exploratory spike`;
  assert.deepEqual(rules(validateBody(noIssue, POLICY)), []);

  const missingRelated = "Closes #173";
  assert.deepEqual(rules(validateBody(missingRelated, POLICY)), ["body:section-missing"]);

  const emptyRelated = `Closes #173

## Related`;
  assert.deepEqual(rules(validateBody(emptyRelated, POLICY)), ["body:section-empty"]);

  const missingKeyword = `## Related
- standards#171`;
  assert.deepEqual(rules(validateBody(missingKeyword, POLICY)), ["body:closing-keyword-missing"]);
});

test("body validation ignores instructional text inside rendered HTML comments", () => {
  const body = `<!-- Template: Closes #123 -->

No linked issue

## Related
- standards#173`;
  assert.deepEqual(rules(validateBody(body, POLICY)), []);
});

test("validatePullRequest aggregates title and body findings", () => {
  const findings = validatePullRequest(
    {
      title: "feat: land policy",
      body: `Closes #173

## Related
- ci-workflows thin-runner follow-on`,
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
    schemaVersion: 1,
    title: { allowedTypes: ["docs"], requireScope: false },
    body: {
      requiredSections: ["Related"],
      closingKeywords: ["Completes"],
      noIssueMarkers: ["No linked issue"],
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
    schemaVersion: 1,
    title: { allowedTypes: ["docs"], requireScope: false },
    body: {
      requiredSections: ["Related"],
      closingKeywords: ["Closes"],
      noIssueMarkers: ["No linked issue"],
    },
  });
  assert.deepEqual(rules(validateTitle("docs: update readme", customPolicy)), []);
  assert.deepEqual(rules(validateTitle("feat: add feature", customPolicy)), [
    "title:title-not-conventional",
  ]);
});
