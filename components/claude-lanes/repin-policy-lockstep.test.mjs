import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { parseLockstepArgs } from "./repin-lockstep-args.mjs";
import { rewriteCallerFiles } from "./repin-policy-lockstep.mjs";

const oldA = "c136b27f404dd32ce3873f39a6f3443891d1c16e";
const oldB = "d26c750691b5498fab529d115b63f84aa7aecebe";
const next = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

const temporaryRoots = [];

test.after(async () => {
  await Promise.all(temporaryRoots.map((root) => rm(root, { force: true, recursive: true })));
});

test("parseLockstepArgs accepts a single old SHA", () => {
  const parsed = parseLockstepArgs([oldA, next, "v0.17.0"]);
  assert.deepEqual(parsed, { oldShas: [oldA], newSha: next, tag: "v0.17.0" });
});

test("parseLockstepArgs accepts the unique-set comma list the apply step emits", () => {
  const parsed = parseLockstepArgs([`${oldA},${oldB}`, next, "v0.17.0"]);
  assert.deepEqual(parsed, { oldShas: [oldA, oldB], newSha: next, tag: "v0.17.0" });
});

test("parseLockstepArgs rejects a comma list with a non-SHA token", () => {
  const parsed = parseLockstepArgs([`${oldA},not-a-sha`, next, "v0.17.0"]);
  assert.deepEqual(parsed, { error: "sha" });
});

test("parseLockstepArgs rejects a missing argument as usage", () => {
  assert.deepEqual(parseLockstepArgs([oldA, next]), { error: "usage" });
});

test("rewriteCallerFiles keeps exactly one trailing newline on a rewritten caller", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "repin-lockstep-"));
  temporaryRoots.push(root);
  const rel = "components/claude-lanes/claude-review.yml";
  const abs = path.join(root, rel);
  await mkdir(path.dirname(abs), { recursive: true });
  const source =
    "jobs:\n" +
    "  review:\n" +
    `    uses: melodic-software/ci-workflows/.github/workflows/claude-review.yml@${oldA} # v0.16.0\n`;
  await writeFile(abs, source);

  const changed = await rewriteCallerFiles(next, "v0.17.0", root);

  assert.equal(changed, true);
  const rewritten = await readFile(abs, "utf8");
  assert.ok(rewritten.includes(`@${next} # v0.17.0`), "pin line carries the new SHA and tag");
  assert.ok(rewritten.endsWith("\n"), "rewritten caller ends with a final newline");
  assert.ok(!rewritten.endsWith("\n\n"), "rewritten caller does not gain a duplicate newline");
});

// The lane callers stopped pinning the selector in ci-perf Phase 3b. The
// selector REPIN_TARGET therefore reads zero pins, skips, and never reaches
// `copySelectorContract`, and `updateTestMjs` is gated on a selector
// copy-forward having actually happened so the next tag cannot insert a
// selector SHA constant that `policy.json` never gained. Assert the premise
// here: if a caller ever pins the selector again, that gating needs revisiting
// rather than silently doing nothing.
test("the shipped lane callers pin no selector, so the repin lane copies no selector contract", async () => {
  for (const name of ["claude-review.yml", "claude-security-review.yml"]) {
    const body = await readFile(new URL(`./${name}`, import.meta.url), "utf8");
    assert.ok(
      !body.includes("/select-runner.yml@"),
      `${name} must not pin the governed selector; it names the fleet label directly`,
    );
  }
});

test("rewriteCallerFiles repins a selector-less caller", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "repin-lockstep-"));
  temporaryRoots.push(root);
  const rel = "components/claude-lanes/claude-security-review.yml";
  const abs = path.join(root, rel);
  await mkdir(path.dirname(abs), { recursive: true });
  await writeFile(
    abs,
    "jobs:\n" +
      "  security-review:\n" +
      `    uses: melodic-software/ci-workflows/.github/workflows/claude-security-review.yml@${oldA} # v0.16.0\n` +
      "    with:\n" +
      "      runner: melodic-review-ubuntu-24.04-x64\n",
  );

  assert.equal(await rewriteCallerFiles(next, "v0.17.0", root), true);
  const rewritten = await readFile(abs, "utf8");
  assert.ok(rewritten.includes(`@${next} # v0.17.0`));
  assert.ok(rewritten.includes("runner: melodic-review-ubuntu-24.04-x64"));
});
