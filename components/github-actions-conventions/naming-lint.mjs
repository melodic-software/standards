#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

import Ajv2020 from "ajv/dist/2020.js";
import { isMap, isScalar, LineCounter, parseDocument } from "yaml";

export class ConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ConfigurationError";
  }
}

const MODULE_DIRECTORY = import.meta.dirname;
export const DEFAULT_VOCABULARY_PATH = path.join(MODULE_DIRECTORY, "vocabulary.json");
const VOCABULARY_SCHEMA_PATH = path.join(MODULE_DIRECTORY, "vocabulary.schema.json");
const KEBAB = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/u;
const GATE_STEM = "pr-require-checks";
const MODES = ["advisory", "enforcing"];
const FORMATS = ["text", "json", "github"];

function parseJson(source, location) {
  // The yaml parser in strict JSON mode rejects duplicate keys, which
  // JSON.parse would silently resolve to the last value.
  const document = parseDocument(source, { schema: "json", strict: true, uniqueKeys: true });
  if (document.errors.length > 0) {
    throw new ConfigurationError(`${location} is not valid JSON: ${document.errors[0].message}`);
  }
  return JSON.parse(source);
}

const validateVocabularyStructure = new Ajv2020({
  allErrors: false,
  strict: true,
  validateFormats: false,
}).compile(parseJson(await readFile(VOCABULARY_SCHEMA_PATH, "utf8"), VOCABULARY_SCHEMA_PATH));

// Cross-field rules JSON Schema cannot state: the function table is keyed by
// exactly the stage list, every function word leads with an accepted verb,
// and a name exemption says which name it accepts.
export function validateVocabulary(vocabulary, location = "vocabulary") {
  if (!validateVocabularyStructure(vocabulary)) {
    const [error] = validateVocabularyStructure.errors;
    throw new ConfigurationError(
      `${location} does not match vocabulary.schema.json: ${error.instancePath || "/"} ${error.message}`,
    );
  }
  const stages = vocabulary.stages.map((stage) => stage.name);
  if (new Set(stages).size !== stages.length) {
    throw new ConfigurationError(`${location} lists a stage twice`);
  }
  const keys = Object.keys(vocabulary.functions);
  const missing = stages.filter((stage) => !keys.includes(stage));
  const unknown = keys.filter((key) => !stages.includes(key));
  if (missing.length > 0 || unknown.length > 0) {
    throw new ConfigurationError(
      `${location} functions must be keyed by exactly the stage list ` +
        `(missing ${JSON.stringify(missing)}, unknown ${JSON.stringify(unknown)})`,
    );
  }
  const verbs = new Set(vocabulary.verbs);
  for (const [stage, functions] of Object.entries(vocabulary.functions)) {
    const names = functions.map((entry) => entry.name);
    if (new Set(names).size !== names.length) {
      throw new ConfigurationError(`${location} lists a function word twice under ${stage}`);
    }
    for (const name of names) {
      if (!verbs.has(name.split("-")[0])) {
        throw new ConfigurationError(
          `${location} function word ${stage}-${name} does not start with an accepted verb`,
        );
      }
    }
  }
  for (const exemption of vocabulary.exemptions) {
    if (exemption.rules.includes("workflow-name") && exemption.expectedName === undefined) {
      throw new ConfigurationError(
        `${location} exemption ${exemption.path} waives workflow-name without an expectedName`,
      );
    }
  }
  const appPattern = new RegExp(vocabulary.apps.pattern, "u");
  for (const app of vocabulary.apps.names) {
    if (!appPattern.test(app.name)) {
      throw new ConfigurationError(`${location} app ${app.name} does not match apps.pattern`);
    }
  }
  return vocabulary;
}

export async function loadVocabulary(file = DEFAULT_VOCABULARY_PATH) {
  let source;
  try {
    source = await readFile(file, "utf8");
  } catch (error) {
    throw new ConfigurationError(`cannot read vocabulary ${file}: ${error.message}`);
  }
  return validateVocabulary(parseJson(source, file), file);
}

function longestPrefix(candidates, text) {
  return candidates
    .filter((candidate) => text === candidate || text.startsWith(`${candidate}-`))
    .sort((left, right) => right.length - left.length)[0];
}

// Splits `<stage>-<function>[-<modifier>]`. Returns undefined members for the
// part that does not match, so callers can say which part is wrong.
export function parseSlotName(name, vocabulary) {
  const stage = longestPrefix(
    vocabulary.stages.map((entry) => entry.name),
    name,
  );
  if (stage === undefined || name === stage) {
    return { stage };
  }
  const rest = name.slice(stage.length + 1);
  const fn = longestPrefix(
    vocabulary.functions[stage].map((entry) => entry.name),
    rest,
  );
  if (fn === undefined) {
    return { stage };
  }
  const modifier = rest === fn ? undefined : rest.slice(fn.length + 1);
  return { stage, function: fn, modifier };
}

function isSlotName(name, vocabulary) {
  return KEBAB.test(name) && parseSlotName(name, vocabulary).function !== undefined;
}

function isVerbFirst(name, vocabulary) {
  return vocabulary.verbs.includes(name.split("-")[0]);
}

export function checkActivityName(name, vocabulary) {
  const grammar = vocabulary.activityGrammar;
  if (!new RegExp(grammar.pattern, "u").test(name)) {
    return `activity \`${name}\` does not match ${grammar.pattern}`;
  }
  const [activity, mode] = name.split("#");
  if (vocabulary.engines.includes(activity)) {
    return undefined;
  }
  if (mode !== undefined && !grammar.modes.flat().includes(mode)) {
    return `activity \`${name}\` uses mode \`${mode}\`, which is not one of ${grammar.modes.flat().join(", ")}`;
  }
  // Only a leading stage word repeats the slot (`pr-explainer` in slot
  // `pr-verify`). A stage word later in the name is an ordinary word, as in
  // `check-release-readiness`.
  const stage = longestPrefix(
    vocabulary.stages.map((entry) => entry.name),
    activity,
  );
  if (stage !== undefined) {
    return `activity \`${name}\` starts with the stage word \`${stage}\``;
  }
  if (!isVerbFirst(activity, vocabulary)) {
    return `activity \`${name}\` does not start with an accepted verb`;
  }
  return undefined;
}

function exemptionsFor(file, repository, vocabulary) {
  return vocabulary.exemptions.filter((exemption) => {
    if (exemption.repository !== undefined && exemption.repository !== repository) {
      return false;
    }
    return exemption.path.endsWith("*")
      ? file.startsWith(exemption.path.slice(0, -1))
      : file === exemption.path;
  });
}

function finding(level, rule, file, line, message) {
  return { level, rule, file, line, message };
}

function lineOf(lineCounter, node) {
  return node?.range ? lineCounter.linePos(node.range[0]).line : 1;
}

function checkWorkflowFilename(stem, vocabulary) {
  if (!KEBAB.test(stem)) {
    return `file name \`${stem}\` is not kebab-case`;
  }
  const parsed = parseSlotName(stem, vocabulary);
  if (parsed.stage === undefined) {
    return (
      `file name \`${stem}\` must start with a stage word ` +
      `(${vocabulary.stages.map((entry) => entry.name).join(", ")})`
    );
  }
  if (parsed.function === undefined) {
    const allowed = vocabulary.functions[parsed.stage].map((entry) => entry.name);
    return (
      `file name \`${stem}\` has no function word allowed for stage \`${parsed.stage}\`` +
      (allowed.length > 0 ? ` (${allowed.join(", ")})` : " (the stage has none yet)")
    );
  }
  return undefined;
}

function checkJobId(file, id, line, vocabulary) {
  if (!KEBAB.test(id)) {
    return finding("error", "job-id-kebab", file, line, `job id \`${id}\` is not kebab-case`);
  }
  if (
    vocabulary.reservedJobIds.includes(id) ||
    vocabulary.engines.includes(id) ||
    vocabulary.toolNames.includes(id) ||
    isSlotName(id, vocabulary)
  ) {
    return undefined;
  }
  const stage = longestPrefix(
    vocabulary.stages.map((entry) => entry.name),
    id,
  );
  if (stage !== undefined) {
    return finding(
      "warning",
      "job-id-stage-word",
      file,
      line,
      `job id \`${id}\` starts with the stage word \`${stage}\` but is not a known slot; ` +
        "a caller job id is the full slot name, and an activity carries no stage word",
    );
  }
  if (isVerbFirst(id, vocabulary)) {
    return undefined;
  }
  return finding(
    "warning",
    "job-id-verb-first",
    file,
    line,
    `job id \`${id}\` does not start with an accepted verb and is not a listed tool, engine ` +
      "or reserved id; name it for what it does, verb first",
  );
}

async function workflowFindings(root, repository, vocabulary) {
  const directory = path.join(root, ".github", "workflows");
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
  const findings = [];
  for (const entry of entries
    .filter((candidate) => candidate.isFile() && /\.ya?ml$/u.test(candidate.name))
    .sort((left, right) => left.name.localeCompare(right.name))) {
    const file = `.github/workflows/${entry.name}`;
    const exemptions = exemptionsFor(file, repository, vocabulary);
    const waived = (rule) =>
      exemptions.find(
        (exemption) => exemption.rules.includes("*") || exemption.rules.includes(rule),
      );
    if (waived("*")?.rules.includes("*")) {
      continue;
    }
    const stem = entry.name.replace(/\.ya?ml$/u, "");
    const filenameProblem = checkWorkflowFilename(stem, vocabulary);
    if (filenameProblem !== undefined && !waived("workflow-filename")) {
      findings.push(finding("error", "workflow-filename", file, 1, filenameProblem));
    }

    const lineCounter = new LineCounter();
    const document = parseDocument(await readFile(path.join(directory, entry.name), "utf8"), {
      lineCounter,
    });
    if (document.errors.length > 0 || !isMap(document.contents)) {
      findings.push(
        finding(
          "error",
          "workflow-unparsable",
          file,
          1,
          `workflow could not be parsed: ${document.errors[0]?.message ?? "top level is not a mapping"}`,
        ),
      );
      continue;
    }

    const nameNode = document.contents.get("name", true);
    const name = isScalar(nameNode) ? String(nameNode.value) : undefined;
    const nameExemption = waived("workflow-name");
    const expectedName = nameExemption?.expectedName ?? stem;
    if (name !== expectedName) {
      findings.push(
        finding(
          "error",
          "workflow-name",
          file,
          lineOf(lineCounter, nameNode),
          name === undefined
            ? `workflow has no \`name:\`; set it to the file stem \`${expectedName}\``
            : `workflow \`name: ${name}\` must equal ${nameExemption ? "the recorded exception" : "the file stem"} \`${expectedName}\``,
        ),
      );
    }

    const jobs = document.contents.get("jobs", true);
    const jobIds = [];
    if (isMap(jobs)) {
      for (const pair of jobs.items) {
        const id = String(pair.key?.value ?? pair.key);
        jobIds.push(id);
        const item = checkJobId(file, id, lineOf(lineCounter, pair.key), vocabulary);
        if (item !== undefined) {
          findings.push(item);
        }
      }
    }
    if (stem === GATE_STEM && !jobIds.some((id) => vocabulary.reservedJobIds.includes(id))) {
      findings.push(
        finding(
          "error",
          "gate-ci-status",
          file,
          1,
          `the gate workflow must keep the job ${vocabulary.reservedJobIds.map((id) => `\`${id}\``).join(", ")}, the only required check`,
        ),
      );
    }
  }
  return findings;
}

async function actionDirectories(root) {
  const base = path.join(root, ".github", "actions");
  const found = [];
  async function walk(relative) {
    let entries;
    try {
      entries = await readdir(path.join(base, relative), { withFileTypes: true });
    } catch (error) {
      if (error.code === "ENOENT") {
        return;
      }
      throw error;
    }
    const metadata = entries.find(
      (entry) => entry.isFile() && (entry.name === "action.yml" || entry.name === "action.yaml"),
    );
    if (metadata !== undefined && relative !== "") {
      found.push({ segments: relative.split("/"), metadata: metadata.name });
    }
    for (const entry of entries) {
      if (entry.isDirectory() && entry.name !== "node_modules" && !entry.name.startsWith(".")) {
        await walk(relative === "" ? entry.name : `${relative}/${entry.name}`);
      }
    }
  }
  await walk("");
  return found.sort((left, right) =>
    left.segments.join("/").localeCompare(right.segments.join("/")),
  );
}

function checkActionDirectory(segments, vocabulary) {
  const display = `.github/actions/${segments.join("/")}`;
  const badSegment = segments.find((segment) => !KEBAB.test(segment));
  if (badSegment !== undefined) {
    return `action directory \`${display}\` has a segment \`${badSegment}\` that is not kebab-case`;
  }
  const unitOk = (unit) =>
    isVerbFirst(unit, vocabulary) ||
    vocabulary.toolNames.includes(unit) ||
    vocabulary.engines.includes(unit);
  if (segments.length === 1) {
    return unitOk(segments[0])
      ? undefined
      : `action directory \`${display}\` must be verb-first, an engine, or the name of the one tool it wraps`;
  }
  if (segments.length === 2) {
    const [lane, unit] = segments;
    if (!isSlotName(lane, vocabulary)) {
      return `action directory \`${display}\`: \`${lane}\` is not a lane slot name (\`<stage>-<function>\`)`;
    }
    return unitOk(unit)
      ? undefined
      : `action directory \`${display}\`: unit \`${unit}\` must be verb-first, an engine, or the name of the one tool it wraps`;
  }
  return `action directory \`${display}\` is nested too deep; use \`.github/actions/<lane>/<unit>/\` or a flat directory`;
}

export async function lintRepository({
  root = process.cwd(),
  repository = "",
  vocabulary,
  mode = "advisory",
} = {}) {
  if (!MODES.includes(mode)) {
    throw new ConfigurationError(`mode must be one of ${MODES.join(", ")}`);
  }
  const words = vocabulary ?? (await loadVocabulary());
  const resolvedRoot = path.resolve(root);
  const findings = await workflowFindings(resolvedRoot, repository, words);
  for (const { segments, metadata } of await actionDirectories(resolvedRoot)) {
    const problem = checkActionDirectory(segments, words);
    if (problem !== undefined) {
      findings.push(
        finding(
          "error",
          "action-directory",
          `.github/actions/${segments.join("/")}/${metadata}`,
          1,
          problem,
        ),
      );
    }
  }
  if (mode === "advisory") {
    for (const item of findings) {
      item.level = "warning";
    }
  }
  return findings.sort((left, right) =>
    [left.file, String(left.line).padStart(6, "0"), left.rule]
      .join("\0")
      .localeCompare([right.file, String(right.line).padStart(6, "0"), right.rule].join("\0")),
  );
}

function escapeData(text) {
  return text.replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");
}

function escapeProperty(text) {
  return escapeData(text).replaceAll(":", "%3A").replaceAll(",", "%2C");
}

export function formatAnnotation(item) {
  return (
    `::${item.level} file=${escapeProperty(item.file)},line=${item.line},` +
    `title=${escapeProperty(`naming-lint ${item.rule}`)}::${escapeData(item.message)}`
  );
}

export function parseArguments(argv, environment = process.env) {
  try {
    const { values } = parseArgs({
      args: argv,
      allowPositionals: false,
      options: {
        format: {
          default: environment.GITHUB_ACTIONS === "true" ? "github" : "text",
          type: "string",
        },
        mode: { default: "advisory", type: "string" },
        repository: { default: environment.GITHUB_REPOSITORY ?? "", type: "string" },
        root: { default: process.cwd(), type: "string" },
        vocabulary: { default: DEFAULT_VOCABULARY_PATH, type: "string" },
      },
      strict: true,
    });
    if (!MODES.includes(values.mode)) {
      throw new Error(`--mode must be one of ${MODES.join(", ")}`);
    }
    if (!FORMATS.includes(values.format)) {
      throw new Error(`--format must be one of ${FORMATS.join(", ")}`);
    }
    return values;
  } catch (error) {
    throw new ConfigurationError(error instanceof Error ? error.message : String(error));
  }
}

async function main() {
  try {
    const options = parseArguments(process.argv.slice(2));
    const vocabulary = await loadVocabulary(options.vocabulary);
    const findings = await lintRepository({ ...options, vocabulary });
    const errors = findings.filter((item) => item.level === "error").length;
    if (options.format === "json") {
      process.stdout.write(
        `${JSON.stringify({ mode: options.mode, ok: errors === 0, findings }, null, 2)}\n`,
      );
    } else {
      for (const item of findings) {
        process.stdout.write(
          options.format === "github"
            ? `${formatAnnotation(item)}\n`
            : `${item.file}:${item.line}: ${item.level}: ${item.rule}: ${item.message}\n`,
        );
      }
      process.stdout.write(
        `naming-lint (${options.mode}): ${findings.length} finding(s), ${errors} blocking.\n`,
      );
    }
    process.exitCode = errors > 0 ? 1 : 0;
  } catch (error) {
    process.stderr.write(`naming-lint: ${error instanceof Error ? error.message : error}\n`);
    process.exitCode = 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
