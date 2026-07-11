import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { auditRepository, ConfigurationError } from "./runner-policy.mjs";

const SHA = "0123456789abcdef0123456789abcdef01234567";
const PRODUCTION_SHA = "9596686335da057de7b575ebf82ca1210768c590";
const SELECTOR_PATH = "melodic-software/ci-workflows/.github/workflows/select-runner.yml";
const SELECTOR_REFERENCE = `${SELECTOR_PATH}@${SHA}`;
const REUSABLE_PATH = "melodic-software/ci-workflows/.github/workflows/osv-scanner.yml";
const REUSABLE_REFERENCE = `${REUSABLE_PATH}@${SHA}`;
const HOSTED_REUSABLE_REFERENCE = `melodic-software/ci-workflows/.github/workflows/link-check.yml@${PRODUCTION_SHA}`;
const SECRET_REUSABLE_REFERENCE = `melodic-software/ci-workflows/.github/workflows/claude-review.yml@${PRODUCTION_SHA}`;
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
            allowedSecrets: {},
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
      "ci.yml": `permissions: read-all\njobs:\n  choose:\n${SELECTOR}  test:\n    needs: choose\n    if: \${{ !cancelled() }}\n    runs-on: \${{ needs.choose.outputs.runner || 'ubuntu-24.04' }}\n    steps: []\n`,
    },
  });
  assert.deepEqual(await audit(root), []);
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
    `\${{ format('{0}', secrets.GITHUB_TOKEN) }}`,
    `\${{ github['token'] }}`,
    `\${{ github.Token }}`,
    `\${{ secrets.GITHUB_TOKEN || 'fallback' }}`,
    `\${{ secrets.PACKAGES_TOKEN }}`,
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

test("production selector allowlist contains only the independently reviewed commit", async () => {
  assert.deepEqual(BASE_POLICY.approvedSelectorReferences, [`${SELECTOR_PATH}@${PRODUCTION_SHA}`]);
  const root = await repository({
    workflows: {
      "ci.yml": `jobs:\n  choose:\n${SELECTOR.replace(SHA, PRODUCTION_SHA)}`,
    },
  });
  await writeFile(
    path.join(root, "runner-policy-policy.json"),
    `${JSON.stringify(BASE_POLICY, null, 2)}\n`,
  );
  assert.deepEqual(await audit(root), []);
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
  assert.deepEqual(
    contracts[`melodic-software/ci-workflows/.github/workflows/semantic-pr.yml@${PRODUCTION_SHA}`],
    {
      routing: "runner-input",
      runnerInput: "runner",
      allowedInputs: ["runner"],
      allowedSecrets: {},
    },
  );
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
