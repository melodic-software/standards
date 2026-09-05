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

const CANONICAL = `concurrency:
  group: \${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: true
`;
const JOBS = 'jobs:\n  build:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: "true"\n';
const temporaryRoots = [];

// The ci-perf contract-only predicate, spelled out here rather than imported so
// the analyzer's copy is compared against an independent literal.
const PREDICATE = `github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))`;
const CONTRACT_BRANCH = `format('ci-contract-{0}-{1}', github.event.pull_request.number, github.run_id)`;

// The branched group as one line, and as the folded scalar the design writes.
// Both spellings reach the analyzer as a single string; the folded one keeps a
// newline and the continuation indent at each of the two operator joins.
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

// Blocking findings only. Info findings never fail the gate, so every
// accept-case assertion below reads them through `fallbacks` instead.
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
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", CANONICAL) },
  });
  const findings = await auditRepository({ root });
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
  const root = await repository({
    workflows: { "ci.yml": workflow("on:\n  pull_request:", quoted) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), []);
});

test("pull_request_target with the canonical block passes", async () => {
  const root = await repository({
    workflows: { "ci.yml": workflow("on: pull_request_target", CANONICAL) },
  });
  assert.deepEqual(rules(await auditRepository({ root })), []);
});

test("array and mapping on: forms are recognized as pull-request-triggered", async () => {
  const array = await repository({
    workflows: { "ci.yml": workflow("on: [push, pull_request]", CANONICAL) },
  });
  assert.deepEqual(rules(await auditRepository({ root: array })), []);
  const mapping = await repository({
    workflows: {
      "ci.yml": workflow("on:\n  push:\n    branches: [main]\n  pull_request:", CANONICAL),
    },
  });
  assert.deepEqual(rules(await auditRepository({ root: mapping })), []);
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
    const single = await repository({
      workflows: { "ci.yml": workflow("on: pull_request", branchedSingleLine(fallback)) },
    });
    const singleFindings = await auditRepository({ root: single });
    assert.deepEqual(rules(singleFindings), []);
    assert.deepEqual(fallbacks(singleFindings), [
      `.github/workflows/ci.yml:concurrency-group-fallback:${fallback}`,
    ]);

    // The folded scalar the design writes. Its continuation lines are
    // more-indented, so the parser keeps a newline and that indent at each
    // join; only the joins and the `${{ }}` delimiters tolerate it.
    const folded = await repository({
      workflows: {
        "ci.yml": workflow(
          "on:\n  push:\n    branches: [main]\n  pull_request:",
          branchedFolded(fallback),
        ),
      },
    });
    const foldedFindings = await auditRepository({ root: folded });
    assert.deepEqual(rules(foldedFindings), []);
    assert.deepEqual(fallbacks(foldedFindings), [
      `.github/workflows/ci.yml:concurrency-group-fallback:${fallback}`,
    ]);
  }
});

test("the branched group pairs with either accepted cancel-in-progress value", async () => {
  const contractOnlyCancel = `\${{ !(${PREDICATE}) }}`;
  for (const cancel of ["true", contractOnlyCancel]) {
    const root = await repository({
      workflows: {
        "ci.yml": workflow("on: pull_request", branchedFolded("github.run_id", cancel)),
      },
    });
    assert.deepEqual(rules(await auditRepository({ root })), []);
  }
});

test("a branched group whose predicate drifts by one byte is rejected", async () => {
  // One space added inside the fromJSON array literal, and separately the
  // base-edit clause dropped. Both are the drift the byte-identity rule exists
  // to catch: the composite compares its own default against this text.
  const spaced = PREDICATE.replace('"labeled","unlabeled"', '"labeled", "unlabeled"');
  const clauseDropped = PREDICATE.replace(
    "(github.event.action == 'edited' && !github.event.changes.base)",
    "github.event.action == 'edited'",
  );
  const bare = `\${{ ${PREDICATE} && ${CONTRACT_BRANCH} || format('{0}-{1}', github.workflow, github.event.pull_request.number || github.run_id) }}`;
  for (const predicate of [spaced, clauseDropped]) {
    assert.notEqual(predicate, PREDICATE);
    const root = await repository({
      workflows: {
        "ci.yml": workflow(
          "on: pull_request",
          branchedSingleLine("github.run_id", CONTRACT_BRANCH, predicate),
        ),
      },
    });
    assert.deepEqual(rules(await auditRepository({ root })), [
      ".github/workflows/ci.yml:concurrency-group-drift",
    ]);
  }

  // The predicate stripped of its surrounding parentheses. `&&` binds tighter
  // than `||` in GitHub expressions, so this happens to evaluate the same way,
  // but it is not the shape the grammar admits.
  const unparenthesized = await repository({
    workflows: {
      "ci.yml": workflow(
        "on: pull_request",
        `concurrency:\n  group: ${bare}\n  cancel-in-progress: true\n`,
      ),
    },
  });
  assert.deepEqual(rules(await auditRepository({ root: unparenthesized })), [
    ".github/workflows/ci.yml:concurrency-group-drift",
  ]);
});

test("a fallback term other than github.ref or github.run_id is rejected", async () => {
  for (const fallback of [
    "github.head_ref",
    "github.sha",
    "github.ref_name",
    "github.run_number",
  ]) {
    const root = await repository({
      workflows: { "ci.yml": workflow("on: pull_request", branchedSingleLine(fallback)) },
    });
    const findings = await auditRepository({ root });
    assert.deepEqual(rules(findings), [".github/workflows/ci.yml:concurrency-group-drift"]);
    assert.deepEqual(fallbacks(findings), []);
  }
});

test("a contract branch without github.run_id is rejected", async () => {
  // Without run_id the contract-only branch is shared across every
  // contract-only run of the pull request, so one can evict another and leave
  // the check suite with no ci-status check run: the failure mode the branch
  // exists to remove.
  const branches = [
    `format('ci-contract-{0}', github.event.pull_request.number)`,
    `format('ci-contract-{0}-{1}', github.event.pull_request.number, github.sha)`,
    `format('ci-contract-{0}-{1}', github.event.pull_request.number, github.run_attempt)`,
  ];
  for (const contractBranch of branches) {
    const root = await repository({
      workflows: {
        "ci.yml": workflow("on: pull_request", branchedSingleLine("github.run_id", contractBranch)),
      },
    });
    assert.deepEqual(rules(await auditRepository({ root })), [
      ".github/workflows/ci.yml:concurrency-group-drift",
    ]);
  }
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

test("the ci-perf contract-only cancel expression passes, and only byte-identically", async () => {
  const canonicalGroup = `concurrency:
  group: \${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}
`;
  const exact = `${canonicalGroup}  cancel-in-progress: \${{ !(github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))) }}
`;
  const rootExact = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", exact) },
  });
  assert.deepEqual(rules(await auditRepository({ root: rootExact })), []);

  // One space added inside the fromJSON array literal. The composite compares
  // its own default against this text, so a reformatted copy is drift, not a
  // stylistic variant.
  const whitespaceVariant = `${canonicalGroup}  cancel-in-progress: \${{ !(github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled", "unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))) }}
`;
  const rootWhitespace = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", whitespaceVariant) },
  });
  assert.deepEqual(rules(await auditRepository({ root: rootWhitespace })), [
    ".github/workflows/ci.yml:concurrency-cancel-missing",
  ]);

  // The base-edit clause dropped. This one is not cosmetic: without it an
  // `edited` event that changed the base branch would be treated as
  // contract-only, so the lanes would never re-test the new merge commit.
  const clauseVariant = `${canonicalGroup}  cancel-in-progress: \${{ !(github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || github.event.action == 'edited')) }}
`;
  const rootClause = await repository({
    workflows: { "ci.yml": workflow("on: pull_request", clauseVariant) },
  });
  assert.deepEqual(rules(await auditRepository({ root: rootClause })), [
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
