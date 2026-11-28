import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  auditRepository,
  ConfigurationError,
  parseArguments,
  parseUniqueJson,
} from "./concurrency-policy.mjs";

const CANONICAL_GROUP = `concurrency:
  group: \${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}
`;
const CANONICAL = `${CANONICAL_GROUP}  cancel-in-progress: true\n`;
const REF_BLOCK = `concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true
`;
const PUSH_AND_PULL_REQUEST = "on:\n  push:\n    branches: [main]\n  pull_request:";
const JOBS = 'jobs:\n  build:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: "true"\n';
const temporaryRoots = [];

const PREDICATE = `github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))`;
const CONTRACT_BRANCH = `format('ci-contract-{0}-{1}', github.event.pull_request.number, github.run_id)`;
const SPACED_PREDICATE = PREDICATE.replace('"labeled","unlabeled"', '"labeled", "unlabeled"');
const CLAUSE_DROPPED_PREDICATE = PREDICATE.replace(
  "(github.event.action == 'edited' && !github.event.changes.base)",
  "github.event.action == 'edited'",
);

function branchedSingleLine(fallback, contractBranch = CONTRACT_BRANCH, predicate = PREDICATE) {
  return `concurrency:
  group: \${{ (${predicate}) && ${contractBranch} || format('{0}-{1}', github.workflow, github.event.pull_request.number || ${fallback}) }}
  cancel-in-progress: true
`;
}

function branchedFolded(fallback, cancelInProgress = "true") {
  return `concurrency:
  group: >-
    \${{ (${PREDICATE})
        && ${CONTRACT_BRANCH}
        || format('{0}-{1}', github.workflow, github.event.pull_request.number || ${fallback}) }}
  cancel-in-progress: ${cancelInProgress}
`;
}

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

async function auditCi(concurrencyYaml, onYaml = "on: pull_request") {
  const root = await repository({ workflows: { "ci.yml": workflow(onYaml, concurrencyYaml) } });
  return auditRepository({ root });
}

function rules(findings) {
  return findings
    .filter((item) => item.level !== "info")
    .map((item) => `${item.file}:${item.rule}`)
    .sort();
}

function fallbacks(findings) {
  return findings
    .filter((item) => item.level === "info")
    .map((item) => `${item.file}:${item.rule}:${item.fallback}`)
    .sort();
}

test.after(async () => {
  await Promise.all(temporaryRoots.map((root) => rm(root, { force: true, recursive: true })));
});

test("command-line parsing preserves defaults and follows strict Node syntax", () => {
  assert.deepEqual(parseArguments(["--"]), {
    root: process.cwd(),
    configPath: ".github/concurrency-policy.json",
    json: false,
  });
  assert.deepEqual(parseArguments(["--json", "--root=repo", "--config=config.json"]), {
    root: "repo",
    configPath: "config.json",
    json: true,
  });
  assert.equal(parseArguments(["--root=-repo"]).root, "-repo");

  for (const [argv, pattern] of [
    [["--unknown"], /Unknown option/u],
    [["--root", "-repo"], /ambiguous/u],
    [["repo"], /Unexpected argument/u],
  ]) {
    assert.throws(
      () => parseArguments(argv),
      (error) => error instanceof ConfigurationError && pattern.test(error.message),
    );
  }
});

test("canonical block on a pull_request workflow passes", async () => {
  const findings = await auditCi(CANONICAL);
  assert.deepEqual(rules(findings), []);
  assert.deepEqual(fallbacks(findings), [
    ".github/workflows/ci.yml:concurrency-group-fallback:github.run_id",
  ]);
});

test("quoted group string and extra expression whitespace still conform", async () => {
  const quoted = `concurrency:
  group: "\${{  github.workflow  }}-\${{ github.event.pull_request.number||github.run_id }}"
  cancel-in-progress: true
`;
  assert.deepEqual(rules(await auditCi(quoted, "on:\n  pull_request:")), []);
});

test("pull_request_target with the canonical block passes", async () => {
  assert.deepEqual(rules(await auditCi(CANONICAL, "on: pull_request_target")), []);
});

test("array and mapping on: forms are recognized as pull-request-triggered", async () => {
  assert.deepEqual(rules(await auditCi(CANONICAL, "on: [push, pull_request]")), []);
  assert.deepEqual(rules(await auditCi(CANONICAL, PUSH_AND_PULL_REQUEST)), []);
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

test("the ci-perf branched group passes single-line and folded, with either fallback", async () => {
  for (const fallback of ["github.ref", "github.run_id"]) {
    const singleFindings = await auditCi(branchedSingleLine(fallback));
    assert.deepEqual(rules(singleFindings), []);
    assert.deepEqual(fallbacks(singleFindings), [
      `.github/workflows/ci.yml:concurrency-group-fallback:${fallback}`,
    ]);

    const foldedFindings = await auditCi(branchedFolded(fallback), PUSH_AND_PULL_REQUEST);
    assert.deepEqual(rules(foldedFindings), []);
    assert.deepEqual(fallbacks(foldedFindings), [
      `.github/workflows/ci.yml:concurrency-group-fallback:${fallback}`,
    ]);
  }
});

test("the branched group pairs with either accepted cancel-in-progress value", async () => {
  const contractOnlyCancel = `\${{ !(${PREDICATE}) }}`;
  for (const cancel of ["true", contractOnlyCancel]) {
    assert.deepEqual(rules(await auditCi(branchedFolded("github.run_id", cancel))), []);
  }
});

test("a branched group whose predicate drifts by one byte is rejected", async () => {
  const bare = `\${{ ${PREDICATE} && ${CONTRACT_BRANCH} || format('{0}-{1}', github.workflow, github.event.pull_request.number || github.run_id) }}`;
  for (const predicate of [SPACED_PREDICATE, CLAUSE_DROPPED_PREDICATE]) {
    assert.notEqual(predicate, PREDICATE);
    assert.deepEqual(
      rules(await auditCi(branchedSingleLine("github.run_id", CONTRACT_BRANCH, predicate))),
      [".github/workflows/ci.yml:concurrency-group-drift"],
    );
  }

  assert.deepEqual(
    rules(await auditCi(`concurrency:\n  group: ${bare}\n  cancel-in-progress: true\n`)),
    [".github/workflows/ci.yml:concurrency-group-drift"],
  );
});

test("a fallback term other than github.ref or github.run_id is rejected", async () => {
  for (const fallback of [
    "github.head_ref",
    "github.sha",
    "github.ref_name",
    "github.run_number",
  ]) {
    const findings = await auditCi(branchedSingleLine(fallback));
    assert.deepEqual(rules(findings), [".github/workflows/ci.yml:concurrency-group-drift"]);
    assert.deepEqual(fallbacks(findings), []);
  }
});

test("a contract branch without github.run_id is rejected", async () => {
  const branches = [
    `format('ci-contract-{0}', github.event.pull_request.number)`,
    `format('ci-contract-{0}-{1}', github.event.pull_request.number, github.sha)`,
    `format('ci-contract-{0}-{1}', github.event.pull_request.number, github.run_attempt)`,
  ];
  for (const contractBranch of branches) {
    assert.deepEqual(rules(await auditCi(branchedSingleLine("github.run_id", contractBranch))), [
      ".github/workflows/ci.yml:concurrency-group-drift",
    ]);
  }
});

test("missing top-level concurrency on a pull_request workflow is flagged", async () => {
  assert.deepEqual(rules(await auditCi()), [".github/workflows/ci.yml:concurrency-missing"]);
});

test("github.ref group drifts from the canonical pull-request-number form", async () => {
  assert.deepEqual(rules(await auditCi(REF_BLOCK, PUSH_AND_PULL_REQUEST)), [
    ".github/workflows/ci.yml:concurrency-group-drift",
  ]);
});

test("head_ref variant is treated as drift from the standard", async () => {
  const headRefBlock = `concurrency:
  group: \${{ github.workflow }}-\${{ github.head_ref || github.run_id }}
  cancel-in-progress: true
`;
  assert.deepEqual(rules(await auditCi(headRefBlock)), [
    ".github/workflows/ci.yml:concurrency-group-drift",
  ]);
});

test("canonical group without cancel-in-progress is flagged", async () => {
  assert.deepEqual(rules(await auditCi(CANONICAL_GROUP)), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
  ]);
});

test("cancel-in-progress as false or an expression is flagged, not crashed", async () => {
  for (const cancel of ["false", `\${{ github.event_name == 'pull_request' }}`]) {
    assert.deepEqual(rules(await auditCi(`${CANONICAL_GROUP}  cancel-in-progress: ${cancel}\n`)), [
      ".github/workflows/ci.yml:concurrency-cancel-missing",
    ]);
  }
});

test("the ci-perf contract-only cancel expression passes, and only byte-identically", async () => {
  const withCancel = (predicate) =>
    auditCi(`${CANONICAL_GROUP}  cancel-in-progress: \${{ !(${predicate}) }}\n`);
  assert.deepEqual(rules(await withCancel(PREDICATE)), []);

  assert.deepEqual(rules(await withCancel(SPACED_PREDICATE)), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
  ]);

  assert.deepEqual(rules(await withCancel(CLAUSE_DROPPED_PREDICATE)), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
  ]);
});

test("group-only string shorthand drifts and lacks cancellation", async () => {
  assert.deepEqual(rules(await auditCi("concurrency: my-static-group\n")), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
    ".github/workflows/ci.yml:concurrency-group-drift",
  ]);
});

test("array concurrency is malformed", async () => {
  assert.deepEqual(rules(await auditCi("concurrency:\n  - group: a\n")), [
    ".github/workflows/ci.yml:concurrency-malformed",
  ]);
});

test("an extra key on the canonical block is flagged", async () => {
  assert.deepEqual(rules(await auditCi(`${CANONICAL}  queue: max\n`)), [
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
    workflows: { "claude-review.yml": workflow("on: pull_request", REF_BLOCK) },
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

test("the command line exits 0 on info findings and 1 on blocking findings", async () => {
  const analyzer = path.join(import.meta.dirname, "concurrency-policy.mjs");
  const run = (root) =>
    new Promise((resolve) => {
      execFile(process.execPath, [analyzer, "--root", root, "--json"], (error, stdout) =>
        resolve({ code: error === null ? 0 : error.code, stdout }),
      );
    });

  const infoOnly = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", branchedFolded("github.ref")) },
  });
  const passed = await run(infoOnly);
  assert.equal(passed.code, 0);
  const passedReport = JSON.parse(passed.stdout);
  assert.equal(passedReport.ok, true);
  assert.deepEqual(passedReport.findings, [
    {
      level: "info",
      rule: "concurrency-group-fallback",
      file: ".github/workflows/ci.yml",
      message:
        "top-level concurrency.group is the branched form with fallback term `github.ref`, so " +
        "push and schedule runs collapse into one group per ref",
      fallback: "github.ref",
    },
  ]);

  const drifted = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", branchedSingleLine("github.head_ref")) },
  });
  const failed = await run(drifted);
  assert.equal(failed.code, 1);
  assert.equal(JSON.parse(failed.stdout).ok, false);
});

test("duplicate JSON members in the config fail closed", () => {
  assert.throws(
    () => parseUniqueJson('{"schemaVersion":1,"schemaVersion":1}', "config at /tmp/c.json"),
    (error) => error instanceof ConfigurationError && error.message.includes("duplicate"),
  );
});
