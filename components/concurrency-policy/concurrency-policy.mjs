#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

import Ajv2020 from "ajv/dist/2020.js";
import { parseDocument } from "yaml";

import {
  ConfigurationError,
  parseUniqueJson,
  readOptionalJson,
  validateAgainstSchema,
} from "../runner-policy/policy-input.mjs";

export { ConfigurationError, parseUniqueJson };

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

const CANONICAL_GROUP =
  /^\$\{\{\s*github\.workflow\s*\}\}-\$\{\{\s*github\.event\.pull_request\.number\s*\|\|\s*github\.run_id\s*\}\}$/u;
const CANONICAL_GROUP_TEXT = `\${{ github.workflow }}-\${{ github.event.pull_request.number || github.run_id }}`;

const CONTRACT_ONLY_PREDICATE_TEXT = `github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('["labeled","unlabeled"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))`;

const CONTRACT_ONLY_CANCEL_TEXT = `\${{ !(${CONTRACT_ONLY_PREDICATE_TEXT}) }}`;

// GitHub cancels a pending run in the same group even with `cancel-in-progress: false`, hence the branched group:
// https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#concurrency
const FALLBACK_TERMS = ["github.ref", "github.run_id"];

function literalPattern(text) {
  return text.replaceAll(/[.*+?^${}()|[\]\\]/gu, String.raw`\$&`);
}

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

function topLevelConcurrency(workflow) {
  const concurrency = workflow.concurrency;
  if (concurrency === undefined) {
    return { present: false, malformed: false, keys: [] };
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
  return { present: true, malformed: true, keys: [] };
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
  const rawConfig = await readOptionalJson(resolvedConfig, "repository concurrency policy");
  const config =
    rawConfig === undefined
      ? { schemaVersion: 1, exceptions: {} }
      : validateAgainstSchema(rawConfig, validateConfigStructure, "concurrency policy");
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
    } else if (!record.error) {
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
  return [...uniqueFindings]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([, item]) => item);
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
