#!/usr/bin/env node

// Lockstep drift check (ADR-0008): `policy.json` is the canonical record of
// the fleet PR convention, but other copies of the contract exist and must
// change in lockstep with it — the ci-workflows `pr-contract` composite (the
// live gate every consumer runs inside its `ci-status` job), the
// source-control plugin's PreToolUse validator, the org `.github` PR
// template, and this repository's distributed
// `.claude/rules/pr-body-contract.md`. Letting any copy drift is exactly the
// failure #393 recorded (and claude-code-plugins#3205 repeated). This check
// also dereferences every consumer's pinned artifact and validates the
// contract AT THAT PIN, because a stale pin enforcing an older contract (the
// codex-plugins v0.9.1 case) is drift no source-copy diff can see.
//
// Phase 3 of the ci-perf program (github-iac#396) moves the fleet from the
// `pr-issue-linkage.yml` reusable to the `pr-contract` composite, one
// repository at a time. A consumer therefore runs one artifact or the other,
// never both, for the days that transition takes: the fleet scan detects
// which one a repository uses and checks the contract with the matching
// extractor, so a mixed fleet passes and a drifted artifact of either kind
// still fails.
//
// CLI mode fetches live sources over the GitHub contents API and exits
// non-zero on drift; every network failure is a distinct `fetch-error`
// failure, never a skip. Parsing and comparison logic is exported for the
// hermetic fixture tests in `lockstep-drift.test.mjs`.

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { parse as parseYaml } from "yaml";

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

// Contents-API URLs, not raw.githubusercontent: several consumers are private
// repositories, and the API honors the token `LOCKSTEP_GITHUB_TOKEN` (or
// `GITHUB_TOKEN`) that the CI lane mints from the org GitHub App. Public
// sources still resolve unauthenticated.
const API_BASE = "https://api.github.com/repos/melodic-software";
const contentsUrl = (repo, ref, filePath) => `${API_BASE}/${repo}/contents/${filePath}?ref=${ref}`;

export const COMPOSITE_DIRECTORY = ".github/actions/pr-contract";
const REUSABLE_PATH = ".github/workflows/pr-issue-linkage.yml";

export const COPY_SOURCES = {
  gateRun: contentsUrl("ci-workflows", "main", `${COMPOSITE_DIRECTORY}/run.sh`),
  gateAction: contentsUrl("ci-workflows", "main", `${COMPOSITE_DIRECTORY}/action.yml`),
  hookValidator: contentsUrl(
    "claude-code-plugins",
    "main",
    "plugins/source-control/hooks/pr-linkage-validator.sh",
  ),
  orgTemplate: contentsUrl(".github", "main", ".github/PULL_REQUEST_TEMPLATE.md"),
};

// Every repository in the fleet, whether or not it is gated today.
export const CONSUMER_REPOSITORIES = [
  ".github",
  "agent-plugins",
  "ci-runner",
  "ci-workflows",
  "claude-code-plugins",
  "claude-code-proxy",
  "codex-plugins",
  "cursor-plugins",
  "dotfiles",
  "github-iac",
  "medley",
  "provisioning",
  "standards",
];

// The three repositories the sync does not reach and the org `ci-gate` ruleset
// does not cover. A repository with neither artifact is REPORTED here and
// FAILS anywhere else: a gated repository that lost its contract check is the
// drift this lane exists to catch.
export const UNSYNCED_REPOSITORIES = ["agent-plugins", "claude-code-proxy", "cursor-plugins"];

// The composite is called from the `ci-status` job, which lives in `ci.yml`
// everywhere except medley. Scanning these first lets the common case
// short-circuit instead of reading a whole workflow directory.
const WORKFLOW_SCAN_PRIORITY = ["ci.yml", "ci-status.yml"];

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

function collect(errors, fn) {
  try {
    fn();
  } catch (error) {
    if (!(error instanceof DriftError)) {
      throw error;
    }
    errors.push(error.message);
  }
}

// ---------------------------------------------------------------------------
// The `pr-contract` composite (the live gate, and every migrated consumer).
//
// `run.sh` states the section list as data: the analyzer's END block calls
// `section_report("<name>")` once per required section, in contract order.
// ---------------------------------------------------------------------------
export function parseCompositeSections(runShText, location) {
  const names = [...runShText.matchAll(/section_report\("([^"]+)"\)/g)].map((m) => m[1]);
  if (names.length === 0) {
    throw new DriftError(`${location}: no \`section_report("<name>")\` calls found in run.sh`);
  }
  return names;
}

// The composite's keyword and marker enforcement are executable awk regex
// literals, so they are validated FUNCTIONALLY the same way the reusable's
// were: extract each declared pattern and probe it with every policy
// keyword/marker. A keyword that survives only in a comment or an error
// message no longer passes.
export function parseCompositePatterns(runShText, location) {
  const keyword = runShText.match(/match\(chunk, \/(.+)\/\)\) break/);
  const marker = runShText.match(/tolower\(body\) ~ \/(.+)\/\) print "no-issue"/);
  if (!keyword || !marker) {
    throw new DriftError(
      `${location}: closing-keyword / no-issue-marker match expressions not found in run.sh`,
    );
  }
  // Both awk patterns are lowercase and match against text the analyzer has
  // already lowercased (`lower = tolower(line)` for the keyword scan,
  // `tolower(body)` in the anchor above for the marker). The probes below
  // lowercase to mirror that. If the lowercasing ever went away the extracted
  // pattern would become case-sensitive against raw text and reject the
  // documented capitalised forms, so its presence is asserted rather than
  // assumed — the composite's equivalent of the reusable's `i` flag.
  if (!/lower = tolower\(line\)/.test(runShText)) {
    throw new DriftError(
      `${location}: the closing-keyword scan no longer lowercases the line (\`lower = tolower(line)\`), so the extracted pattern is not the one the gate applies`,
    );
  }
  return { keyword: new RegExp(keyword[1]), marker: new RegExp(marker[1]) };
}

// `action.yml`'s `inputs.types.default` is the composite's copy of
// `policy.json`'s `allowedTypes`: the title regex is built from it at runtime,
// and no caller in the fleet overrides it. Parsed as YAML rather than by
// regex so the anchor is the data key, not the shape of the description block
// above it.
export function parseCompositeTypes(actionYmlText, location) {
  let document;
  try {
    document = parseYaml(actionYmlText);
  } catch (error) {
    throw new DriftError(`${location}: action.yml is not parsable YAML: ${error.message}`);
  }
  const declared = document?.inputs?.types?.default;
  if (typeof declared !== "string") {
    throw new DriftError(`${location}: action.yml declares no string \`inputs.types.default\``);
  }
  const types = declared
    .split(",")
    .map((type) => type.trim())
    .filter(Boolean);
  if (types.length === 0) {
    throw new DriftError(`${location}: the \`types\` input default is empty`);
  }
  return types;
}

// ---------------------------------------------------------------------------
// The `pr-issue-linkage.yml` reusable (the predecessor, still pinned by every
// consumer that has not taken its Phase 3 pull request yet).
//
// The reusable declares its contract as a `requiredSections` array of
// `{ name: "...", guidance: "..." }` literals inside an actions/github-script
// step. The array literal is the narrowest stable surface to parse.
// ---------------------------------------------------------------------------
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

export function parseGatePatterns(workflowText, location) {
  // Accept any declared flag set rather than a literal `/i;`: ci-workflows made
  // CLOSING_KEYWORD global (`/gi;`, so every occurrence on a line can be
  // classified) and the old literal match turned a healthy gate into
  // "declarations not found" — a parse failure wearing a drift error's clothes.
  //
  // Flags are CAPTURED, not discarded, because they are behavior. Both bodies are
  // lowercase and depend on `i` to accept the documented capitalised keyword forms;
  // rebuilding the probe with a hardcoded `i` would silently pass a gate that had
  // dropped it and become case-sensitive, which is exactly the enforcement drift this check
  // exists to catch. `g` and `y` are the one exception, stripped below.
  const keyword = workflowText.match(/const CLOSING_KEYWORD =\s*\/(.+)\/([dgimsuvy]*);/);
  const marker = workflowText.match(/const NO_ISSUE_MARKER =\s*\/(.+)\/([dgimsuvy]*);/);
  if (!keyword || !marker) {
    throw new DriftError(
      `${location}: CLOSING_KEYWORD / NO_ISSUE_MARKER regex declarations not found`,
    );
  }
  // `g` and `y` make `.test()` stateful via lastIndex, and assertPatternsEnforce
  // probes each pattern once per policy keyword, so a retained `g` would make
  // every probe after the first read a moved cursor instead of the pattern.
  // Neither flag changes WHAT the pattern matches, so dropping them is safe.
  const probeFlags = (flags) => flags.replaceAll(/[gy]/g, "");
  return {
    keyword: new RegExp(keyword[1], probeFlags(keyword[2])),
    marker: new RegExp(marker[1], probeFlags(marker[2])),
  };
}

// ---------------------------------------------------------------------------
// The other two remote copies.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Which artifact a consumer runs.
// ---------------------------------------------------------------------------

// A `uses:` of the composite, pinned to a 40-hex ci-workflows SHA.
const COMPOSITE_PIN_PATTERN =
  /melodic-software\/ci-workflows\/\.github\/actions\/pr-contract@([0-9a-f]{40})/;
// ci-workflows dogfoods its own composite through a local `./` reference,
// which carries no SHA — the artifact is that repository's own tree at `main`.
// Anchored on `uses:` so the same path in a lint `paths:` list or a
// `bash .github/actions/pr-contract/run.test.sh` line is not mistaken for a
// call site.
const COMPOSITE_LOCAL_PATTERN = /uses:\s*\.\/\.github\/actions\/pr-contract(?=\s|$)/m;
const REUSABLE_PIN_PATTERN = /pr-issue-linkage\.yml@([0-9a-f]{40})/;

// The composite wins over the reusable: during the Phase 3 transition
// ci-workflows carries both (its `pr-issue-linkage-self.yml` caller stays
// until 3.4), and the artifact that gates is the one inside `ci-status`.
export function detectArtifactPin(workflowText) {
  const pinned = workflowText.match(COMPOSITE_PIN_PATTERN);
  if (pinned) {
    return { kind: "composite", sha: pinned[1] };
  }
  if (COMPOSITE_LOCAL_PATTERN.test(workflowText)) {
    return { kind: "composite", sha: "main" };
  }
  const reusable = workflowText.match(REUSABLE_PIN_PATTERN);
  if (reusable) {
    return { kind: "reusable", sha: reusable[1] };
  }
  return null;
}

export function parseCallerPin(workflowText, location) {
  const match = workflowText.match(REUSABLE_PIN_PATTERN);
  if (!match) {
    throw new DriftError(`${location}: no 40-hex pr-issue-linkage.yml@<sha> pin found`);
  }
  return match[1];
}

// ---------------------------------------------------------------------------
// Comparisons.
// ---------------------------------------------------------------------------

function assertPatternsEnforce(patterns, policy, location, { lowercaseProbe = false } = {}) {
  const probe = (text) => (lowercaseProbe ? text.toLowerCase() : text);
  const missing = [];
  for (const keyword of policy.body.closingKeywords) {
    if (!patterns.keyword.test(probe(` ${keyword} #12 `))) {
      missing.push(`closing keyword "${keyword}"`);
    }
  }
  for (const marker of policy.body.noIssueMarkers) {
    if (!patterns.marker.test(probe(` ${marker}: none `))) {
      missing.push(`no-issue marker "${marker}"`);
    }
  }
  if (missing.length > 0) {
    throw new DriftError(`${location}: declared pattern rejects ${missing.join(", ")}`);
  }
}

function assertExactSections(actual, expected, location) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new DriftError(
      `${location}: section list [${actual.join(", ")}] != policy [${expected.join(", ")}]`,
    );
  }
}

// Order is not behavior here — the composite builds a regex alternation from
// the list — so the comparison is set-wise and the message names the exact
// divergence rather than printing two lists to diff by eye.
function assertAllowedTypes(actual, expected, location) {
  const missing = expected.filter((type) => !actual.includes(type));
  const unexpected = actual.filter((type) => !expected.includes(type));
  if (missing.length === 0 && unexpected.length === 0) {
    return;
  }
  const parts = [];
  if (missing.length > 0) {
    parts.push(`missing ${missing.join(", ")}`);
  }
  if (unexpected.length > 0) {
    parts.push(`unexpected ${unexpected.join(", ")}`);
  }
  throw new DriftError(
    `${location}: allowed title types ${parts.join("; ")} (declared: ${actual.join(", ")})`,
  );
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
  const run = (fn) => collect(errors, fn);
  run(() =>
    assertExactSections(
      parseCompositeSections(texts.gateRun, "gate composite"),
      sections,
      "gate composite",
    ),
  );
  run(() =>
    assertPatternsEnforce(
      parseCompositePatterns(texts.gateRun, "gate composite"),
      policy,
      "gate composite (enforcement patterns)",
      { lowercaseProbe: true },
    ),
  );
  run(() =>
    assertAllowedTypes(
      parseCompositeTypes(texts.gateAction, "gate composite"),
      policy.title.allowedTypes,
      "gate composite (title types)",
    ),
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
      parseValidatorPatterns(texts.hookValidator, "hook validator"),
      policy,
      "hook validator (enforcement patterns)",
    ),
  );
  return errors;
}

function pinLabel(sha) {
  return sha === "main" ? "local at main" : `pin ${sha.slice(0, 7)}`;
}

// Validates the full contract at the pin — sections AND the executable
// keyword/marker patterns — so a pinned reusable whose section list matches
// current policy but whose keyword or marker enforcement is stale still
// reports drift.
export function checkPinnedReusable(policy, repo, sha, reusableText) {
  const location = `caller ${repo} ${pinLabel(sha)}`;
  const errors = [];
  const run = (fn) => collect(errors, fn);
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

// The composite's equivalent: sections and enforcement patterns from `run.sh`,
// allowed title types from `action.yml`. The types are checked at the pin
// because a consumer pinned to a pre-`security` composite would reject a
// `security:` title that policy allows — drift the source-copy check on `main`
// cannot see.
export function checkPinnedComposite(policy, repo, sha, runShText, actionYmlText) {
  const location = `caller ${repo} ${pinLabel(sha)}`;
  const errors = [];
  const run = (fn) => collect(errors, fn);
  run(() =>
    assertExactSections(
      parseCompositeSections(runShText, location),
      policy.body.requiredSections,
      location,
    ),
  );
  run(() =>
    assertPatternsEnforce(parseCompositePatterns(runShText, location), policy, location, {
      lowercaseProbe: true,
    }),
  );
  run(() =>
    assertAllowedTypes(
      parseCompositeTypes(actionYmlText, location),
      policy.title.allowedTypes,
      location,
    ),
  );
  return errors;
}

// One verdict per consumer over a resolved fleet. `kind: "none"` is a drift
// finding everywhere except the three repositories the sync does not reach,
// where it is a note; `kind: "unresolved"` means the live loop already
// recorded a fetch failure for that repository and this pass adds nothing.
export function checkFleet(policy, resolutions) {
  const errors = [];
  const notes = [];
  for (const repo of CONSUMER_REPOSITORIES) {
    const resolution = resolutions.get(repo);
    if (resolution === undefined) {
      errors.push(`caller ${repo}: the fleet scan produced no artifact resolution`);
      continue;
    }
    if (resolution.kind === "unresolved") {
      continue;
    }
    if (resolution.kind === "none") {
      const message = `caller ${repo}: no pr-contract composite step and no pr-issue-linkage caller`;
      if (UNSYNCED_REPOSITORIES.includes(repo)) {
        notes.push(`${message} (known unsynced repository; reported, not failed)`);
      } else {
        errors.push(message);
      }
      continue;
    }
    if (resolution.kind === "composite") {
      errors.push(
        ...checkPinnedComposite(
          policy,
          repo,
          resolution.sha,
          resolution.runSh,
          resolution.actionYml,
        ),
      );
      continue;
    }
    errors.push(...checkPinnedReusable(policy, repo, resolution.sha, resolution.reusable));
  }
  return { errors, notes };
}

// ---------------------------------------------------------------------------
// Live mode.
// ---------------------------------------------------------------------------

function apiHeaders(accept) {
  const token = process.env.LOCKSTEP_GITHUB_TOKEN || process.env.GITHUB_TOKEN;
  const headers = { Accept: accept };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  return headers;
}

async function fetchWithRetry(url, accept, { notFoundIsNull = false } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(url, { headers: apiHeaders(accept) });
      if (response.ok) {
        return response;
      }
      // A missing `.github/workflows` directory is a fact about the fleet, not
      // a transport failure: the repository simply runs no workflows.
      if (notFoundIsNull && response.status === 404) {
        return null;
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

async function fetchText(url) {
  const response = await fetchWithRetry(url, "application/vnd.github.raw+json");
  return await response.text();
}

async function fetchDirectory(url) {
  const response = await fetchWithRetry(url, "application/vnd.github+json", {
    notFoundIsNull: true,
  });
  if (response === null) {
    return [];
  }
  return await response.json();
}

function scanOrder(names) {
  const rank = (name) => (WORKFLOW_SCAN_PRIORITY.includes(name) ? 0 : 1);
  return [...names].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
}

// Reads a repository's workflow directory and returns the artifact it runs.
// The composite short-circuits the scan; a reusable pin is remembered but the
// scan continues, because a repository mid-transition can carry both and the
// composite is the one that gates.
async function resolveConsumerArtifact(repo, cachedText) {
  const entries = await fetchDirectory(`${API_BASE}/${repo}/contents/.github/workflows?ref=main`);
  const names = entries
    .filter((entry) => entry.type === "file" && /\.ya?ml$/.test(entry.name))
    .map((entry) => entry.name);
  let reusable = null;
  for (const name of scanOrder(names)) {
    const text = await cachedText(contentsUrl(repo, "main", `.github/workflows/${name}`));
    const found = detectArtifactPin(text);
    if (!found) {
      continue;
    }
    if (found.kind === "composite") {
      return found;
    }
    reusable ??= found;
  }
  return reusable ?? { kind: "none" };
}

export async function runLiveCheck() {
  const policy = parseUniqueJson(await readFile(POLICY_PATH, "utf8"), POLICY_PATH);
  const cache = new Map();
  const cachedText = async (url) => {
    if (!cache.has(url)) {
      cache.set(url, await fetchText(url));
    }
    return cache.get(url);
  };

  const texts = {
    gateRun: await cachedText(COPY_SOURCES.gateRun),
    gateAction: await cachedText(COPY_SOURCES.gateAction),
    hookValidator: await cachedText(COPY_SOURCES.hookValidator),
    orgTemplate: await cachedText(COPY_SOURCES.orgTemplate),
    rulesFile: await readFile(RULES_FILE_PATH, "utf8"),
  };
  const errors = checkCopies(policy, texts);

  // A consumer whose fetch fails is reported and the loop continues, so one
  // unreachable private repository cannot mask drift findings collected from
  // the rest; any fetch-error still fails the run.
  const resolutions = new Map();
  for (const repo of CONSUMER_REPOSITORIES) {
    try {
      const found = await resolveConsumerArtifact(repo, cachedText);
      if (found.kind === "none") {
        resolutions.set(repo, found);
        continue;
      }
      if (found.kind === "composite") {
        // `main` means a local `./` reference: the artifact is that
        // repository's own tree, which for ci-workflows is the gate source
        // already fetched above (the cache makes this free).
        const source = found.sha === "main" ? repo : "ci-workflows";
        const ref = found.sha;
        resolutions.set(repo, {
          kind: "composite",
          sha: found.sha,
          runSh: await cachedText(contentsUrl(source, ref, `${COMPOSITE_DIRECTORY}/run.sh`)),
          actionYml: await cachedText(
            contentsUrl(source, ref, `${COMPOSITE_DIRECTORY}/action.yml`),
          ),
        });
        continue;
      }
      resolutions.set(repo, {
        kind: "reusable",
        sha: found.sha,
        reusable: await cachedText(contentsUrl("ci-workflows", found.sha, REUSABLE_PATH)),
      });
    } catch (error) {
      if (!(error instanceof FetchError) && !(error instanceof DriftError)) {
        throw error;
      }
      resolutions.set(repo, { kind: "unresolved" });
      errors.push(`caller ${repo}: ${error.message}`);
    }
  }

  const fleet = checkFleet(policy, resolutions);
  return { errors: [...errors, ...fleet.errors], notes: fleet.notes };
}

// This block is the CLI entrypoint of a shebang script whose entire contract is
// what it prints and what it exits with, so stdout/stderr are the interface
// rather than stray debugging. noConsole is suppressed per call rather than
// repo-wide, which would blind the rule everywhere else in this component.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    const { errors, notes } = await runLiveCheck();
    for (const message of notes) {
      // biome-ignore lint/suspicious/noConsole: CLI note output is this script's interface
      console.log(`note: ${message}`);
    }
    if (errors.length > 0) {
      for (const message of errors) {
        // biome-ignore lint/suspicious/noConsole: CLI drift output is this script's interface
        console.error(`drift: ${message}`);
      }
      process.exit(1);
    }
    // biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
    console.log("pr-convention lockstep: all copies and consumer pins match policy.json");
  } catch (error) {
    // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
    console.error(error.message);
    process.exit(1);
  }
}
