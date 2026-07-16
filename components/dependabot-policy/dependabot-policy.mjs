#!/usr/bin/env node

import { readFile } from "node:fs/promises";
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
const DEFAULT_POLICY_PATH = path.join(MODULE_DIRECTORY, "policy.json");
const DEFAULT_CONFIG_PATH = ".github/dependabot-policy.json";
const DEFAULT_DEPENDABOT_PATH = ".github/dependabot.yml";
const POLICY_SCHEMA_PATH = path.join(MODULE_DIRECTORY, "policy.schema.json");
const CONFIG_SCHEMA_PATH = path.join(MODULE_DIRECTORY, "dependabot-policy.schema.json");
const POLICY_SCHEMA = parseUniqueJson(
  await readFile(POLICY_SCHEMA_PATH, "utf8"),
  `dependabot policy schema at ${POLICY_SCHEMA_PATH}`,
);
const CONFIG_SCHEMA = parseUniqueJson(
  await readFile(CONFIG_SCHEMA_PATH, "utf8"),
  `repository dependabot policy schema at ${CONFIG_SCHEMA_PATH}`,
);
const SCHEMA_VALIDATOR = new Ajv2020({
  allErrors: false,
  strict: true,
  validateFormats: false,
});
const validatePolicyStructure = SCHEMA_VALIDATOR.compile(POLICY_SCHEMA);
const validateConfigStructure = SCHEMA_VALIDATOR.compile(CONFIG_SCHEMA);

// Which policy rule each waive category suppresses.
const WAIVE_BY_RULE = {
  "schedule-not-standard": "schedule",
  "cooldown-below-minimum": "cooldown",
  "groups-missing": "groups",
};

function finding(rule, file, entry, message) {
  return entry === undefined ? { rule, file, message } : { rule, file, entry, message };
}

function jsonPointerLocation(location, instancePath) {
  return `${location}${instancePath
    .split("/")
    .slice(1)
    .map((segment) => `.${segment.replaceAll("~1", "/").replaceAll("~0", "~")}`)
    .join("")}`;
}

function validateStructure(value, validator, location) {
  if (validator(value)) {
    return value;
  }
  const [error] = validator.errors;
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

async function readDependabot(filePath) {
  let source;
  try {
    source = await readFile(filePath, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") {
      return undefined;
    }
    throw new ConfigurationError(
      `dependabot config could not be read at ${filePath}: ${error.message}`,
    );
  }
  const document = parseDocument(source, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    strict: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new ConfigurationError(
      `dependabot config at ${filePath} is not valid YAML: ${document.errors[0].message}`,
    );
  }
  const value = document.toJS({ maxAliasCount: 0 });
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ConfigurationError(`dependabot config at ${filePath} must be a mapping`);
  }
  return value;
}

// A stable identifier for one `updates` entry. Dependabot keys an entry by its
// ecosystem and its directory; the plural `directories` list is joined so an
// entry that scans several roots still has one deterministic key.
function entryKey(entry) {
  const ecosystem = entry["package-ecosystem"];
  const prefix = typeof ecosystem === "string" && ecosystem.length > 0 ? ecosystem : "?";
  if (typeof entry.directory === "string") {
    return `${prefix}:${entry.directory}`;
  }
  if (Array.isArray(entry.directories)) {
    return `${prefix}:${entry.directories.join(",")}`;
  }
  return `${prefix}:?`;
}

function entryFindings(file, key, entry, policy) {
  const findings = [];
  const interval = entry.schedule?.interval;
  if (interval !== policy.scheduleInterval) {
    findings.push(
      finding(
        "schedule-not-standard",
        file,
        key,
        `schedule.interval must be ${JSON.stringify(policy.scheduleInterval)}, found ${JSON.stringify(interval ?? null)}`,
      ),
    );
  }
  const cooldownDays = entry.cooldown?.["default-days"];
  if (typeof cooldownDays !== "number" || cooldownDays < policy.cooldownMinimumDays) {
    findings.push(
      finding(
        "cooldown-below-minimum",
        file,
        key,
        `cooldown.default-days must be an integer >= ${policy.cooldownMinimumDays}, found ${JSON.stringify(cooldownDays ?? null)}`,
      ),
    );
  }
  if (policy.requireGroups) {
    const groups = entry.groups;
    const hasGroups =
      groups !== null &&
      typeof groups === "object" &&
      !Array.isArray(groups) &&
      Object.keys(groups).length > 0;
    if (!hasGroups) {
      findings.push(
        finding(
          "groups-missing",
          file,
          key,
          "a groups block is required so related bumps batch into one pull request",
        ),
      );
    }
  }
  const limit = entry["open-pull-requests-limit"];
  if (typeof limit === "number" && limit > policy.maxOpenPullRequests) {
    findings.push(
      finding(
        "pr-limit-too-high",
        file,
        key,
        `open-pull-requests-limit must be <= ${policy.maxOpenPullRequests}, found ${limit}`,
      ),
    );
  }
  return findings;
}

export async function auditRepository({
  root = process.cwd(),
  configPath = DEFAULT_CONFIG_PATH,
  policyPath = DEFAULT_POLICY_PATH,
  dependabotPath = DEFAULT_DEPENDABOT_PATH,
} = {}) {
  const resolvedRoot = path.resolve(root);
  const resolve = (candidate) =>
    path.isAbsolute(candidate) ? candidate : path.join(resolvedRoot, candidate);
  const policy = validateStructure(
    await readJson(resolve(policyPath), "dependabot policy"),
    validatePolicyStructure,
    "policy",
  );
  const rawConfig = await readJson(resolve(configPath), "repository dependabot policy");
  const config =
    rawConfig === undefined
      ? { schemaVersion: 1, exceptions: {} }
      : validateStructure(rawConfig, validateConfigStructure, "dependabot policy");
  const exceptions = config.exceptions ?? {};

  const dependabot = await readDependabot(resolve(dependabotPath));
  const findings = [];
  if (dependabot === undefined) {
    findings.push(
      finding(
        "dependabot-config-missing",
        DEFAULT_DEPENDABOT_PATH,
        undefined,
        "the repository declares no .github/dependabot.yml, so no dependency-update policy is enforced",
      ),
    );
    return sortFindings(findings);
  }

  const file = DEFAULT_DEPENDABOT_PATH;
  if (dependabot.version !== 2) {
    findings.push(
      finding(
        "unsupported-version",
        file,
        undefined,
        `dependabot config version must be 2, found ${JSON.stringify(dependabot.version ?? null)}`,
      ),
    );
  }
  const updates = Array.isArray(dependabot.updates) ? dependabot.updates : [];

  // (entryKey, waivedRule) pairs that suppressed a real finding.
  const consumedWaives = new Set();
  const seenKeys = new Set();
  for (const entry of updates) {
    if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
      continue;
    }
    const key = entryKey(entry);
    seenKeys.add(key);
    const exception = Object.hasOwn(exceptions, key) ? exceptions[key] : undefined;
    const waived = new Set(exception?.waives ?? []);
    for (const item of entryFindings(file, key, entry, policy)) {
      const waiveCategory = WAIVE_BY_RULE[item.rule];
      if (waiveCategory && waived.has(waiveCategory)) {
        consumedWaives.add(`${key}\0${waiveCategory}`);
        continue;
      }
      findings.push(item);
    }
  }

  for (const [key, exception] of Object.entries(exceptions)) {
    if (!seenKeys.has(key)) {
      findings.push(
        finding(
          "exception-inventory-drift",
          file,
          key,
          "dependabot-policy exception names an updates entry that does not exist",
        ),
      );
      continue;
    }
    for (const waiveCategory of exception.waives) {
      if (!consumedWaives.has(`${key}\0${waiveCategory}`)) {
        findings.push(
          finding(
            "exception-inventory-drift",
            file,
            key,
            `waives ${JSON.stringify(waiveCategory)} but that rule is already satisfied; remove the unused waiver`,
          ),
        );
      }
    }
  }

  return sortFindings(findings);
}

function sortFindings(findings) {
  const unique = new Map();
  for (const item of findings) {
    const key = [item.file, item.entry ?? "", item.rule, item.message].join("\0");
    if (!unique.has(key)) {
      unique.set(key, item);
    }
  }
  return [...unique.values()].sort((left, right) =>
    [left.file, left.entry ?? "", left.rule, left.message]
      .join("\0")
      .localeCompare([right.file, right.entry ?? "", right.rule, right.message].join("\0")),
  );
}

function parseArguments(argv) {
  const options = {
    root: process.cwd(),
    configPath: DEFAULT_CONFIG_PATH,
    policyPath: DEFAULT_POLICY_PATH,
    json: argv.includes("--json"),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--json") {
      options.json = true;
      continue;
    }
    if (argument === "--root" || argument === "--config" || argument === "--policy") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new ConfigurationError(`${argument} requires a value`);
      }
      index += 1;
      if (argument === "--root") options.root = value;
      if (argument === "--config") options.configPath = value;
      if (argument === "--policy") options.policyPath = value;
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
      process.stdout.write("Dependabot policy passed.\n");
    } else {
      for (const item of findings) {
        const location = item.entry ? `${item.file}#${item.entry}` : item.file;
        process.stderr.write(`${location}: ${item.rule}: ${item.message}\n`);
      }
    }
    process.exitCode = findings.length === 0 ? 0 : 1;
  } catch (error) {
    const output = error instanceof Error ? error.message : String(error);
    process.stderr.write(`dependabot-policy: ${output}\n`);
    process.exitCode = 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
