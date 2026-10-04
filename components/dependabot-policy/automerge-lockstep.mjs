#!/usr/bin/env node

// Lockstep check: the ci-workflows `pr-automerge-dependabot.yml` reusable
// carries its own copy of `autoMerge.publisherAllowlist` as the
// PUBLISHER_ALLOWLIST env constant. This script fetches the reusable at the
// SHA runner-policy approves for it and fails when that constant differs from
// `policy.json`.

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

import { parse as parseYaml } from "yaml";

const REUSABLE_PATH = ".github/workflows/pr-automerge-dependabot.yml";
const CONTRACT_PREFIX = `melodic-software/ci-workflows/${REUSABLE_PATH}@`;

function fail(message) {
  // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
  console.error(message);
  process.exit(1);
}

const readJson = async (...segments) =>
  JSON.parse(await readFile(path.join(import.meta.dirname, ...segments), "utf8"));

const expected = (await readJson("policy.json")).autoMerge.publisherAllowlist;
const runnerPolicy = await readJson("..", "runner-policy", "policy.json");
const pins = Object.keys(runnerPolicy.approvedReusableWorkflowContracts)
  .filter((key) => key.startsWith(CONTRACT_PREFIX))
  .map((key) => key.slice(CONTRACT_PREFIX.length));
if (pins.length !== 1) {
  fail(
    `lockstep: expected exactly one runner-policy contract for ${REUSABLE_PATH}, found ${pins.length} (${pins.join(", ")}); this check reads its SHA from that key`,
  );
}
const sha = pins[0];
const url = `https://api.github.com/repos/melodic-software/ci-workflows/contents/${REUSABLE_PATH}?ref=${sha}`;

const headers = { Accept: "application/vnd.github.raw+json" };
const token = process.env.LOCKSTEP_GITHUB_TOKEN || process.env.GITHUB_TOKEN;
if (token) {
  headers.Authorization = `Bearer ${token}`;
}

async function fetchText() {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(url, { headers });
      if (response.ok) {
        return await response.text();
      }
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    if (attempt < 3) {
      await new Promise((resolve) => setTimeout(resolve, attempt * 2000));
    }
  }
  fail(`fetch-error: ${url}: ${lastError.message}`);
}

const workflow = parseYaml(await fetchText());
const constants = Object.values(workflow?.jobs ?? {}).flatMap((job) =>
  (job.steps ?? [])
    .map((step) => step.env?.PUBLISHER_ALLOWLIST)
    .filter((value) => value !== undefined),
);
if (constants.length !== 1) {
  fail(
    `drift: expected one PUBLISHER_ALLOWLIST in ${REUSABLE_PATH}@${sha}, found ${constants.length}`,
  );
}

const actual = JSON.parse(constants[0]);
if (JSON.stringify(actual) !== JSON.stringify(expected)) {
  fail(
    `drift: ${REUSABLE_PATH}@${sha} PUBLISHER_ALLOWLIST ${JSON.stringify(actual)} != policy.json autoMerge.publisherAllowlist ${JSON.stringify(expected)}`,
  );
}
// biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
console.log(
  `dependabot automerge lockstep: PUBLISHER_ALLOWLIST at ${sha.slice(0, 7)} matches policy.json`,
);
