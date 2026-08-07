import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
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
      default-days: 7
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
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      github-actions:
        patterns:
          - "*"
`;
  const root = await repository({ dependabotYaml: dependabot(entries) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a longer cooldown than the floor passes", async () => {
  const entry = CONFORMANT.replace("default-days: 7", "default-days: 14");
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
  const entry = CONFORMANT.replace("default-days: 7", "default-days: 3");
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-below-minimum"]);
});

test("a match-all cooldown exclude bypasses the soak and is flagged", async () => {
  const entry = CONFORMANT.replace(
    "    cooldown:\n      default-days: 7\n",
    '    cooldown:\n      default-days: 7\n      exclude:\n        - "*"\n',
  );
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-soak-bypassed"]);
});

test("a cooldown include restricts the soak and is flagged", async () => {
  const entry = CONFORMANT.replace(
    "    cooldown:\n      default-days: 7\n",
    '    cooldown:\n      default-days: 7\n      include:\n        - "some-dep"\n',
  );
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:cooldown-soak-bypassed"]);
});

test("a narrow first-party cooldown exclude still passes", async () => {
  const entry = CONFORMANT.replace(
    "    cooldown:\n      default-days: 7\n",
    '    cooldown:\n      default-days: 7\n      exclude:\n        - "melodic-software/*"\n',
  );
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a cooldown waiver also suppresses a bypassed soak", async () => {
  const entry = CONFORMANT.replace(
    "    cooldown:\n      default-days: 7\n",
    '    cooldown:\n      default-days: 7\n      exclude:\n        - "*"\n',
  );
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
      default-days: 7
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
  const entry = `  - package-ecosystem: npm
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      security-only:
        applies-to: security-updates
        patterns:
          - "*"
`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:groups-missing"]);
});

test("a groups block that explicitly applies to version updates passes", async () => {
  const entry = `  - package-ecosystem: npm
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      versions:
        applies-to: version-updates
        patterns:
          - "*"
`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(await auditRepository({ root }), []);
});

test("a version group that excludes every pattern is flagged", async () => {
  const entry = `  - package-ecosystem: npm
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      versions:
        patterns:
          - "*"
        exclude-patterns:
          - "*"
`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:groups-missing"]);
});

test("a match-all ignore rule disables updates and is flagged", async () => {
  const entry = `  - package-ecosystem: npm
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      npm-minor-patch:
        update-types:
          - minor
          - patch
    ignore:
      - dependency-name: "*"
`;
  const root = await repository({ dependabotYaml: dependabot(entry) });
  assert.deepEqual(rules(await auditRepository({ root })), ["npm:/:ignore-disables-updates"]);
});

test("a narrow ignore rule still passes", async () => {
  const entry = `  - package-ecosystem: npm
    directory: /
    open-pull-requests-limit: 5
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      npm-minor-patch:
        update-types:
          - minor
          - patch
    ignore:
      - dependency-name: "melodic-software/ci-workflows/*"
`;
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
      default-days: 7
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
  await assert.rejects(
    auditRepository({ root: badReason }),
    (error) => error instanceof ConfigurationError,
  );
  const badWaive = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": { reason: "single-tool-ecosystem", justification: "x", waives: ["limit"] },
      },
    },
  });
  await assert.rejects(
    auditRepository({ root: badWaive }),
    (error) => error instanceof ConfigurationError,
  );
  const noJustification = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: { "npm:/": { reason: "single-tool-ecosystem", waives: ["groups"] } },
    },
  });
  await assert.rejects(
    auditRepository({ root: noJustification }),
    (error) => error instanceof ConfigurationError,
  );
});

test("an unknown config key fails closed", async () => {
  const root = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: { schemaVersion: 1, exceptions: {}, extra: true },
  });
  await assert.rejects(auditRepository({ root }), (error) => error instanceof ConfigurationError);
});

test("a malformed dependabot.yml fails closed", async () => {
  const root = await repository({ dependabotYaml: "version: 2\nupdates: : :\n" });
  await assert.rejects(auditRepository({ root }), (error) => error instanceof ConfigurationError);
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
  const entry = CONFORMANT.replace(
    "    cooldown:\n      default-days: 7\n",
    "    cooldown:\n      default-days: 7\n      semver-patch-days: 0\n",
  );
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
  await assert.rejects(
    auditRepository({ root: single }),
    (error) => error instanceof ConfigurationError,
  );
  const tracks = await repository({
    dependabotYaml: dependabot(CONFORMANT),
    config: {
      schemaVersion: 1,
      exceptions: {
        "npm:/": { reason: "tracks-upstream-release", justification: "x", waives: ["groups"] },
      },
    },
  });
  await assert.rejects(
    auditRepository({ root: tracks }),
    (error) => error instanceof ConfigurationError,
  );
});

test("duplicate JSON members in the config fail closed", () => {
  assert.throws(
    () => parseUniqueJson('{"schemaVersion":1,"schemaVersion":1}', "config at /tmp/c.json"),
    (error) => error instanceof ConfigurationError && error.message.includes("duplicate"),
  );
});
