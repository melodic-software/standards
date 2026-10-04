#!/usr/bin/env node

// Lockstep check: the ci-workflows `pr-automerge-dependabot.yml` reusable
// carries its own copy of `autoMerge.publisherAllowlist` as the
// PUBLISHER_ALLOWLIST env constant. This script fetches the reusable at the
// pinned SHA and fails when that constant differs from `policy.json`. Bump
// CI_WORKFLOWS_SHA when the fleet repins the reusable.

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

import { parse as parseYaml } from "yaml";

const CI_WORKFLOWS_SHA = "69e506b7c119517ef1dfc421479232b386b93a52";
const REUSABLE_PATH = ".github/workflows/pr-automerge-dependabot.yml";
const url = `https://api.github.com/repos/melodic-software/ci-workflows/contents/${REUSABLE_PATH}?ref=${CI_WORKFLOWS_SHA}`;

const policy = JSON.parse(await readFile(path.join(import.meta.dirname, "policy.json"), "utf8"));
const expected = policy.autoMerge.publisherAllowlist;

const headers = { Accept: "application/vnd.github.raw+json" };
const token = process.env.LOCKSTEP_GITHUB_TOKEN || process.env.GITHUB_TOKEN;
if (token) {
  headers.Authorization = `Bearer ${token}`;
}
const response = await fetch(url, { headers });
if (!response.ok) {
  // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
  console.error(`fetch-error: ${url}: HTTP ${response.status}`);
  process.exit(1);
}

const workflow = parseYaml(await response.text());
const constants = Object.values(workflow.jobs).flatMap((job) =>
  (job.steps ?? [])
    .map((step) => step.env?.PUBLISHER_ALLOWLIST)
    .filter((value) => value !== undefined),
);
if (constants.length !== 1) {
  // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
  console.error(
    `drift: expected one PUBLISHER_ALLOWLIST in ${REUSABLE_PATH}@${CI_WORKFLOWS_SHA}, found ${constants.length}`,
  );
  process.exit(1);
}

const actual = JSON.parse(constants[0]);
if (JSON.stringify(actual) !== JSON.stringify(expected)) {
  // biome-ignore lint/suspicious/noConsole: CLI drift output is this script's interface
  console.error(
    `drift: ${REUSABLE_PATH}@${CI_WORKFLOWS_SHA} PUBLISHER_ALLOWLIST ${JSON.stringify(actual)} != policy.json autoMerge.publisherAllowlist ${JSON.stringify(expected)}`,
  );
  process.exit(1);
}
// biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
console.log(
  `dependabot automerge lockstep: PUBLISHER_ALLOWLIST at ${CI_WORKFLOWS_SHA.slice(0, 7)} matches policy.json`,
);
