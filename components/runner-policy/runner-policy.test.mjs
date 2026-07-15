import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { auditRepository, ConfigurationError, parseUniqueJson } from "./runner-policy.mjs";

const SHA = "0123456789abcdef0123456789abcdef01234567";
const PRODUCTION_SHA = "99ac2f8c5b09dbb785d4eaf18465cbd96c30290c";
const FAIL_CLOSED_SEMANTIC_PR_SHA = "51012e2c7b8bf74bc26e08c6446b488254a8770f";
const LATEST_SELECTOR_SHA = "029a1c37a9b86f8200ef03f6f0c54fb1e7e6cdb1";
const SELF_HOSTED_ONLY_SELECTOR_SHA = "3cb83c9502da0b210c335785e250023508c4b8e3";
const LOCAL_SELECTOR_SHA = "de50a08b6093d231519ee7a4c9371db76c0a7e1e";
const LIVENESS_SELECTOR_SHA = "3415de3ff2fafee40e4d087eb6073d2f6952b595";
const SECURITY_HARDENING_SHA = "f2d5e06757201f2fce187096a2c6fa805836c3d2";
const DEPENDABOT_ROUTING_SHA = "3931f91ccba9bfe97500196091ae2cc039672952";
const STANDARDS_SYNC_SHA = "35f2684ac953794b854bac1959df00e74eeca1d9";
const SELECTOR_PATH = "melodic-software/ci-workflows/.github/workflows/select-runner.yml";
const SELECTOR_REFERENCE = `${SELECTOR_PATH}@${SHA}`;
const REUSABLE_PATH = "melodic-software/ci-workflows/.github/workflows/osv-scanner.yml";
const REUSABLE_REFERENCE = `${REUSABLE_PATH}@${SHA}`;
const FAIL_CLOSED_SEMANTIC_PR_REFERENCE = `melodic-software/ci-workflows/.github/workflows/semantic-pr.yml@${FAIL_CLOSED_SEMANTIC_PR_SHA}`;
const HOSTED_REUSABLE_REFERENCE = `melodic-software/ci-workflows/.github/workflows/link-check.yml@${PRODUCTION_SHA}`;
const SECRET_REUSABLE_REFERENCE = `melodic-software/ci-workflows/.github/workflows/claude-review.yml@${PRODUCTION_SHA}`;
const PULUMI_DRIFT_SHA = "15aefd8799e8a8b5ffdfcc183dcbfcbf58044481";
const PULUMI_DRIFT_REUSABLE_REFERENCE = `melodic-software/ci-workflows/.github/workflows/pulumi-version-drift-check.yml@${PULUMI_DRIFT_SHA}`;
const STANDARDS_SYNC_REUSABLE_REFERENCE = `melodic-software/ci-workflows/.github/workflows/standards-sync.yml@${STANDARDS_SYNC_SHA}`;
const CANONICAL_POLICY_EXPRESSION = `\${{ vars.CI_RUNNER_POLICY }}`;
const ARBITRARY_POLICY_EXPRESSION = `\${{ vars.ARBITRARY_POLICY }}`;
const CANONICAL_OBSERVER_SECRET_EXPRESSION = `\${{ secrets.CI_RUNNER_OBSERVER_PRIVATE_KEY }}`;
const BASE_POLICY = JSON.parse(await readFile(new URL("./policy.json", import.meta.url), "utf8"));
const temporaryRoots = [];

test("duplicate JSON object members fail closed with their policy or schema path", () => {
  for (const [location, source] of [
    ["central policy at /tmp/policy.json", '{"schemaVersion":1,"schemaVersion":1}'],
    ["repository policy at /tmp/repository.json", '{"exceptions":{"job":{},"job":{}}}'],
    ["policy schema at /tmp/policy.schema.json", '{"properties":{"a":{},"a":{}}}'],
    [
      "repository policy schema at /tmp/repository-policy.schema.json",
      '{"$defs":{"exception":{"type":"object","type":"array"}}}',
    ],
  ]) {
    assert.throws(
      () => parseUniqueJson(source, location),
      (error) =>
        error instanceof ConfigurationError &&
        error.message.includes(location) &&
        error.message.includes("duplicate"),
    );
  }
});
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
  repositoryOwner,
  visibility = "private",
  selfHostedCi = true,
  exceptions = {},
  policyOverrides = {},
  workflows = {},
} = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "runner-policy-"));
  temporaryRoots.push(root);
  await mkdir(path.join(root, ".github", "workflows"), { recursive: true });
  await writeFile(
    path.join(root, ".github", "runner-policy.json"),
    `${JSON.stringify(
      {
        schemaVersion: 1,
        ...(repositoryOwner ? { repositoryOwner } : {}),
        visibility,
        selfHostedCi,
        exceptions,
      },
      null,
      2,
    )}\n`,
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
            allowedSecrets: {},
          },
        },
        ...policyOverrides,
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

for (const managedLabel of [
  "melodic-ubuntu-24.04-x64",
  "melodic-build-ubuntu-24.04-x64",
  "melodic-canary-ubuntu-24.04-x64",
  "kyle-ubuntu-24.04-x64",
  "kyle-build-ubuntu-24.04-x64",
]) {
  test(`managed runner namespace ${managedLabel} requires selector output`, async () => {
    const root = await repository({
      visibility: "public",
      selfHostedCi: false,
      workflows: {
        "ci.yml": `jobs:\n  test:\n    runs-on: ${managedLabel}\n    steps: []\n`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      ["raw-self-hosted-label"],
    );
  });
}

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
      "ci.yml": `permissions: read-all\njobs:\n  choose:\n${SELECTOR}  test:\n    needs: choose\n    if: \${{ !cancelled() }}\n    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}\n    steps: []\n`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("same-contract workloads can share one selector decision", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all\njobs:\n  choose:\n${SELECTOR}  lint:\n    needs: choose\n    if: \${{ !cancelled() }}\n    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}\n    steps: []\n  test:\n    needs: choose\n    if: \${{ !cancelled() }}\n    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}\n    steps: []\n`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("selector recovery derives its literal fallback from the governed default", async () => {
  const alternateDefault = "ubuntu-22.04";
  const policyOverrides = {
    approvedHostedRunnerLabels: [...BASE_POLICY.approvedHostedRunnerLabels, alternateDefault],
    governedReusableRunnerInput: {
      ...BASE_POLICY.governedReusableRunnerInput,
      default: alternateDefault,
    },
  };
  const workflow = (fallback) => `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || '${fallback}' }}
    steps: []
`;

  const acceptedRoot = await repository({
    policyOverrides,
    workflows: { "ci.yml": workflow(alternateDefault) },
  });
  assert.deepEqual(await audit(acceptedRoot), []);

  const mismatchedRoot = await repository({
    policyOverrides,
    workflows: { "ci.yml": workflow(BASE_POLICY.governedReusableRunnerInput.default) },
  });
  const findings = await audit(mismatchedRoot);
  assert.deepEqual(
    findings.map(({ rule, job }) => ({ rule, job })),
    [{ rule: "selector-contract", job: "test" }],
  );
  const selectorFinding = findings.find(({ rule }) => rule === "selector-contract");
  assert.equal(
    selectorFinding.message,
    "runner routing must use exactly needs.<selector-job>.outputs.runner || 'ubuntu-22.04', or a raw selector output passed to a required no-default repository-local runner input",
  );
});

test("omitted permissions keep a full-SHA untrusted action off the local fleet", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:
  choose:
    permissions: read-all
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - uses: attacker/untrusted-action@0123456789abcdef0123456789abcdef01234567
`,
    },
  });
  const findings = await audit(root);
  assert.deepEqual(
    findings.map(({ rule }) => rule),
    ["hosted-exception-required", "privileged-hosted-only"],
  );
  assert.match(findings[0].message, /omitted GITHUB_TOKEN permissions/);
});

test("empty and read-or-none permission mappings are explicit local-safe boundaries", async () => {
  for (const declaration of [
    "permissions: {}",
    "permissions:\n  contents: read\n  packages: none",
  ]) {
    const root = await repository({
      workflows: {
        "ci.yml": `${declaration}
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
      },
    });
    assert.deepEqual(await audit(root), [], declaration);
  }
});

test("omitted local permissions require the precise privileged hosted exception", async () => {
  for (const [reason, expectedRules] of [
    ["hosted-control-plane", ["hosted-exception-category", "privileged-hosted-only"]],
    ["privileged-control-plane", ["privileged-hosted-only"]],
  ]) {
    const root = await repository({
      exceptions: {
        ".github/workflows/ci.yml#test": {
          reason,
          justification: "Unknown repository token defaults must remain on the hosted backend.",
        },
      },
      workflows: {
        "ci.yml": `jobs:
  choose:
    permissions: read-all
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      expectedRules,
      reason,
    );
  }
});

test("selector recovery accepts cancellation-safe conditions with a nested disjunction", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() && (github.ref == 'refs/heads/main' || github.ref == 'refs/heads/develop') }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("selector recovery rejects noncanonical or variable-controlled hosted fallbacks", async () => {
  const targets = [
    `\${{ needs.choose.outputs.runner }}`,
    `\${{ needs.choose.outputs.runner || vars.CI_HOSTED_RUNNER }}`,
    `\${{ needs.choose.outputs.runner || vars.CI_HOSTED_RUNNER || 'ubuntu-24.04' }}`,
    `\${{ needs.choose.outputs.runner || 'windows-2025' }}`,
    `\${{ needs.choose.outputs.runner || "ubuntu-24.04" }}`,
    `\${{ needs.choose.outputs.runner || format('{0}', 'ubuntu-24.04') }}`,
  ];
  for (const target of targets) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: ${target}
    steps: []
`,
      },
    });
    const finding = (await audit(root)).find(({ rule }) => rule === "selector-contract");
    assert.ok(finding, target);
    assert.match(finding.message, /exactly needs\.<selector-job>\.outputs\.runner/);
  }
});

test("selector recovery rejects conditions that can start work after cancellation", async () => {
  const conditions = [
    undefined,
    `always()`,
    `\${{ always() }}`,
    `\${{ !cancelled() || github.ref == 'refs/heads/main' }}`,
    `\${{ github.ref == 'refs/heads/main' && !cancelled() }}`,
    `\${{ !cancelled() && github.ref == 'refs/heads/main' || github.actor == 'octocat' }}`,
  ];
  for (const condition of conditions) {
    const conditionLine = condition === undefined ? "" : `    if: ${condition}\n`;
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
${conditionLine}    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
      },
    });
    const finding = (await audit(root)).find(({ rule }) => rule === "selector-contract");
    assert.ok(finding, String(condition));
    assert.match(finding.message, /cancel|condition/i);
  }
});

test("selector recovery validates the exact selector dependency and job identity", async () => {
  for (const [needs, selectorId, message] of [
    ["[]", "choose", /must declare choose in needs/],
    ["missing", "missing", /missing is not a workflow job/],
  ]) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: ${needs}
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.${selectorId}.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
      },
    });
    const finding = (await audit(root)).find(({ rule }) => rule === "selector-contract");
    assert.ok(finding, selectorId);
    assert.match(finding.message, message);
  }
});

test("read-only permissions and the selector's exact observer secret remain locally routable", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    permissions:
      contents: read
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("job permissions replace inherited workflow permissions", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: write-all
jobs:
  choose:
    permissions: read-all
${SELECTOR}  test:
    needs: choose
    permissions:
      contents: read
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("workflow permissions are inherited when a workload has no job override", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions:
  contents: write
jobs:
  choose:
    permissions: read-all
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required", "privileged-hosted-only"],
  );
});

test("write-all and every write-capable GITHUB_TOKEN scope require privileged hosted execution", async () => {
  const writableScopes = [
    "actions",
    "artifact-metadata",
    "attestations",
    "checks",
    "code-quality",
    "contents",
    "deployments",
    "discussions",
    "id-token",
    "issues",
    "packages",
    "pages",
    "pull-requests",
    "security-events",
    "statuses",
  ];
  for (const permissions of ["write-all", ...writableScopes.map((scope) => `${scope}: write`)]) {
    const declaration =
      permissions === "write-all"
        ? "    permissions: write-all"
        : `    permissions:\n      ${permissions}`;
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
${declaration}
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      ["hosted-exception-required", "privileged-hosted-only"],
      `permissions declaration must remain hosted: ${permissions}`,
    );
  }
});

test("deployment environments cannot run on the local fleet", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  deploy:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    environment: production
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required", "privileged-hosted-only"],
  );
});

test("explicit secret credentials cannot run on the local fleet", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: ./test.sh
        env:
          TOKEN: \${{ secrets.CROSS_REPOSITORY_TOKEN }}
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required", "privileged-hosted-only"],
  );
});

test("workflow-level secret environment values are inherited by local workloads", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
env:
  TOKEN: \${{ secrets['CROSS_REPOSITORY_TOKEN'] }}
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required", "privileged-hosted-only"],
  );
});

test("credential-minting actions cannot run on the local fleet", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  mint:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - uses: actions/create-github-app-token@v2
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-required", "privileged-hosted-only"],
  );
});

test("exact GitHub-provided token expressions are allowed only in read-only step env/with", async () => {
  for (const expression of [
    CANONICAL_OBSERVER_SECRET_EXPRESSION.replace("CI_RUNNER_OBSERVER_PRIVATE_KEY", "GITHUB_TOKEN"),
    `\${{ github.token }}`,
  ]) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions:
  contents: read
  packages: read
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: npm ci
        env:
          NODE_AUTH_TOKEN: ${expression}
      - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567
        with:
          token: ${expression}
`,
      },
    });
    assert.deepEqual(await audit(root), [], `canonical token expression must pass: ${expression}`);
  }
});

test("GitHub token expressions require statically read-only effective permissions", async () => {
  for (const permissions of ["", "    permissions:\n      packages: write\n"]) {
    const root = await repository({
      workflows: {
        "ci.yml": `jobs:
  choose:
    permissions: read-all
${SELECTOR}  test:
    needs: choose
${permissions}    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: npm ci
        env:
          NODE_AUTH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      ["hosted-exception-required", "privileged-hosted-only"],
    );
  }
});

test("GitHub token aliases, case variants, and transformed expressions fail closed", async () => {
  const variants = [
    `\${{ secrets.github_token }}`,
    `\${{ secrets['GITHUB_TOKEN'] }}`,
    `\${{ secrets [ 'PACKAGES_TOKEN' ] }}`,
    `\${{ format('{0}', secrets.GITHUB_TOKEN) }}`,
    `\${{ format('}}', secrets.PACKAGES_TOKEN) }}`,
    `\${{ github['token'] }}`,
    `\${{ github [ "token" ] }}`,
    `\${{ github.Token }}`,
    `\${{ secrets.GITHUB_TOKEN || 'fallback' }}`,
    `\${{ secrets.PACKAGES_TOKEN }}`,
    `prefix \${{ vars.FLAG }} suffix \${{ secrets.PACKAGES_TOKEN }}`,
    `\${{ secrets.PACKAGES_TOKEN`,
  ];
  for (const expression of variants) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: npm ci
        env:
          NODE_AUTH_TOKEN: ${expression}
`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      ["hosted-exception-required", "privileged-hosted-only"],
      `credential variant must remain hosted: ${expression}`,
    );
  }
});

test("whole credential contexts and direct credential properties remain hosted", async () => {
  const variants = [
    `\${{ toJSON(secrets) }}`,
    `\${{ toJSON( secrets ) }}`,
    `\${{ format('{0}', toJSON(secrets)) }}`,
    `\${{ toJSON(github) }}`,
    `\${{ secrets }}`,
    `\${{ format('{0}', github) }}`,
    `\${{ secrets.PACKAGES_TOKEN }}`,
    `\${{ format('{0}', github.token) }}`,
    `\${{ github[format('{0}{1}', 'to', 'ken')] }}`,
    `\${{ github[fromJSON('"token"')] }}`,
    `\${{ github['to' + 'ken'] }}`,
    `\${{ github[*] }}`,
    `\${{ toJSON(github.*) }}`,
    `\${{ github['repository' }}`,
    `\${{ github["repository"] }}`,
    `prefix \${{ vars.FLAG }} suffix \${{ toJSON(secrets) }}`,
    `\${{ toJSON(secrets)`,
  ];
  for (const expression of variants) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: npm test
        env:
          CREDENTIAL_CONTEXT: ${expression}
`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      ["hosted-exception-required", "privileged-hosted-only"],
      `credential context must remain hosted: ${expression}`,
    );
  }
});

test("non-credential expression lookalikes remain eligible for the local fleet", async () => {
  const variants = [
    "secrets.PACKAGES_TOKEN",
    `\${{ mysecrets.PACKAGES_TOKEN }}`,
    `\${{ secretsValue }}`,
    `\${{ githubish }}`,
    `\${{ github.tokens }}`,
    `\${{ github['tokens'] }}`,
    `\${{ github.repository }}`,
    `\${{ github['repository'] }}`,
    `\${{ github['repository-owner'] }}`,
    `\${{ github.secrets }}`,
    `\${{ github.token_type }}`,
    `\${{ github['token_type'] }}`,
    `\${{ vars.CREDENTIAL }}`,
    `\${{ vars.secrets }}`,
    `\${{ vars.github }}`,
    `\${{ toJSON('secrets') }}`,
    `\${{ toJSON('github') }}`,
    `\${{ format('secrets github.token', vars.VALUE) }}`,
    `\${{ format('It''s github.token and secrets', vars.VALUE) }}`,
    `prefix \${{ vars.secrets }} suffix \${{ github.repository }}`,
  ];
  for (const expression of variants) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: npm test
        env:
          BENIGN: ${expression}
`,
      },
    });
    assert.deepEqual(await audit(root), [], `benign lookalike must pass: ${expression}`);
  }
});

test("long repeated expression prefixes without credentials remain eligible", async () => {
  const repeatedPrefix = "${{".repeat(20_000);
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: npm test
        env:
          BENIGN: "${repeatedPrefix} github.tokens }}"
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("implicit job conditions keep credential contexts off the local fleet", async () => {
  const variants = [
    "github.token",
    "github['token']",
    "github[format('{0}{1}', 'to', 'ken')]",
    `github[fromJSON('"token"')]`,
    "github[*]",
    "toJSON(github.*)",
    "github",
    "secrets",
    "format('{0}', toJSON(secrets))",
  ];
  for (const expression of variants) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: ${expression} && !cancelled()
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
      },
    });
    const workloadFindings = (await audit(root)).filter(({ job }) => job === "test");
    assert.ok(
      workloadFindings.some(({ rule }) => rule === "privileged-hosted-only"),
      `implicit job credential must remain hosted: ${expression}`,
    );
  }
});

test("implicit step conditions keep credential contexts off the local fleet", async () => {
  const variants = [
    "github.token",
    "github['token']",
    "github[format('{0}{1}', 'to', 'ken')]",
    `github[fromJSON('"token"')]`,
    "github[*]",
    "toJSON(github.*)",
    "github",
    "secrets",
    "format('{0}', toJSON(secrets))",
  ];
  for (const expression of variants) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - if: ${expression}
        run: npm test
`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      ["hosted-exception-required", "privileged-hosted-only"],
      `implicit step credential must remain hosted: ${expression}`,
    );
  }
});

test("implicit conditions allow static noncredential GitHub fields and quoted text", async () => {
  const conditions = [
    "github.repository == 'owner/repo'",
    "github['repository'] == 'owner/repo'",
    "contains('github.token secrets', github.repository)",
  ];
  for (const condition of conditions) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: ${condition} && !cancelled()
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - if: ${condition}
        run: npm test
`,
      },
    });
    assert.deepEqual(
      (await audit(root)).map(({ rule }) => rule),
      ["selector-contract"],
      `benign implicit condition must add no credential finding: ${condition}`,
    );
  }
});

test("GitHub-provided tokens are rejected outside narrow step env/with values", async () => {
  const workflows = [
    `permissions: read-all
env:
  NODE_AUTH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps: []
`,
    `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    env:
      NODE_AUTH_TOKEN: \${{ github.token }}
    steps: []
`,
    `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
    steps:
      - run: echo \${{ secrets.GITHUB_TOKEN }}
`,
  ];
  for (const workflow of workflows) {
    const root = await repository({ workflows: { "ci.yml": workflow } });
    const workloadFindings = (await audit(root)).filter(({ job }) => job === "test");
    assert.deepEqual(
      workloadFindings.map(({ rule }) => rule),
      ["hosted-exception-required", "privileged-hosted-only"],
    );
  }
});

test("privileged workloads require the privileged-control-plane exception category", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#publish": {
        reason: "hosted-control-plane",
        justification: "This intentionally exercises privilege-category validation.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  publish:
    permissions:
      packages: write
    runs-on: ubuntu-24.04
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-category"],
  );
});

test("privileged hosted workloads pass with the exact exception category", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#publish": {
        reason: "privileged-control-plane",
        justification:
          "Package publication requires a write-scoped token on hosted infrastructure.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  publish:
    permissions:
      packages: write
    runs-on: ubuntu-24.04
    steps: []
`,
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

test("production selector allowlist contains only independently reviewed commits", async () => {
  const selectorShas = [PRODUCTION_SHA, LATEST_SELECTOR_SHA, SELF_HOSTED_ONLY_SELECTOR_SHA];
  assert.deepEqual(
    BASE_POLICY.approvedSelectorReferences,
    selectorShas.map((sha) => `${SELECTOR_PATH}@${sha}`),
  );
  assert.deepEqual(BASE_POLICY.approvedSelectorReferencesByRepositoryOwner, {
    "melodic-software": [
      `${SELECTOR_PATH}@${LOCAL_SELECTOR_SHA}`,
      `${SELECTOR_PATH}@${LIVENESS_SELECTOR_SHA}`,
      `${SELECTOR_PATH}@${SECURITY_HARDENING_SHA}`,
      `${SELECTOR_PATH}@${DEPENDABOT_ROUTING_SHA}`,
    ],
  });
  for (const sha of selectorShas) {
    const root = await repository({
      workflows: {
        "ci.yml": `jobs:\n  choose:\n${SELECTOR.replace(SHA, sha)}`,
      },
    });
    await writeFile(
      path.join(root, "runner-policy-policy.json"),
      `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
    );
    assert.deepEqual(await audit(root), []);
  }
  for (const sha of [
    LOCAL_SELECTOR_SHA,
    LIVENESS_SELECTOR_SHA,
    SECURITY_HARDENING_SHA,
    DEPENDABOT_ROUTING_SHA,
  ]) {
    const root = await repository({
      repositoryOwner: "melodic-software",
      workflows: {
        "ci.yml": `jobs:\n  choose:\n${SELECTOR.replace(SHA, sha)}`,
      },
    });
    await writeFile(
      path.join(root, "runner-policy-policy.json"),
      `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
    );
    assert.deepEqual(await audit(root, { githubRepository: "melodic-software/standards" }), []);
  }
});

test("owner-scoped selector approval requires external repository identity", async () => {
  const workflow = `jobs:\n  choose:\n${SELECTOR.replace(SHA, LOCAL_SELECTOR_SHA)}`;
  const melodicRoot = await repository({
    repositoryOwner: "melodic-software",
    workflows: { "ci.yml": workflow },
  });
  await writeFile(
    path.join(melodicRoot, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  const selfDeclaredFindings = await audit(melodicRoot);
  assert.equal(selfDeclaredFindings.length, 1);
  assert.equal(selfDeclaredFindings[0].rule, "selector-pin");
  assert.match(selfDeclaredFindings[0].message, /owner-scoped.*owner evidence is unavailable/);
  assert.deepEqual(
    await audit(melodicRoot, { githubRepository: "melodic-software/standards" }),
    [],
  );

  const personalRoot = await repository({
    repositoryOwner: "kyle-sexton",
    workflows: { "ci.yml": workflow },
  });
  await writeFile(
    path.join(personalRoot, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  const personalFindings = await audit(personalRoot, {
    githubRepository: "kyle-sexton/standards",
  });
  assert.equal(personalFindings.length, 1);
  assert.equal(personalFindings[0].rule, "selector-pin");
  assert.match(personalFindings[0].message, /not approved for repository owner kyle-sexton/);

  const ownerlessRoot = await repository({ workflows: { "ci.yml": workflow } });
  await writeFile(
    path.join(ownerlessRoot, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(
    await audit(ownerlessRoot, { githubRepository: "melodic-software/standards" }),
    [],
  );
});

test("GITHUB_REPOSITORY owner evidence must match reviewed inventory", async () => {
  const workflow = `jobs:\n  choose:\n${SELECTOR.replace(SHA, LOCAL_SELECTOR_SHA)}`;
  const root = await repository({
    repositoryOwner: "melodic-software",
    workflows: { "ci.yml": workflow },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(await audit(root, { githubRepository: "melodic-software/standards" }), []);
  await assert.rejects(
    () => audit(root, { githubRepository: "kyle-sexton/standards" }),
    /GITHUB_REPOSITORY owner evidence is kyle-sexton.*declares melodic-software/,
  );
});

test("malformed repository ownership evidence fails closed", async () => {
  for (const repositoryOwner of [
    "Melodic-Software",
    "melodic/software",
    " melodic-software",
    "owner-",
    "owner--name",
  ]) {
    const root = await repository({ repositoryOwner });
    await assert.rejects(
      () => audit(root),
      /repository config\.repositoryOwner must match pattern/,
    );
  }
  const root = await repository({ repositoryOwner: "melodic-software" });
  for (const githubRepository of [
    "not-a-repository",
    "owner-/repository",
    "owner--name/repository",
  ]) {
    await assert.rejects(
      () => audit(root, { githubRepository }),
      /GITHUB_REPOSITORY evidence must be an owner\/repository name/,
    );
  }
});

test("global selector approvals remain owner-independent", async () => {
  const workflow = `jobs:\n  choose:\n${SELECTOR.replace(SHA, PRODUCTION_SHA)}`;
  const root = await repository({
    repositoryOwner: "kyle-sexton",
    workflows: { "ci.yml": workflow },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(await audit(root), []);
});

test("policy schema rejects malformed or ambiguous owner-scoped approvals", async () => {
  const invalidPolicies = [
    {
      approvedSelectorReferencesByRepositoryOwner: {
        "Melodic-Software": [SELECTOR_REFERENCE],
      },
    },
    {
      approvedSelectorReferencesByRepositoryOwner: {
        "owner-": [SELECTOR_REFERENCE],
      },
    },
    {
      approvedSelectorReferencesByRepositoryOwner: {
        "owner--name": [SELECTOR_REFERENCE],
      },
    },
    {
      approvedSelectorReferencesByRepositoryOwner: {
        "melodic-software": [],
      },
    },
    {
      approvedSelectorReferencesByRepositoryOwner: {
        "melodic-software": [`${SELECTOR_PATH}@main`],
      },
    },
    {
      approvedSelectorReferences: [SELECTOR_REFERENCE],
      approvedSelectorReferencesByRepositoryOwner: {
        "melodic-software": [SELECTOR_REFERENCE],
      },
    },
  ];
  for (const policyOverrides of invalidPolicies) {
    const root = await repository({ policyOverrides });
    await assert.rejects(() => audit(root), ConfigurationError);
  }
});

test("hosted matrix expression policy remains required, unique, and structurally exact", async () => {
  const omittedRoot = await repository({
    policyOverrides: { hostedMatrixExpressions: undefined },
  });
  await assert.rejects(
    () => audit(omittedRoot),
    (error) =>
      error instanceof ConfigurationError &&
      error.message === "policy must have required property 'hostedMatrixExpressions'",
  );

  for (const hostedMatrixExpressions of [
    [`\${{ matrix.os }}`, `\${{ matrix.os }}`],
    [`\${{ matrix.os || 'ubuntu-24.04' }}`],
  ]) {
    const root = await repository({ policyOverrides: { hostedMatrixExpressions } });
    await assert.rejects(
      () => audit(root),
      (error) =>
        error instanceof ConfigurationError &&
        error.message.startsWith("policy.hostedMatrixExpressions"),
    );
  }
});

test("production contracts pin reviewed Windows and selectable Linux workflows", () => {
  const contracts = BASE_POLICY.approvedReusableWorkflowContracts;
  assert.deepEqual(
    contracts[
      `melodic-software/ci-workflows/.github/workflows/claude-review.yml@${PRODUCTION_SHA}`
    ],
    {
      routing: "hosted-only",
      allowedInputs: ["skip-actors"],
      allowedSecrets: {
        CLAUDE_CODE_OAUTH_TOKEN: `\${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}`,
      },
      fixedRunsOn: ["ubuntu-24.04"],
    },
  );
  assert.deepEqual(
    contracts[
      "melodic-software/ci-workflows/.github/workflows/claude-review.yml@1d3762c2ace413db0f347048307946c46850161c"
    ].allowedInputs,
    [],
  );
  assert.deepEqual(
    contracts[`melodic-software/ci-workflows/.github/workflows/pester.yml@${PRODUCTION_SHA}`],
    {
      routing: "hosted-only",
      allowedInputs: [
        "run",
        "pester-version",
        "working-directory",
        "sparse-checkout",
        "sparse-checkout-cone-mode",
      ],
      allowedSecrets: {},
      fixedRunsOn: ["windows-2025"],
    },
  );
  assert.deepEqual(contracts[PULUMI_DRIFT_REUSABLE_REFERENCE], {
    routing: "hosted-only",
    allowedInputs: [],
    allowedSecrets: {},
    fixedRunsOn: ["ubuntu-24.04"],
  });
  assert.deepEqual(contracts[STANDARDS_SYNC_REUSABLE_REFERENCE], {
    routing: "hosted-only",
    allowedInputs: ["dry-run", "targets"],
    allowedSecrets: {
      "app-client-id": `\${{ secrets.STANDARDS_SYNC_APP_CLIENT_ID }}`,
      "app-private-key": `\${{ secrets.STANDARDS_SYNC_APP_PRIVATE_KEY }}`,
    },
    fixedRunsOn: ["ubuntu-24.04"],
  });
  assert.deepEqual(
    contracts[`melodic-software/ci-workflows/.github/workflows/semantic-pr.yml@${PRODUCTION_SHA}`],
    {
      routing: "runner-input",
      runnerInput: "runner",
      allowedInputs: ["runner"],
      allowedSecrets: {},
    },
  );
  assert.deepEqual(
    contracts[`melodic-software/ci-workflows/.github/workflows/zizmor.yml@${LOCAL_SELECTOR_SHA}`],
    {
      routing: "runner-input",
      runnerInput: "runner",
      allowedInputs: ["runner", "paths"],
      allowedSecrets: {},
    },
  );
  assert.deepEqual(
    contracts[
      `melodic-software/ci-workflows/.github/workflows/osv-scanner.yml@${SECURITY_HARDENING_SHA}`
    ],
    {
      routing: "runner-input",
      runnerInput: "runner",
      allowedInputs: ["runner"],
      allowedSecrets: {},
    },
  );
  assert.deepEqual(
    contracts[
      `melodic-software/ci-workflows/.github/workflows/zizmor.yml@${SECURITY_HARDENING_SHA}`
    ],
    {
      routing: "runner-input",
      runnerInput: "runner",
      allowedInputs: ["runner", "paths"],
      allowedSecrets: {},
    },
  );
  assert.deepEqual(
    contracts[
      `melodic-software/ci-workflows/.github/workflows/semantic-pr.yml@${FAIL_CLOSED_SEMANTIC_PR_SHA}`
    ],
    {
      routing: "runner-input",
      runnerInput: "runner",
      selectorResultInput: "prerequisite-result",
      allowedInputs: ["runner", "prerequisite-result"],
      allowedSecrets: {},
    },
  );
});

test("policy rejects invalid selector-result contract shapes", async () => {
  for (const contract of [
    {
      routing: "runner-input",
      runnerInput: "runner",
      selectorResultInput: "runner",
      allowedInputs: ["runner"],
      allowedSecrets: {},
    },
    {
      routing: "runner-input",
      runnerInput: "runner",
      selectorResultInput: "prerequisite-result",
      allowedInputs: ["runner"],
      allowedSecrets: {},
    },
    {
      routing: "hosted-only",
      selectorResultInput: "prerequisite-result",
      allowedInputs: ["prerequisite-result"],
      allowedSecrets: {},
      fixedRunsOn: ["ubuntu-24.04"],
    },
  ]) {
    const root = await repository({
      policyOverrides: {
        approvedReusableWorkflowContracts: {
          [FAIL_CLOSED_SEMANTIC_PR_REFERENCE]: contract,
        },
      },
    });
    await assert.rejects(() => audit(root), ConfigurationError);
  }
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
      "ci.yml": `permissions: read-all\njobs:\n  choose:\n${SELECTOR}  test:\n    needs: [choose]\n    if: \${{ !cancelled() }}\n    uses: ${REUSABLE_REFERENCE}\n    with:\n      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}\n`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("fail-closed reusable gate reports every selector result", async () => {
  const root = await repository({
    policyOverrides: {
      approvedReusableWorkflowContracts: {
        [FAIL_CLOSED_SEMANTIC_PR_REFERENCE]: {
          routing: "runner-input",
          runnerInput: "runner",
          selectorResultInput: "prerequisite-result",
          allowedInputs: ["runner", "prerequisite-result"],
          allowedSecrets: {},
        },
      },
    },
    workflows: {
      "pr-title.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  pr-title:
    needs: choose
    if: \${{ always() }}
    uses: ${FAIL_CLOSED_SEMANTIC_PR_REFERENCE}
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
      prerequisite-result: \${{ needs.choose.result }}
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("fail-closed reusable gate requires exact always and selector-result mapping", async () => {
  for (const [condition, result] of [
    [`\${{ !cancelled() }}`, `\${{ needs.choose.result }}`],
    [`\${{ always() }}`, `\${{ needs.other.result }}`],
    [`\${{ always() }}`, undefined],
  ]) {
    const resultMapping = result === undefined ? "" : `      prerequisite-result: ${result}\n`;
    const root = await repository({
      policyOverrides: {
        approvedReusableWorkflowContracts: {
          [FAIL_CLOSED_SEMANTIC_PR_REFERENCE]: {
            routing: "runner-input",
            runnerInput: "runner",
            selectorResultInput: "prerequisite-result",
            allowedInputs: ["runner", "prerequisite-result"],
            allowedSecrets: {},
          },
        },
      },
      workflows: {
        "pr-title.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  pr-title:
    needs: choose
    if: ${condition}
    uses: ${FAIL_CLOSED_SEMANTIC_PR_REFERENCE}
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
${resultMapping}`,
      },
    });
    assert.ok((await audit(root)).some(({ rule }) => rule === "selector-contract"));
  }
});

test("fail-closed reusable gate rejects additional prerequisites", async () => {
  const root = await repository({
    policyOverrides: {
      approvedReusableWorkflowContracts: {
        [FAIL_CLOSED_SEMANTIC_PR_REFERENCE]: {
          routing: "runner-input",
          runnerInput: "runner",
          selectorResultInput: "prerequisite-result",
          allowedInputs: ["runner", "prerequisite-result"],
          allowedSecrets: {},
        },
      },
    },
    workflows: {
      "pr-title.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  setup:
    runs-on: ubuntu-24.04
    steps:
      - run: exit 1
  pr-title:
    needs: [choose, setup]
    if: \${{ always() }}
    uses: ${FAIL_CLOSED_SEMANTIC_PR_REFERENCE}
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
      prerequisite-result: \${{ needs.choose.result }}
`,
    },
  });
  const findings = await audit(root);
  assert.ok(
    findings.some(
      ({ rule, message }) =>
        rule === "selector-contract" && /must declare exactly needs: choose/.test(message),
    ),
  );
});

test("repository-local workflows cannot wrap fail-closed selector-result gates", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/semantic-wrapper.yml#wrapped": {
        reason: "hosted-control-plane",
        justification:
          "An exception cannot make a wrapper around a selector-result contract trustworthy.",
      },
    },
    policyOverrides: {
      approvedReusableWorkflowContracts: {
        [FAIL_CLOSED_SEMANTIC_PR_REFERENCE]: {
          routing: "runner-input",
          runnerInput: "runner",
          selectorResultInput: "prerequisite-result",
          allowedInputs: ["runner", "prerequisite-result"],
          allowedSecrets: {},
        },
      },
    },
    workflows: {
      "semantic-wrapper.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
      prerequisite-result:
        type: string
        default: success
jobs:
  wrapped:
    uses: ${FAIL_CLOSED_SEMANTIC_PR_REFERENCE}
    with:
      runner: \${{ inputs.runner }}
      prerequisite-result: \${{ inputs.prerequisite-result }}
`,
      "pr-title.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  pr-title:
    needs: choose
    if: \${{ !cancelled() }}
    uses: ./.github/workflows/semantic-wrapper.yml
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
      prerequisite-result: success
`,
    },
  });
  const findings = await audit(root);
  assert.ok(
    findings.some(
      ({ rule, message }) =>
        rule === "runner-target-contract" &&
        /cannot wrap a selector-result reporting contract/.test(message),
    ),
  );
});

test("co-triggered repository-local workflows cannot wrap fail-closed selector-result gates", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/semantic-wrapper.yml#wrapped": {
        reason: "hosted-control-plane",
        justification:
          "An exception cannot make a co-triggered wrapper around a selector-result contract trustworthy.",
      },
    },
    policyOverrides: {
      approvedReusableWorkflowContracts: {
        [FAIL_CLOSED_SEMANTIC_PR_REFERENCE]: {
          routing: "runner-input",
          runnerInput: "runner",
          selectorResultInput: "prerequisite-result",
          allowedInputs: ["runner", "prerequisite-result"],
          allowedSecrets: {},
        },
      },
    },
    workflows: {
      "semantic-wrapper.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
      prerequisite-result:
        type: string
        default: success
  workflow_dispatch:
jobs:
  wrapped:
    uses: ${FAIL_CLOSED_SEMANTIC_PR_REFERENCE}
    with:
      runner: \${{ inputs.runner }}
      prerequisite-result: \${{ inputs.prerequisite-result }}
`,
      "pr-title.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  pr-title:
    needs: choose
    if: \${{ !cancelled() }}
    uses: ./.github/workflows/semantic-wrapper.yml
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
      prerequisite-result: success
`,
    },
  });
  const findings = await audit(root);
  assert.ok(
    findings.some(
      ({ rule, message }) =>
        rule === "runner-target-contract" &&
        /cannot wrap a selector-result reporting contract/.test(message),
    ),
  );
});

test("reusable workflow callers use the same literal fallback and cancellation contract", async () => {
  for (const [condition, runner] of [
    [`\${{ always() }}`, `\${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}`],
    [
      `\${{ !cancelled() }}`,
      `\${{ needs.choose.outputs.runner || vars.CI_HOSTED_RUNNER || 'ubuntu-24.04' }}`,
    ],
  ]) {
    const root = await repository({
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: ${condition}
    uses: ${REUSABLE_REFERENCE}
    with:
      runner: ${runner}
`,
      },
    });
    assert.ok(
      (await audit(root)).some(({ rule }) => rule === "selector-contract"),
      `${condition} / ${runner}`,
    );
  }
});

test("unreviewed reusable workflow cannot forward an approved selector output", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  attack:
    needs: choose
    if: \${{ !cancelled() }}
    uses: attacker/unreviewed/.github/workflows/arbitrary.yml@${SHA}
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
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

test("hosted-only reusable contract rejects inherited caller secrets", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  title:
    uses: ${HOSTED_REUSABLE_REFERENCE}
    secrets: inherit
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "runner-target-contract");
  assert.match(findings[0].message, /secrets: inherit/);
});

test("runner-input reusable contract rejects inherited caller secrets", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  scan:
    uses: ${REUSABLE_REFERENCE}
    secrets: inherit
    with:
      runner: ubuntu-24.04
`,
    },
  });
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "runner-target-contract");
  assert.match(findings[0].message, /secrets: inherit/);
});

test("reusable contract rejects secret names absent from its reviewed map", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  scan:
    uses: ${REUSABLE_REFERENCE}
    secrets:
      unexpected: \${{ secrets.UNRELATED }}
    with:
      runner: ubuntu-24.04
`,
    },
  });
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "runner-target-contract");
  assert.match(findings[0].message, /unapproved properties: unexpected/);
});

test("hosted-only reusable contract accepts its exact reviewed secret mapping", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  review:
    uses: ${SECRET_REUSABLE_REFERENCE}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(await audit(root), []);
});

test("reviewed Pulumi drift workflow is an exact privileged hosted contract", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#drift": {
        reason: "privileged-control-plane",
        justification: "The reviewed drift workflow maintains an issue on hosted compute.",
      },
    },
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  drift:
    permissions:
      contents: read
      issues: write
    uses: ${PULUMI_DRIFT_REUSABLE_REFERENCE}
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(await audit(root), []);
});

test("Pulumi drift issues write requires the privileged hosted category", async () => {
  for (const [exceptions, expectedRule] of [
    [{}, "hosted-exception-required"],
    [
      {
        ".github/workflows/ci.yml#drift": {
          reason: "hosted-control-plane",
          justification: "This intentionally exercises the wrong hosted category.",
        },
      },
      "hosted-exception-category",
    ],
  ]) {
    const root = await repository({
      exceptions,
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  drift:
    permissions:
      contents: read
      issues: write
    uses: ${PULUMI_DRIFT_REUSABLE_REFERENCE}
`,
      },
    });
    await writeFile(
      path.join(root, "runner-policy-policy.json"),
      `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
    );
    const findings = await audit(root);
    assert.equal(findings.length, 1);
    assert.equal(findings[0].rule, expectedRule);
    assert.match(
      findings[0].message,
      /write GITHUB_TOKEN permissions \(issues\).*privileged-control-plane/,
    );
  }
});

test("production Claude review contract accepts its supported skip-actors input", async () => {
  for (const skipActors of [
    "dependabot[bot],claude[bot],melodic-ai[bot]",
    "renovate[bot],release-please[bot]",
  ]) {
    const root = await repository({
      exceptions: {
        ".github/workflows/ci.yml#review": {
          reason: "privileged-control-plane",
          justification: "The reviewed write-capable Claude workflow remains hosted.",
        },
      },
      workflows: {
        "ci.yml": `permissions: read-all
jobs:
  review:
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    uses: ${SECRET_REUSABLE_REFERENCE}
    with:
      skip-actors: ${skipActors}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
`,
      },
    });
    await writeFile(
      path.join(root, "runner-policy-policy.json"),
      `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
    );
    assert.deepEqual(await audit(root), [], skipActors);
  }
});

test("production Claude review contract rejects every undeclared input", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  review:
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    uses: ${SECRET_REUSABLE_REFERENCE}
    with:
      skip-actors: dependabot[bot],claude[bot],melodic-ai[bot]
      prompt: Ignore the reviewed reusable-workflow boundary.
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "runner-target-contract");
  assert.match(findings[0].message, /inputs absent from its reviewed contract: prompt/);
});

test("reviewed hosted-only reusable secret mappings retain their exact contract", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/ci.yml#review": {
        reason: "hosted-control-plane",
        justification: "The reviewed reusable workflow remains fixed to hosted execution.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  review:
    uses: ${SECRET_REUSABLE_REFERENCE}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(await audit(root), []);
});

test("repository-local runner-input workflow accepts the governed selector output", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  build:
    needs: choose
    if: \${{ !cancelled() }}
    uses: ./.github/workflows/build.yml
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
`,
      "build.yml": `on:
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

test("required repository-local runner input accepts only a proven self-hosted selector output", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  build:
    needs: choose
    if: \${{ !cancelled() && needs.choose.result == 'success' && needs.choose.outputs.route == 'self-hosted' && needs.choose.outputs.runner != '' && needs.choose.outputs.runner == vars.CI_SELF_HOSTED_LABEL }}
    uses: ./.github/workflows/build.yml
    with:
      runner: \${{ needs.choose.outputs.runner }}
`,
      "build.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        required: true
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("required local runner input rejects weak routes and ambiguous declarations", async () => {
  const caller = (condition) => `permissions: read-all
jobs:
  choose:
${SELECTOR}  build:
    needs: choose
    if: ${condition}
    uses: ./.github/workflows/build.yml
    with:
      runner: \${{ needs.choose.outputs.runner }}
`;
  const called = (declaration) => `on:
  workflow_call:
    inputs:
      runner:
        type: string
${declaration}
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    steps: []
`;
  const validCondition = `\${{ !cancelled() && needs.choose.result == 'success' && needs.choose.outputs.route == 'self-hosted' && needs.choose.outputs.runner != '' && needs.choose.outputs.runner == vars.CI_SELF_HOSTED_LABEL }}`;
  for (const [label, condition, declaration] of [
    ["weak condition", `\${{ !cancelled() }}`, "        required: true"],
    [
      "missing nonempty proof",
      `\${{ !cancelled() && needs.choose.result == 'success' && needs.choose.outputs.route == 'self-hosted' && needs.choose.outputs.runner == vars.CI_SELF_HOSTED_LABEL }}`,
      "        required: true",
    ],
    [
      "required input with a default",
      validCondition,
      "        required: true\n        default: ubuntu-24.04",
    ],
    ["non-boolean required value", validCondition, '        required: "true"'],
    ["optional input without its governed default", validCondition, "        required: false"],
  ]) {
    const root = await repository({
      workflows: { "ci.yml": caller(condition), "build.yml": called(declaration) },
    });
    const findings = await audit(root);
    assert.ok(findings.length > 0, `${label} must fail closed`);
    assert.ok(
      findings.some(
        ({ message }) =>
          message.includes("required no-default") ||
          message.includes("required string with no default") ||
          message.includes("required local runner inputs"),
      ),
      `${label} must report the runner-input contract`,
    );
  }
});

test("required repository-local runner input must be supplied by every caller", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:
  build:
    uses: ./.github/workflows/build.yml
`,
      "build.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        required: true
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    permissions: read-all
    steps: []
`,
    },
  });
  assert.ok(
    (await audit(root)).some(({ message }) => message.includes("omits required inputs: runner")),
  );
});

function selectorFailureWorkflow({
  needs = "choose",
  condition = `\${{ !cancelled() && (needs.choose.result != 'success' || !(needs.choose.outputs.route == 'self-hosted' && needs.choose.outputs.runner != '' && needs.choose.outputs.runner == vars.CI_SELF_HOSTED_LABEL)) }}`,
  target = "ci-runner-selection-failed",
  timeout = 1,
  permissions = "{}",
  extra = "",
  run = 'echo "::error::A governed self-hosted route is required"\n          exit 1',
} = {}) {
  return `jobs:
  choose:
${SELECTOR}  reject-route:
    needs: ${needs}
    if: ${condition}
    runs-on: ${target}
    timeout-minutes: ${timeout}
    permissions: ${permissions}
${extra}    steps:
      - name: Reject non-governed route
        run: |
          ${run}
`;
}

test("reserved unroutable sentinel accepts only the exact selector rejection topology", async () => {
  const root = await repository({ workflows: { "ci.yml": selectorFailureWorkflow() } });
  assert.deepEqual(await audit(root), []);
});

test("reserved unroutable sentinel rejects every widened execution surface", async () => {
  for (const [label, overrides] of [
    ["wrong literal", { target: "another-unmatched-label" }],
    ["multiple needs", { needs: "[choose, choose]" }],
    ["weak condition", { condition: `\${{ !cancelled() }}` }],
    [
      "selector-failure skip",
      {
        condition: `\${{ !cancelled() && needs.choose.result == 'success' && !(needs.choose.outputs.route == 'self-hosted' && needs.choose.outputs.runner != '' && needs.choose.outputs.runner == vars.CI_SELF_HOSTED_LABEL) }}`,
      },
    ],
    [
      "noncomplementary condition",
      {
        condition: `\${{ !cancelled() && needs.choose.result == 'success' && needs.choose.outputs.route != 'self-hosted' }}`,
      },
    ],
    ["long timeout", { timeout: 2 }],
    ["read permission", { permissions: "{ contents: read }" }],
    ["environment", { extra: "    env:\n      VALUE: present\n" }],
    ["action call", { extra: "    uses: owner/workflow/.github/workflows/a.yml@main\n" }],
    ["secret mapping", { extra: "    secrets: inherit\n" }],
    [
      "extra command",
      {
        run: 'echo "::error::A governed self-hosted route is required"\n          echo unsafe\n          exit 1',
      },
    ],
    ["nonfailing command", { run: 'echo "::error::A governed self-hosted route is required"' }],
  ]) {
    const root = await repository({
      workflows: { "ci.yml": selectorFailureWorkflow(overrides) },
    });
    const findings = await audit(root);
    assert.ok(findings.length > 0, `${label} must fail closed`);
  }
});

test("sentinel requires an approved selector and private self-hosted enrollment", async () => {
  const unapprovedSelector = await repository({
    policyOverrides: { approvedSelectorReferences: [] },
    workflows: { "ci.yml": selectorFailureWorkflow() },
  });
  assert.ok((await audit(unapprovedSelector)).length > 0);

  const publicRepository = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: { "ci.yml": selectorFailureWorkflow() },
  });
  assert.ok(
    (await audit(publicRepository)).some(({ rule }) => rule === "public-self-hosted-routing"),
  );

  const routingDisabled = await repository({
    visibility: "private",
    selfHostedCi: false,
    workflows: { "ci.yml": selectorFailureWorkflow() },
  });
  assert.ok(
    (await audit(routingDisabled)).some(({ rule }) => rule === "self-hosted-routing-disabled"),
  );
});

test("sentinel cannot enter any hosted or managed runner label set", async () => {
  for (const policyOverrides of [
    {
      approvedHostedRunnerLabels: [
        ...BASE_POLICY.approvedHostedRunnerLabels,
        BASE_POLICY.governedReusableRunnerInput.failureSentinel,
      ],
    },
    {
      forbiddenHostedRunnerLabels: [
        ...BASE_POLICY.forbiddenHostedRunnerLabels,
        BASE_POLICY.governedReusableRunnerInput.failureSentinel,
      ],
    },
    {
      managedLabelPatterns: [...BASE_POLICY.managedLabelPatterns, "^ci-runner-selection-failed$"],
    },
  ]) {
    const root = await repository({
      policyOverrides,
      workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps: []\n" },
    });
    await assert.rejects(() => audit(root), /failureSentinel must remain outside/);
  }
});

test("policy schema fixes the reserved sentinel literal", async () => {
  const root = await repository({
    policyOverrides: {
      governedReusableRunnerInput: {
        ...BASE_POLICY.governedReusableRunnerInput,
        failureSentinel: "another-unmatched-label",
      },
    },
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps: []\n" },
  });
  await assert.rejects(() => audit(root), /governedReusableRunnerInput\.failureSentinel/);
});

test("sentinel is not a general local reusable runner value", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  build:
    needs: choose
    if: \${{ !cancelled() && needs.choose.result == 'success' }}
    uses: ./.github/workflows/build.yml
    with:
      runner: ci-runner-selection-failed
`,
      "build.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        required: true
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    steps: []
`,
    },
  });
  assert.ok((await audit(root)).length > 0);
});

test("repository-local hosted structural and privileged jobs are inspected at their definitions", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/hosted.yml#service": {
        reason: "service-container",
        justification: "The service-container job remains on the hosted backend.",
      },
      ".github/workflows/hosted.yml#publish": {
        reason: "privileged-control-plane",
        justification: "The write-scoped control-plane job remains hosted.",
      },
    },
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  hosted:
    uses: ./.github/workflows/hosted.yml
`,
      "hosted.yml": `on:
  workflow_call:
jobs:
  service:
    runs-on: ubuntu-24.04
    services:
      postgres:
        image: postgres:18
    steps: []
  publish:
    permissions:
      contents: write
    runs-on: ubuntu-24.04
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("local reusable calls may pass write permission only when every local job narrows it", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/mixed.yml#windows": {
        reason: "privileged-control-plane",
        justification: "The fixed Windows job inherits the caller's write-capable token.",
      },
    },
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  shell:
    needs: choose
    if: \${{ !cancelled() }}
    permissions:
      pull-requests: write
    uses: ./.github/workflows/mixed.yml
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
`,
      "mixed.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
jobs:
  linux:
    permissions:
      contents: read
    runs-on: \${{ inputs.runner }}
    steps: []
  windows:
    runs-on: windows-2025
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("local reusable workflow permissions can explicitly narrow a caller write grant", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  build:
    needs: choose
    if: \${{ !cancelled() }}
    permissions:
      pull-requests: write
    uses: ./.github/workflows/build.yml
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
`,
      "build.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
permissions: read-all
jobs:
  test:
    runs-on: \${{ inputs.runner }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("local reusable dynamic jobs reject inherited write when they omit a read-only override", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:
  choose:
    permissions: read-all
${SELECTOR}  build:
    needs: choose
    if: \${{ !cancelled() }}
    permissions:
      pull-requests: write
    uses: ./.github/workflows/build.yml
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
`,
      "build.yml": `on:
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
  const findings = await audit(root);
  assert.ok(findings.some(({ rule }) => rule === "local-reusable-permissions"));
  assert.ok(findings.some(({ file, job }) => file.endsWith("build.yml") && job === "test"));
});

test("local reusable fixed-hosted jobs inheriting write require the privileged category", async () => {
  const root = await repository({
    exceptions: {
      ".github/workflows/mixed.yml#windows": {
        reason: "windows",
        justification: "This deliberately exercises inherited-permission category enforcement.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  call:
    permissions:
      pull-requests: write
    uses: ./.github/workflows/mixed.yml
`,
      "mixed.yml": `on:
  workflow_call:
jobs:
  windows:
    runs-on: windows-2025
    steps: []
`,
    },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["hosted-exception-category"],
  );
});

test("local reusable permission narrowing is preserved through nested calls", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:
  choose:
    permissions: read-all
${SELECTOR}  call:
    needs: choose
    if: \${{ !cancelled() }}
    permissions:
      pull-requests: write
    uses: ./.github/workflows/middle.yml
    with:
      runner: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
`,
      "middle.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
jobs:
  call:
    uses: ./.github/workflows/leaf.yml
    with:
      runner: \${{ inputs.runner }}
`,
      "leaf.yml": `on:
  workflow_call:
    inputs:
      runner:
        type: string
        default: ubuntu-24.04
jobs:
  test:
    permissions:
      contents: read
    runs-on: \${{ inputs.runner }}
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("repository-local reusable path traversal and unknown files fail closed", async () => {
  for (const reference of [
    "./.github/workflows/../outside.yml",
    "./.github/workflows/missing.yml",
  ]) {
    const root = await repository({
      workflows: {
        "ci.yml": `jobs:
  call:
    uses: ${reference}
`,
      },
    });
    const findings = await audit(root);
    assert.ok(findings.some(({ rule }) => rule === "runner-target-contract"));
    assert.ok(findings.some(({ message }) => /traversal|does not exist/.test(message)));
  }
});

test("repository-local reusable calls reject extra inputs and secrets", async () => {
  for (const extra of ["with:\n      unexpected: value", "secrets:\n      unexpected: value"]) {
    const root = await repository({
      workflows: {
        "ci.yml": `jobs:
  call:
    uses: ./.github/workflows/called.yml
    ${extra}
`,
        "called.yml": `on:
  workflow_call:
jobs:
  test:
    runs-on: ubuntu-24.04
    steps: []
`,
      },
      exceptions: {
        ".github/workflows/called.yml#test": {
          reason: "hosted-control-plane",
          justification: "The fixture's called workload remains hosted.",
        },
      },
    });
    const findings = await audit(root);
    assert.ok(findings.some(({ rule }) => rule === "runner-target-contract"));
    assert.ok(findings.some(({ message }) => /undeclared (?:inputs|secrets)/.test(message)));
  }
});

test("repository-local reusable recursion is rejected", async () => {
  const root = await repository({
    workflows: {
      "a.yml": `on:
  workflow_call:
jobs:
  call-b:
    uses: ./.github/workflows/b.yml
`,
      "b.yml": `on:
  workflow_call:
jobs:
  call-a:
    uses: ./.github/workflows/a.yml
`,
    },
  });
  const findings = await audit(root);
  assert.ok(findings.filter(({ message }) => /recursion cycle/.test(message)).length >= 2);
});

test("repository-local reusable workflow symlinks are rejected", async (context) => {
  const root = await repository({
    exceptions: {
      ".github/workflows/real.yml#test": {
        reason: "hosted-control-plane",
        justification: "The real fixture workflow remains hosted.",
      },
    },
    workflows: {
      "ci.yml": `jobs:
  call:
    uses: ./.github/workflows/link.yml
`,
      "real.yml": `on:
  workflow_call:
jobs:
  test:
    runs-on: ubuntu-24.04
    steps: []
`,
    },
  });
  try {
    await symlink("real.yml", path.join(root, ".github", "workflows", "link.yml"), "file");
  } catch (error) {
    if (new Set(["EPERM", "EACCES", "ENOTSUP"]).has(error.code)) {
      context.skip(`symlink creation unavailable: ${error.code}`);
      return;
    }
    throw error;
  }
  const findings = await audit(root);
  assert.ok(findings.some(({ message }) => /symlink|regular workflow file/.test(message)));
});

test("hosted-only reusable contract rejects an alternate secret expression", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  review:
    uses: ${SECRET_REUSABLE_REFERENCE}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets.UNRELATED }}
`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  const findings = await audit(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, "runner-target-contract");
  assert.match(findings[0].message, /must be exactly/);
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

test("empty hosted matrix expression policy permits approved literals", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    policyOverrides: { hostedMatrixExpressions: [] },
    workflows: {
      "ci.yml": `jobs:
  test:
    runs-on: ubuntu-24.04
    steps: []
`,
    },
  });
  assert.deepEqual(await audit(root), []);
});

test("empty hosted matrix expression policy disables matrix routing fail closed", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    policyOverrides: { hostedMatrixExpressions: [] },
    workflows: {
      "ci.yml": `jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-24.04]
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

test("hosted matrix exclude cannot alter the proven runner axis", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": `jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-24.04, windows-2025]
        exclude:
          - os: windows-2025
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
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
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
      "ci.yml": `permissions: read-all
jobs:
  choose:
${SELECTOR}  test:
    needs: choose
    if: \${{ !cancelled() }}
    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}
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

test("hosted-only repository rejects exception inventory", async () => {
  const root = await repository({
    visibility: "private",
    selfHostedCi: false,
    exceptions: {
      ".github/workflows/ci.yml#test": {
        reason: "hosted-control-plane",
        justification: "This fixed hosted job does not route to the local fleet.",
      },
    },
    workflows: { "ci.yml": "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps: []\n" },
  });
  assert.deepEqual(
    (await audit(root)).map(({ rule }) => rule),
    ["exception-inventory-drift"],
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
      "ci.yml": `jobs:\n  choose:\n    uses: melodic-software/ci-workflows/.github/workflows/select-runner.yml@main\n  test:\n    needs: choose\n    if: \${{ !cancelled() }}\n    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}\n    steps: []\n`,
    },
  });
  const rules = (await audit(root)).map(({ rule }) => rule);
  assert.deepEqual(rules, ["selector-pin", "selector-contract"]);
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

const pinnedStepWorkflow = (comment) =>
  "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps:\n" +
  "      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0" +
  ` # ${comment}\n`;

test("a pin comment claiming a different commit fails as provenance drift", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: { "ci.yml": pinnedStepWorkflow("99ac2f8 2026-07-11") },
  });
  const findings = (await audit(root)).filter(({ rule }) => rule === "pin-provenance-drift");
  assert.equal(findings.length, 1);
  assert.match(findings[0].message, /claims commit 99ac2f8/u);
});

test("a pin comment matching the pinned commit prefix passes", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: { "ci.yml": pinnedStepWorkflow("9c091bb 2026-07-11") },
  });
  assert.deepEqual(
    (await audit(root)).filter(({ rule }) => rule === "pin-provenance-drift"),
    [],
  );
});

test("version, prose, hex-word, and date comments are not SHA claims", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "a.yml": pinnedStepWorkflow("v7.0.0"),
      "b.yml": pinnedStepWorkflow("reviewed canary contract"),
      "c.yml": pinnedStepWorkflow("acceded to on 2026-07-11"),
      "d.yml": pinnedStepWorkflow("20260711"),
    },
  });
  assert.deepEqual(
    (await audit(root)).filter(({ rule }) => rule === "pin-provenance-drift"),
    [],
  );
});

test("a full-length mismatched SHA in the comment fails as provenance drift", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": pinnedStepWorkflow("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    },
  });
  assert.equal((await audit(root)).filter(({ rule }) => rule === "pin-provenance-drift").length, 1);
});

test("a drifted quoted pin is still audited", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml":
        "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps:\n" +
        "      - uses: 'actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0'" +
        " # 99ac2f8 2026-07-11\n",
    },
  });
  assert.equal((await audit(root)).filter(({ rule }) => rule === "pin-provenance-drift").length, 1);
});

test("an example uses line inside a run block scalar is not audited", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml":
        "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps:\n" +
        "      - run: |\n" +
        "          cat <<'DOC'\n" +
        "          uses: actions/checkout@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # 99ac2f8 2026-07-11\n" +
        "          DOC\n",
    },
  });
  assert.deepEqual(
    (await audit(root)).filter(({ rule }) => rule === "pin-provenance-drift"),
    [],
  );
});

test("a block-scalar example cannot borrow the SHA of a real parsed pin", async () => {
  const root = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml":
        "jobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps:\n" +
        "      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0" +
        " # 9c091bb 2026-07-11\n" +
        "      - run: |\n" +
        "          uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0" +
        " # 99ac2f8 2026-07-11\n",
    },
  });
  assert.deepEqual(
    (await audit(root)).filter(({ rule }) => rule === "pin-provenance-drift"),
    [],
  );
});

test("uppercase pins and provenance claims are audited case-insensitively", async () => {
  const matching = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": pinnedStepWorkflow("9C091BB 2026-07-11").replace(
        "9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0",
        "9C091BB21B7C1C1D1991BB908D89E4E9DDDFE3E0",
      ),
    },
  });
  assert.deepEqual(
    (await audit(matching)).filter(({ rule }) => rule === "pin-provenance-drift"),
    [],
  );

  const mismatched = await repository({
    visibility: "public",
    selfHostedCi: false,
    workflows: {
      "ci.yml": pinnedStepWorkflow("99AC2F8 2026-07-11").replace(
        "9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0",
        "9C091BB21B7C1C1D1991BB908D89E4E9DDDFE3E0",
      ),
    },
  });
  assert.equal(
    (await audit(mismatched)).filter(({ rule }) => rule === "pin-provenance-drift").length,
    1,
  );
});
