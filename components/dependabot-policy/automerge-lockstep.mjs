#!/usr/bin/env node

// Lockstep check: the ci-workflows `pr-automerge-dependabot.yml` reusable
// carries its own copy of `autoMerge.publisherAllowlist` as the
// PUBLISHER_ALLOWLIST env constant. This script fetches the reusable at the
// SHA runner-policy approves for it and fails when that constant differs from
// `policy.json`. The pure checks are exported for automerge-lockstep.test.mjs.

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { parse as parseYaml } from "yaml";

export const REUSABLE_PATH = ".github/workflows/pr-automerge-dependabot.yml";
const CONTRACT_PREFIX = `melodic-software/ci-workflows/${REUSABLE_PATH}@`;

export class LockstepError extends Error {
  constructor(message) {
    super(message);
    this.name = "LockstepError";
  }
}

export function resolveApprovedSha(runnerPolicy) {
  const pins = Object.keys(runnerPolicy.approvedReusableWorkflowContracts ?? {})
    .filter((key) => key.startsWith(CONTRACT_PREFIX))
    .map((key) => key.slice(CONTRACT_PREFIX.length));
  if (pins.length !== 1) {
    throw new LockstepError(
      `lockstep: expected exactly one runner-policy contract for ${REUSABLE_PATH}, found ${pins.length} (${pins.join(", ")}); this check reads its SHA from that key`,
    );
  }
  return pins[0];
}

export function extractPublisherAllowlist(workflowText) {
  let workflow;
  try {
    workflow = parseYaml(workflowText);
  } catch (error) {
    throw new LockstepError(`drift: ${REUSABLE_PATH} is not valid YAML: ${error.message}`);
  }
  const constants = Object.values(workflow?.jobs ?? {}).flatMap((job) =>
    (job?.steps ?? [])
      .map((step) => step?.env?.PUBLISHER_ALLOWLIST)
      .filter((value) => value !== undefined),
  );
  if (constants.length !== 1) {
    throw new LockstepError(
      `drift: expected one PUBLISHER_ALLOWLIST in ${REUSABLE_PATH}, found ${constants.length}`,
    );
  }
  try {
    return JSON.parse(constants[0]);
  } catch (error) {
    throw new LockstepError(`drift: PUBLISHER_ALLOWLIST is not valid JSON: ${error.message}`);
  }
}

// Order-sensitive: the two copies stay textually identical, so a reorder is drift.
export function checkLockstep(dependabotPolicy, workflowText) {
  const expected = dependabotPolicy.autoMerge.publisherAllowlist;
  const actual = extractPublisherAllowlist(workflowText);
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new LockstepError(
      `drift: ${REUSABLE_PATH} PUBLISHER_ALLOWLIST ${JSON.stringify(actual)} != policy.json autoMerge.publisherAllowlist ${JSON.stringify(expected)}`,
    );
  }
}

async function fetchText(url) {
  const headers = { Accept: "application/vnd.github.raw+json" };
  const token = process.env.LOCKSTEP_GITHUB_TOKEN || process.env.GITHUB_TOKEN;
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
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
  throw new LockstepError(`fetch-error: ${url}: ${lastError.message}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const readJson = async (...segments) =>
    JSON.parse(await readFile(path.join(import.meta.dirname, ...segments), "utf8"));
  try {
    const sha = resolveApprovedSha(await readJson("..", "runner-policy", "policy.json"));
    const workflowText = await fetchText(
      `https://api.github.com/repos/melodic-software/ci-workflows/contents/${REUSABLE_PATH}?ref=${sha}`,
    );
    checkLockstep(await readJson("policy.json"), workflowText);
    // biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
    console.log(
      `dependabot automerge lockstep: PUBLISHER_ALLOWLIST at ${sha.slice(0, 7)} matches policy.json`,
    );
  } catch (error) {
    // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
    console.error(error.message);
    process.exit(1);
  }
}
