#!/usr/bin/env node
/**
 * Runner-policy lockstep for claude-lanes re-pins. When the upstream selector
 * and lane reusable contracts are unchanged between the old and new ci-workflows
 * SHAs, copy-forward the approved allowlist entries and refresh the repo-local
 * caller pin. Otherwise report that a human must complete the policy half.
 *
 * Invoked from .github/workflows/claude-lanes-repin.yml after repin-callers.sh
 * apply. Reports through GITHUB_OUTPUT (lockstep, policy-note).
 */
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  ConfigurationError,
  parseUniqueJson,
  reusableWorkflowSecuritySurfacesMatch,
  validatePolicy,
} from "../runner-policy/runner-policy.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../..");
const UPSTREAM = "melodic-software/ci-workflows";
const SELECTOR_PATH = `${UPSTREAM}/.github/workflows/select-runner.yml`;
const POLICY_PATH = path.join(ROOT, "components/runner-policy/policy.json");
const TEST_PATH = path.join(ROOT, "components/runner-policy/runner-policy.test.mjs");

/**
 * Each entry is one upstream reusable plus the caller files that pin it.
 * Old SHAs are read per caller file — do not assume a single-SHA world.
 * `kind` selects which policy.json map receives a copy-forward.
 */
const REPIN_TARGETS = [
  {
    workflowPath: `${UPSTREAM}/.github/workflows/select-runner.yml`,
    callerFiles: [
      "components/claude-lanes/claude-review.yml",
      "components/claude-lanes/claude-security-review.yml",
    ],
    kind: "selector",
  },
  {
    workflowPath: `${UPSTREAM}/.github/workflows/claude-review.yml`,
    callerFiles: [
      "components/claude-lanes/claude-review.yml",
      ".github/workflows/claude-review.yml",
    ],
    kind: "lane",
  },
  {
    workflowPath: `${UPSTREAM}/.github/workflows/claude-security-review.yml`,
    callerFiles: ["components/claude-lanes/claude-security-review.yml"],
    kind: "lane",
  },
  {
    workflowPath: `${UPSTREAM}/.github/workflows/standards-sync.yml`,
    callerFiles: [".github/workflows/sync.yml"],
    kind: "reusable",
  },
  {
    workflowPath: `${UPSTREAM}/.github/workflows/standards-sync-stuck-automerge-alert.yml`,
    callerFiles: [".github/workflows/standards-sync-stuck-automerge-alert.yml"],
    kind: "reusable",
  },
];

const PIN_RE = /uses:\s+melodic-software\/ci-workflows\/[^@\s]+@([0-9a-fA-F]{40})/u;

function emitError(message) {
  process.stderr.write(`${message}\n`);
}

function emitNotice(message) {
  process.stdout.write(`${message}\n`);
}

const SHA_RE = /^[0-9a-f]{40}$/u;

function usage() {
  emitError("usage: repin-policy-lockstep.mjs <old-sha[,old-sha...]> <new-sha> <tag>");
}

/**
 * Parse lockstep argv. `old-sha` is the unique-set output from
 * repin-callers.sh apply: one SHA, or several comma-separated when
 * enumerated callers already pin different revisions. Each token must be a
 * 40-character lowercase hex SHA. Lockstep still reads each caller file for
 * copy-forward; this list only gates the CLI and the all-already-new no-op.
 */
export function parseLockstepArgs(argv) {
  const [oldShaCsv, newSha, tag] = argv;
  if (!oldShaCsv || !newSha || !tag) {
    return { error: "usage" };
  }
  const oldShas = oldShaCsv.split(",").map((sha) => sha.trim());
  if (oldShas.length === 0 || oldShas.some((sha) => sha === "" || !SHA_RE.test(sha))) {
    return { error: "sha" };
  }
  if (!SHA_RE.test(newSha)) {
    return { error: "sha" };
  }
  return { oldShas, newSha, tag };
}

function requireOutputFile() {
  const file = process.env.GITHUB_OUTPUT;
  if (!file) {
    emitError("::error::GITHUB_OUTPUT is not set; nothing can report a result.");
    process.exit(2);
  }
  return file;
}

async function appendOutput(file, pairs) {
  let block = "";
  for (const [key, value] of pairs) {
    if (value.includes("\n")) {
      const delim = `NOTE_${Math.random().toString(36).slice(2)}`;
      block += `${key}<<${delim}\n${value}\n${delim}\n`;
    } else {
      block += `${key}=${value}\n`;
    }
  }
  await writeFile(file, block, { flag: "a" });
}

function ghApiJson(route) {
  return JSON.parse(execFileSync("gh", ["api", route], { encoding: "utf8" }));
}

function fetchUpstreamFile(repoPath, ref) {
  const encoded = encodeURIComponent(repoPath);
  const { content } = ghApiJson(`repos/${UPSTREAM}/contents/${encoded}?ref=${ref}`);
  return Buffer.from(content, "base64").toString("utf8");
}

function laneSecuritySurfacesMatch(oldSource, newSource, lanePath, policy) {
  try {
    const result = reusableWorkflowSecuritySurfacesMatch({
      oldSource,
      newSource,
      workflowPath: lanePath,
      policy,
    });
    if (!result.unchanged) {
      return {
        unchanged: false,
        reason: `${lanePath} ${result.diffField} changed between revisions`,
      };
    }
    return { unchanged: true };
  } catch (error) {
    if (error instanceof ConfigurationError) {
      return { unchanged: false, reason: error.message };
    }
    throw error;
  }
}

function constantNameForTag(tag) {
  const body = tag.replace(/^v/u, "").replaceAll(".", "_").toUpperCase();
  return `REPINE_LANE_SHA_V${body}`;
}

function rewritePinLine(line, newSha, tag) {
  return line.replace(
    /(@[0-9a-fA-F]{40})(?:\s+# v[0-9]+\.[0-9]+\.[0-9]+)?/u,
    `@${newSha} # ${tag}`,
  );
}

function pinsInFile(text, workflowPath) {
  const needle = `${workflowPath}@`;
  const shas = [];
  for (const line of text.split("\n")) {
    if (!line.includes(needle)) continue;
    const match = line.match(PIN_RE);
    if (match) shas.push(match[1].toLowerCase());
  }
  return shas;
}

function readHeadFile(rel) {
  try {
    return execFileSync("git", ["show", `HEAD:${rel}`], {
      encoding: "utf8",
      cwd: ROOT,
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return undefined;
  }
}

async function readCallerPins(workflowPath, callerFiles) {
  const found = [];
  for (const rel of callerFiles) {
    // apply rewrites the worktree first. Read the committed pin so each
    // path keeps its own old SHA instead of collapsing to the new one.
    const text = readHeadFile(rel);
    if (text === undefined) continue;
    for (const sha of pinsInFile(text, workflowPath)) {
      found.push({ callerFile: rel, oldSha: sha });
    }
  }
  return found;
}

async function rewriteCallerFiles(newSha, tag) {
  const uniqueFiles = [...new Set(REPIN_TARGETS.flatMap((target) => target.callerFiles))];
  let anyChanged = false;
  for (const rel of uniqueFiles) {
    const abs = path.join(ROOT, rel);
    let text;
    try {
      text = await readFile(abs, "utf8");
    } catch (error) {
      if (error && error.code === "ENOENT") continue;
      throw error;
    }
    const lines = text.split("\n");
    let changed = false;
    const next = lines.map((line) => {
      if (!line.includes("melodic-software/ci-workflows/")) return line;
      const updated = rewritePinLine(line, newSha, tag);
      if (updated !== line) changed = true;
      return updated;
    });
    if (!changed) continue;
    await writeFile(abs, `${next.join("\n")}\n`);
    anyChanged = true;
  }
  return anyChanged;
}

function copySelectorContract(policy, oldSha, newSha) {
  const ownerList = policy.approvedSelectorReferencesByRepositoryOwner?.["melodic-software"];
  assert.ok(Array.isArray(ownerList), "melodic-software selector allowlist is missing");
  const selectorRef = `${SELECTOR_PATH}@${newSha}`;
  let changed = false;
  if (!ownerList.includes(selectorRef)) {
    ownerList.push(selectorRef);
    changed = true;
  }
  const oldSelectorKey = `${SELECTOR_PATH}@${oldSha}`;
  const contract = policy.approvedSelectorInputContracts?.[oldSelectorKey];
  if (!contract) {
    throw new Error(`policy.json has no selector input contract for ${oldSelectorKey}`);
  }
  if (!policy.approvedSelectorInputContracts[selectorRef]) {
    policy.approvedSelectorInputContracts[selectorRef] = structuredClone(contract);
    changed = true;
  }
  return changed;
}

function copyReusableContract(policy, workflowPath, oldSha, newSha) {
  const oldKey = `${workflowPath}@${oldSha}`;
  const newKey = `${workflowPath}@${newSha}`;
  const contract = policy.approvedReusableWorkflowContracts?.[oldKey];
  if (!contract) {
    throw new Error(`policy.json has no contract entry for ${oldKey}`);
  }
  if (policy.approvedReusableWorkflowContracts[newKey]) return false;
  policy.approvedReusableWorkflowContracts[newKey] = structuredClone(contract);
  return true;
}

async function updatePolicyJson(copyForwards) {
  const policy = JSON.parse(await readFile(POLICY_PATH, "utf8"));
  let changed = false;

  for (const item of copyForwards) {
    switch (item.kind) {
      case "selector":
        if (copySelectorContract(policy, item.oldSha, item.newSha)) changed = true;
        break;
      case "lane":
      case "reusable":
        if (copyReusableContract(policy, item.workflowPath, item.oldSha, item.newSha)) {
          changed = true;
        }
        break;
      default: {
        const exhaustive = item.kind;
        throw new Error(`unhandled repin target kind: ${exhaustive}`);
      }
    }
  }

  if (changed) {
    await writeFile(POLICY_PATH, `${JSON.stringify(policy, null, 2)}\n`);
  }
  return changed;
}

async function updateTestMjs(newSha, tag, selectorUnchanged) {
  if (!selectorUnchanged) return false;
  let text = await readFile(TEST_PATH, "utf8");
  if (text.includes(`@${newSha}`)) return false;

  const constantName = constantNameForTag(tag);
  if (text.includes(`const ${constantName} = "${newSha}"`)) return false;

  const constLine = `const ${constantName} = "${newSha}";\n`;
  const anchor = "const AVAILABILITY_RULING_LANE_SHA = ";
  const anchorIndex = text.indexOf(anchor);
  if (anchorIndex === -1) {
    throw new Error("could not locate selector SHA constants in runner-policy.test.mjs");
  }
  const lineEnd = text.indexOf("\n", anchorIndex);
  text = `${text.slice(0, lineEnd + 1)}${constLine}${text.slice(lineEnd + 1)}`;

  const arrayNeedle = "$" + "{SELECTOR_PATH}@" + "${AVAILABILITY_RULING_LANE_SHA}`,";
  const arrayIndex = text.indexOf(arrayNeedle);
  if (arrayIndex === -1) {
    throw new Error(
      "could not locate production selector allowlist array in runner-policy.test.mjs",
    );
  }
  const insertAt = arrayIndex + arrayNeedle.length;
  const insertion = `\n      \`\${SELECTOR_PATH}@\${${constantName}}\`,`;
  text = `${text.slice(0, insertAt)}${insertion}${text.slice(insertAt)}`;

  await writeFile(TEST_PATH, text);
  return true;
}

async function main() {
  const parsed = parseLockstepArgs(process.argv.slice(2));
  if (parsed.error === "usage") {
    usage();
    process.exit(2);
  }
  if (parsed.error === "sha") {
    emitError("::error::old-sha and new-sha must be 40-character commit SHAs.");
    process.exit(1);
  }
  const { oldShas, newSha, tag } = parsed;
  if (oldShas.every((sha) => sha === newSha)) {
    emitNotice("::notice::Old and new SHAs are identical; policy lockstep is a no-op.");
    await appendOutput(requireOutputFile(), [
      ["lockstep", "noop"],
      ["policy-note", "Policy lockstep skipped: callers already carry the target SHA."],
    ]);
    return;
  }

  const outputFile = requireOutputFile();
  const policy = validatePolicy(parseUniqueJson(await readFile(POLICY_PATH, "utf8"), POLICY_PATH));
  const newSourceByRepoPath = new Map();
  const reasons = [];
  const copyForwards = [];
  let selectorUnchanged = true;

  for (const target of REPIN_TARGETS) {
    const pins = await readCallerPins(target.workflowPath, target.callerFiles);
    const oldShas = [...new Set(pins.map((pin) => pin.oldSha).filter((sha) => sha !== newSha))];
    if (oldShas.length === 0) continue;

    const repoPath = target.workflowPath.replace(`${UPSTREAM}/`, "");
    let newSource = newSourceByRepoPath.get(repoPath);
    if (newSource === undefined) {
      newSource = fetchUpstreamFile(repoPath, newSha);
      newSourceByRepoPath.set(repoPath, newSource);
    }

    for (const fromSha of oldShas) {
      if (target.kind === "selector") {
        const oldSource = fetchUpstreamFile(repoPath, fromSha);
        if (oldSource !== newSource) {
          selectorUnchanged = false;
          reasons.push(`\`${repoPath}\` changed between ${fromSha.slice(0, 7)} and the new SHA`);
          continue;
        }
        copyForwards.push({
          kind: "selector",
          workflowPath: target.workflowPath,
          oldSha: fromSha,
          newSha,
        });
        continue;
      }

      const oldSource = fetchUpstreamFile(repoPath, fromSha);
      const surface = laneSecuritySurfacesMatch(oldSource, newSource, target.workflowPath, policy);
      if (!surface.unchanged) {
        reasons.push(`${target.workflowPath} ${surface.reason} (from ${fromSha.slice(0, 7)})`);
        continue;
      }
      copyForwards.push({
        kind: target.kind,
        workflowPath: target.workflowPath,
        oldSha: fromSha,
        newSha,
      });
    }
  }

  if (reasons.length > 0) {
    const note =
      `> [!WARNING]\n` +
      `> **Runner-policy lockstep requires a human.** ${reasons.join("; ")}. ` +
      "Before merging, add the selector allowlist entry, both lane contract entries, " +
      "the README rollout record, and the test constants — see PR #345 for precedent. " +
      "This pull request is never auto-merged.";
    emitNotice(`::warning::${reasons.join("; ")} — policy lockstep deferred to a human.`);
    await appendOutput(outputFile, [
      ["lockstep", "manual"],
      ["policy-note", note],
    ]);
    return;
  }

  const policyChanged = await updatePolicyJson(copyForwards);
  const testChanged = await updateTestMjs(newSha, tag, selectorUnchanged);
  const callerChanged = await rewriteCallerFiles(newSha, tag);

  const note =
    "Runner-policy lockstep applied automatically: selector is byte-identical and both lane " +
    "reusable-workflow security surfaces are unchanged between revisions, so `policy.json`, " +
    "`runner-policy.test.mjs`, and the repo-local caller pin were copy-forwarded. " +
    "**Operator:** add the README rollout record describing what this revision carries " +
    "before merging (see `components/runner-policy/README.md` precedent).";

  emitNotice(
    `Policy lockstep applied (policy=${policyChanged}, test=${testChanged}, caller=${callerChanged}).`,
  );
  await appendOutput(outputFile, [
    ["lockstep", "applied"],
    ["policy-note", note],
  ]);
}

if (import.meta.url === pathToFileURL(path.resolve(process.argv[1] ?? "")).href) {
  main().catch((error) => {
    emitError(`::error::${error.message}`);
    process.exit(1);
  });
}
