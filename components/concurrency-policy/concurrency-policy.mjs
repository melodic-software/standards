#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

import Ajv2020 from "ajv/dist/2020.js";
import { parseDocument } from "yaml";

export class ConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ConfigurationError";
  }
}

export function parseUniqueJson(source, location) {
  const document = parseDocument(source, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    schema: "json",
    strict: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new ConfigurationError(
      `${location} has duplicate object members or ambiguous structure: ${document.errors[0].message}`,
    );
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new ConfigurationError(`${location} is not valid JSON: ${error.message}`);
  }
}

const MODULE_DIRECTORY = import.meta.dirname;
const DEFAULT_CONFIG_PATH = ".github/concurrency-policy.json";
const CONFIG_SCHEMA_PATH = path.join(MODULE_DIRECTORY, "concurrency-policy.schema.json");
const CONFIG_SCHEMA = parseUniqueJson(
  await readFile(CONFIG_SCHEMA_PATH, "utf8"),
  `concurrency policy schema at ${CONFIG_SCHEMA_PATH}`,
);
const SCHEMA_VALIDATOR = new Ajv2020({
  allErrors: false,
  strict: true,
  validateFormats: false,
});
const validateConfigStructure = SCHEMA_VALIDATOR.compile(CONFIG_SCHEMA);

// The canonical top-level concurrency group for a pull-request-triggered
// workflow. github.workflow keys the run per workflow; github.event.pull_request.number
// supersedes an in-flight run of the same pull request; and because that number
// is empty on push and schedule events, those runs fall back to the unique
// github.run_id and are never cancelled. The pull-request number (not
// github.head_ref) is used deliberately: head_ref is a fork-controllable branch
// name that collides across same-named branches from different head repositories
// on pull_request_target, whereas the number is unique and trusted. Internal
// expression whitespace is tolerated; the token order and identity are exact.
const CANONICAL_GROUP =
  /^\$\{\{\s*github\.workflow\s*\}\}-\$\{\{\s*github\.event\.pull_request\.number\s*\|\|\s*github\.run_id\s*\}\}$/u;
const CANONICAL_GROUP_TEXT = `\${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}`;

// The ci-perf contract-only predicate. A workflow whose required check carries
// the pull-request contract re-runs on `edited`, `labeled` and `unlabeled`,
// events that change the contract answer without a new commit. Those runs gate
// every lane off and carry the recorded lane verdict forward. The predicate is
// the one the `ci-status` composite in ci-workflows carries as its
// `contract-only` default at v0.20.0, and it must match that default exactly:
// a drifted copy would gate lanes off while the composite still aggregates.
// Both places it can appear here, `cancel-in-progress` and the branched
// `group`, therefore hold it byte for byte, with none of the whitespace
// tolerance the canonical `group` tokens enjoy.
const CONTRACT_ONLY_PREDICATE_TEXT = `github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))`;

// The contract-only `cancel-in-progress` text, kept for repositories not yet
// reshaped onto the branched group. Expressed as `!(<predicate>)`, cancellation
// stays on for every full-run event and switches off only for the events that
// carry forward. This is a fail-closed allow-list of two values, the literal
// `true` and this string.
const CONTRACT_ONLY_CANCEL_TEXT = `\${{ !(${CONTRACT_ONLY_PREDICATE_TEXT}) }}`;

// The ci-perf branched group (github-iac#378, Phase 6b). Two runs of the
// required workflow on one head SHA share one concurrency group, and GitHub
// evicts a pending run unconditionally, so `cancel-in-progress: false` does not
// protect the contract-only run that queues behind the full run it reads. The
// branched group puts contract-only runs in their own per-run group keyed on
// github.run_id: no contract-only run can be cancelled, evicted, or evict
// anything, and the composite's bounded carry-forward wait replaces the queue.
// The full branch keeps the canonical shape, and its fallback term is the
// per-repository push decision: `github.ref` keeps push-side burst collapse,
// `github.run_id` gives none because every push lands in its own group. Exactly
// those two terms are admitted.
const FALLBACK_TERMS = ["github.ref", "github.run_id"];

// Escape a literal for embedding in a RegExp source, so the predicate and the
// two format() calls are matched byte for byte rather than as patterns.
function literalPattern(text) {
  return text.replaceAll(/[.*+?^${}()|[\]\\]/gu, String.raw`\$&`);
}

// Whitespace is tolerated only where the design's folded scalar puts it: the
// `${{ }}` delimiters and the two operator joins. Written as `group: >-` with
// the continuation lines more-indented, the YAML parser preserves a newline and
// the extra indent at each join, so the folded and single-line spellings differ
// only there. Everything else, above all the predicate, is exact. One pattern
// per admitted fallback term, so a match names the term without a capture
// group and an unlisted term matches nothing.
const BRANCHED_GROUP_BY_FALLBACK = new Map(
  FALLBACK_TERMS.map((term) => [
    term,
    new RegExp(
      `^\\$\\{\\{\\s*\\(${literalPattern(CONTRACT_ONLY_PREDICATE_TEXT)}\\)` +
        `\\s+&&\\s+${literalPattern("format('ci-contract-{0}-{1}', github.event.pull_request.number, github.run_id)")}` +
        `\\s+\\|\\|\\s+${literalPattern(`format('{0}-{1}', github.workflow, github.event.pull_request.number || ${term})`)}` +
        `\\s*\\}\\}$`,
      "u",
    ),
  ]),
);
const BRANCHED_GROUP_TEXT = `\${{ (<contract-only predicate>) && format('ci-contract-{0}-{1}', github.event.pull_request.number, github.run_id) || format('{0}-{1}', github.workflow, github.event.pull_request.number || <${FALLBACK_TERMS.join(" or ")}>) }}`;
const ALLOWED_CONCURRENCY_KEYS = new Set(["group", "cancel-in-progress"]);

function finding(rule, file, message, extra = {}) {
  return { level: "error", rule, file, message, ...extra };
}

// Classify a conforming group and name the fallback term it carries. The
// canonical form has one by construction, `github.run_id`; the branched form
// carries the repository's own decision. A group that matches neither returns
// undefined and is reported as drift.
function classifyGroup(group) {
  if (typeof group !== "string") {
    return undefined;
  }
  if (CANONICAL_GROUP.test(group)) {
    return { form: "canonical", fallback: "github.run_id" };
  }
  for (const [fallback, pattern] of BRANCHED_GROUP_BY_FALLBACK) {
    if (pattern.test(group)) {
      return { form: "branched", fallback };
    }
  }
  return undefined;
}

export function hasBlockingFindings(findings) {
  return findings.some((item) => item.level !== "info");
}

function jsonPointerLocation(location, instancePath) {
  return `${location}${instancePath
    .split("/")
    .slice(1)
    .map((segment) => `.${segment.replaceAll("~1", "/").replaceAll("~0", "~")}`)
    .join("")}`;
}

function validateConfig(value, location) {
  if (validateConfigStructure(value)) {
    return value;
  }
  const [error] = validateConfigStructure.errors;
  let errorLocation = jsonPointerLocation(location, error.instancePath);
  if (error.keyword === "additionalProperties") {
    errorLocation += `.${error.params.additionalProperty}`;
  } else if (error.keyword === "propertyNames") {
    errorLocation += `.${error.params.propertyName}`;
  }
  throw new ConfigurationError(`${errorLocation} ${error.message}`);
}

async function readJson(filePath, location) {
  let source;
  try {
    source = await readFile(filePath, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") {
      return undefined;
    }
    throw new ConfigurationError(`${location} could not be read at ${filePath}: ${error.message}`);
  }
  return parseUniqueJson(source, `${location} at ${filePath}`);
}

function parseWorkflow(source) {
  const document = parseDocument(source, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    strict: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new Error(document.errors.map((error) => error.message).join("; "));
  }
  const workflow = document.toJS({ maxAliasCount: 0 });
  if (workflow === null || typeof workflow !== "object" || Array.isArray(workflow)) {
    throw new Error("workflow must be a mapping");
  }
  return workflow;
}

// A workflow's `on:` may be a single event string, an array of event strings,
// or a mapping of event names to filters. YAML 1.2 keeps `on` a string key, so
// no true/false coercion occurs.
function triggerNames(on) {
  if (typeof on === "string") {
    return new Set([on]);
  }
  if (Array.isArray(on)) {
    return new Set(on.filter((event) => typeof event === "string"));
  }
  if (on !== null && typeof on === "object") {
    return new Set(Object.keys(on));
  }
  return new Set();
}

function isPullRequestTriggered(workflow) {
  const triggers = triggerNames(workflow.on);
  return triggers.has("pull_request") || triggers.has("pull_request_target");
}

// Read the top-level concurrency declaration. `concurrency: <string>` is the
// group-only shorthand and leaves cancel-in-progress false; the mapping form
// carries an explicit group and cancel-in-progress.
function topLevelConcurrency(workflow) {
  const concurrency = workflow.concurrency;
  if (concurrency === undefined) {
    return {
      present: false,
      malformed: false,
      group: undefined,
      cancelInProgress: undefined,
      keys: [],
    };
  }
  if (typeof concurrency === "string") {
    return {
      present: true,
      malformed: false,
      group: concurrency,
      cancelInProgress: false,
      keys: [],
    };
  }
  if (concurrency !== null && typeof concurrency === "object" && !Array.isArray(concurrency)) {
    return {
      present: true,
      malformed: false,
      group: concurrency.group,
      cancelInProgress: concurrency["cancel-in-progress"],
      keys: Object.keys(concurrency),
    };
  }
  return {
    present: true,
    malformed: true,
    group: undefined,
    cancelInProgress: undefined,
    keys: [],
  };
}

function concurrencyFindings(file, workflow) {
  const concurrency = topLevelConcurrency(workflow);
  if (!concurrency.present) {
    return [
      finding(
        "concurrency-missing",
        file,
        `pull-request-triggered workflow declares no top-level concurrency block; ` +
          `add \`concurrency: { group: ${CANONICAL_GROUP_TEXT}, cancel-in-progress: true }\``,
      ),
    ];
  }
  if (concurrency.malformed) {
    return [
      finding(
        "concurrency-malformed",
        file,
        "top-level concurrency must be a group string or a mapping with group and cancel-in-progress",
      ),
    ];
  }
  const findings = [];
  const shape = classifyGroup(concurrency.group);
  if (shape === undefined) {
    findings.push(
      finding(
        "concurrency-group-drift",
        file,
        `top-level concurrency.group must be \`${CANONICAL_GROUP_TEXT}\` or the ci-perf branched ` +
          `form \`${BRANCHED_GROUP_TEXT}\`, found ${JSON.stringify(concurrency.group ?? null)}`,
      ),
    );
  } else {
    // Informational, never blocking: the fallback term is a per-repository
    // decision, not drift, and reporting it lets a fleet check list which
    // repositories keep push-side burst collapse.
    findings.push(
      finding(
        "concurrency-group-fallback",
        file,
        `top-level concurrency.group is the ${shape.form} form with fallback term ` +
          `\`${shape.fallback}\`, so push and schedule runs ` +
          `${shape.fallback === "github.ref" ? "collapse into one group per ref" : "each land in their own group and are never superseded"}`,
        { level: "info", fallback: shape.fallback },
      ),
    );
  }
  if (
    concurrency.cancelInProgress !== true &&
    concurrency.cancelInProgress !== CONTRACT_ONLY_CANCEL_TEXT
  ) {
    findings.push(
      finding(
        "concurrency-cancel-missing",
        file,
        `top-level concurrency.cancel-in-progress must be the literal true or the ci-perf ` +
          `contract-only expression \`${CONTRACT_ONLY_CANCEL_TEXT}\`, found ` +
          `${JSON.stringify(concurrency.cancelInProgress ?? null)}`,
      ),
    );
  }
  // The canonical block is exactly group and cancel-in-progress. GitHub also
  // accepts `queue`, but a pending queue is meaningless once cancel-in-progress
  // supersedes the in-flight run, so any extra key is drift from the standard.
  const extraKeys = concurrency.keys.filter((key) => !ALLOWED_CONCURRENCY_KEYS.has(key));
  if (extraKeys.length > 0) {
    findings.push(
      finding(
        "concurrency-extra-keys",
        file,
        `top-level concurrency has unexpected keys ${JSON.stringify(extraKeys)}; the canonical ` +
          "block is exactly group and cancel-in-progress",
      ),
    );
  }
  return findings;
}

async function repositoryWorkflowIndex(root) {
  const directory = path.join(root, ".github", "workflows");
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") {
      return new Map();
    }
    throw error;
  }
  const records = new Map();
  for (const entry of entries
    .filter((candidate) => /\.ya?ml$/iu.test(candidate.name))
    .sort((left, right) => left.name.localeCompare(right.name))) {
    const file = `.github/workflows/${entry.name}`;
    const absoluteFile = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      records.set(file, {
        file,
        error: `${file} must be a regular file; workflow symlinks are forbidden`,
      });
      continue;
    }
    if (!entry.isFile()) {
      continue;
    }
    try {
      const source = await readFile(absoluteFile, "utf8");
      records.set(file, { file, workflow: parseWorkflow(source) });
    } catch (error) {
      records.set(file, { file, error: error.message });
    }
  }
  return records;
}

export async function auditRepository({
  root = process.cwd(),
  configPath = DEFAULT_CONFIG_PATH,
} = {}) {
  const resolvedRoot = path.resolve(root);
  const resolvedConfig = path.isAbsolute(configPath)
    ? configPath
    : path.join(resolvedRoot, configPath);
  const rawConfig = await readJson(resolvedConfig, "repository concurrency policy");
  const config =
    rawConfig === undefined
      ? { schemaVersion: 1, exceptions: {} }
      : validateConfig(rawConfig, "concurrency policy");
  const exceptions = config.exceptions ?? {};

  const records = await repositoryWorkflowIndex(resolvedRoot);
  const findings = [];
  const consumedExceptions = new Set();

  for (const record of records.values()) {
    if (record.error) {
      findings.push(
        finding(
          "workflow-unparsable",
          record.file,
          `workflow could not be parsed, so its concurrency block cannot be verified: ${record.error}`,
        ),
      );
      continue;
    }
    if (!isPullRequestTriggered(record.workflow)) {
      continue;
    }
    if (Object.hasOwn(exceptions, record.file)) {
      consumedExceptions.add(record.file);
      // A delegated-job-level exception waives only the missing top-level block.
      // A present block is still active, so it is validated regardless of the
      // exception, and the now-unnecessary exception is reported: an exception
      // must never license an unsafe or non-canonical block.
      if (topLevelConcurrency(record.workflow).present) {
        findings.push(
          finding(
            "exception-inventory-drift",
            record.file,
            "declares a concurrency-policy exception but carries a top-level concurrency " +
              "block; remove the exception or the block",
          ),
        );
        findings.push(...concurrencyFindings(record.file, record.workflow));
      }
      continue;
    }
    findings.push(...concurrencyFindings(record.file, record.workflow));
  }

  for (const file of Object.keys(exceptions)) {
    if (consumedExceptions.has(file)) {
      continue;
    }
    const record = records.get(file);
    if (record === undefined) {
      findings.push(
        finding(
          "exception-inventory-drift",
          file,
          "concurrency-policy exception names a workflow that does not exist",
        ),
      );
    } else if (record.error) {
      // The workflow exists but could not be parsed; the unparsable finding
      // already fired. Leave the exception unconsumed without a second report.
    } else {
      findings.push(
        finding(
          "exception-inventory-drift",
          file,
          "concurrency-policy exception names a workflow that is not pull-request-triggered, " +
            "so no top-level concurrency requirement applies",
        ),
      );
    }
  }

  const uniqueFindings = new Map();
  for (const item of findings) {
    const key = [item.file, item.rule, item.message].join("\0");
    if (!uniqueFindings.has(key)) {
      uniqueFindings.set(key, item);
    }
  }
  return [...uniqueFindings.values()].sort((left, right) =>
    [left.file, left.rule, left.message]
      .join("\0")
      .localeCompare([right.file, right.rule, right.message].join("\0")),
  );
}

export function parseArguments(argv) {
  try {
    const { values } = parseArgs({
      args: argv,
      allowPositionals: false,
      options: {
        config: { default: DEFAULT_CONFIG_PATH, type: "string" },
        json: { default: false, type: "boolean" },
        root: { default: process.cwd(), type: "string" },
      },
      strict: true,
    });
    return {
      root: values.root,
      configPath: values.config,
      json: values.json,
    };
  } catch (error) {
    throw new ConfigurationError(error instanceof Error ? error.message : String(error));
  }
}

async function main() {
  try {
    const { json, ...options } = parseArguments(process.argv.slice(2));
    const findings = await auditRepository(options);
    const blocked = hasBlockingFindings(findings);
    if (json) {
      process.stdout.write(`${JSON.stringify({ findings, ok: !blocked }, null, 2)}\n`);
    } else {
      // Info findings are reported on stdout and never fail the gate; blocking
      // findings keep the stderr channel and the non-zero exit status.
      for (const item of findings) {
        const line = `${item.file}: ${item.level}: ${item.rule}: ${item.message}\n`;
        if (item.level === "info") {
          process.stdout.write(line);
        } else {
          process.stderr.write(line);
        }
      }
      if (!blocked) {
        process.stdout.write("Concurrency policy passed.\n");
      }
    }
    process.exitCode = blocked ? 1 : 0;
  } catch (error) {
    const output = error instanceof Error ? error.message : String(error);
    process.stderr.write(`concurrency-policy: ${output}\n`);
    process.exitCode = 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
