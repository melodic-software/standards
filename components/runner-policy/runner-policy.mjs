#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { parseDocument } from "yaml";

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_POLICY_PATH = path.join(MODULE_DIRECTORY, "policy.json");
const DEFAULT_CONFIG_PATH = ".github/runner-policy.json";
const RUNNER_OUTPUT = /^\s*\$\{\{\s*needs\.([A-Za-z0-9_-]+)\.outputs\.runner\s*}}\s*$/;
const MATRIX_OUTPUT = /^\$\{\{ matrix\.([A-Za-z0-9_-]+) }}$/;
const FULL_SHA = /^[0-9a-f]{40}$/i;
const REUSABLE_WORKFLOW_PATH =
  /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml$/;

class ConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ConfigurationError";
  }
}

function assertPlainObject(value, location) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ConfigurationError(`${location} must be an object`);
  }
}

function assertExactKeys(value, allowed, location) {
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unknown.length > 0) {
    throw new ConfigurationError(`${location} has unknown properties: ${unknown.join(", ")}`);
  }
}

function assertStringArray(value, location, { allowEmpty = false } = {}) {
  if (
    !Array.isArray(value) ||
    (!allowEmpty && value.length === 0) ||
    value.some((item) => typeof item !== "string" || item.trim() === "")
  ) {
    throw new ConfigurationError(`${location} must be a non-empty array of non-empty strings`);
  }
  if (new Set(value).size !== value.length) {
    throw new ConfigurationError(`${location} must not contain duplicates`);
  }
}

function assertStringMap(value, location, { allowEmpty = false } = {}) {
  assertPlainObject(value, location);
  if (!allowEmpty && Object.keys(value).length === 0) {
    throw new ConfigurationError(`${location} must not be empty`);
  }
  for (const [key, item] of Object.entries(value)) {
    if (key.trim() === "" || typeof item !== "string" || item.trim() === "") {
      throw new ConfigurationError(`${location} must map non-empty keys to non-empty strings`);
    }
  }
}

function validatePolicy(value) {
  assertPlainObject(value, "policy");
  assertExactKeys(
    value,
    [
      "schemaVersion",
      "selectorWorkflowPaths",
      "approvedSelectorReferences",
      "approvedReusableWorkflowContracts",
      "canonicalSelectorInputs",
      "optionalCanonicalSelectorInputs",
      "canonicalSelectorSecrets",
      "approvedHostedRunnerLabels",
      "hostedMatrixExpressions",
      "governedReusableRunnerInput",
      "forbiddenHostedRunnerLabels",
      "managedLabelPatterns",
      "hostedExceptionReasons",
    ],
    "policy",
  );
  if (value.schemaVersion !== 1) {
    throw new ConfigurationError("policy.schemaVersion must be 1");
  }
  assertStringArray(value.selectorWorkflowPaths, "policy.selectorWorkflowPaths");
  if (value.selectorWorkflowPaths.some((workflow) => !REUSABLE_WORKFLOW_PATH.test(workflow))) {
    throw new ConfigurationError(
      "policy.selectorWorkflowPaths must contain only owner/repository/.github/workflows/<file>.yml paths",
    );
  }
  if (!Array.isArray(value.approvedSelectorReferences)) {
    throw new ConfigurationError("policy.approvedSelectorReferences must be an array");
  }
  if (
    value.approvedSelectorReferences.some(
      (reference) => typeof reference !== "string" || reference.trim() === "",
    )
  ) {
    throw new ConfigurationError(
      "policy.approvedSelectorReferences must contain only non-empty strings",
    );
  }
  if (new Set(value.approvedSelectorReferences).size !== value.approvedSelectorReferences.length) {
    throw new ConfigurationError("policy.approvedSelectorReferences must not contain duplicates");
  }
  assertPlainObject(
    value.approvedReusableWorkflowContracts,
    "policy.approvedReusableWorkflowContracts",
  );
  assertStringMap(value.canonicalSelectorInputs, "policy.canonicalSelectorInputs");
  assertStringMap(value.optionalCanonicalSelectorInputs, "policy.optionalCanonicalSelectorInputs", {
    allowEmpty: true,
  });
  assertStringMap(value.canonicalSelectorSecrets, "policy.canonicalSelectorSecrets");
  assertStringArray(value.approvedHostedRunnerLabels, "policy.approvedHostedRunnerLabels");
  assertStringArray(value.hostedMatrixExpressions, "policy.hostedMatrixExpressions");
  assertPlainObject(value.governedReusableRunnerInput, "policy.governedReusableRunnerInput");
  assertExactKeys(
    value.governedReusableRunnerInput,
    ["name", "expression", "default"],
    "policy.governedReusableRunnerInput",
  );
  for (const property of ["name", "expression", "default"]) {
    if (
      typeof value.governedReusableRunnerInput[property] !== "string" ||
      value.governedReusableRunnerInput[property].trim() === ""
    ) {
      throw new ConfigurationError(
        `policy.governedReusableRunnerInput.${property} must be a non-empty string`,
      );
    }
  }
  assertStringArray(value.forbiddenHostedRunnerLabels, "policy.forbiddenHostedRunnerLabels");
  assertStringArray(value.managedLabelPatterns, "policy.managedLabelPatterns");
  assertStringArray(value.hostedExceptionReasons, "policy.hostedExceptionReasons");

  const approvedHostedRunnerLabels = new Set(value.approvedHostedRunnerLabels);
  const forbiddenHostedRunnerLabels = new Set(
    value.forbiddenHostedRunnerLabels.map((label) => label.toLowerCase()),
  );
  const knownGitHubHostedRunnerLabels = new Set([
    ...value.approvedHostedRunnerLabels.map((label) => label.toLowerCase()),
    ...forbiddenHostedRunnerLabels,
  ]);

  const managedLabelRegexes = value.managedLabelPatterns.map((pattern, index) => {
    try {
      return new RegExp(pattern, "i");
    } catch (error) {
      throw new ConfigurationError(
        `policy.managedLabelPatterns[${index}] is not a valid regular expression: ${error.message}`,
      );
    }
  });

  const selectorWorkflowPaths = new Set(value.selectorWorkflowPaths);
  for (const reference of value.approvedSelectorReferences) {
    const parsed = parseReusableWorkflowReference(reference);
    if (!parsed || !selectorWorkflowPaths.has(parsed.workflow) || !FULL_SHA.test(parsed.revision)) {
      throw new ConfigurationError(
        `policy.approvedSelectorReferences entry ${JSON.stringify(reference)} must be an approved selector path pinned to a full 40-character SHA`,
      );
    }
  }

  const approvedReusableWorkflowContracts = new Map();
  for (const [reference, contract] of Object.entries(value.approvedReusableWorkflowContracts)) {
    const parsed = parseReusableWorkflowReference(reference);
    if (
      !parsed ||
      !REUSABLE_WORKFLOW_PATH.test(parsed.workflow) ||
      !FULL_SHA.test(parsed.revision) ||
      selectorWorkflowPaths.has(parsed.workflow)
    ) {
      throw new ConfigurationError(
        `policy.approvedReusableWorkflowContracts key ${JSON.stringify(reference)} must be a non-selector reusable workflow path pinned to a full 40-character SHA`,
      );
    }
    assertPlainObject(contract, `reusable workflow contract ${reference}`);
    assertExactKeys(
      contract,
      ["routing", "runnerInput", "allowedInputs", "fixedRunsOn"],
      `reusable workflow contract ${reference}`,
    );
    if (!new Set(["hosted-only", "runner-input"]).has(contract.routing)) {
      throw new ConfigurationError(
        `reusable workflow contract ${reference}.routing must be hosted-only or runner-input`,
      );
    }
    assertStringArray(
      contract.allowedInputs,
      `reusable workflow contract ${reference}.allowedInputs`,
      { allowEmpty: true },
    );
    if (contract.routing === "runner-input") {
      if (
        typeof contract.runnerInput !== "string" ||
        !/^[A-Za-z][A-Za-z0-9_-]*$/.test(contract.runnerInput)
      ) {
        throw new ConfigurationError(
          `reusable workflow contract ${reference}.runnerInput must be a canonical input name`,
        );
      }
      if (!contract.allowedInputs.includes(contract.runnerInput)) {
        throw new ConfigurationError(
          `reusable workflow contract ${reference}.allowedInputs must include ${contract.runnerInput}`,
        );
      }
      if (Object.hasOwn(contract, "fixedRunsOn")) {
        throw new ConfigurationError(
          `runner-input reusable workflow contract ${reference} cannot declare fixedRunsOn`,
        );
      }
    } else {
      if (Object.hasOwn(contract, "runnerInput")) {
        throw new ConfigurationError(
          `hosted-only reusable workflow contract ${reference} cannot declare runnerInput`,
        );
      }
      assertStringArray(
        contract.fixedRunsOn,
        `reusable workflow contract ${reference}.fixedRunsOn`,
      );
      const unknownLabel = contract.fixedRunsOn.find(
        (label) => !knownGitHubHostedRunnerLabels.has(label.toLowerCase()),
      );
      if (unknownLabel) {
        throw new ConfigurationError(
          `hosted-only reusable workflow contract ${reference}.fixedRunsOn contains unrecognized GitHub-hosted label ${unknownLabel}`,
        );
      }
    }
    approvedReusableWorkflowContracts.set(reference, {
      routing: contract.routing,
      ...(contract.runnerInput ? { runnerInput: contract.runnerInput } : {}),
      allowedInputs: new Set(contract.allowedInputs),
      ...(contract.fixedRunsOn ? { fixedRunsOn: new Set(contract.fixedRunsOn) } : {}),
    });
  }

  const canonicalInputNames = new Set(Object.keys(value.canonicalSelectorInputs));
  for (const name of Object.keys(value.optionalCanonicalSelectorInputs)) {
    if (canonicalInputNames.has(name)) {
      throw new ConfigurationError(
        `policy optional selector input ${name} duplicates a required canonical input`,
      );
    }
  }

  if (!approvedHostedRunnerLabels.has(value.governedReusableRunnerInput.default)) {
    throw new ConfigurationError(
      "policy.governedReusableRunnerInput.default must be an approved hosted runner label",
    );
  }
  const hostedMatrixAxes = new Map();
  for (const expression of value.hostedMatrixExpressions) {
    const match = MATRIX_OUTPUT.exec(expression);
    if (!match) {
      throw new ConfigurationError(
        `policy.hostedMatrixExpressions entry ${JSON.stringify(expression)} must use the exact form \${{ matrix.<axis> }}`,
      );
    }
    if (hostedMatrixAxes.has(match[1])) {
      throw new ConfigurationError(
        `policy.hostedMatrixExpressions contains duplicate matrix axis ${match[1]}`,
      );
    }
    hostedMatrixAxes.set(match[1], expression);
  }

  return {
    ...value,
    selectorWorkflowPaths,
    approvedSelectorReferences: new Set(value.approvedSelectorReferences),
    approvedReusableWorkflowContracts,
    canonicalSelectorInputNames: new Set([
      ...Object.keys(value.canonicalSelectorInputs),
      ...Object.keys(value.optionalCanonicalSelectorInputs),
    ]),
    canonicalSelectorSecretNames: new Set(Object.keys(value.canonicalSelectorSecrets)),
    approvedHostedRunnerLabels,
    hostedMatrixAxes,
    forbiddenHostedRunnerLabels,
    hostedExceptionReasons: new Set(value.hostedExceptionReasons),
    managedLabelRegexes,
  };
}

function validateRepositoryConfig(value, policy) {
  assertPlainObject(value, "repository config");
  assertExactKeys(
    value,
    ["schemaVersion", "visibility", "selfHostedCi", "exceptions"],
    "repository config",
  );
  if (value.schemaVersion !== 1) {
    throw new ConfigurationError("repository config schemaVersion must be 1");
  }
  if (!new Set(["public", "private"]).has(value.visibility)) {
    throw new ConfigurationError('repository config visibility must be "public" or "private"');
  }
  if (typeof value.selfHostedCi !== "boolean") {
    throw new ConfigurationError("repository config selfHostedCi must be a boolean");
  }
  if (value.visibility === "public" && value.selfHostedCi) {
    throw new ConfigurationError("public repositories cannot enable selfHostedCi");
  }
  assertPlainObject(value.exceptions, "repository config exceptions");

  const exceptions = new Map();
  for (const [key, exception] of Object.entries(value.exceptions)) {
    if (!/^\.github\/workflows\/[^/#]+\.ya?ml#[A-Za-z0-9_-]+$/.test(key)) {
      throw new ConfigurationError(
        `exception key ${JSON.stringify(key)} must be .github/workflows/<file>.yml#<job-id>`,
      );
    }
    assertPlainObject(exception, `exception ${key}`);
    assertExactKeys(exception, ["reason", "justification"], `exception ${key}`);
    if (
      typeof exception.reason !== "string" ||
      !policy.hostedExceptionReasons.has(exception.reason)
    ) {
      throw new ConfigurationError(
        `exception ${key} reason must be one of: ${[...policy.hostedExceptionReasons].join(", ")}`,
      );
    }
    if (typeof exception.justification !== "string" || exception.justification.trim() === "") {
      throw new ConfigurationError(`exception ${key} justification must be a non-empty string`);
    }
    exceptions.set(key, exception);
  }

  return { ...value, exceptions };
}

async function readJson(filePath, location) {
  let source;
  try {
    source = await readFile(filePath, "utf8");
  } catch (error) {
    throw new ConfigurationError(`${location} could not be read at ${filePath}: ${error.message}`);
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new ConfigurationError(`${location} is not valid JSON: ${error.message}`);
  }
}

function parseWorkflow(source, file) {
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
    throw new Error(`${file} must contain a workflow mapping`);
  }
  if (workflow.jobs === null || typeof workflow.jobs !== "object" || Array.isArray(workflow.jobs)) {
    throw new Error(`${file} must contain a jobs mapping`);
  }
  return workflow;
}

function stringsIn(value) {
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value)) {
    return value.flatMap(stringsIn);
  }
  if (value !== null && typeof value === "object") {
    return Object.values(value).flatMap(stringsIn);
  }
  return [];
}

function normalizeNeeds(value) {
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value) && value.every((item) => typeof item === "string")) {
    return value;
  }
  return [];
}

function parseReusableWorkflowReference(value) {
  if (typeof value !== "string") {
    return undefined;
  }
  const separator = value.lastIndexOf("@");
  if (separator < 1) {
    return undefined;
  }
  return { workflow: value.slice(0, separator), revision: value.slice(separator + 1) };
}

function exactCanonicalMap(actual, required, optional, allowedNames, location) {
  if (actual === null || typeof actual !== "object" || Array.isArray(actual)) {
    return `${location} must be an explicit mapping`;
  }
  const actualNames = Object.keys(actual);
  const unexpected = actualNames.filter((name) => !allowedNames.has(name));
  if (unexpected.length > 0) {
    return `${location} has unapproved properties: ${unexpected.join(", ")}`;
  }
  for (const [name, expected] of Object.entries(required)) {
    if (actual[name] !== expected) {
      return `${location}.${name} must be exactly ${JSON.stringify(expected)}`;
    }
  }
  for (const [name, expected] of Object.entries(optional)) {
    if (Object.hasOwn(actual, name) && actual[name] !== expected) {
      return `${location}.${name} must be exactly ${JSON.stringify(expected)}`;
    }
  }
  return undefined;
}

function selectorStatus(job, policy) {
  const reference = parseReusableWorkflowReference(job?.uses);
  if (!reference || !policy.selectorWorkflowPaths.has(reference.workflow)) {
    return { isSelector: false, approved: false };
  }
  if (!FULL_SHA.test(reference.revision)) {
    return {
      approved: false,
      isSelector: true,
      reason: "the selector reusable workflow must be pinned to a full 40-character SHA",
    };
  }
  if (!policy.approvedSelectorReferences.has(job.uses)) {
    return {
      approved: false,
      isSelector: true,
      reason:
        policy.approvedSelectorReferences.size === 0
          ? "no reviewed selector path@SHA is currently approved"
          : "the selector path@SHA is not in the reviewed approval allowlist",
    };
  }
  if (job.secrets === "inherit") {
    return {
      approved: false,
      isSelector: true,
      reason: "the selector must not use secrets: inherit",
    };
  }
  if (job.secrets === null || typeof job.secrets !== "object" || Array.isArray(job.secrets)) {
    return {
      approved: false,
      isSelector: true,
      reason: "the selector must receive an explicit observer-private-key secret",
    };
  }
  const secretError = exactCanonicalMap(
    job.secrets,
    policy.canonicalSelectorSecrets,
    {},
    policy.canonicalSelectorSecretNames,
    "selector secrets",
  );
  if (secretError) {
    return {
      approved: false,
      isSelector: true,
      reason: secretError,
    };
  }
  const inputError = exactCanonicalMap(
    job.with,
    policy.canonicalSelectorInputs,
    policy.optionalCanonicalSelectorInputs,
    policy.canonicalSelectorInputNames,
    "selector inputs",
  );
  if (inputError) {
    return {
      approved: false,
      isSelector: true,
      reason: inputError,
    };
  }
  return { approved: true, isSelector: true };
}

function reusableWorkflowStatus(job, policy) {
  if (typeof job?.uses !== "string") {
    return { isReusable: false, approved: false };
  }
  const contract = policy.approvedReusableWorkflowContracts.get(job.uses);
  if (!contract) {
    return {
      isReusable: true,
      approved: false,
      reason: "the reusable workflow path@SHA has no reviewed runner-input contract",
    };
  }
  const inputs = job.with === undefined ? {} : job.with;
  if (inputs === null || typeof inputs !== "object" || Array.isArray(inputs)) {
    return {
      isReusable: true,
      approved: false,
      reason: "the reviewed reusable workflow inputs must be an explicit mapping",
    };
  }
  const unexpected = Object.keys(inputs).filter((name) => !contract.allowedInputs.has(name));
  if (unexpected.length > 0) {
    return {
      isReusable: true,
      approved: false,
      reason: `the reusable workflow call has inputs absent from its reviewed contract: ${unexpected.join(", ")}`,
    };
  }
  if (contract.routing === "hosted-only") {
    return { isReusable: true, approved: true, contract };
  }
  if (!Object.hasOwn(inputs, contract.runnerInput)) {
    return {
      isReusable: true,
      approved: false,
      reason: `the reviewed reusable workflow must receive its ${contract.runnerInput} input explicitly`,
    };
  }
  return { isReusable: true, approved: true, contract };
}

function routeStatus(jobId, target, job, jobs, policy) {
  const match = RUNNER_OUTPUT.exec(target);
  if (!match) {
    return {
      attempted: target.includes("outputs.runner"),
      approved: false,
      reason: "runner routing must use needs.<selector-job>.outputs.runner",
    };
  }

  const selectorId = match[1];
  if (!normalizeNeeds(job.needs).includes(selectorId)) {
    return {
      attempted: true,
      approved: false,
      reason: `${jobId} must declare ${selectorId} in needs`,
    };
  }
  const selector = jobs[selectorId];
  if (selector === null || typeof selector !== "object" || Array.isArray(selector)) {
    return { attempted: true, approved: false, reason: `${selectorId} is not a workflow job` };
  }
  const status = selectorStatus(selector, policy);
  if (!status.isSelector) {
    return {
      attempted: true,
      approved: false,
      reason: `${selectorId} does not call an approved selector workflow`,
    };
  }
  if (!status.approved) {
    return { attempted: true, approved: false, reason: status.reason };
  }
  return { attempted: true, approved: true, selectorId };
}

function governedReusableRunnerStatus(workflow, policy) {
  const contract = policy.governedReusableRunnerInput;
  if (
    workflow.on === null ||
    typeof workflow.on !== "object" ||
    Array.isArray(workflow.on) ||
    Object.keys(workflow.on).length !== 1 ||
    !Object.hasOwn(workflow.on, "workflow_call")
  ) {
    return {
      approved: false,
      reason: `${contract.expression} is allowed only when workflow_call is the exclusive trigger`,
    };
  }
  const workflowCall = workflow.on?.workflow_call;
  const declaration = workflowCall?.inputs?.[contract.name];
  if (declaration === null || typeof declaration !== "object" || Array.isArray(declaration)) {
    return {
      approved: false,
      reason: `${contract.expression} requires on.workflow_call.inputs.${contract.name}`,
    };
  }
  if (
    declaration.type !== "string" ||
    declaration.default !== contract.default ||
    declaration.required === true
  ) {
    return {
      approved: false,
      reason: `on.workflow_call.inputs.${contract.name} must be an optional string defaulting to ${contract.default}`,
    };
  }
  return { approved: true };
}

function hostedMatrixStatus(job, target, policy) {
  const match = MATRIX_OUTPUT.exec(target);
  if (!match) {
    return undefined;
  }
  const axis = match[1];
  if (!policy.hostedMatrixAxes.has(axis)) {
    return {
      approved: false,
      reason: `${target} is not an approved hosted-runner matrix expression`,
    };
  }
  const matrix = job.strategy?.matrix;
  if (matrix === null || typeof matrix !== "object" || Array.isArray(matrix)) {
    return { approved: false, reason: `${target} requires a static strategy.matrix mapping` };
  }
  if (Object.hasOwn(matrix, "include") || Object.hasOwn(matrix, "exclude")) {
    return {
      approved: false,
      reason: `${target} cannot be proven hosted when matrix include/exclude is present`,
    };
  }
  const values = matrix[axis];
  if (
    !Array.isArray(values) ||
    values.length === 0 ||
    values.some(
      (value) => typeof value !== "string" || !policy.approvedHostedRunnerLabels.has(value),
    )
  ) {
    return {
      approved: false,
      reason: `${target} must resolve only from the approved hosted-runner label allowlist`,
    };
  }
  return { approved: true };
}

function runnerTargetStatus(jobId, job, jobs, workflow, policy) {
  const reusable = reusableWorkflowStatus(job, policy);
  if (reusable.isReusable && !reusable.approved) {
    return { approved: false, kind: "invalid", reason: reusable.reason };
  }
  if (reusable.approved && reusable.contract.routing === "hosted-only") {
    return { approved: true, kind: "hosted-reusable" };
  }
  const target = reusable.approved ? job.with[reusable.contract.runnerInput] : job?.["runs-on"];
  if (typeof target !== "string") {
    return {
      approved: false,
      kind: "invalid",
      reason: "runs-on (or a reusable workflow runner input) must be a governed string target",
    };
  }

  const route = routeStatus(jobId, target, job, jobs, policy);
  if (route.approved) {
    return { approved: true, kind: "selector-output", route };
  }
  if (route.attempted) {
    return { approved: false, kind: "invalid", reason: route.reason, route };
  }

  if (target === policy.governedReusableRunnerInput.expression) {
    const status = governedReusableRunnerStatus(workflow, policy);
    return {
      approved: status.approved,
      kind: status.approved ? "reusable-input" : "invalid",
      ...(status.reason ? { reason: status.reason } : {}),
    };
  }

  const matrix = hostedMatrixStatus(job, target, policy);
  if (matrix) {
    return {
      approved: matrix.approved,
      kind: matrix.approved ? "hosted-matrix" : "invalid",
      ...(matrix.reason ? { reason: matrix.reason } : {}),
    };
  }

  if (target.includes("${{") || target.includes("}}")) {
    return {
      approved: false,
      kind: "invalid",
      reason: `runner expression ${JSON.stringify(target)} is not an approved routing contract`,
    };
  }
  if (policy.approvedHostedRunnerLabels.has(target)) {
    return { approved: true, kind: "hosted-literal" };
  }
  return {
    approved: false,
    kind: "invalid",
    reason: `runner target ${JSON.stringify(target)} is not in the approved hosted-runner label allowlist`,
  };
}

function rawRunnerStrings(job, includeReusableInputs) {
  return stringsIn({
    matrix: job?.strategy?.matrix,
    reusableInputs: includeReusableInputs ? job?.with : undefined,
    runsOn: job?.["runs-on"],
  });
}

function rawManagedLabel(value, policy) {
  const trimmed = value.trim();
  if (trimmed.toLowerCase().includes("self-hosted")) {
    return true;
  }
  if (/CI_(?:SELF_HOSTED_LABEL|MANAGED_RUNNER)/i.test(trimmed)) {
    return true;
  }
  return policy.managedLabelRegexes.some((pattern) => pattern.test(trimmed));
}

function structuralHostedRequirement(job) {
  const hasJobContainer = Object.hasOwn(job, "container");
  const hasServices = Object.hasOwn(job, "services");
  if (!hasJobContainer && !hasServices) {
    return undefined;
  }
  if (hasJobContainer) {
    return {
      reason: "job-container",
      description: hasServices ? "job container and services" : "job container",
    };
  }
  return { reason: "service-container", description: "services" };
}

function finding(rule, file, job, message) {
  return { rule, file, ...(job ? { job } : {}), message };
}

async function workflowFiles(root) {
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
  return entries
    .filter((entry) => entry.isFile() && /\.ya?ml$/i.test(entry.name))
    .map((entry) => path.join(directory, entry.name))
    .sort((left, right) => left.localeCompare(right));
}

export async function auditRepository({
  root = process.cwd(),
  configPath = DEFAULT_CONFIG_PATH,
  policyPath = DEFAULT_POLICY_PATH,
  repositoryVisibility,
} = {}) {
  const resolvedRoot = path.resolve(root);
  const resolvedConfig = path.isAbsolute(configPath)
    ? configPath
    : path.join(resolvedRoot, configPath);
  const resolvedPolicy = path.isAbsolute(policyPath)
    ? policyPath
    : path.join(resolvedRoot, policyPath);
  const policy = validatePolicy(await readJson(resolvedPolicy, "runner policy"));
  const config = validateRepositoryConfig(
    await readJson(resolvedConfig, "repository runner config"),
    policy,
  );
  if (repositoryVisibility) {
    if (!new Set(["public", "private"]).has(repositoryVisibility)) {
      throw new ConfigurationError('repository visibility evidence must be "public" or "private"');
    }
    if (repositoryVisibility !== config.visibility) {
      throw new ConfigurationError(
        `repository visibility evidence is ${repositoryVisibility}, but .github/runner-policy.json declares ${config.visibility}`,
      );
    }
  }
  const findings = [];
  const consumedExceptions = new Set();

  for (const absoluteFile of await workflowFiles(resolvedRoot)) {
    const file = path.relative(resolvedRoot, absoluteFile).replaceAll(path.sep, "/");
    let workflow;
    try {
      workflow = parseWorkflow(await readFile(absoluteFile, "utf8"), file);
    } catch (error) {
      findings.push(finding("workflow-parse", file, undefined, error.message));
      continue;
    }

    for (const [jobId, job] of Object.entries(workflow.jobs)) {
      if (job === null || typeof job !== "object" || Array.isArray(job)) {
        findings.push(finding("job-shape", file, jobId, "job must be a mapping"));
        continue;
      }
      const key = `${file}#${jobId}`;
      const exception = config.exceptions.get(key);
      const selector = selectorStatus(job, policy);
      const target = selector.isSelector
        ? undefined
        : runnerTargetStatus(jobId, job, workflow.jobs, workflow, policy);
      const attemptsSelectorRoute =
        target !== undefined && Object.hasOwn(target, "route") && target.route.attempted === true;
      const runnerStrings = rawRunnerStrings(job, !selector.isSelector);
      const structuralHosted = structuralHostedRequirement(job);
      let hasForbiddenHostedLabel = false;
      let hasRawManagedLabel = false;

      for (const runner of runnerStrings) {
        const forbiddenLabel = [...policy.forbiddenHostedRunnerLabels].find((label) =>
          runner.toLowerCase().includes(label),
        );
        if (forbiddenLabel) {
          hasForbiddenHostedLabel = true;
          findings.push(
            finding(
              "explicit-hosted-runner",
              file,
              jobId,
              `${JSON.stringify(forbiddenLabel)} is forbidden; pin the hosted image explicitly (ubuntu-24.04)`,
            ),
          );
        }
      }

      for (const runner of runnerStrings) {
        if (rawManagedLabel(runner, policy)) {
          hasRawManagedLabel = true;
          findings.push(
            finding(
              "raw-self-hosted-label",
              file,
              jobId,
              `raw managed runner target ${JSON.stringify(runner.trim())} is forbidden; consume the approved selector output`,
            ),
          );
        }
      }

      if (
        target &&
        !target.approved &&
        ((!hasForbiddenHostedLabel && !hasRawManagedLabel) || typeof job.uses === "string") &&
        !attemptsSelectorRoute
      ) {
        findings.push(finding("runner-target-contract", file, jobId, target.reason));
      }

      if (structuralHosted) {
        if (!exception) {
          findings.push(
            finding(
              "hosted-exception-required",
              file,
              jobId,
              `${structuralHosted.description} requires a hosted exception with reason ${structuralHosted.reason}`,
            ),
          );
        } else {
          consumedExceptions.add(key);
          if (exception.reason !== structuralHosted.reason) {
            findings.push(
              finding(
                "hosted-exception-category",
                file,
                jobId,
                `${structuralHosted.description} requires exception reason ${structuralHosted.reason}, not ${exception.reason}`,
              ),
            );
          }
        }
        if (
          selector.isSelector ||
          (target?.kind !== "hosted-literal" &&
            target?.kind !== "hosted-matrix" &&
            target?.kind !== "hosted-reusable")
        ) {
          findings.push(
            finding(
              "structural-hosted-only",
              file,
              jobId,
              `${structuralHosted.description} cannot use selector or reusable local-runner routing`,
            ),
          );
        }
      }

      const routingEnabled = config.visibility === "private" && config.selfHostedCi;
      if (!routingEnabled) {
        if (selector.isSelector || target?.kind === "selector-output" || attemptsSelectorRoute) {
          findings.push(
            finding(
              config.visibility === "public"
                ? "public-self-hosted-routing"
                : "self-hosted-routing-disabled",
              file,
              jobId,
              "this repository is not permitted to use the local-runner selector",
            ),
          );
        }
        continue;
      }

      if (selector.isSelector) {
        if (!selector.approved) {
          findings.push(finding("selector-pin", file, jobId, selector.reason));
        }
        continue;
      }

      if (target?.kind === "selector-output" && target.approved) {
        continue;
      }
      if (attemptsSelectorRoute) {
        findings.push(finding("selector-contract", file, jobId, target.reason));
      }
      if (target?.kind === "reusable-input") {
        continue;
      }
      if (target?.kind === "invalid") {
        if (exception) {
          consumedExceptions.add(key);
        } else if (!structuralHosted) {
          findings.push(
            finding(
              "hosted-exception-required",
              file,
              jobId,
              `eligible private job must consume the approved selector or declare ${key} in .github/runner-policy.json`,
            ),
          );
        }
        continue;
      }
      if (!exception && !structuralHosted) {
        findings.push(
          finding(
            "hosted-exception-required",
            file,
            jobId,
            `eligible private job must consume the approved selector or declare ${key} in .github/runner-policy.json`,
          ),
        );
      } else if (exception) {
        consumedExceptions.add(key);
      }
    }
  }

  for (const key of config.exceptions.keys()) {
    if (!consumedExceptions.has(key)) {
      findings.push(
        finding(
          "exception-inventory-drift",
          key.split("#", 1)[0],
          key.includes("#") ? key.slice(key.indexOf("#") + 1) : undefined,
          `configured exception ${key} is unused; remove or correct it`,
        ),
      );
    }
  }

  return findings.sort((left, right) =>
    [left.file, left.job ?? "", left.rule, left.message]
      .join("\0")
      .localeCompare([right.file, right.job ?? "", right.rule, right.message].join("\0")),
  );
}

function parseArguments(argv) {
  const options = {
    root: process.cwd(),
    configPath: DEFAULT_CONFIG_PATH,
    policyPath: DEFAULT_POLICY_PATH,
    repositoryVisibility: process.env.CI_REPOSITORY_VISIBILITY,
    json: argv.includes("--json"),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--json") {
      options.json = true;
      continue;
    }
    if (new Set(["--root", "--config", "--policy", "--repository-visibility"]).has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new ConfigurationError(`${argument} requires a value`);
      }
      index += 1;
      if (argument === "--root") options.root = value;
      if (argument === "--config") options.configPath = value;
      if (argument === "--policy") options.policyPath = value;
      if (argument === "--repository-visibility") options.repositoryVisibility = value;
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
      process.stdout.write("Runner policy passed.\n");
    } else {
      for (const item of findings) {
        const location = item.job ? `${item.file}#${item.job}` : item.file;
        process.stderr.write(`${location}: ${item.rule}: ${item.message}\n`);
      }
    }
    process.exitCode = findings.length === 0 ? 0 : 1;
  } catch (error) {
    const output = error instanceof Error ? error.message : String(error);
    process.stderr.write(`runner-policy: ${output}\n`);
    process.exitCode = 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}

export { ConfigurationError };
