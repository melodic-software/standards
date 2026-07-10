import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { auditRepository, ConfigurationError } from "./runner-policy.mjs";

const SHA = "0123456789abcdef0123456789abcdef01234567";
const SELECTOR_PATH = "melodic-software/ci-workflows/.github/workflows/select-runner.yml";
const SELECTOR_REFERENCE = `${SELECTOR_PATH}@${SHA}`;
const REUSABLE_PATH = "melodic-software/ci-workflows/.github/workflows/osv-scanner.yml";
const REUSABLE_REFERENCE = `${REUSABLE_PATH}@${SHA}`;
const HOSTED_REUSABLE_REFERENCE =
  "melodic-software/ci-workflows/.github/workflows/semantic-pr.yml@1d3762c2ace413db0f347048307946c46850161c";
const CANONICAL_POLICY_EXPRESSION = `\${{ vars.CI_RUNNER_POLICY }}`;
const ARBITRARY_POLICY_EXPRESSION = `\${{ vars.ARBITRARY_POLICY }}`;
const CANONICAL_OBSERVER_SECRET_EXPRESSION = `\${{ secrets.CI_RUNNER_OBSERVER_PRIVATE_KEY }}`;
const BASE_POLICY = JSON.parse(await readFile(new URL("./policy.json", import.meta.url), "utf8"));
const temporaryRoots = [];
const SELECTOR = `    uses: ${SELECTOR_REFERENCE}
    secrets:
      observer-private-key: \${{ secrets.CI_RUNNER_OBSERVER_PRIVATE_KEY }}
    with:
      policy: \${{ vars.CI_RUNNER_POLICY }}
      self-hosted-label: \${{ vars.CI_SELF_HOSTED_LABEL }}
      hosted-runner: \${{ vars.CI_HOSTED_RUNNER }}
      scope: \${{ vars.CI_RUNNER_SCOPE }}
      managed-runner-prefix: \${{ vars.CI_MANAGED_RUNNER_PREFIX }}
      observer-client-id: \${{ vars.CI_RUNNER_OBSERVER_CLIENT_ID }}
`;

async function repository({
  visibility = "private",
  selfHostedCi = true,
  exceptions = {},
  workflows = {},
} = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "runner-policy-"));
  temporaryRoots.push(root);
  await mkdir(path.join(root, ".github", "workflows"), { recursive: true });
  await writeFile(
    path.join(root, ".github", "runner-policy.json"),
    `${JSON.stringify({ schemaVersion: 1, visibility, selfHostedCi, exceptions }, null, 2)}\n`,
  );
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(
      {
        ...BASE_POLICY,
        approvedSelectorReferences: [SELECTOR_REFERENCE],
        approvedReusableWorkflowContracts: {
          [REUSABLE_REFERENCE]: {
            routing: "runner-input",
            runnerInput: "runner",
            allowedInputs: ["runner"],
          },
        },
      },
      null,
      2,
    )}\n`,
  );
  for (const [name, source] of Object.entries(workflows)) {
    await writeFile(path.join(root, ".github", "workflows", name), source);
  }
  return root;
}

function audit(root, options = {}) {
  return auditRepository({
    root,
    policyPath: path.join(root, "runner-policy-policy.json"),
    ...options,
  });
}

test.after(async () => {
  await Promise.all(temporaryRoots.map((root) => rm(root, { force: true, recursive: true })));
});

test("public repository with explicit hosted image passes", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps: []\n" },
  });
  assert.deepEqual(await audit(root), []);
});

test("GitHub visibility evidence must agree with governed inventory", async () => {
  const root = await repository({
    visibility: "private",
    selfHostedCi: false,
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps: []\n" },
  });
  await assert.rejects(
    () => audit(root, { repositoryVisibility: "public" }),
    /visibility evidence is public/,
  );
});

test("public repository cannot target a raw self-hosted label", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: [self-hosted, linux]\n    steps: []\n" },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["raw-self-hosted-label"],
  );
});

test("moving ubuntu-latest alias is forbidden", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps: []\n" },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["explicit-hosted-runner"],
  );
});

test("private job can consume a full-SHA-pinned selector output", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n${SELECTOR}  test:\n    needs: choose\n    runs-on: \${{ needs.choose.outputs.runner }}\n    steps: []\n`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("obsolete full selector SHA is rejected unless that exact path@SHA is approved", async () => {
  const obsolete = "fedcba9876543210fedcba9876543210fedcba98";
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n${SELECTOR.replace(SHA, obsolete)}`,
    },
  });
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "selector-pin");
  assert.match(findings[0].message, /path@SHA.*allowlist/);
});

test("empty production selector allowlist fails closed until publication", async () => {
  const root = await repository({
    workflows: { "ci.yml": `jobs:\n  choose:\n${SELECTOR}` },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "selector-pin");
  assert.match(findings[0].message, /no reviewed selector path@SHA/);
});

test("selector policy must use the governed variable expression, not hosted-only", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n${SELECTOR.replace(CANONICAL_POLICY_EXPRESSION, "hosted-only")}`,
    },
  });
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "selector-pin");
  assert.match(findings[0].message, /selector inputs\.policy must be exactly/);
});

test("selector policy rejects arbitrary variable indirection", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n${SELECTOR.replace(
        CANONICAL_POLICY_EXPRESSION,
        ARBITRARY_POLICY_EXPRESSION,
      )}`,
    },
  });
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "selector-pin");
  assert.match(findings[0].message, /selector inputs\.policy must be exactly/);
});

test("selector observer key must use the exact governed secret expression", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n${SELECTOR.replace(
        CANONICAL_OBSERVER_SECRET_EXPRESSION,
        "literal-private-key",
      )}`,
    },
  });
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "selector-pin");
  assert.match(findings[0].message, /selector secrets\.observer-private-key must be exactly/);
});

test("reusable workflow caller passes the approved runner input", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n${SELECTOR}  test:\n    needs: [choose]\n    uses: ${REUSABLE_REFERENCE}\n    with:\n      runner: \${{ needs.choose.outputs.runner }}\n`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("unreviewed reusable workflow cannot forward an approved selector output", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:
  choose:
${SELECTOR}  attack:
    needs: choose
    uses: attacker/unreviewed/.github/workflows/arbitrary.yml@${SHA}
    with:
      runner: \${{ needs.choose.outputs.runner }}
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required", "runner-target-contract"],
  );
});

test("obsolete reusable workflow SHA is outside the exact reviewed contract", async () => {
  const obsolete = "fedcba9876543210fedcba9876543210fedcba98";
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  scan:
    uses: ${REUSABLE_PATH}@${obsolete}
    with:
      runner: ubuntu-24.04
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["runner-target-contract"],
  );
});

test("public opaque reusable call and alternate runner-label input are rejected", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  attack:
    uses: attacker/unreviewed/.github/workflows/arbitrary.yml@${SHA}
    with:
      runner-label: melodic-ubuntu-24.04-x64
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["raw-self-hosted-label", "runner-target-contract"],
  );
});

test("reviewed reusable workflow rejects inputs outside its explicit contract", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  attack:
    uses: ${REUSABLE_REFERENCE}
    with:
      runner: ubuntu-24.04
      runner-label: melodic-ubuntu-24.04-x64
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["raw-self-hosted-label", "runner-target-contract"],
  );
});

test("reviewed reusable workflow can remain hosted with an exception", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#scan": {
        reason: "hosted-control-plane",
        justification: "The reviewed reusable scan remains hosted during rollout.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  scan:
    uses: ${REUSABLE_REFERENCE}
    with:
      runner: ubuntu-24.04
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("exact reviewed hosted-only reusable workflow needs no runner input", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  title:
    uses: ${HOSTED_REUSABLE_REFERENCE}
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(await audit(root), []);
});

test("hosted-only reusable contract rejects a caller-added runner input", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  title:
    uses: ${HOSTED_REUSABLE_REFERENCE}
    with:
      runner-label: melodic-ubuntu-24.04-x64
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["raw-self-hosted-label", "runner-target-contract"],
  );
});

test("eligible private hosted job requires a machine-readable exception", async () => {
  const root = await repository({
    workflows: { "ci.yml": "jobs:\n  windows:\n    runs-on: windows-2025\n    steps: []\n" },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required"],
  );
});

test("allowlisted hosted exception is consumed", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#windows": {
        reason: "windows",
        justification: "The local fleet has no Windows worker backend.",
      },
    },
    workflows: { "ci.yml": "jobs:\n  windows:\n    runs-on: windows-2025\n    steps: []\n" },
  });
  assert.deepEqual(await audit(root), []);
});

test("public jobs reject dynamic runner indirection", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  test:
    runs-on: \${{ vars.ARBITRARY_RUNNER }}
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["runner-target-contract"],
  );
});

test("hosted exception cannot authorize runner indirection", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#test": {
        reason: "hosted-control-plane",
        justification: "This job intentionally remains on a GitHub-hosted runner.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  test:
    runs-on: \${{ vars.ARBITRARY_RUNNER }}
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["runner-target-contract"],
  );
});

test("static allowlisted hosted matrix is supported", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-24.04, windows-2025]
    runs-on: \${{ matrix.os }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("hosted matrix include cannot override the proven runner axis", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-24.04]
        include:
          - os: ubuntu-24.04
    runs-on: \${{ matrix.os }}
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["runner-target-contract"],
  );
});

test("governed reusable workflow runner input is supported", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "reusable.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("governed reusable runner input rejects workflow_dispatch co-trigger", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "reusable.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
  workflow_dispatch:
    inputs:
      runner:
        type: choice
        default: melodic-ubuntu-24.04-x64
        options: [melodic-ubuntu-24.04-x64]
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["runner-target-contract"],
  );
});

test("selector-routed job container is rejected and requires matching hosted exception", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    runs-on: \${{ needs.choose.outputs.runner }}
    container: node:24
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required", "structural-hosted-only"],
  );
});

test("selector-routed services are rejected even with matching hosted exception", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#test": {
        reason: "service-container",
        justification: "Service containers require the GitHub-hosted backend.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    runs-on: \${{ needs.choose.outputs.runner }}
    services:
      postgres:
        image: postgres:18
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["structural-hosted-only"],
  );
});

test("reusable runner input cannot route a job container locally", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/reusable.yml#test": {
        reason: "job-container",
        justification: "Job containers require the GitHub-hosted backend.",
      },
    },
    workflows: {
      "reusable.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    container: node:24
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["structural-hosted-only"],
  );
});

test("hosted job container passes with matching machine-readable exception", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#test": {
        reason: "job-container",
        justification: "Job containers require the GitHub-hosted backend.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  test:
    runs-on: ubuntu-24.04
    container: node:24
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("hosted services pass with matching machine-readable exception", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#test": {
        reason: "service-container",
        justification: "Service containers require the GitHub-hosted backend.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  test:
    runs-on: ubuntu-24.04
    services:
      postgres:
        image: postgres:18
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("structural hosted exception reason must match the job shape", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#test": {
        reason: "service-container",
        justification: "This intentionally exercises category validation.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  test:
    runs-on: ubuntu-24.04
    container: node:24
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-category"],
  );
});

test("exception inventory drift fails", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#renamed": {
        reason: "service-container",
        justification: "The local fleet excludes service-container workloads.",
      },
    },
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps: []\n" },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["exception-inventory-drift", "hosted-exception-required"],
  );
});

test("managed label is forbidden even when listed in a matrix", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  test:\n    strategy:\n      matrix:\n        runner: [ubuntu-24.04, melodic-ubuntu-24.04-x64]\n    runs-on: \${{ matrix.runner }}\n    steps: []\n`,
    },
  });
  const rules = (await audit(root)).map(({ rule }) => rule);
  assert.deepEqual(rules, ["hosted-exception-required", "raw-self-hosted-label"]);
});

test("selector ref must be a full SHA", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n    uses: melodic-software/ci-workflows/.github/workflows/select-runner.yml@main\n  test:\n    needs: choose\n    runs-on: \${{ needs.choose.outputs.runner }}\n    steps: []\n`,
    },
  });
  const rules = (await audit(root)).map(({ rule }) => rule);
  assert.deepEqual(rules, ["selector-pin", "hosted-exception-required", "selector-contract"]);
});

test("selector cannot inherit all caller secrets", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n    uses: melodic-software/ci-workflows/.github/workflows/select-runner.yml@${SHA}\n    secrets: inherit\n    with:\n      policy: prefer-self-hosted\n      self-hosted-label: melodic-ubuntu-24.04-x64\n      hosted-runner: ubuntu-24.04\n      scope: organization\n      managed-runner-prefix: ci-runner-melo-\n      observer-client-id: Iv23example\n`,
    },
  });
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "selector-pin");
  assert.match(findings[0].message, /secrets: inherit/);
});

test("unrecognized hosted reason is a configuration error", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#test": { reason: "because", justification: "No." },
    },
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps: []\n" },
  });
  await assert.rejects(() => audit(root), ConfigurationError);
});

test("duplicate YAML keys fail closed", async () => {
  const root = await repository({
    workflows: {
      "ci.yml":
        "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    runs-on: windows-2025\n    steps: []\n",
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["workflow-parse"],
  );
});
