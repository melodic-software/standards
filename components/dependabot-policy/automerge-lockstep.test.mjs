import assert from "node:assert/strict";
import test from "node:test";

import {
  checkLockstep,
  extractPublisherAllowlist,
  LockstepError,
  resolveApprovedSha,
} from "./automerge-lockstep.mjs";

const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);
const contractKey = (sha) =>
  `melodic-software/ci-workflows/.github/workflows/pr-automerge-dependabot.yml@${sha}`;

const policy = (publisherAllowlist) => ({ autoMerge: { publisherAllowlist } });
const POLICY = policy(["actions/*", "github/*", "anthropics/*"]);

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

test("the SHA comes from the single runner-policy contract key", () => {
  const runnerPolicy = {
    approvedReusableWorkflowContracts: {
      [contractKey(SHA_A)]: {},
      "melodic-software/ci-workflows/.github/workflows/pr-run-checks.yml@cccc": {},
    },
  };
  assert.equal(resolveApprovedSha(runnerPolicy), SHA_A);
});

test("no contract key for the reusable fails", () => {
  throwsLockstep(() => resolveApprovedSha({ approvedReusableWorkflowContracts: {} }), /found 0/u);
});

test("two contract keys for the reusable fail", () => {
  const runnerPolicy = {
    approvedReusableWorkflowContracts: { [contractKey(SHA_A)]: {}, [contractKey(SHA_B)]: {} },
  };
  throwsLockstep(() => resolveApprovedSha(runnerPolicy), /found 2/u);
});
