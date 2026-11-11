#!/usr/bin/env node

// Generates the org issue forms from contract.json. `check` (the default) fails when a committed
// form differs from what the contract generates; `write` regenerates them. The sync materializes
// the committed forms byte-exact into melodic-software/.github, so a form is changed here, in the
// contract, and nowhere else.

import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { stringify } from "yaml";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const CONTRACT_PATH = path.join(HERE, "contract.json");
export const FORMS_DIR = path.join(HERE, "forms");
const KINDS = new Set(["textarea", "input", "dropdown"]);
const HEADER =
  "# Generated from melodic-software/standards components/issue-body-contract/contract.json.\n" +
  "# Edit the contract and run `node components/issue-body-contract/issue-forms.mjs write`.\n";

export function validateContract(contract) {
  const errors = [];
  const fail = (message) => errors.push(message);
  if (contract.schemaVersion !== 1) fail(`schemaVersion must be 1, got ${contract.schemaVersion}`);
  if (!Array.isArray(contract.floorLabels) || contract.floorLabels.length === 0) {
    fail("floorLabels must be a non-empty array");
  }
  const forms = new Set();
  for (const [key, type] of Object.entries(contract.types ?? {})) {
    const at = `types.${key}`;
    if (!/^[a-z0-9-]+\.yml$/.test(type.form ?? ""))
      fail(`${at}.form must be a kebab-case .yml name`);
    if (forms.has(type.form)) fail(`${at}.form ${type.form} is used twice`);
    forms.add(type.form);
    for (const field of ["name", "description"]) {
      if (typeof type[field] !== "string" || type[field] === "") fail(`${at}.${field} is required`);
    }
    if (type.nativeType !== null && typeof type.nativeType !== "string") {
      fail(`${at}.nativeType must be a string or null`);
    }
    for (const label of contract.floorLabels ?? []) {
      if (!type.labels?.includes(label)) fail(`${at}.labels lacks the floor label ${label}`);
    }
    const ids = new Set();
    const headings = new Set();
    if (!type.fields?.some((field) => field.required))
      fail(`${at} needs at least one required field`);
    for (const [index, field] of (type.fields ?? []).entries()) {
      const where = `${at}.fields[${index}]`;
      if (!/^[a-z0-9-]+$/.test(field.id ?? "")) fail(`${where}.id must be kebab-case`);
      if (ids.has(field.id)) fail(`${where}.id ${field.id} repeats`);
      if (headings.has(field.heading)) fail(`${where}.heading ${field.heading} repeats`);
      ids.add(field.id);
      headings.add(field.heading);
      if (typeof field.heading !== "string" || field.heading === "")
        fail(`${where}.heading is required`);
      if (!KINDS.has(field.kind)) fail(`${where}.kind must be one of ${[...KINDS].join(", ")}`);
      if (typeof field.required !== "boolean") fail(`${where}.required must be a boolean`);
      if ((field.kind === "dropdown") !== Array.isArray(field.options)) {
        fail(`${where}.options is required for a dropdown and only for a dropdown`);
      }
    }
  }
  if (forms.size === 0) fail("types must declare at least one issue type");
  // GitHub's community profile counts no issue template when every form sets `type:`.
  if (Object.values(contract.types ?? {}).every((type) => type.nativeType !== null)) {
    fail(
      "at least one type must set nativeType null, or the community profile reports no issue templates",
    );
  }
  return errors;
}

function renderField(field) {
  const attributes = { label: field.heading, description: field.description };
  if (field.placeholder !== undefined) attributes.placeholder = field.placeholder;
  if (field.options !== undefined) attributes.options = field.options;
  const element = { type: field.kind, id: field.id, attributes };
  if (field.required) element.validations = { required: true };
  return element;
}

export function renderForm(type) {
  const form = { name: type.name, description: type.description };
  if (type.nativeType !== null) form.type = type.nativeType;
  form.labels = type.labels;
  form.body = type.fields.map(renderField);
  return HEADER + stringify(form, { lineWidth: 0, flowCollectionPadding: false });
}

export function renderAll(contract) {
  return Object.fromEntries(
    Object.values(contract.types).map((type) => [type.form, renderForm(type)]),
  );
}

export async function loadContract(file = CONTRACT_PATH) {
  return JSON.parse(await readFile(file, "utf8"));
}

export async function diffForms(contract, formsDir = FORMS_DIR) {
  const expected = renderAll(contract);
  const present = (await readdir(formsDir)).filter((name) => name.endsWith(".yml"));
  const drift = [];
  for (const name of present) {
    if (!(name in expected)) drift.push(`forms/${name}: no contract type generates this form`);
  }
  for (const [name, text] of Object.entries(expected)) {
    if (!present.includes(name)) {
      drift.push(`forms/${name}: missing`);
    } else if ((await readFile(path.join(formsDir, name), "utf8")) !== text) {
      drift.push(`forms/${name}: differs from what contract.json generates`);
    }
  }
  return drift;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const mode = process.argv[2] ?? "check";
  const contract = await loadContract();
  const errors = validateContract(contract);
  if (errors.length > 0) {
    for (const error of errors) process.stderr.write(`${`contract.json: ${error}`}\n`);
    process.exit(1);
  }
  if (mode === "write") {
    for (const [name, text] of Object.entries(renderAll(contract))) {
      await writeFile(path.join(FORMS_DIR, name), text);
    }
    process.stdout.write(`${`issue-forms: wrote ${Object.keys(contract.types).length} forms`}\n`);
  } else if (mode === "check") {
    const drift = await diffForms(contract);
    if (drift.length > 0) {
      for (const line of drift) process.stderr.write(`${`drift: ${line}`}\n`);
      process.stderr.write(
        `${"Run `node components/issue-body-contract/issue-forms.mjs write` and commit the result."}\n`,
      );
      process.exit(1);
    }
    process.stdout.write(`${"issue-forms: committed forms match contract.json"}\n`);
  } else {
    process.stderr.write(`${`usage: issue-forms.mjs [check|write], got ${mode}`}\n`);
    process.exit(2);
  }
}
