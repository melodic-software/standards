#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

import Ajv2020 from "ajv/dist/2020.js";
import { isMap, isScalar, isSeq, LineCounter, parseDocument } from "yaml";

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
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new ConfigurationError(`${location} is not valid JSON: ${error.message}`);
  }
}

function compilePattern(pattern, location) {
  try {
    return new RegExp(pattern, "u");
  } catch (error) {
    throw new ConfigurationError(`${location} is not a valid regular expression: ${error.message}`);
  }
}

// A schema that cannot be read or compiled is a configuration error, reported
// when a vocabulary is validated so the CLI maps it to exit status 2.
let validateVocabularyStructure;
let schemaError;
try {
  validateVocabularyStructure = new Ajv2020({
    allErrors: false,
    strict: true,
    validateFormats: false,
  }).compile(parseJson(await readFile(VOCABULARY_SCHEMA_PATH, "utf8"), VOCABULARY_SCHEMA_PATH));
} catch (error) {
  schemaError =
    error instanceof ConfigurationError
      ? error
      : new ConfigurationError(`cannot load ${VOCABULARY_SCHEMA_PATH}: ${error.message}`);
}

// Cross-field rules JSON Schema cannot state: the function table is keyed by
// exactly the stage list, every function word leads with an accepted verb,
// and a name exemption says which name it accepts.
export function validateVocabulary(vocabulary, location = "vocabulary") {
  if (schemaError !== undefined) {
    throw schemaError;
  }
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
  compilePattern(vocabulary.activityGrammar.pattern, `${location} activityGrammar.pattern`);
  const appPattern = compilePattern(vocabulary.apps.pattern, `${location} apps.pattern`);
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

// A file or directory stem's display name: hyphens become spaces, each word is
// capitalized, and a word in `displayWords` takes its listed form.
export function titleCaseName(stem, displayWords) {
  return stem
    .split("-")
    .map((word) =>
      Object.hasOwn(displayWords, word)
        ? displayWords[word]
        : word.charAt(0).toUpperCase() + word.slice(1).toLowerCase(),
    )
    .join(" ");
}

// The words of a display name, with `${{ }}` expressions and backtick spans
// removed and surrounding punctuation and a possessive `'s` trimmed.
function displayTokens(name) {
  return name
    .replace(/\$\{\{.*?\}\}/gu, " ")
    .replace(/`[^`]*`/gu, " ")
    .split(/\s+/u)
    .map((token) => token.replace(/^[^\p{L}\p{N}.]+|[^\p{L}\p{N}]+$/gu, "").replace(/'s$/u, ""))
    .filter((token) => token !== "");
}

function knownNames(vocabulary) {
  return new Set([
    ...Object.values(vocabulary.displayWords),
    ...vocabulary.properNouns.filter((noun) => !noun.includes(" ")),
    ...vocabulary.toolNames,
    ...vocabulary.engines,
  ]);
}

// A job's display name is Title Case: every word starts with a capital letter
// or a digit, or is a `displayWords` form (`markdownlint`, `yq`).
export function checkJobName(id, name, vocabulary) {
  const exception = vocabulary.jobNameExceptions.find((entry) => entry.jobId === id);
  if (exception !== undefined) {
    return name === exception.name
      ? undefined
      : `job \`${id}\` is a recorded exception and must be named exactly \`${exception.name}\``;
  }
  const suggestion = titleCaseName(id, vocabulary.displayWords);
  if (name === undefined) {
    return `job \`${id}\` has no \`name:\`; give it a Title Case display name such as \`${suggestion}\``;
  }
  // The required check's context is this job's name, so it is fixed.
  if (vocabulary.reservedJobIds.includes(id) && name !== suggestion) {
    return `job \`${id}\` is the required check and must be named exactly \`${suggestion}\``;
  }
  const displayForms = new Set(Object.values(vocabulary.displayWords));
  const lower = displayTokens(name).filter(
    (token) => /^\p{Ll}/u.test(token) && !displayForms.has(token),
  );
  if (lower.length > 0) {
    return `job \`${id}\` name \`${name}\` is not Title Case (${lower.map((token) => `\`${token}\``).join(", ")}); for example \`${suggestion}\``;
  }
  return undefined;
}

// A step name is sentence case, as GitHub's own steps are (`Set up job`): the
// first word is capitalized unless it is a known lowercase name or an
// identifier, and a later capitalized word is a proper noun from the
// vocabulary, an acronym, or a mixed-case identifier.
export function checkStepName(name, vocabulary) {
  const known = knownNames(vocabulary);
  const tokens = displayTokens(name);
  // A multi-word proper noun exempts its words where they appear together,
  // and only there: `Claude Code` passes, `Code` alone does not.
  const exempt = tokens.map((token) => known.has(token));
  for (const noun of vocabulary.properNouns.filter((entry) => entry.includes(" "))) {
    const words = noun.split(" ");
    for (let start = 0; start + words.length <= tokens.length; start += 1) {
      if (words.every((word, offset) => tokens[start + offset] === word)) {
        words.forEach((_, offset) => {
          exempt[start + offset] = true;
        });
      }
    }
  }
  const [first] = tokens;
  // A name that opens with an expression or a code span has no checked first
  // word: the token after it is not where the sentence starts.
  const opensWithSpan = /^\s*(\$\{\{|`)/u.test(name);
  if (first !== undefined && !opensWithSpan && !exempt[0] && /^\p{Ll}+$/u.test(first)) {
    return `step name \`${name}\` must start with a capital letter (sentence case)`;
  }
  const capitalized = tokens.filter(
    (token, index) => index > 0 && !exempt[index] && /^\p{Lu}\p{Ll}+$/u.test(token),
  );
  if (capitalized.length > 0) {
    return (
      `step name \`${name}\` is not sentence case: ${capitalized.map((token) => `\`${token}\``).join(", ")} ` +
      "is capitalized; lower-case it, or add the proper noun to `properNouns`"
    );
  }
  return undefined;
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
  if (mode !== undefined && !grammar.modes.flat().includes(mode)) {
    return `activity \`${name}\` uses mode \`${mode}\`, which is not one of ${grammar.modes.flat().join(", ")}`;
  }
  if (vocabulary.engines.includes(activity)) {
    return undefined;
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

function stepFindings(file, steps, lineCounter, vocabulary) {
  if (!isSeq(steps)) {
    return [];
  }
  const findings = [];
  for (const step of steps.items) {
    const nameNode = isMap(step) ? step.get("name", true) : undefined;
    if (!isScalar(nameNode)) {
      continue;
    }
    const problem = checkStepName(String(nameNode.value), vocabulary);
    if (problem !== undefined) {
      findings.push(
        finding(
          vocabulary.displayNameLevel,
          "step-name",
          file,
          lineOf(lineCounter, nameNode),
          problem,
        ),
      );
    }
  }
  return findings;
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
    if (exemptions.some((exemption) => exemption.rules.includes("*"))) {
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
    const titleCase = titleCaseName(stem, vocabulary.displayWords);
    // A recorded exception is exact: it takes neither the stem nor its Title
    // Case form.
    const expected = nameExemption ? nameExemption.expectedName : titleCase;
    if (name !== expected) {
      const target = nameExemption
        ? `the recorded exception \`${expected}\``
        : `the Title Case form of the file stem, \`${titleCase}\``;
      findings.push(
        finding(
          "error",
          "workflow-name",
          file,
          lineOf(lineCounter, nameNode),
          name === undefined
            ? `workflow has no \`name:\`; set it to ${target}`
            : `workflow \`name: ${name}\` must equal ${target}`,
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
        const job = isMap(pair.value) ? pair.value : undefined;
        const jobNameNode = job?.get("name", true);
        const jobNameProblem = checkJobName(
          id,
          isScalar(jobNameNode) ? String(jobNameNode.value) : undefined,
          vocabulary,
        );
        if (jobNameProblem !== undefined) {
          findings.push(
            finding(
              vocabulary.displayNameLevel,
              "job-name",
              file,
              lineOf(lineCounter, jobNameNode ?? pair.key),
              jobNameProblem,
            ),
          );
        }
        findings.push(...stepFindings(file, job?.get("steps", true), lineCounter, vocabulary));
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

// An action's `name:` is its directory's Title Case form, and its composite
// steps follow the step-name rule.
async function actionMetadataFindings(root, file, directory, vocabulary) {
  const lineCounter = new LineCounter();
  const document = parseDocument(await readFile(path.join(root, file), "utf8"), { lineCounter });
  if (document.errors.length > 0 || !isMap(document.contents)) {
    return [
      finding(
        "error",
        "action-unparsable",
        file,
        1,
        `action metadata could not be parsed: ${document.errors[0]?.message ?? "top level is not a mapping"}`,
      ),
    ];
  }
  const findings = [];
  const nameNode = document.contents.get("name", true);
  const name = isScalar(nameNode) ? String(nameNode.value) : undefined;
  const expected = titleCaseName(directory, vocabulary.displayWords);
  if (name !== expected) {
    findings.push(
      finding(
        "error",
        "action-name",
        file,
        lineOf(lineCounter, nameNode),
        name === undefined
          ? `action has no \`name:\`; set it to the Title Case form of its directory, \`${expected}\``
          : `action \`name: ${name}\` must equal the Title Case form of its directory, \`${expected}\``,
      ),
    );
  }
  const runs = document.contents.get("runs", true);
  findings.push(
    ...stepFindings(
      file,
      isMap(runs) ? runs.get("steps", true) : undefined,
      lineCounter,
      vocabulary,
    ),
  );
  return findings;
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
    const file = `.github/actions/${segments.join("/")}/${metadata}`;
    const problem = checkActionDirectory(segments, words);
    if (problem !== undefined) {
      findings.push(finding("error", "action-directory", file, 1, problem));
    }
    findings.push(...(await actionMetadataFindings(resolvedRoot, file, segments.at(-1), words)));
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
