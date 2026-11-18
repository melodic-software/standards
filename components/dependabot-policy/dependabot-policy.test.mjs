import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  auditRepository,
  ConfigurationError,
  parseArguments,
  parseUniqueJson,
} from "./dependabot-policy.mjs";

const temporaryRoots = [];

const CONFORMANT = `  - package-ecosystem: npm
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: weekly
    cooldown:
      default-days: 3
    groups:
      npm-minor-patch:
        update-types:
          - minor
          - patch
`;

function dependabot(entries) {
  return `version: 2\nupdates:\n${entries}`;
}

async function repository({ config, dependabotYaml } = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "dependabot-policy-"));
  temporaryRoots.push(root);
  await mkdir(path.join(root, ".github"), { recursive: true });
  if (dependabotYaml !== undefined) {
    await writeFile(path.join(root, ".github", "dependabot.yml"), dependabotYaml);
  }
  if (config !== undefined) {
    await writeFile(
      path.join(root, ".github", "dependabot-policy.json"),
      typeof config === "string" ? config : `${JSON.stringify(config, null, 2)}\n`,
    );
  }
  return root;
}

function rules(findings) {
  return findings.map((item) => `${item.entry ?? item.file}:${item.rule}`).sort();
}

const COOLDOWN = "    cooldown:\n      default-days: 3\n";

// CONFORMANT with extra keys appended to its cooldown block.
function withCooldown(extra) {
  return CONFORMANT.replace(COOLDOWN, `${COOLDOWN}${extra}`);
}

// CONFORMANT with its groups block replaced.
function withGroups(groups) {
  return CONFORMANT.replace(/ {4}groups:\n[\s\S]*$/u, `    groups:\n${groups}`);
}

function rejectsConfiguration(promise, message) {
  return assert.rejects(promise, (error) => error instanceof ConfigurationError, message);
}

test.after(async () => {
  await Promise.all(temporaryRoots.map((root) => rm(root, { force: true, recursive: true })));
});

test("command-line parsing preserves defaults and follows strict Node syntax", () => {
  assert.deepEqual(parseArguments(["--"]), {
    root: process.cwd(),
    configPath: ".github/dependabot-policy.json",
    policyPath: fileURLToPath(new URL("./policy.json", import.meta.url)),
    json: false,
  });
  assert.deepEqual(
    parseArguments(["--json", "--root=repo", "--config=config.json", "--policy=policy.json"]),
    {
      root: "repo",
      configPath: "config.json",
      policyPath: "policy.json",
      json: true,
    },
  );
  assert.equal(parseArguments(["--policy=-policy.json"]).policyPath, "-policy.json");

  for (const [argv, pattern] of [
    [["--unknown"], /Unknown option/u],
    [["--policy", "-policy.json"], /ambiguous/u],
    [["repo"], /Unexpected argument/u],
  ]) {
    assert.throws(
      () => parseArguments(argv),
      (error) => error instanceof ConfigurationError && pattern.test(error.message),
    );
  }
});

test("a fully conformant config passes", async () => {
  const root = await repository({ dependabotYaml: dependabot(CONFORMANT) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("multiple conformant entries including the directories plural form pass", async () => {
  const entries = `${CONFORMANT}  - package-ecosystem: github-actions
    directories:
      - /
      - /.github/actions/*
    open-pull-requests-limit: 5
    schedule:
      interval: daily
    cooldown:
      default-days: 3
    groups:
      github-actions:
        patterns:
          - "*"
`;
  const root = await repository({ dependabotYaml: dependabot(entries) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a longer cooldown than the floor passes", async () => {
  const entry = CONFORMANT.replace("default-days: 3", "default-days: 14");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a missing dependabot.yml is flagged", async () => {
  const root = await repository({});
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/dependabot.yml:dependabot-config-missing",
  ]);
});

test("a non-weekly schedule is flagged", async () => {
  const entry = CONFORMANT.replace("interval: weekly", "interval: daily");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:schedule-not-standard"]);
});

test("a missing cooldown is flagged", async () => {
  const entry = `  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    groups:
      npm-minor-patch:
        update-types:
          - minor
          - patch
`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-below-minimum"]);
});

test("a cooldown below the floor is flagged", async () => {
  const entry = CONFORMANT.replace("default-days: 3", "default-days: 2");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-below-minimum"]);
});

test("a match-all cooldown exclude bypasses the soak and is flagged", async () => {
  const entry = withCooldown('      exclude:\n        - "*"\n');
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-soak-bypassed"]);
});

test("a cooldown include restricts the soak and is flagged", async () => {
  const entry = withCooldown('      include:\n        - "some-dep"\n');
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-soak-bypassed"]);
});

test("a narrow first-party cooldown exclude still passes", async () => {
  const entry = withCooldown('      exclude:\n        - "melodic-software/*"\n');
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a cooldown waiver also suppresses a bypassed soak", async () => {
  const entry = withCooldown('      exclude:\n        - "*"\n');
  const root = await repository({
    dependabotYaml: dependabot(entry),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": {
          reason: "tracks-upstream-release",
          justification: "This root intentionally opts out of the soak.",
          waives: ["cooldown"],
        },
      },
    },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a version 2 config with no updates entries fails closed", async () => {
  const noUpdates = await repository({ dependabotYaml: "version: 2\n" });
  assert.deepEqual(rules(await auditRepository({ root: noUpdates })), [
    ".github/dependabot.yml:updates-missing",
  ]);
  const nonArray = await repository({ dependabotYaml: "version: 2\nupdates:\n  foo: bar\n" });
  assert.deepEqual(rules(await auditRepository({ root: nonArray })), [
    ".github/dependabot.yml:updates-missing",
  ]);
});

test("a missing groups block is flagged", async () => {
  const entry = `  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 3
`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:groups-missing"]);
});

test("an open-pull-requests-limit above the maximum is flagged", async () => {
  const entry = CONFORMANT.replace("open-pull-requests-limit: 5", "open-pull-requests-limit: 10");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:pr-limit-too-high"]);
});

test("a zero open-pull-requests-limit disables updates and is flagged", async () => {
  const entry = CONFORMANT.replace("open-pull-requests-limit: 5", "open-pull-requests-limit: 0");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:pr-limit-disables-updates"]);
});

test("a groups block that only applies to security updates is flagged", async () => {
  const entry = withGroups(`      security-only:
        applies-to: security-updates
        patterns:
          - "*"
`);
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:groups-missing"]);
});

test("a groups block that explicitly applies to version updates passes", async () => {
  const entry = withGroups(`      versions:
        applies-to: version-updates
        patterns:
          - "*"
`);
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a version group that excludes every pattern is flagged", async () => {
  const entry = withGroups(`      versions:
        patterns:
          - "*"
        exclude-patterns:
          - "*"
`);
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:groups-missing"]);
});

test("a match-all ignore rule disables updates and is flagged", async () => {
  const entry = `${CONFORMANT}    ignore:\n      - dependency-name: "*"\n`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:ignore-disables-updates"]);
});

test("a narrow ignore rule still passes", async () => {
  const entry = `${CONFORMANT}    ignore:\n      - dependency-name: "melodic-software/ci-workflows/*"\n`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("an omitted open-pull-requests-limit is accepted (GitHub default is the maximum)", async () => {
  const entry = CONFORMANT.replace("    open-pull-requests-limit: 5\n", "");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("an unsupported version is flagged", async () => {
  const root = await repository({ dependabotYaml: `version: 1\nupdates:\n${CONFORMANT}` });
  assert.deepEqual(rules(await auditRepository({ root })), [
    ".github/dependabot.yml:unsupported-version",
  ]);
});

test("tracks-upstream-release waives schedule and cooldown for a fast-tracked entry", async () => {
  const entry = `  - package-ecosystem: npm
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: daily
    groups:
      npm-minor-patch:
        update-types:
          - minor
          - patch
`;
  const root = await repository({
    dependabotYaml: dependabot(entry),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": {
          reason: "tracks-upstream-release",
          justification: "This root tracks the latest upstream release deliberately.",
          waives: ["schedule", "cooldown"],
        },
      },
    },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("single-tool-ecosystem waives the groups requirement", async () => {
  const entry = `  - package-ecosystem: pip
    directory: /.github
    schedule:
      interval: weekly
    cooldown:
      default-days: 3
`;
  const root = await repository({
    dependabotYaml: dependabot(entry),
    config: {
      schemaVersion: 1,
      exceptions: {
        "pip:/.github": {
          reason: "single-tool-ecosystem",
          justification: "One pinned tool; grouping is a no-op.",
          waives: ["groups"],
        },
      },
    },
  });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("an exception on a non-existent entry is drift", async () => {
  const root = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: {
        "gomod:/": {
          reason: "single-tool-ecosystem",
          justification: "No such entry.",
          waives: ["groups"],
        },
      },
    },
  });
  assert.deepEqual(rules(await auditRepository({ root })), ["gomod:/:exception-inventory-drift"]);
});

test("a waiver for an already-satisfied rule is drift", async () => {
  const root = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": {
          reason: "single-tool-ecosystem",
          justification: "Groups are actually present, so this waiver is unused.",
          waives: ["groups"],
        },
      },
    },
  });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:exception-inventory-drift"]);
});

test("an unknown reason, unknown waiver, or missing justification fails closed", async () => {
  const badReason = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: { "npm:/": { reason: "because", justification: "x", waives: ["groups"] } },
    },
  });
  await rejectsConfiguration(auditRepository({ root: badReason }));
  const badWaive = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": { reason: "single-tool-ecosystem", justification: "x", waives: ["limit"] },
      },
    },
  });
  await rejectsConfiguration(auditRepository({ root: badWaive }));
  const noJustification = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: { "npm:/": { reason: "single-tool-ecosystem", waives: ["groups"] } },
    },
  });
  await rejectsConfiguration(auditRepository({ root: noJustification }));
});

test("an unknown config key fails closed", async () => {
  const root = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: { schemaVersion: 1, exceptions: {}, extra: true },
  });
  await rejectsConfiguration(auditRepository({ root }));
});

test("a malformed dependabot.yml fails closed", async () => {
  const root = await repository({ dependabotYaml: "version: 2\nupdates: : :\n" });
  await rejectsConfiguration(auditRepository({ root }));
});

test("a scalar or null update entry is flagged", async () => {
  const scalar = await repository({ dependabotYaml: "version: 2\nupdates:\n  - just-a-string\n" });
  assert.deepEqual(rules(await auditRepository({ root: scalar })), [
    "updates[0]:malformed-update-entry",
  ]);
  const nullEntry = await repository({ dependabotYaml: "version: 2\nupdates:\n  - null\n" });
  assert.deepEqual(rules(await auditRepository({ root: nullEntry })), [
    "updates[0]:malformed-update-entry",
  ]);
});

test("an update entry missing identity keys is flagged", async () => {
  const noEcosystem = await repository({
    dependabotYaml:
      "version: 2\nupdates:\n  - directory: /\n    schedule:\n      interval: weekly\n",
  });
  assert.deepEqual(rules(await auditRepository({ root: noEcosystem })), [
    "updates[0]:incomplete-update-entry",
  ]);
  const noDirectory = await repository({
    dependabotYaml:
      "version: 2\nupdates:\n  - package-ecosystem: npm\n    schedule:\n      interval: weekly\n",
  });
  assert.deepEqual(rules(await auditRepository({ root: noDirectory })), [
    "updates[0]:incomplete-update-entry",
  ]);
});

test("a semver-specific cooldown below the floor is flagged", async () => {
  const entry = withCooldown("      semver-patch-days: 0\n");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-below-minimum"]);
});

test("a waiver outside the reason's scope fails closed", async () => {
  const single = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": { reason: "single-tool-ecosystem", justification: "x", waives: ["cooldown"] },
      },
    },
  });
  await rejectsConfiguration(auditRepository({ root: single }));
  const tracks = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": { reason: "tracks-upstream-release", justification: "x", waives: ["groups"] },
      },
    },
  });
  await rejectsConfiguration(auditRepository({ root: tracks }));
});

test("duplicate JSON members in the config fail closed", () => {
  assert.throws(
    () => parseUniqueJson('{"schemaVersion":1,"schemaVersion":1}', "config at /tmp/c.json"),
    (error) => error instanceof ConfigurationError && error.message.includes("duplicate"),
  );
});

function updateClasses() {
  return {
    cooldownDays: { own: 0, patch: 3, minor: 3, major: 7 },
    fastTrack: {
      reviewed: "2026-11-11",
      basis: "test",
      npm: ["@anthropic-ai/claude-code"],
      "github-actions": ["anthropics/*"],
      own: ["melodic-software/*"],
    },
  };
}

function minimalPolicy() {
  return {
    schemaVersion: 2,
    scheduleInterval: "weekly",
    cooldownMinimumDays: 3,
    ...updateClasses(),
    maxOpenPullRequests: 5,
    requireGroups: true,
    autoMerge: {
      ecosystems: ["github-actions"],
      publishers: { "actions/*": { tier: "auto", reviewed: "2026-10-08", basis: "test" } },
      reviewOnly: [],
      excludeSemverMajor: true,
      requiredCheck: "CI Status",
    },
  };
}

async function auditWithPolicy(policy, entries = CONFORMANT, config) {
  const root = await repository({ dependabotYaml: dependabot(entries), config });
  const policyPath = path.join(root, "policy.json");
  await writeFile(policyPath, JSON.stringify(policy));
  return auditRepository({ root, policyPath });
}

test("the shipped policy records the owner's cooldown classes and fast track", async () => {
  const policy = parseUniqueJson(
    await readFile(new URL("./policy.json", import.meta.url), "utf8"),
    "policy.json",
  );
  assert.equal(policy.schemaVersion, 2);
  assert.deepEqual(policy.cooldownDays, { own: 0, patch: 3, minor: 3, major: 7 });
  assert.equal(policy.cooldownMinimumDays, 3, "the analyzer floor stays the patch class");
  assert.deepEqual(policy.fastTrack.npm, ["@anthropic-ai/claude-code"]);
  assert.deepEqual(policy.fastTrack["github-actions"], ["anthropics/*"]);
  assert.deepEqual(policy.fastTrack.own, ["melodic-software/*"]);
});

test("a v2 policy with the update classes validates and audits clean", async () => {
  assert.deepEqual(await auditWithPolicy(minimalPolicy()), []);
});

const ACTIONS_ENTRY = `  - package-ecosystem: github-actions
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: weekly
    cooldown:
      default-days: 3
    groups:
      github-actions:
        patterns:
          - "*"
`;

function actionsEntry(interval) {
  return ACTIONS_ENTRY.replace("interval: weekly", `interval: ${interval}`);
}

function dailyActionsPolicy() {
  return {
    ...minimalPolicy(),
    scheduleIntervalByEcosystem: {
      "github-actions": { accepted: ["daily", "weekly"], reviewed: "2026-11-16", basis: "test" },
    },
  };
}

test("a github-actions entry may schedule daily or weekly when its ecosystem accepts both", async () => {
  for (const interval of ["daily", "weekly"]) {
    assert.deepEqual(
      await auditWithPolicy(dailyActionsPolicy(), actionsEntry(interval)),
      [],
      `github-actions ${interval} must pass`,
    );
  }
});

test("a github-actions interval outside its accepted list names the accepted values", async () => {
  const findings = await auditWithPolicy(dailyActionsPolicy(), actionsEntry("monthly"));
  assert.deepEqual(rules(findings), ["github-actions:/:schedule-not-standard"]);
  assert.equal(
    findings[0].message,
    'schedule.interval must be one of ["daily","weekly"] for github-actions, found "monthly"',
  );
});

test("an override that accepts one interval rejects the standard interval for that ecosystem", async () => {
  const policy = dailyActionsPolicy();
  policy.scheduleIntervalByEcosystem["github-actions"].accepted = ["daily"];
  assert.deepEqual(await auditWithPolicy(policy, actionsEntry("daily")), []);
  const findings = await auditWithPolicy(policy, actionsEntry("weekly"));
  assert.deepEqual(rules(findings), ["github-actions:/:schedule-not-standard"]);
  assert.equal(findings[0].message, 'schedule.interval must be "daily", found "weekly"');
});

test("an ecosystem with no interval override still accepts only the standard interval", async () => {
  const findings = await auditWithPolicy(
    dailyActionsPolicy(),
    CONFORMANT.replace("interval: weekly", "interval: daily"),
  );
  assert.deepEqual(rules(findings), ["npm:/:schedule-not-standard"]);
  assert.equal(findings[0].message, 'schedule.interval must be "weekly", found "daily"');
});

test("a policy with no interval overrides holds github-actions to the standard interval", async () => {
  assert.deepEqual(await auditWithPolicy(minimalPolicy(), actionsEntry("weekly")), []);
  const findings = await auditWithPolicy(minimalPolicy(), actionsEntry("daily"));
  assert.deepEqual(rules(findings), ["github-actions:/:schedule-not-standard"]);
  assert.equal(findings[0].message, 'schedule.interval must be "weekly", found "daily"');
});

test("a schedule waiver on an entry its accepted intervals already cover is drift", async () => {
  const findings = await auditWithPolicy(dailyActionsPolicy(), actionsEntry("daily"), {
    schemaVersion: 1,
    exceptions: {
      "github-actions:/": {
        reason: "tracks-upstream-release",
        justification: "Daily is already accepted for this ecosystem.",
        waives: ["schedule"],
      },
    },
  });
  assert.deepEqual(rules(findings), ["github-actions:/:exception-inventory-drift"]);
});

test("a malformed interval override fails closed", async () => {
  const cases = [
    ["unknown interval", (override) => (override.accepted = ["hourly"])],
    ["empty accepted list", (override) => (override.accepted = [])],
    ["duplicate interval", (override) => (override.accepted = ["daily", "daily"])],
    ["missing basis", (override) => delete override.basis],
    ["unknown key", (override) => (override.extra = true)],
  ];
  for (const [name, mutate] of cases) {
    const policy = dailyActionsPolicy();
    mutate(policy.scheduleIntervalByEcosystem["github-actions"]);
    await rejectsConfiguration(auditWithPolicy(policy), `${name} must be rejected`);
  }
});

test("a floor that differs from the patch class fails closed", async () => {
  const policy = minimalPolicy();
  policy.cooldownMinimumDays = 4;
  await assert.rejects(
    auditWithPolicy(policy),
    (error) =>
      error instanceof ConfigurationError &&
      error.message.includes("must equal policy.cooldownDays.patch"),
  );
});

test("a malformed cooldown class or fast-track block fails closed", async () => {
  const cases = [
    ["missing cooldownDays", (policy) => delete policy.cooldownDays],
    ["missing fastTrack", (policy) => delete policy.fastTrack],
    ["negative own days", (policy) => (policy.cooldownDays.own = -1)],
    ["zero major days", (policy) => (policy.cooldownDays.major = 0)],
    ["unknown class", (policy) => (policy.cooldownDays.prerelease = 3)],
    ["npm name with a space", (policy) => (policy.fastTrack.npm = ["bad name"])],
    [
      "action that is not a publisher glob",
      (policy) => (policy.fastTrack["github-actions"] = ["anthropics/claude-code-action"]),
    ],
    ["own that is not a publisher glob", (policy) => (policy.fastTrack.own = ["melodic-software"])],
    ["schema version 1", (policy) => (policy.schemaVersion = 1)],
  ];
  for (const [name, mutate] of cases) {
    const policy = minimalPolicy();
    mutate(policy);
    await rejectsConfiguration(auditWithPolicy(policy), `${name} must be rejected`);
  }
});

test("an auto-merge publisher key that is not a whole publisher fails closed", async () => {
  const review = { tier: "auto", reviewed: "2026-10-08", basis: "test" };
  const policy = minimalPolicy();
  for (const publishers of [
    { "actions/checkout": review },
    { "actions/*": { ...review, tier: "unknown" } },
  ]) {
    policy.autoMerge.publishers = publishers;
    await assert.rejects(
      auditWithPolicy(policy),
      (error) => error instanceof ConfigurationError && error.message.includes("publishers"),
    );
  }
  policy.autoMerge.publishers = { "actions/*": review };
  assert.deepEqual(await auditWithPolicy(policy), []);
});

test("a review-only dependency entry needs its scope and the control it cites", async () => {
  const entry = {
    repository: "melodic-software/standards",
    ecosystem: "npm",
    directory: "/distribution",
    dependency: "yaml",
    reviewed: "2026-10-16",
    basis: "test",
    control: "distribution/THREAT-MODEL.md#npm-supply-chain-production-engine",
  };
  const policy = minimalPolicy();
  policy.autoMerge.reviewOnly = [entry];
  assert.deepEqual(await auditWithPolicy(policy), []);
  const { control: _control, ...withoutControl } = entry;
  for (const reviewOnly of [
    [withoutControl],
    [{ ...entry, directory: "distribution" }],
    undefined,
  ]) {
    policy.autoMerge.reviewOnly = reviewOnly;
    await rejectsConfiguration(auditWithPolicy(policy));
  }
});
