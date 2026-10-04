import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { validatePolicy } from "../runner-policy/runner-policy.mjs";
import { parseLockstepArgs } from "./repin-lockstep-args.mjs";
import {
  appliedPolicyNote,
  copyForwardContracts,
  manualPolicyNote,
  pairCallerPins,
  planLockstep,
  rewriteCallerFiles,
  settleLockstep,
} from "./repin-policy-lockstep.mjs";

const SYNC_WORKFLOW = "melodic-software/ci-workflows/.github/workflows/standards-sync.yml";

const oldA = "c136b27f404dd32ce3873f39a6f3443891d1c16e";
const oldB = "d26c750691b5498fab529d115b63f84aa7aecebe";
const next = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

const temporaryRoots = [];

test.after(async () => {
  await Promise.all(temporaryRoots.map((root) => rm(root, { force: true, recursive: true })));
});

test("parseLockstepArgs accepts a single old SHA", () => {
  const parsed = parseLockstepArgs([oldA, next, "v0.17.0"]);
  assert.deepEqual(parsed, { oldShas: [oldA], newSha: next, tag: "v0.17.0" });
});

test("parseLockstepArgs accepts the unique-set comma list the apply step emits", () => {
  const parsed = parseLockstepArgs([`${oldA},${oldB}`, next, "v0.17.0"]);
  assert.deepEqual(parsed, { oldShas: [oldA, oldB], newSha: next, tag: "v0.17.0" });
});

test("parseLockstepArgs rejects a comma list with a non-SHA token", () => {
  const parsed = parseLockstepArgs([`${oldA},not-a-sha`, next, "v0.17.0"]);
  assert.deepEqual(parsed, { error: "sha" });
});

test("parseLockstepArgs rejects a missing argument as usage", () => {
  assert.deepEqual(parseLockstepArgs([oldA, next]), { error: "usage" });
});

test("rewriteCallerFiles keeps exactly one trailing newline on a rewritten caller", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "repin-lockstep-"));
  temporaryRoots.push(root);
  const rel = "components/claude-lanes/claude-review.yml";
  const abs = path.join(root, rel);
  await mkdir(path.dirname(abs), { recursive: true });
  const source =
    "jobs:\n" +
    "  review:\n" +
    `    uses: melodic-software/ci-workflows/.github/workflows/claude-review.yml@${oldA} # v0.16.0\n`;
  await writeFile(abs, source);

  const changed = await rewriteCallerFiles(next, "v0.17.0", root);

  assert.equal(changed, true);
  const rewritten = await readFile(abs, "utf8");
  assert.ok(rewritten.includes(`@${next} # v0.17.0`), "pin line carries the new SHA and tag");
  assert.ok(rewritten.endsWith("\n"), "rewritten caller ends with a final newline");
  assert.ok(!rewritten.endsWith("\n\n"), "rewritten caller does not gain a duplicate newline");
});

// The selector target is gone; the assertion guards against putting that pin back.
test("the shipped lane callers pin no selector, so the repin lane copies no selector contract", async () => {
  for (const name of ["claude-review.yml", "claude-security-review.yml"]) {
    const body = await readFile(new URL(`./${name}`, import.meta.url), "utf8");
    assert.ok(
      !body.includes("/select-runner.yml@"),
      `${name} must not pin the governed selector; it names the fleet label directly`,
    );
  }
});

test("rewriteCallerFiles repins a selector-less caller", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "repin-lockstep-"));
  temporaryRoots.push(root);
  const rel = "components/claude-lanes/claude-security-review.yml";
  const abs = path.join(root, rel);
  await mkdir(path.dirname(abs), { recursive: true });
  await writeFile(
    abs,
    "jobs:\n" +
      "  security-review:\n" +
      `    uses: melodic-software/ci-workflows/.github/workflows/claude-security-review.yml@${oldA} # v0.16.0\n` +
      "    with:\n" +
      "      runner: melodic-review-ubuntu-24.04-x64\n",
  );

  assert.equal(await rewriteCallerFiles(next, "v0.17.0", root), true);
  const rewritten = await readFile(abs, "utf8");
  assert.ok(rewritten.includes(`@${next} # v0.17.0`));
  assert.ok(rewritten.includes("runner: melodic-review-ubuntu-24.04-x64"));
});

const CURRENT_REVIEW_SHA = "91d06c94d733e5daa507e0afaa06a140bb46d337";
const FRESH_SHA = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const REVIEW_WORKFLOW = "melodic-software/ci-workflows/.github/workflows/claude-review.yml";

const NOTE_FORBIDDEN = [
  "selector allowlist",
  "approvedSelector",
  "AVAILABILITY_RULING",
  "select-runner.yml",
];

function assertNoSelectorKeys(value, pathLabel = "policy") {
  if (!value || typeof value !== "object") return;
  for (const key of Object.keys(value)) {
    assert.ok(!key.toLowerCase().includes("selector"), `${pathLabel}.${key} is a selector key`);
    assertNoSelectorKeys(value[key], `${pathLabel}.${key}`);
  }
}

test("manual and applied notes name the schema-4 registration and omit the selector machinery", () => {
  const tag = "v0.26.0";
  const declined = manualPolicyNote(
    "melodic-software/ci-workflows/.github/workflows/claude-review.yml routing changed between revisions (from 91d06c9)",
    tag,
    [],
  );
  const withheld = manualPolicyNote("a sibling declined", tag, [
    "melodic-software/ci-workflows/.github/workflows/claude-security-review.yml",
    "melodic-software/ci-workflows/.github/workflows/standards-sync.yml",
  ]);
  const applied = appliedPolicyNote(tag);
  for (const note of [declined, withheld, applied]) {
    assert.match(note, /approvedReusableWorkflowContracts/u);
    assert.match(note, /components\/runner-policy\/README\.md/u);
    assert.match(note, /runner-policy\.test\.mjs/u);
    assert.match(note, /REPINE_LANE_SHA_V0_26_0/u);
    assert.match(note, /#589/u);
    assert.ok(!note.includes("#345"), "notes cite PR #589 only");
    for (const forbidden of NOTE_FORBIDDEN) {
      assert.ok(!note.includes(forbidden), `note contains ${forbidden}`);
    }
  }
  assert.match(declined, /PR #589\)\. This pull request is never auto-merged\.$/u);
  assert.ok(!declined.includes("were not copy-forwarded"));
  assert.match(
    withheld,
    / These surfaces were unchanged and were not copy-forwarded, because any decline suppresses every write: melodic-software\/ci-workflows\/\.github\/workflows\/claude-security-review\.yml, melodic-software\/ci-workflows\/\.github\/workflows\/standards-sync\.yml\. Register one `approvedReusableWorkflowContracts` entry for each of those withheld paths too\. This pull request is never auto-merged\.$/u,
  );
});

test("the lockstep script no longer carries selector-allowlist machinery", async () => {
  const source = await readFile(new URL("./repin-policy-lockstep.mjs", import.meta.url), "utf8");
  for (const forbidden of [
    "approvedSelectorReferencesByRepositoryOwner",
    "approvedSelectorInputContracts",
    "AVAILABILITY_RULING_LANE_SHA",
    "selector allowlist",
    "copySelectorContract",
  ]) {
    assert.ok(!source.includes(forbidden), `script source still contains ${forbidden}`);
  }
});

test("copy-forward clones one real claude-review contract onto a new SHA", async () => {
  const onDisk = JSON.parse(
    await readFile(new URL("../runner-policy/policy.json", import.meta.url), "utf8"),
  );
  const policy = structuredClone(onDisk);
  const oldKey = `${REVIEW_WORKFLOW}@${CURRENT_REVIEW_SHA}`;
  const newKey = `${REVIEW_WORKFLOW}@${FRESH_SHA}`;
  const original = onDisk.approvedReusableWorkflowContracts[oldKey];
  assert.ok(original, "on-disk policy is missing the current claude-review contract");
  assert.equal(policy.approvedReusableWorkflowContracts[newKey], undefined);

  assert.equal(
    copyForwardContracts(policy, [
      {
        kind: "lane",
        workflowPath: REVIEW_WORKFLOW,
        oldSha: CURRENT_REVIEW_SHA,
        newSha: FRESH_SHA,
      },
    ]),
    true,
  );
  assert.deepEqual(policy.approvedReusableWorkflowContracts[newKey], original);
  assert.deepEqual(policy.approvedReusableWorkflowContracts[oldKey], original);
  assert.doesNotThrow(() => validatePolicy(policy));
  assertNoSelectorKeys(policy);
});

// Renamed-path fixtures: the old -> new pair is the claude-review entry of
// components/github-actions-conventions/rename-map.json.
const RENAMED_REVIEW_WORKFLOW = "melodic-software/ci-workflows/.github/workflows/pr-review.yml";
const callerText = (workflowPath, sha, tag) =>
  `jobs:\n  review:\n    uses: ${workflowPath}@${sha} # ${tag}\n    with:\n      runner: x\n`;

test("pairCallerPins follows a pin that apply moved to its renamed path", () => {
  const pairs = pairCallerPins(
    callerText(REVIEW_WORKFLOW, oldA, "v0.33.0"),
    callerText(RENAMED_REVIEW_WORKFLOW, next, "v0.34.0"),
  );
  assert.deepEqual(pairs, [
    { oldWorkflowPath: REVIEW_WORKFLOW, oldSha: oldA, newWorkflowPath: RENAMED_REVIEW_WORKFLOW },
  ]);
});

test("pairCallerPins keeps the path for a release cut before the rename", () => {
  const pairs = pairCallerPins(
    callerText(REVIEW_WORKFLOW, oldA, "v0.33.0"),
    callerText(REVIEW_WORKFLOW, next, "v0.33.1"),
  );
  assert.deepEqual(pairs, [
    { oldWorkflowPath: REVIEW_WORKFLOW, oldSha: oldA, newWorkflowPath: REVIEW_WORKFLOW },
  ]);
});

test("pairCallerPins refuses a pin line that apply did not leave as a pin", () => {
  assert.throws(
    () => pairCallerPins(callerText(REVIEW_WORKFLOW, oldA, "v0.33.0"), "jobs:\n  review:\n"),
    /line 3/u,
  );
});

test("a renamed pin with an unchanged surface writes no contract and lands on the human checklist", async () => {
  const policy = JSON.parse(
    await readFile(new URL("../runner-policy/policy.json", import.meta.url), "utf8"),
  );
  const before = structuredClone(policy);
  const pins = [
    {
      kind: "lane",
      oldWorkflowPath: REVIEW_WORKFLOW,
      oldSha: CURRENT_REVIEW_SHA,
      newWorkflowPath: RENAMED_REVIEW_WORKFLOW,
    },
  ];

  const { reasons, copyForwards } = planLockstep(pins, FRESH_SHA, () => ({ unchanged: true }));
  copyForwardContracts(policy, copyForwards);

  assert.deepEqual(copyForwards, []);
  assert.deepEqual(policy, before, "no contract is written for a renamed path");
  const note = manualPolicyNote(reasons.join("; "), "v0.34.0");
  assert.ok(
    note.includes(
      `${REVIEW_WORKFLOW} is renamed to ${RENAMED_REVIEW_WORKFLOW} (from 91d06c9); ` +
        "a renamed path needs a hand-reviewed approvedReusableWorkflowContracts entry",
    ),
    note,
  );
});

test("a same-path pin beside a rename still plans its copy-forward, and the rename declines the run", () => {
  const pins = [
    {
      kind: "lane",
      oldWorkflowPath: REVIEW_WORKFLOW,
      oldSha: CURRENT_REVIEW_SHA,
      newWorkflowPath: RENAMED_REVIEW_WORKFLOW,
    },
    {
      kind: "reusable",
      oldWorkflowPath: SYNC_WORKFLOW,
      oldSha: oldA,
      newWorkflowPath: SYNC_WORKFLOW,
    },
  ];
  const compared = [];
  const plan = planLockstep(pins, FRESH_SHA, (pin) => {
    compared.push(pin.newWorkflowPath);
    return { unchanged: true };
  });

  assert.deepEqual(compared, [SYNC_WORKFLOW], "a renamed pin is never surface-compared");
  assert.equal(plan.reasons.length, 1);
  assert.deepEqual(plan.copyForwards, [
    { kind: "reusable", workflowPath: SYNC_WORKFLOW, oldSha: oldA, newSha: FRESH_SHA },
  ]);
});

test("a same-path pin whose surface changed is declined, not copied forward", () => {
  const plan = planLockstep(
    [
      {
        kind: "lane",
        oldWorkflowPath: REVIEW_WORKFLOW,
        oldSha: CURRENT_REVIEW_SHA,
        newWorkflowPath: REVIEW_WORKFLOW,
      },
    ],
    FRESH_SHA,
    () => ({ unchanged: false, reason: "x" }),
  );
  assert.deepEqual(plan.copyForwards, []);
  assert.deepEqual(plan.reasons, [`${REVIEW_WORKFLOW} x (from 91d06c9)`]);
});

async function policyRoot() {
  const root = await mkdtemp(path.join(tmpdir(), "repin-settle-"));
  temporaryRoots.push(root);
  const rel = "components/runner-policy/policy.json";
  await mkdir(path.join(root, path.dirname(rel)), { recursive: true });
  const bytes = await readFile(new URL("../runner-policy/policy.json", import.meta.url), "utf8");
  await writeFile(path.join(root, rel), bytes);
  return { file: path.join(root, rel), root, bytes };
}

const reviewCopyForward = {
  kind: "lane",
  workflowPath: REVIEW_WORKFLOW,
  oldSha: CURRENT_REVIEW_SHA,
  newSha: FRESH_SHA,
};

test("settleLockstep writes no policy.json when any pin was declined", async () => {
  const { file, root, bytes } = await policyRoot();
  const output = await settleLockstep(
    { reasons: ["x"], copyForwards: [reviewCopyForward] },
    FRESH_SHA,
    "v0.34.0",
    root,
  );
  assert.equal(await readFile(file, "utf8"), bytes);
  assert.deepEqual(output[0], ["lockstep", "manual"]);
});

test("settleLockstep writes the copy-forward when nothing was declined", async () => {
  const { file, root } = await policyRoot();
  const output = await settleLockstep(
    { reasons: [], copyForwards: [reviewCopyForward] },
    FRESH_SHA,
    "v0.34.0",
    root,
  );
  const written = JSON.parse(await readFile(file, "utf8"));
  assert.ok(written.approvedReusableWorkflowContracts[`${REVIEW_WORKFLOW}@${FRESH_SHA}`]);
  assert.deepEqual(output[0], ["lockstep", "applied"]);
});

test("a selector copy-forward throws and adds no selector key", async () => {
  const onDisk = JSON.parse(
    await readFile(new URL("../runner-policy/policy.json", import.meta.url), "utf8"),
  );
  const policy = structuredClone(onDisk);
  const before = structuredClone(policy);
  assert.throws(
    () =>
      copyForwardContracts(policy, [
        {
          kind: "selector",
          workflowPath: "melodic-software/ci-workflows/.github/workflows/select-runner.yml",
          oldSha: CURRENT_REVIEW_SHA,
          newSha: FRESH_SHA,
        },
      ]),
    /unhandled repin target kind: selector/u,
  );
  assert.deepEqual(policy, before);
  assertNoSelectorKeys(policy);
});
