#!/usr/bin/env node
/**
 * Runner-policy lockstep for claude-lanes re-pins. When every pinned
 * reusable workflow's security surface is unchanged between the old and new
 * ci-workflows SHAs, copy-forward its approvedReusableWorkflowContracts
 * entry and refresh the repo-local caller pin. Otherwise write nothing and
 * emit the human checklist. schemaVersion 4 has no selector key; this
 * script does not read or write one.
 *
 * Invoked from .github/workflows/claude-lanes-repin.yml after repin-callers.sh
 * apply. Reports through GITHUB_OUTPUT (lockstep, policy-note).
 */
import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import {
  ConfigurationError,
  parseUniqueJson,
  reusableWorkflowSecuritySurfacesMatch,
  validatePolicy,
} from "../runner-policy/runner-policy.mjs";
import { parseLockstepArgs } from "./repin-lockstep-args.mjs";

const ROOT = path.resolve(import.meta.dirname, "../..");
const UPSTREAM = "melodic-software/ci-workflows";
const POLICY_PATH = path.join(ROOT, "components/runner-policy/policy.json");

/**
 * Each entry is one upstream reusable plus the caller files that pin it.
 * Old SHAs are read per caller file — do not assume a single-SHA world.
 * `kind` is lane or reusable. Both copy forward approvedReusableWorkflowContracts.
 * Any other kind throws and does not add a property.
 */
const REPIN_TARGETS = [
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
];

const PIN_RE = /uses:\s+melodic-software\/ci-workflows\/[^@\s]+@([0-9a-fA-F]{40})/u;

function emitError(message) {
  process.stderr.write(`${message}\n`);
}

function emitNotice(message) {
  process.stdout.write(`${message}\n`);
}

function usage() {
  emitError("usage: repin-policy-lockstep.mjs <old-sha[,old-sha...]> <new-sha> <tag>");
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

export function constantNameForTag(tag) {
  const body = tag.replace(/^v/u, "").replaceAll(".", "_").toUpperCase();
  return `REPINE_LANE_SHA_V${body}`;
}

function withheldSurfacesClause(unchangedPaths) {
  if (unchangedPaths.length === 0) return "";
  return (
    " These surfaces were unchanged and were not copy-forwarded, because any decline suppresses every write: " +
    `${unchangedPaths.join(", ")}. ` +
    "Register one `approvedReusableWorkflowContracts` entry for each of those withheld paths too."
  );
}

export function manualPolicyNote(reasons, tag, unchangedPaths = []) {
  const withheld = withheldSurfacesClause(unchangedPaths);
  return (
    "> [!WARNING]\n" +
    `> **Runner-policy lockstep requires a human.** ${reasons}. ` +
    "Before merging, register one `approvedReusableWorkflowContracts` entry for each declined workflow named above, " +
    "add the rollout record in `components/runner-policy/README.md`, and add " +
    `\`${constantNameForTag(tag)}\` plus a verbatim copy-forward assertion in ` +
    "`components/runner-policy/runner-policy.test.mjs` " +
    `(same shape as the v0.25.0 registration, PR #589).${withheld} ` +
    "This pull request is never auto-merged."
  );
}

export function appliedPolicyNote(tag) {
  return (
    "Runner-policy lockstep applied automatically: every pinned reusable workflow's security surface is unchanged, " +
    "so each matching `approvedReusableWorkflowContracts` entry in `components/runner-policy/policy.json` was copy-forwarded and the repo-local caller pins were rewritten. " +
    "**Operator:** before merging, add the rollout record in `components/runner-policy/README.md` and " +
    `\`${constantNameForTag(tag)}\` plus a verbatim copy-forward assertion in ` +
    "`components/runner-policy/runner-policy.test.mjs` " +
    "(same shape as the v0.25.0 registration, PR #589). This script writes neither of those two files."
  );
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

function readCallerPins(workflowPath, callerFiles) {
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

export async function rewriteCallerFiles(newSha, tag, root = ROOT) {
  const uniqueFiles = [...new Set(REPIN_TARGETS.flatMap((target) => target.callerFiles))];
  let anyChanged = false;
  for (const rel of uniqueFiles) {
    const abs = path.join(root, rel);
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
    // split preserved any trailing newline as an empty element, so trim
    // trailing newlines before re-adding exactly one final newline.
    await writeFile(abs, `${next.join("\n").replace(/\n+$/u, "")}\n`);
    anyChanged = true;
  }
  return anyChanged;
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

export function copyForwardContracts(policy, copyForwards) {
  let changed = false;
  for (const item of copyForwards) {
    switch (item.kind) {
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
  return changed;
}

async function updatePolicyJson(copyForwards) {
  const policy = JSON.parse(await readFile(POLICY_PATH, "utf8"));
  const changed = copyForwardContracts(policy, copyForwards);
  if (changed) {
    await writeFile(POLICY_PATH, `${JSON.stringify(policy, null, 2)}\n`);
  }
  return changed;
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

  for (const target of REPIN_TARGETS) {
    const pins = readCallerPins(target.workflowPath, target.callerFiles);
    const pinnedOldShas = [
      ...new Set(pins.map((pin) => pin.oldSha).filter((sha) => sha !== newSha)),
    ];
    if (pinnedOldShas.length === 0) continue;

    const repoPath = target.workflowPath.replace(`${UPSTREAM}/`, "");
    let newSource = newSourceByRepoPath.get(repoPath);
    if (newSource === undefined) {
      newSource = fetchUpstreamFile(repoPath, newSha);
      newSourceByRepoPath.set(repoPath, newSource);
    }

    for (const fromSha of pinnedOldShas) {
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
    const unchangedPaths = [...new Set(copyForwards.map((item) => item.workflowPath))];
    const note = manualPolicyNote(reasons.join("; "), tag, unchangedPaths);
    emitNotice(`::warning::${reasons.join("; ")} — policy lockstep deferred to a human.`);
    await appendOutput(outputFile, [
      ["lockstep", "manual"],
      ["policy-note", note],
    ]);
    return;
  }

  const policyChanged = await updatePolicyJson(copyForwards);
  const callerChanged = await rewriteCallerFiles(newSha, tag);
  const note = appliedPolicyNote(tag);

  emitNotice(`Policy lockstep applied (policy=${policyChanged}, caller=${callerChanged}).`);
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
