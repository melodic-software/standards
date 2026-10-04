import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";

// ajv comes from the distribution package's install (`npm ci --prefix distribution`).
const Ajv2020 = createRequire(new URL("../../distribution/package.json", import.meta.url))(
  "ajv/dist/2020",
).default;

const read = (name) => JSON.parse(readFileSync(new URL(name, import.meta.url), "utf8"));

const list = read("./trusted-actors.json");
const validate = new Ajv2020({ strict: true, allErrors: true }).compile(
  read("./trusted-actors.schema.json"),
);

test("the committed list validates against the schema", () => {
  assert.equal(validate(list), true, JSON.stringify(validate.errors));
});

test("a string id is rejected", () => {
  const copy = structuredClone(list);
  copy.actors[0].id = "x";
  assert.equal(validate(copy), false);
  assert.equal(validate.errors[0].instancePath, "/actors/0/id");
});

test("an extra key on an actor is rejected", () => {
  const copy = structuredClone(list);
  copy.actors[0].note = "extra";
  assert.equal(validate(copy), false);
  assert.equal(validate.errors[0].keyword, "additionalProperties");
});

test("every id is listed once", () => {
  const ids = list.actors.map((actor) => actor.id);
  assert.deepEqual(
    ids.filter((id, index) => ids.indexOf(id) !== index),
    [],
  );
});

test("github-actions[bot] is not trusted", () => {
  assert.equal(
    list.actors.some((actor) => actor.id === 41898282),
    false,
  );
});

test("chatgpt-codex-connector[bot] is not trusted", () => {
  assert.equal(
    list.actors.some((actor) => actor.id === 199175422),
    false,
  );
});
