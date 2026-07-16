#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

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

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
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

function finding(rule, file, message) {
  return { rule, file, message };
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
    return { present: false, malformed: false, group: undefined, cancelInProgress: undefined };
  }
  if (typeof concurrency === "string") {
    return { present: true, malformed: false, group: concurrency, cancelInProgress: false };
  }
  if (concurrency !== null && typeof concurrency === "object" && !Array.isArray(concurrency)) {
    return {
      present: true,
      malformed: false,
      group: concurrency.group,
      cancelInProgress: concurrency["cancel-in-progress"],
    };
  }
  return { present: true, malformed: true, group: undefined, cancelInProgress: undefined };
}

function conformsToCanonical(workflow) {
  const concurrency = topLevelConcurrency(workflow);
  return (
    concurrency.present &&
    !concurrency.malformed &&
    typeof concurrency.group === "string" &&
    CANONICAL_GROUP.test(concurrency.group) &&
    concurrency.cancelInProgress === true
  );
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
  if (typeof concurrency.group !== "string" || !CANONICAL_GROUP.test(concurrency.group)) {
    findings.push(
      finding(
        "concurrency-group-drift",
        file,
        `top-level concurrency.group must be \`${CANONICAL_GROUP_TEXT}\`, found ` +
          `${JSON.stringify(concurrency.group ?? null)}`,
      ),
    );
  }
  if (concurrency.cancelInProgress !== true) {
    findings.push(
      finding(
        "concurrency-cancel-missing",
        file,
        `top-level concurrency.cancel-in-progress must be the literal true, found ` +
          `${JSON.stringify(concurrency.cancelInProgress ?? null)}`,
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
      // An exception waives the top-level requirement only when the requirement
      // is otherwise unmet; a workflow that already conforms does not need one.
      if (conformsToCanonical(record.workflow)) {
        findings.push(
          finding(
            "exception-inventory-drift",
            record.file,
            "declares a concurrency-policy exception but already carries the canonical " +
              "top-level block; remove the unnecessary exception",
          ),
        );
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

function parseArguments(argv) {
  const options = {
    root: process.cwd(),
    configPath: DEFAULT_CONFIG_PATH,
    json: argv.includes("--json"),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--json") {
      options.json = true;
      continue;
    }
    if (argument === "--root" || argument === "--config") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new ConfigurationError(`${argument} requires a value`);
      }
      index += 1;
      if (argument === "--root") options.root = value;
      if (argument === "--config") options.configPath = value;
      continue;
    }
    throw new ConfigurationError(`unknown argument: ${argument}`);
  }
  return options;
}

async function main() {
  try {
    const { json, ...options } = parseArguments(process.argv.slice(2));
    const findings = await auditRepository(options);
    if (json) {
      process.stdout.write(`${JSON.stringify({ findings, ok: findings.length === 0 }, null, 2)}\n`);
    } else if (findings.length === 0) {
      process.stdout.write("Concurrency policy passed.\n");
    } else {
      for (const item of findings) {
        process.stderr.write(`${item.file}: ${item.rule}: ${item.message}\n`);
      }
    }
    process.exitCode = findings.length === 0 ? 0 : 1;
  } catch (error) {
    const output = error instanceof Error ? error.message : String(error);
    process.stderr.write(`concurrency-policy: ${output}\n`);
    process.exitCode = 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
