import assert from "node:assert/strict";
import test from "node:test";

import {
  checkLockstep,
  extractPublisherAllowlist,
  LockstepError,
  requireContract,
} from "./automerge-lockstep.mjs";

const CONTRACT_KEY = "melodic-software/ci-workflows/.github/workflows/pr-automerge-dependabot.yml";

const policy = (tiers) => ({
  autoMerge: {
    publishers: Object.fromEntries(
      Object.entries(tiers).map(([publisher, tier]) => [
        publisher,
        { tier, reviewed: "2026-10-08", basis: "test" },
      ]),
    ),
  },
});
const POLICY = policy({ "actions/*": "auto", "github/*": "auto", "anthropics/*": "auto" });

const workflow = (...allowlists) => `on:
  workflow_call:
jobs:
  enable-auto-merge:
    steps:
      - name: Fetch Dependabot metadata
        uses: dependabot/fetch-metadata@25dd0e34f4fe68f24cc83900b1fe3fe149efef98
${allowlists
  .map(
    (list) => `      - name: Gate and arm auto-merge
        env:
          SENDER_ID: "1"
          PUBLISHER_ALLOWLIST: '${list}'
`,
  )
  .join("")}`;
const MATCHING = workflow('["actions/*","github/*","anthropics/*"]');

const throwsLockstep = (fn, pattern) =>
  assert.throws(fn, (error) => error instanceof LockstepError && pattern.test(error.message));

test("a reusable whose PUBLISHER_ALLOWLIST equals the policy passes", () => {
  assert.doesNotThrow(() => checkLockstep(POLICY, MATCHING));
  assert.deepEqual(extractPublisherAllowlist(MATCHING), ["actions/*", "github/*", "anthropics/*"]);
});

test("an entry added to the reusable is drift", () => {
  throwsLockstep(
    () => checkLockstep(POLICY, workflow('["actions/*","github/*","anthropics/*","docker/*"]')),
    /^drift: .*docker\/\*.* != policy\.json/u,
  );
});

test("an entry removed from the reusable is drift", () => {
  throwsLockstep(() => checkLockstep(POLICY, workflow('["actions/*","github/*"]')), /^drift: /u);
});

test("a review-tier publisher absent from the reusable passes", () => {
  const withReview = policy({
    "actions/*": "auto",
    "oven-sh/*": "review",
    "github/*": "auto",
    "anthropics/*": "auto",
  });
  assert.doesNotThrow(() => checkLockstep(withReview, MATCHING));
});

test("an auto-tier publisher missing from the reusable is drift", () => {
  const withExtraAuto = policy({
    "actions/*": "auto",
    "github/*": "auto",
    "anthropics/*": "auto",
    "docker/*": "auto",
  });
  throwsLockstep(() => checkLockstep(withExtraAuto, MATCHING), /^drift: .*docker\/\*/u);
});

test("a reusable entry the policy holds as review is drift", () => {
  const dockerReview = policy({
    "actions/*": "auto",
    "github/*": "auto",
    "anthropics/*": "auto",
    "docker/*": "review",
  });
  throwsLockstep(
    () =>
      checkLockstep(dockerReview, workflow('["actions/*","github/*","anthropics/*","docker/*"]')),
    /^drift: /u,
  );
});

test("a reordered list is drift, since the copies stay identical", () => {
  throwsLockstep(
    () => checkLockstep(POLICY, workflow('["github/*","actions/*","anthropics/*"]')),
    /^drift: /u,
  );
});

test("a workflow with no PUBLISHER_ALLOWLIST fails", () => {
  throwsLockstep(() => extractPublisherAllowlist(workflow()), /found 0$/u);
});

test("a workflow with two PUBLISHER_ALLOWLIST entries fails", () => {
  throwsLockstep(
    () => extractPublisherAllowlist(workflow('["actions/*"]', '["github/*"]')),
    /found 2$/u,
  );
});

test("malformed YAML fails as drift, not a crash", () => {
  throwsLockstep(() => extractPublisherAllowlist("jobs: [unclosed\n  - : :"), /not valid YAML/u);
});

test("a PUBLISHER_ALLOWLIST that is not JSON fails", () => {
  throwsLockstep(() => extractPublisherAllowlist(workflow("actions/*")), /not valid JSON/u);
});

test("the reusable's path-keyed runner-policy contract satisfies the check", () => {
  const runnerPolicy = { approvedReusableWorkflowContracts: { [CONTRACT_KEY]: {} } };
  assert.doesNotThrow(() => requireContract(runnerPolicy));
});

test("no contract for the reusable fails, even with another reusable's contract present", () => {
  const runnerPolicy = {
    approvedReusableWorkflowContracts: {
      "melodic-software/ci-workflows/.github/workflows/pr-run-checks.yml": {},
    },
  };
  throwsLockstep(() => requireContract(runnerPolicy), /found none/u);
});

test("a path@SHA key no longer counts as the reusable's contract", () => {
  const runnerPolicy = {
    approvedReusableWorkflowContracts: { [`${CONTRACT_KEY}@${"a".repeat(40)}`]: {} },
  };
  throwsLockstep(() => requireContract(runnerPolicy), /found none/u);
});
