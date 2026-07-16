import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { auditRepository, ConfigurationError, parseUniqueJson } from "./concurrency-policy.mjs";

const CANONICAL = `concurrency:
  group: \${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: true
`;
const JOBS = 'jobs:\n  build:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: "true"\n';
const temporaryRoots = [];

function workflow(onYaml, concurrencyYaml = "") {
  return `${onYaml}\n${concurrencyYaml}${JOBS}`;
}

async function repository({ config, workflows = {} } = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "concurrency-policy-"));
  temporaryRoots.push(root);
  await mkdir(path.join(root, ".github", "workflows"), { recursive: true });
  if (config !== undefined) {
    await writeFile(
      path.join(root, ".github", "concurrency-policy.json"),
      typeof config === "string" ? config : `${JSON.stringify(config, null, 2)}\n`,
    );
  }
  for (const [name, source] of Object.entries(workflows)) {
    await writeFile(path.join(root, ".github", "workflows", name), source);
  }
  return root;
}

function rules(findings) {
  return findings.map((item) => `${item.file}:${item.rule}`).sort();
}

test.after(async () => {
  await Promise.all(temporaryRoots.map((root) => rm(root, { force: true, recursive: true })));
});

test("canonical block on a pull_request workflow passes", async () => {
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", CANONICAL) },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("quoted group string and extra expression whitespace still conform", async () => {
  const quoted = `concurrency:
  group: "\${{  github.workflow  }}-\${{ github.event.pull_request.number||github.run_id }}"
  cancel-in-progress: true
`;
  const root = await repository({
    workflows: { "ci.yml": workflow("on:\n  pull_request:", quoted) },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("pull_request_target with the canonical block passes", async () => {
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request_target", CANONICAL) },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("array and mapping on: forms are recognized as pull-request-triggered", async () => {
  const array = await repository({
    workflows: { "ci.yml": workflow("on: [push, pull_request]", CANONICAL) },
  });
  assert.deepEqual(await auditRepository({ root: array }), []);
  const mapping = await repository({
    workflows: {
      "ci.yml": workflow("on:\n  push:\n    branches: [main]\n  pull_request:", CANONICAL),
    },
  });
  assert.deepEqual(await auditRepository({ root: mapping }), []);
});

test("non-pull-request workflows are out of scope", async () => {
  const root = await repository({
    workflows: {
      "release.yml": workflow("on:\n  push:\n    tags: ['v*']"),
      "schedule.yml": workflow("on:\n  schedule:\n    - cron: '0 0 * * 0'"),
      "reusable.yml": workflow("on: workflow_call"),
      "dispatch.yml": workflow("on: workflow_dispatch"),
    },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("repository with no workflows directory passes", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "concurrency-policy-empty-"));
  temporaryRoots.push(root);
  assert.deepEqual(await auditRepository({ root }), []);
});

test("missing top-level concurrency on a pull_request workflow is flagged", async () => {
  const root = await repository({ workflows: { "ci.yml": workflow("on: pull_request") } });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:concurrency-missing",
  ]);
});

test("github.ref group drifts from the canonical pull-request-number form", async () => {
  const refBlock = `concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true
`;
  const root = await repository({
    workflows: {
      "ci.yml": workflow("on:\n  push:\n    branches: [main]\n  pull_request:", refBlock),
    },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:concurrency-group-drift",
  ]);
});

test("head_ref variant is treated as drift from the standard", async () => {
  const headRefBlock = `concurrency:
  group: \${{ github.workflow }}-\${{ github.head_ref || github.run_id }}
  cancel-in-progress: true
`;
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", headRefBlock) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:concurrency-group-drift",
  ]);
});

test("canonical group without cancel-in-progress is flagged", async () => {
  const noCancel = `concurrency:
  group: \${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}
`;
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", noCancel) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
  ]);
});

test("cancel-in-progress as false or an expression is flagged, not crashed", async () => {
  const falseCancel = `concurrency:
  group: \${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: false
`;
  const rootFalse = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", falseCancel) },
  });
  assert.deepEqual(rules(await auditRepository({ root: rootFalse })), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
  ]);
  const exprCancel = `concurrency:
  group: \${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: \${{ github.event_name == 'pull_request' }}
`;
  const rootExpr = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", exprCancel) },
  });
  assert.deepEqual(rules(await auditRepository({ root: rootExpr })), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
  ]);
});

test("group-only string shorthand drifts and lacks cancellation", async () => {
  const shorthand = "concurrency: my-static-group\n";
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", shorthand) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
    ".github/workflows/ci.yml:concurrency-group-drift",
  ]);
});

test("array concurrency is malformed", async () => {
  const malformed = "concurrency:\n  - group: a\n";
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", malformed) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:concurrency-malformed",
  ]);
});

test("an extra key on the canonical block is flagged", async () => {
  const withQueue = `${CANONICAL}  queue: max\n`;
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", withQueue) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:concurrency-extra-keys",
  ]);
});

test("a delegated-job-level exception waives the missing top-level block", async () => {
  const root = await repository({
    config: {
      schemaVersion: 1,
      exceptions: {
        ".github/workflows/claude-review.yml": {
          reason: "delegated-job-level",
          justification: "Concurrency is enforced at job level in the reusable it calls.",
        },
      },
    },
    workflows: { "claude-review.yml": workflow("on: pull_request") },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("an exception on an already-conformant workflow is unconsumed drift", async () => {
  const root = await repository({
    config: {
      schemaVersion: 1,
      exceptions: {
        ".github/workflows/ci.yml": {
          reason: "delegated-job-level",
          justification: "Unnecessary because the workflow already conforms.",
        },
      },
    },
    workflows: { "ci.yml": workflow("on: pull_request", CANONICAL) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:exception-inventory-drift",
  ]);
});

test("an exception does not license a present non-canonical block", async () => {
  const refBlock = `concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true
`;
  const root = await repository({
    config: {
      schemaVersion: 1,
      exceptions: {
        ".github/workflows/claude-review.yml": {
          reason: "delegated-job-level",
          justification: "Delegates to a reusable but also carries a stray top-level block.",
        },
      },
    },
    workflows: { "claude-review.yml": workflow("on: pull_request", refBlock) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/claude-review.yml:concurrency-group-drift",
    ".github/workflows/claude-review.yml:exception-inventory-drift",
  ]);
});

test("an exception on a missing or non-pull-request workflow is drift", async () => {
  const missing = await repository({
    config: {
      schemaVersion: 1,
      exceptions: {
        ".github/workflows/ghost.yml": {
          reason: "delegated-job-level",
          justification: "No such workflow.",
        },
      },
    },
  });
  assert.deepEqual(rules(await auditRepository({ root: missing })), [
    ".github/workflows/ghost.yml:exception-inventory-drift",
  ]);
  const nonPr = await repository({
    config: {
      schemaVersion: 1,
      exceptions: {
        ".github/workflows/release.yml": {
          reason: "delegated-job-level",
          justification: "Not pull-request-triggered.",
        },
      },
    },
    workflows: { "release.yml": workflow("on:\n  push:\n    tags: ['v*']") },
  });
  assert.deepEqual(rules(await auditRepository({ root: nonPr })), [
    ".github/workflows/release.yml:exception-inventory-drift",
  ]);
});

test("an unparsable workflow fails closed", async () => {
  const root = await repository({ workflows: { "ci.yml": "on: pull_request\nfoo: 1\nfoo: 2\n" } });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/workflows/ci.yml:workflow-unparsable",
  ]);
});

test("workflow symlinks are forbidden", async () => {
  const root = await repository({
    workflows: { "real.yml": workflow("on: pull_request", CANONICAL) },
  });
  try {
    await symlink(
      path.join(root, ".github", "workflows", "real.yml"),
      path.join(root, ".github", "workflows", "link.yml"),
    );
  } catch {
    return; // Platform without symlink support (e.g. unprivileged Windows).
  }
  const findings = await auditRepository({ root });
  assert.deepEqual(
    findings.filter((item) => item.file === ".github/workflows/link.yml").map((item) => item.rule),
    ["workflow-unparsable"],
  );
});

test("an unknown exception reason fails closed at schema time", async () => {
  const root = await repository({
    config: {
      schemaVersion: 1,
      exceptions: {
        ".github/workflows/ci.yml": { reason: "because-i-said-so", justification: "nope" },
      },
    },
    workflows: { "ci.yml": workflow("on: pull_request") },
  });
  await assert.rejects(auditRepository({ root }), (error) => error instanceof ConfigurationError);
});

test("an unknown config key and a missing justification fail closed", async () => {
  const extraKey = await repository({
    config: { schemaVersion: 1, exceptions: {}, extra: true },
  });
  await assert.rejects(
    auditRepository({ root: extraKey }),
    (error) => error instanceof ConfigurationError,
  );
  const noJustification = await repository({
    config: {
      schemaVersion: 1,
      exceptions: { ".github/workflows/ci.yml": { reason: "delegated-job-level" } },
    },
    workflows: { "ci.yml": workflow("on: pull_request") },
  });
  await assert.rejects(
    auditRepository({ root: noJustification }),
    (error) => error instanceof ConfigurationError,
  );
});

test("duplicate JSON members in the config fail closed", () => {
  assert.throws(
    () => parseUniqueJson('{"schemaVersion":1,"schemaVersion":1}', "config at /tmp/c.json"),
    (error) => error instanceof ConfigurationError && error.message.includes("duplicate"),
  );
});
