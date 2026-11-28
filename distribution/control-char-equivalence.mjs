#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const NUL = String.fromCharCode(0);
const CONTROL_RE = new RegExp(`[${NUL}-${String.fromCharCode(31)}${String.fromCharCode(127)}]`);

const rootProbe = spawnSync("git", ["rev-parse", "--show-toplevel"], {
  encoding: "utf8",
});
if (rootProbe.error || rootProbe.status !== 0) {
  process.stderr.write("ERROR: not inside a git repository\n");
  process.exit(1);
}
const root = rootProbe.stdout.replace(/\r?\n$/, "");
const fixture = path.join(root, "distribution", "fixtures", "control-char-equivalence.tsv");
if (!fs.existsSync(fixture)) {
  process.stderr.write(`ERROR: missing fixture ${fixture}\n`);
  process.exit(1);
}

let failed = 0;
let checked = 0;
const rows = fs.readFileSync(fixture, "utf8").split("\n");
for (const row of rows) {
  if (!row || row.startsWith("byte\t")) continue;
  const [byteText, , posixControl] = row.split("\t");
  const byte = Number.parseInt(byteText, 10);
  const expected = byte <= 31 || byte === 127 ? "yes" : "no";
  if (posixControl !== expected) {
    process.stderr.write(
      `FAIL: byte ${byte} fixture posix_control is ${posixControl}, expected ${expected}\n`,
    );
    failed += 1;
    continue;
  }
  const probe = `p${String.fromCharCode(byte)}s`;
  const actual = CONTROL_RE.test(probe) ? "yes" : "no";
  if (actual !== expected) {
    process.stderr.write(
      `FAIL: byte ${byte} engine class says ${actual}, fixture says ${expected}\n`,
    );
    failed += 1;
    continue;
  }
  checked += 1;
}
if (checked !== 256) {
  process.stderr.write(`ERROR: fixture covered ${checked} bytes, expected 256\n`);
  process.exit(1);
}
if (CONTROL_RE.test("docs/adr/README.md")) {
  process.stderr.write("FAIL: plain path misclassified as containing a control\n");
  failed += 1;
}
if (failed > 0) process.exit(1);
process.stdout.write("control-char equivalence (Node): 256 bytes verified\n");
