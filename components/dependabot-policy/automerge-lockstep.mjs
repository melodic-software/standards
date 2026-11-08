#!/usr/bin/env node

// Lockstep check: the ci-workflows `pr-automerge-dependabot.yml` reusable
// carries its own copy of the `tier: auto` keys of `autoMerge.publishers` as
// the default of its `publisher-allowlist` input. This script fetches the
// reusable at `main`, the ref every caller runs, and fails when that default
// differs from those keys. The pure checks are exported for automerge-lockstep.test.mjs.

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { parse as parseYaml } from "yaml";

export const REUSABLE_PATH = ".github/workflows/pr-automerge-dependabot.yml";
const INPUT = "publisher-allowlist";
const CONTRACT_KEY = `melodic-software/ci-workflows/${REUSABLE_PATH}`;

export class LockstepError extends Error {
  constructor(message) {
    super(message);
    this.name = "LockstepError";
  }
}

export function requireContract(runnerPolicy) {
  if (!Object.hasOwn(runnerPolicy.approvedReusableWorkflowContracts ?? {}, CONTRACT_KEY)) {
    throw new LockstepError(
      `lockstep: expected a runner-policy contract for ${CONTRACT_KEY}, found none`,
    );
  }
}

export function extractPublisherAllowlist(workflowText) {
  let workflow;
  try {
    workflow = parseYaml(workflowText);
  } catch (error) {
    throw new LockstepError(`drift: ${REUSABLE_PATH} is not valid YAML: ${error.message}`);
  }
  const value = workflow?.on?.workflow_call?.inputs?.[INPUT]?.default;
  if (typeof value !== "string") {
    throw new LockstepError(`drift: expected a string ${INPUT} input default in ${REUSABLE_PATH}`);
  }
  try {
    return JSON.parse(value);
  } catch (error) {
    throw new LockstepError(`drift: ${INPUT} default is not valid JSON: ${error.message}`);
  }
}

// Order-sensitive: the constant lists the auto-tier keys in policy.json order, so a reorder is drift.
export function checkLockstep(dependabotPolicy, workflowText) {
  const expected = Object.keys(dependabotPolicy.autoMerge.publishers).filter(
    (publisher) => dependabotPolicy.autoMerge.publishers[publisher].tier === "auto",
  );
  const actual = extractPublisherAllowlist(workflowText);
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new LockstepError(
      `drift: ${REUSABLE_PATH} ${INPUT} default ${JSON.stringify(actual)} != policy.json autoMerge.publishers tier auto ${JSON.stringify(expected)}`,
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
    const dependabotPolicy = await readJson("policy.json");
    requireContract(await readJson("..", "runner-policy", "policy.json"));
    const workflowText = await fetchText(
      `https://api.github.com/repos/melodic-software/ci-workflows/contents/${REUSABLE_PATH}?ref=main`,
    );
    checkLockstep(dependabotPolicy, workflowText);
    // biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
    console.log("dependabot automerge lockstep: allowlist default at main matches policy.json");
  } catch (error) {
    // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
    console.error(error.message);
    process.exit(1);
  }
}
