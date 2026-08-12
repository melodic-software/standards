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
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../..");
const UPSTREAM = "melodic-software/ci-workflows";
const SELECTOR_PATH = `${UPSTREAM}/.github/workflows/select-runner.yml`;
const LANE_PATHS = [
  `${UPSTREAM}/.github/workflows/claude-review.yml`,
  `${UPSTREAM}/.github/workflows/claude-security-review.yml`,
];
const POLICY_PATH = path.join(ROOT, "components/runner-policy/policy.json");
const TEST_PATH = path.join(ROOT, "components/runner-policy/runner-policy.test.mjs");
const LOCAL_CALLER_PATH = path.join(ROOT, ".github/workflows/claude-review.yml");

function usage() {
  console.error(`usage: repin-policy-lockstep.mjs <old-sha> <new-sha> <tag>`);
}

function requireOutputFile() {
  const file = process.env.GITHUB_OUTPUT;
  if (!file) {
    console.error("::error::GITHUB_OUTPUT is not set; nothing can report a result.");
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

function workflowCallSurface(yamlText) {
  const doc = parseYaml(yamlText);
  return JSON.stringify(doc.on?.workflow_call ?? null);
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

async function rewriteLocalCaller(newSha, tag) {
  const text = await readFile(LOCAL_CALLER_PATH, "utf8");
  const lines = text.split("\n");
  let changed = false;
  const next = lines.map((line) => {
    if (!line.includes("melodic-software/ci-workflows/.github/workflows/claude-review.yml@")) {
      return line;
    }
    const updated = rewritePinLine(line, newSha, tag);
    if (updated !== line) changed = true;
    return updated;
  });
  if (!changed) return false;
  await writeFile(LOCAL_CALLER_PATH, `${next.join("\n")}\n`);
  return true;
}

async function updatePolicyJson(oldSha, newSha, selectorUnchanged, laneUnchanged) {
  const policy = JSON.parse(await readFile(POLICY_PATH, "utf8"));
  let changed = false;

  if (selectorUnchanged) {
    const ownerList = policy.approvedSelectorReferencesByRepositoryOwner?.["melodic-software"];
    assert.ok(Array.isArray(ownerList), "melodic-software selector allowlist is missing");
    const selectorRef = `${SELECTOR_PATH}@${newSha}`;
    if (!ownerList.includes(selectorRef)) {
      ownerList.push(selectorRef);
      changed = true;
    }
  }

  if (laneUnchanged) {
    for (const lanePath of LANE_PATHS) {
      const oldKey = `${lanePath}@${oldSha}`;
      const newKey = `${lanePath}@${newSha}`;
      const contract = policy.approvedReusableWorkflowContracts?.[oldKey];
      if (!contract) {
        throw new Error(`policy.json has no contract entry for ${oldKey}`);
      }
      if (!policy.approvedReusableWorkflowContracts[newKey]) {
        policy.approvedReusableWorkflowContracts[newKey] = structuredClone(contract);
        changed = true;
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

  const arrayNeedle = "${SELECTOR_PATH}@${AVAILABILITY_RULING_LANE_SHA}`,";
  const arrayIndex = text.indexOf(arrayNeedle);
  if (arrayIndex === -1) {
    throw new Error("could not locate production selector allowlist array in runner-policy.test.mjs");
  }
  const insertAt = arrayIndex + arrayNeedle.length;
  const insertion = `\n      \`\${SELECTOR_PATH}@\${${constantName}}\`,`;
  text = `${text.slice(0, insertAt)}${insertion}${text.slice(insertAt)}`;

  await writeFile(TEST_PATH, text);
  return true;
}

async function main() {
  const [oldSha, newSha, tag] = process.argv.slice(2);
  if (!oldSha || !newSha || !tag) {
    usage();
    process.exit(2);
  }
  if (!/^[0-9a-f]{40}$/u.test(oldSha) || !/^[0-9a-f]{40}$/u.test(newSha)) {
    console.error("::error::old-sha and new-sha must be 40-character commit SHAs.");
    process.exit(1);
  }
  if (oldSha === newSha) {
    console.log("::notice::Old and new SHAs are identical; policy lockstep is a no-op.");
    await appendOutput(requireOutputFile(), [
      ["lockstep", "noop"],
      ["policy-note", "Policy lockstep skipped: callers already carry the target SHA."],
    ]);
    return;
  }

  const outputFile = requireOutputFile();
  const selectorOld = fetchUpstreamFile(".github/workflows/select-runner.yml", oldSha);
  const selectorNew = fetchUpstreamFile(".github/workflows/select-runner.yml", newSha);
  const selectorUnchanged = selectorOld === selectorNew;

  let laneUnchanged = true;
  for (const lanePath of LANE_PATHS) {
    const repoPath = lanePath.replace(`${UPSTREAM}/`, "");
    const oldSurface = workflowCallSurface(fetchUpstreamFile(repoPath, oldSha));
    const newSurface = workflowCallSurface(fetchUpstreamFile(repoPath, newSha));
    if (oldSurface !== newSurface) laneUnchanged = false;
  }

  if (!selectorUnchanged || !laneUnchanged) {
    const reasons = [];
    if (!selectorUnchanged) reasons.push("`select-runner.yml` changed between revisions");
    if (!laneUnchanged) reasons.push("a lane `workflow_call` surface changed between revisions");
    const note =
      `> [!WARNING]\n` +
      `> **Runner-policy lockstep requires a human.** ${reasons.join("; ")}. ` +
      "Before merging, add the selector allowlist entry, both lane contract entries, " +
      "the README rollout record, and the test constants — see PR #345 for precedent. " +
      "This pull request is never auto-merged.";
    console.log(`::warning::${reasons.join("; ")} — policy lockstep deferred to a human.`);
    await appendOutput(outputFile, [
      ["lockstep", "manual"],
      ["policy-note", note],
    ]);
    return;
  }

  const policyChanged = await updatePolicyJson(oldSha, newSha, selectorUnchanged, laneUnchanged);
  const testChanged = await updateTestMjs(newSha, tag, selectorUnchanged);
  const callerChanged = await rewriteLocalCaller(newSha, tag);

  const note =
    "Runner-policy lockstep applied automatically: selector and both lane contracts are " +
    "byte-identical / unchanged between revisions, so `policy.json`, " +
    "`runner-policy.test.mjs`, and the repo-local caller pin were copy-forwarded. " +
    "**Operator:** add the README rollout record describing what this revision carries " +
    "before merging (see `components/runner-policy/README.md` precedent).";

  console.log(
    `Policy lockstep applied (policy=${policyChanged}, test=${testChanged}, caller=${callerChanged}).`,
  );
  await appendOutput(outputFile, [
    ["lockstep", "applied"],
    ["policy-note", note],
  ]);
}

main().catch((error) => {
  console.error(`::error::${error.message}`);
  process.exit(1);
});
