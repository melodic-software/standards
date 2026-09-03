#!/usr/bin/env node

// Lockstep drift check (ADR-0008): `policy.json` is the canonical record of
// the fleet PR-body convention, but four other copies of the contract exist
// and must change in lockstep with it — the ci-workflows `pr-issue-linkage`
// reusable, the source-control plugin's PreToolUse validator, the org
// `.github` PR template, and this repository's distributed
// `.claude/rules/pr-body-contract.md`. Letting any copy drift is exactly the
// failure #393 recorded (and claude-code-plugins#3205 repeated). This check
// also dereferences every gate caller's pinned SHA and validates the section
// list of the reusable AT THAT PIN, because a stale pin enforcing an older
// contract (the codex-plugins v0.9.1 case) is drift no source-copy diff can
// see.
//
// CLI mode fetches live sources over raw.githubusercontent (public repos,
// unauthenticated) and exits non-zero on drift; every network failure is a
// distinct `fetch-error` failure, never a skip. Parsing and comparison logic
// is exported for the hermetic fixture tests in `lockstep-drift.test.mjs`.

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { parseUniqueJson } from "./pr-convention-policy.mjs";

const MODULE_DIRECTORY = import.meta.dirname;
const POLICY_PATH = path.join(MODULE_DIRECTORY, "policy.json");
const RULES_FILE_PATH = path.join(
  MODULE_DIRECTORY,
  "..",
  "..",
  ".claude",
  "rules",
  "pr-body-contract.md",
);

// Contents-API URLs, not raw.githubusercontent: four gate callers are private
// repositories, and the API honors the token `LOCKSTEP_GITHUB_TOKEN` (or
// `GITHUB_TOKEN`) that the CI lane mints from the org GitHub App. Public
// sources still resolve unauthenticated.
const API_BASE = "https://api.github.com/repos/melodic-software";
const contentsUrl = (repo, ref, filePath) => `${API_BASE}/${repo}/contents/${filePath}?ref=${ref}`;
export const COPY_SOURCES = {
  gate: contentsUrl("ci-workflows", "main", ".github/workflows/pr-issue-linkage.yml"),
  hookValidator: contentsUrl(
    "claude-code-plugins",
    "main",
    "plugins/source-control/hooks/pr-linkage-validator.sh",
  ),
  orgTemplate: contentsUrl(".github", "main", ".github/PULL_REQUEST_TEMPLATE.md"),
};

// Every repository that requires the pr-issue-linkage check. ci-workflows
// hosts the reusable and calls it through a self-caller with its own name.
export const GATE_CALLERS = {
  ".github": ".github/workflows/pr-issue-linkage.yml",
  "ci-runner": ".github/workflows/pr-issue-linkage.yml",
  "ci-workflows": ".github/workflows/pr-issue-linkage-self.yml",
  "claude-code-plugins": ".github/workflows/pr-issue-linkage.yml",
  "codex-plugins": ".github/workflows/pr-issue-linkage.yml",
  dotfiles: ".github/workflows/pr-issue-linkage.yml",
  "github-iac": ".github/workflows/pr-issue-linkage.yml",
  medley: ".github/workflows/pr-issue-linkage.yml",
  provisioning: ".github/workflows/pr-issue-linkage.yml",
  standards: ".github/workflows/pr-issue-linkage.yml",
};

export class DriftError extends Error {
  constructor(message) {
    super(message);
    this.name = "DriftError";
  }
}

export class FetchError extends Error {
  constructor(message) {
    super(message);
    this.name = "FetchError";
  }
}

// The reusable declares its contract as a `requiredSections` array of
// `{ name: "...", guidance: "..." }` literals inside an actions/github-script
// step. The array literal is the narrowest stable surface to parse.
export function parseGateSections(workflowText, location) {
  const arrayMatch = workflowText.match(/const requiredSections = \[([\s\S]*?)\n\s*\];/);
  if (!arrayMatch) {
    throw new DriftError(`${location}: no \`const requiredSections = [...]\` block found`);
  }
  const names = [...arrayMatch[1].matchAll(/name:\s*"([^"]+)"/g)].map((m) => m[1]);
  if (names.length === 0) {
    throw new DriftError(`${location}: requiredSections block carries no name: entries`);
  }
  return names;
}

// The hook validator declares `REQUIRED_SECTIONS=(Summary Fix ...)`.
export function parseValidatorSections(shellText, location) {
  const match = shellText.match(/REQUIRED_SECTIONS=\(([^)]*)\)/);
  if (!match) {
    throw new DriftError(`${location}: no REQUIRED_SECTIONS=(...) declaration found`);
  }
  const names = match[1].split(/\s+/).filter(Boolean);
  if (names.length === 0) {
    throw new DriftError(`${location}: REQUIRED_SECTIONS declaration is empty`);
  }
  return names;
}

export function parseMarkdownHeadings(markdownText) {
  return [...markdownText.matchAll(/^## (.+)$/gm)].map((m) => m[1].trim());
}

// The gate's keyword and marker enforcement are executable regex
// declarations, so they are validated FUNCTIONALLY: extract each declared
// pattern and probe it with every policy keyword/marker. A keyword that
// survives only in a comment or error message no longer passes.
export function parseGatePatterns(workflowText, location) {
  // Flags on the DECLARATION are not part of the contract being checked: only the
  // pattern body is extracted, and both probes below are constructed with "i"
  // regardless. Pinning the match to a literal `/i;` therefore asserted an
  // incidental detail, and ci-workflows making CLOSING_KEYWORD global (`/gi;`, so
  // every occurrence on a line can be classified) turned a healthy gate into
  // "declarations not found" — a parse failure wearing a drift error's clothes.
  // Accept any flag set; drift is still caught functionally by probing the body.
  const keyword = workflowText.match(/const CLOSING_KEYWORD =\s*\/(.+)\/[dgimsuvy]*;/);
  const marker = workflowText.match(/const NO_ISSUE_MARKER =\s*\/(.+)\/[dgimsuvy]*;/);
  if (!keyword || !marker) {
    throw new DriftError(
      `${location}: CLOSING_KEYWORD / NO_ISSUE_MARKER regex declarations not found`,
    );
  }
  return { keyword: new RegExp(keyword[1], "i"), marker: new RegExp(marker[1], "i") };
}

// The hook validator's enforcement is a pair of POSIX ERE strings; translate
// the one POSIX class they use and probe them the same way. The probes pad
// with spaces because both EREs guard with [^a-z0-9_] boundary classes.
export function parseValidatorPatterns(shellText, location) {
  const keyword = shellText.match(/KEYWORD_ERE='([^']+)'/);
  const marker = shellText.match(/NO_ISSUE_ERE='([^']+)'/);
  if (!keyword || !marker) {
    throw new DriftError(`${location}: KEYWORD_ERE / NO_ISSUE_ERE declarations not found`);
  }
  const toJs = (ere) => new RegExp(ere.replaceAll("[[:space:]]", "\\s"), "i");
  return { keyword: toJs(keyword[1]), marker: toJs(marker[1]) };
}

function assertPatternsEnforce(patterns, policy, location) {
  const missing = [];
  for (const keyword of policy.body.closingKeywords) {
    if (!patterns.keyword.test(` ${keyword} #12 `)) {
      missing.push(`closing keyword "${keyword}"`);
    }
  }
  for (const marker of policy.body.noIssueMarkers) {
    if (!patterns.marker.test(` ${marker}: none `)) {
      missing.push(`no-issue marker "${marker}"`);
    }
  }
  if (missing.length > 0) {
    throw new DriftError(`${location}: declared pattern rejects ${missing.join(", ")}`);
  }
}

export function parseCallerPin(workflowText, location) {
  const match = workflowText.match(/pr-issue-linkage\.yml@([0-9a-f]{40})/);
  if (!match) {
    throw new DriftError(`${location}: no 40-hex pr-issue-linkage.yml@<sha> pin found`);
  }
  return match[1];
}

function assertExactSections(actual, expected, location) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new DriftError(
      `${location}: section list [${actual.join(", ")}] != policy [${expected.join(", ")}]`,
    );
  }
}

function assertContainsSections(headings, expected, location) {
  const missing = expected.filter((name) => !headings.includes(name));
  if (missing.length > 0) {
    throw new DriftError(
      `${location}: missing policy section heading(s): ${missing.join(", ")} (found: ${headings.join(", ")})`,
    );
  }
}

function assertMentions(text, terms, location) {
  const missing = terms.filter((term) => !text.includes(term));
  if (missing.length > 0) {
    throw new DriftError(`${location}: does not mention: ${missing.join(", ")}`);
  }
}

// One drift verdict per copy; every check runs so a single invocation reports
// the whole divergence set instead of the first hit.
export function checkCopies(policy, texts) {
  const errors = [];
  const sections = policy.body.requiredSections;
  const run = (fn) => {
    try {
      fn();
    } catch (error) {
      if (error instanceof DriftError) {
        errors.push(error.message);
        return;
      }
      throw error;
    }
  };
  run(() =>
    assertExactSections(parseGateSections(texts.gate, "gate reusable"), sections, "gate reusable"),
  );
  run(() =>
    assertExactSections(
      parseValidatorSections(texts.hookValidator, "hook validator"),
      sections,
      "hook validator",
    ),
  );
  run(() =>
    assertContainsSections(parseMarkdownHeadings(texts.orgTemplate), sections, "org PR template"),
  );
  // The rules file names the section headings in prose (backticked, inside
  // bullets), not as its own document headings — a mention check, not a
  // heading parse.
  run(() =>
    assertMentions(
      texts.rulesFile,
      sections.map((name) => `## ${name}`),
      "rules file (sections)",
    ),
  );
  run(() =>
    assertMentions(texts.rulesFile, policy.body.closingKeywords, "rules file (closing keywords)"),
  );
  // The rules file is guidance, not enforcement: it must steer agents to at
  // least one accepted opt-out marker, not enumerate every accepted phrasing.
  run(() => {
    if (!policy.body.noIssueMarkers.some((marker) => texts.rulesFile.includes(marker))) {
      throw new DriftError(
        `rules file (no-issue markers): mentions none of: ${policy.body.noIssueMarkers.join(", ")}`,
      );
    }
  });
  run(() => assertMentions(texts.orgTemplate, ["Closes"], "org PR template (closing keyword)"));
  run(() =>
    assertMentions(
      texts.orgTemplate,
      policy.body.noIssueMarkers,
      "org PR template (no-issue markers)",
    ),
  );
  run(() =>
    assertPatternsEnforce(
      parseGatePatterns(texts.gate, "gate reusable"),
      policy,
      "gate reusable (enforcement patterns)",
    ),
  );
  run(() =>
    assertPatternsEnforce(
      parseValidatorPatterns(texts.hookValidator, "hook validator"),
      policy,
      "hook validator (enforcement patterns)",
    ),
  );
  return errors;
}

// Validates the full contract at the pin — sections AND the executable
// keyword/marker patterns — so a pinned reusable whose section list matches
// current policy but whose keyword or marker enforcement is stale still
// reports drift.
export function checkPinnedReusable(policy, repo, sha, reusableText) {
  const location = `caller ${repo} pin ${sha.slice(0, 7)}`;
  const errors = [];
  const run = (fn) => {
    try {
      fn();
    } catch (error) {
      if (!(error instanceof DriftError)) {
        throw error;
      }
      errors.push(error.message);
    }
  };
  run(() =>
    assertExactSections(
      parseGateSections(reusableText, location),
      policy.body.requiredSections,
      location,
    ),
  );
  run(() => assertPatternsEnforce(parseGatePatterns(reusableText, location), policy, location));
  return errors;
}

async function fetchText(url) {
  const token = process.env.LOCKSTEP_GITHUB_TOKEN || process.env.GITHUB_TOKEN;
  const headers = { Accept: "application/vnd.github.raw+json" };
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
  throw new FetchError(`fetch-error: ${url}: ${lastError.message}`);
}

export async function runLiveCheck() {
  const policy = parseUniqueJson(await readFile(POLICY_PATH, "utf8"), POLICY_PATH);
  const texts = {
    gate: await fetchText(COPY_SOURCES.gate),
    hookValidator: await fetchText(COPY_SOURCES.hookValidator),
    orgTemplate: await fetchText(COPY_SOURCES.orgTemplate),
    rulesFile: await readFile(RULES_FILE_PATH, "utf8"),
  };
  const errors = checkCopies(policy, texts);

  // A caller whose fetch fails is reported and the loop continues, so one
  // unreachable private repository cannot mask drift findings collected from
  // the rest; any fetch-error still fails the run.
  const pinTexts = new Map();
  for (const [repo, callerPath] of Object.entries(GATE_CALLERS)) {
    try {
      const callerText = await fetchText(contentsUrl(repo, "main", callerPath));
      const sha = parseCallerPin(callerText, `caller ${repo}`);
      if (!pinTexts.has(sha)) {
        pinTexts.set(
          sha,
          await fetchText(
            contentsUrl("ci-workflows", sha, ".github/workflows/pr-issue-linkage.yml"),
          ),
        );
      }
      errors.push(...checkPinnedReusable(policy, repo, sha, pinTexts.get(sha)));
    } catch (error) {
      if (!(error instanceof FetchError) && !(error instanceof DriftError)) {
        throw error;
      }
      errors.push(error.message);
    }
  }
  return errors;
}

// This block is the CLI entrypoint of a shebang script whose entire contract is
// what it prints and what it exits with, so stdout/stderr are the interface
// rather than stray debugging. noConsole is suppressed per call rather than
// repo-wide, which would blind the rule everywhere else in this component.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    const errors = await runLiveCheck();
    if (errors.length > 0) {
      for (const message of errors) {
        // biome-ignore lint/suspicious/noConsole: CLI drift output is this script's interface
        console.error(`drift: ${message}`);
      }
      process.exit(1);
    }
    // biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
    console.log("pr-convention lockstep: all copies and caller pins match policy.json");
  } catch (error) {
    // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
    console.error(error.message);
    process.exit(1);
  }
}
