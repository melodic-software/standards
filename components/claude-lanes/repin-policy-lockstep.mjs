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
const POLICY_REL = "components/runner-policy/policy.json";
const POLICY_PATH = path.join(ROOT, POLICY_REL);

/**
 * Each entry is the caller files that pin one upstream reusable. The
 * reusable's path is read from each pin, never named here: repin-callers.sh
 * apply moves a pin to its renamed path (rename-map.json) when the release
 * carries only the new one. Old SHAs are read per caller file — do not assume
 * a single-SHA world. `kind` is lane or reusable. Both copy forward
 * approvedReusableWorkflowContracts. Any other kind throws and does not add a
 * property.
 *
 * The hosted lane callers (components/claude-lanes-hosted/) are deliberately
 * absent: runner-policy.test.mjs holds them to the fleet callers' pin, so the
 * fleet entries already supply their old SHA, and leaving them out keeps
 * repin-callers.sh, with its ahead-of-release fence, their only rewriter.
 */
const REPIN_TARGETS = [
  {
    callerFiles: [
      "components/claude-lanes/claude-review.yml",
      ".github/workflows/claude-review.yml",
    ],
    kind: "lane",
  },
  {
    callerFiles: ["components/claude-lanes/claude-security-review.yml"],
    kind: "lane",
  },
  {
    callerFiles: [".github/workflows/sync.yml"],
    kind: "reusable",
  },
];

const PIN_RE = /uses:\s+(melodic-software\/ci-workflows\/[^@\s]+)@([0-9a-fA-F]{40})/u;

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

/**
 * Pairs each pin in a caller's committed text with the same line after
 * repin-callers.sh apply rewrote it in place. The rewritten line names the
 * path the new SHA's contract is keyed under, renamed or not.
 */
export function pairCallerPins(headText, worktreeText) {
  const after = worktreeText.split("\n");
  const pairs = [];
  headText.split("\n").forEach((line, index) => {
    const before = line.match(PIN_RE);
    if (!before) return;
    const rewritten = after[index]?.match(PIN_RE);
    if (!rewritten) {
      throw new Error(`line ${index + 1} no longer carries a ci-workflows pin after apply`);
    }
    pairs.push({
      oldWorkflowPath: before[1],
      oldSha: before[2].toLowerCase(),
      newWorkflowPath: rewritten[1],
    });
  });
  return pairs;
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

async function readCallerPins(callerFiles) {
  const found = [];
  for (const rel of callerFiles) {
    // apply rewrites the worktree first. Read the committed pin so each
    // path keeps its own old SHA instead of collapsing to the new one.
    const text = readHeadFile(rel);
    if (text === undefined) continue;
    found.push(...pairCallerPins(text, await readFile(path.join(ROOT, rel), "utf8")));
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

export function renamedPathReason(pin) {
  return (
    `${pin.oldWorkflowPath} is renamed to ${pin.newWorkflowPath} (from ${pin.oldSha.slice(0, 7)}); ` +
    "a renamed path needs a hand-reviewed approvedReusableWorkflowContracts entry"
  );
}

/**
 * Splits re-pinned callers into contract copy-forwards and declines. A pin
 * whose path changed is always declined: a contract for a renamed path is
 * reviewed by hand, never copied, however its surface compares. Every other
 * pin copies forward only when `surfaceOf(pin)` reports it unchanged.
 */
export function planLockstep(pins, newSha, surfaceOf) {
  const reasons = [];
  const copyForwards = [];
  const unique = new Map(
    pins
      .filter((pin) => pin.oldSha !== newSha)
      .map((pin) => [`${pin.oldWorkflowPath}@${pin.oldSha}>${pin.newWorkflowPath}`, pin]),
  );
  for (const pin of unique.values()) {
    if (pin.oldWorkflowPath !== pin.newWorkflowPath) {
      reasons.push(renamedPathReason(pin));
      continue;
    }
    const surface = surfaceOf(pin);
    if (!surface.unchanged) {
      reasons.push(`${pin.newWorkflowPath} ${surface.reason} (from ${pin.oldSha.slice(0, 7)})`);
      continue;
    }
    copyForwards.push({
      kind: pin.kind,
      workflowPath: pin.oldWorkflowPath,
      oldSha: pin.oldSha,
      newSha,
    });
  }
  return { reasons, copyForwards };
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

async function updatePolicyJson(copyForwards, root) {
  const policyPath = path.join(root, POLICY_REL);
  const policy = JSON.parse(await readFile(policyPath, "utf8"));
  const changed = copyForwardContracts(policy, copyForwards);
  if (changed) {
    await writeFile(policyPath, `${JSON.stringify(policy, null, 2)}\n`);
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
  const repoPathOf = (workflowPath) => workflowPath.replace(`${UPSTREAM}/`, "");
  const pins = [];
  for (const target of REPIN_TARGETS) {
    for (const pin of await readCallerPins(target.callerFiles)) {
      pins.push({ ...pin, kind: target.kind });
    }
  }
  const { reasons, copyForwards } = planLockstep(pins, newSha, (pin) => {
    const repoPath = repoPathOf(pin.newWorkflowPath);
    let newSource = newSourceByRepoPath.get(repoPath);
    if (newSource === undefined) {
      newSource = fetchUpstreamFile(repoPath, newSha);
      newSourceByRepoPath.set(repoPath, newSource);
    }
    const oldSource = fetchUpstreamFile(repoPathOf(pin.oldWorkflowPath), pin.oldSha);
    return laneSecuritySurfacesMatch(oldSource, newSource, pin.newWorkflowPath, policy);
  });

  await appendOutput(outputFile, await settleLockstep({ reasons, copyForwards }, newSha, tag));
}

/**
 * Any decline suppresses every write: with a reason present, policy.json and
 * the callers stay as they are and only the human checklist is returned.
 * Returns the GITHUB_OUTPUT pairs.
 */
export async function settleLockstep({ reasons, copyForwards }, newSha, tag, root = ROOT) {
  if (reasons.length > 0) {
    const unchangedPaths = [...new Set(copyForwards.map((item) => item.workflowPath))];
    emitNotice(`::warning::${reasons.join("; ")} — policy lockstep deferred to a human.`);
    return [
      ["lockstep", "manual"],
      ["policy-note", manualPolicyNote(reasons.join("; "), tag, unchangedPaths)],
    ];
  }

  const policyChanged = await updatePolicyJson(copyForwards, root);
  const callerChanged = await rewriteCallerFiles(newSha, tag, root);
  emitNotice(`Policy lockstep applied (policy=${policyChanged}, caller=${callerChanged}).`);
  return [
    ["lockstep", "applied"],
    ["policy-note", appliedPolicyNote(tag)],
  ];
}

if (import.meta.url === pathToFileURL(path.resolve(process.argv[1] ?? "")).href) {
  main().catch((error) => {
    emitError(`::error::${error.message}`);
    process.exit(1);
  });
}
