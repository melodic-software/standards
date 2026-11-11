import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { parse } from "yaml";

import {
  diffForms,
  loadContract,
  renderAll,
  renderForm,
  validateContract,
} from "./issue-forms.mjs";

const contract = await loadContract();
const clone = () => structuredClone(contract);

test("the committed contract is valid", () => {
  assert.deepEqual(validateContract(contract), []);
});

test("the committed forms match the contract", async () => {
  assert.deepEqual(await diffForms(contract), []);
});

test("each generated form carries the contract's name, type, labels and fields", () => {
  for (const type of Object.values(contract.types).filter((t) => t.form !== null)) {
    const form = parse(renderForm(type));
    assert.equal(form.name, type.name);
    assert.equal(form.description, type.description);
    assert.equal(form.type, type.nativeType ?? undefined);
    assert.deepEqual(form.labels, type.labels);
    assert.deepEqual(
      form.body.map((element) => [
        element.id,
        element.type,
        element.attributes.label,
        element.validations?.required === true,
      ]),
      type.fields.map((field) => [field.id, field.kind, field.heading, field.required]),
    );
  }
});

test("no form applies the agent-ready role label: triage grants it", () => {
  for (const type of Object.values(contract.types)) {
    assert.ok(!type.labels.includes("agent-ready"), `${type.form} must not apply agent-ready`);
  }
});

test("a contract where every form sets a native type is rejected", () => {
  const bad = clone();
  for (const type of Object.values(bad.types)) type.nativeType ??= "Task";
  assert.match(validateContract(bad).join("\n"), /community profile/);
});

test("a form whose labels are not exactly the floor is rejected", () => {
  for (const labels of [[], ["needs-triage", "agent-ready"]]) {
    const bad = clone();
    bad.types.task.labels = labels;
    assert.match(validateContract(bad).join("\n"), /types\.task\.labels must equal floorLabels/);
  }
});

test("a type with no form generates no form file and skips the floor rule", () => {
  assert.equal(contract.types["decomposed-item"].form, null);
  const forms = Object.keys(renderAll(contract));
  assert.deepEqual(
    forms.sort((a, b) => a.localeCompare(b)),
    Object.values(contract.types)
      .flatMap((type) => (type.form === null ? [] : [type.form]))
      .sort((a, b) => a.localeCompare(b)),
  );
});

test("a repeated heading, a bad kind and a dropdown without options are rejected", () => {
  const bad = clone();
  const fields = bad.types.bug.fields;
  fields[1].heading = fields[0].heading;
  fields[2].kind = "checkbox";
  delete fields[3].options;
  const errors = validateContract(bad).join("\n");
  assert.match(errors, /heading Steps to reproduce repeats/);
  assert.match(errors, /kind must be one of/);
  assert.match(errors, /options is required for a dropdown/);
});

test("drift reports an edited, a missing and an extra form", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "issue-forms-"));
  const forms = renderAll(contract);
  const [first, second, ...rest] = Object.keys(forms);
  await writeFile(path.join(dir, first), `${forms[first]}# hand edit\n`);
  for (const name of rest) await writeFile(path.join(dir, name), forms[name]);
  await writeFile(path.join(dir, "extra.yml"), "name: Extra\n");
  const byText = (a, b) => a.localeCompare(b);
  assert.deepEqual(
    (await diffForms(contract, dir)).sort(byText),
    [
      `forms/${first}: differs from what contract.json generates`,
      `forms/${second}: missing`,
      "forms/extra.yml: no contract type generates this form",
    ].sort(byText),
  );
});
