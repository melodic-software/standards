import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import {
  diffOutputs,
  loadInputs,
  OUTPUTS,
  renderAll,
  renderGuide,
  renderTemplate,
  validateInputs,
} from "./contract-docs.mjs";

const { policy, contract } = await loadInputs();

function withBody(overrides) {
  return { ...policy, body: { ...policy.body, ...overrides } };
}

test("the committed records validate", () => {
  assert.deepEqual(validateInputs(policy, contract), []);
});

test("guidance keys that differ from requiredSections are rejected", () => {
  const errors = validateInputs(
    withBody({ requiredSections: ["Summary", "Risk"], sectionGuidance: { Summary: "s" } }),
    contract,
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /sectionGuidance keys \[Summary\] must equal .*\[Summary, Risk\]/);
});

test("guidance in a different order than requiredSections is rejected", () => {
  const errors = validateInputs(
    withBody({ requiredSections: ["A", "B"], sectionGuidance: { B: "b", A: "a" } }),
    contract,
  );
  assert.equal(errors.length, 1);
});

test("a policy that drops the steered no-issue marker is rejected", () => {
  const errors = validateInputs(withBody({ noIssueMarkers: ["No linked issue"] }), contract);
  assert.deepEqual(errors, [
    'policy.json body.noIssueMarkers no longer accepts "No related issue"',
  ]);
});

test("a policy that drops the steered non-closing marker is rejected", () => {
  const errors = validateInputs(withBody({ nonClosingMarkers: ["Relates to"] }), contract);
  assert.deepEqual(errors, ['policy.json body.nonClosingMarkers no longer accepts "Refs"']);
});

test("a section added to policy appears in the template with its guidance", () => {
  const text = renderTemplate(
    withBody({
      requiredSections: ["Summary", "Risk"],
      sectionGuidance: { Summary: "one line", Risk: "first\nsecond" },
    }),
  );
  assert.ok(
    text.endsWith("## Summary\n\n<!-- one line -->\n\n## Risk\n\n<!--\nfirst\nsecond\n-->\n"),
  );
});

test("the guide gives each typed form its gh --type flag and each untyped one none", () => {
  const text = renderGuide(policy, contract);
  assert.match(text, /\| Bug Report \| `--type Bug` \| `bug-report.yml` \|/);
  assert.match(
    text,
    /\| Agent-Ready Work Item \| no `--type`: triage sets it \| `agent-ready.yml` \|/,
  );
  assert.match(text, /\| Decomposed work item \| set by its publisher \| none \|/);
});

test("the guide marks required and optional issue fields", () => {
  const text = renderGuide(policy, contract);
  assert.match(text, /- `Steps to reproduce` \(required\): /);
  assert.match(text, /- `Environment` \(optional\): /);
});

test("the guide states that a repository's own template, forms and AGENTS.md win, before its first section", () => {
  const text = renderGuide(policy, contract);
  const precedence = text.indexOf("This guide is the organization default.");
  assert.ok(precedence > 0);
  assert.ok(precedence < text.indexOf("\n## "));
  assert.match(
    text,
    /PR template, issue forms or\n`AGENTS\.md` differ from it, the repository's own wins/,
  );
});

test("the guide names the floor label and the three routing labels", () => {
  const text = renderGuide(policy, contract);
  assert.match(text, /floor label `needs-triage`/);
  for (const label of ["session-owned", "attended", "needs-human"]) {
    assert.match(text, new RegExp(`^- \`${label}\`: `, "m"));
  }
});

test("check passes on the committed copies", async () => {
  assert.deepEqual(await diffOutputs(renderAll(policy, contract)), []);
});

test("check reports a hand-edited and a missing copy", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "contract-docs-"));
  try {
    const outputs = renderAll(policy, contract);
    await mkdir(path.join(root, path.dirname(OUTPUTS.template)), { recursive: true });
    await writeFile(path.join(root, OUTPUTS.template), `${outputs[OUTPUTS.template]}edited\n`);
    const drift = await diffOutputs(outputs, root);
    assert.deepEqual(drift, [
      `${OUTPUTS.template}: differs from what the records generate`,
      `${OUTPUTS.guide}: missing`,
    ]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
