// Behavioral tests for launcher.js --vault, on Windows and Linux. A stub
// vault-exec under a temporary home and a stub server in a temporary git repo
// stand in for the real ones; no test reads a real secret.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const launcher = path.join(here, "launcher.js");
const windows = process.platform === "win32";
const noPwsh =
  windows && spawnSync("pwsh", ["-NoProfile", "-Command", "exit 0"]).error !== undefined;
const INPUT = '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n';

function sandbox({ resolver = true } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-launcher-"));
  const home = path.join(root, "home");
  const repo = path.join(root, "repo");
  const server = path.join(repo, "mcp-servers", "stub");
  fs.mkdirSync(server, { recursive: true });
  fs.copyFileSync(
    path.join(here, "fixtures", "stub-server.js"),
    path.join(server, "stub-server.js"),
  );
  assert.equal(spawnSync("git", ["init", "-q"], { cwd: repo }).status, 0);
  if (resolver) {
    const bin = path.join(home, ".local", "bin");
    const stub = windows ? "vault-exec.ps1" : "vault-exec";
    fs.mkdirSync(bin, { recursive: true });
    fs.copyFileSync(path.join(here, "fixtures", stub), path.join(bin, stub));
    fs.chmodSync(path.join(bin, stub), 0o755);
  }
  return { root, home, repo, log: path.join(root, "vault.log") };
}

function run(box, args, env = {}) {
  const base = { ...process.env };
  for (const name of ["KEY_A", "KEY_B", "MCP_LAUNCHER_VAULT_TRIED", "STUB_VAULT_MODE"])
    delete base[name];
  const result = spawnSync(
    process.execPath,
    [launcher, ...args, "mcp-servers/stub", "node", "stub-server.js", "7", "KEY_A", "KEY_B"],
    {
      cwd: box.repo,
      input: INPUT,
      encoding: "utf8",
      env: {
        ...base,
        HOME: box.home,
        USERPROFILE: box.home,
        MCP_LAUNCHER_FNM_ACTIVE: "1",
        STUB_VAULT_LOG: box.log,
        ...env,
      },
    },
  );
  const calls = fs.existsSync(box.log)
    ? fs.readFileSync(box.log, "utf8").trim().split(/\r?\n/)
    : [];
  fs.rmSync(box.root, { recursive: true, force: true, maxRetries: 3 });
  return { ...result, calls };
}

// Every case: the server's stdout is the input, byte for byte, and its exit code survives.
function assertPassthrough(result) {
  assert.equal(result.stdout, INPUT);
  assert.equal(result.status, 7, result.stderr);
}

const launcherLines = (stderr) =>
  stderr.split(/\r?\n/).filter((line) => line.startsWith("mcp-launcher:"));

const vaultTest = { skip: noPwsh && "pwsh not found" };

test("a set variable dispatches directly without vault-exec", () => {
  const r = run(sandbox(), ["--vault", "KEY_A=secret-a"], { KEY_A: "from-env" });
  assertPassthrough(r);
  assert.deepEqual(r.calls, []);
  assert.match(r.stderr, /stub-server: KEY_A=from-env/);
  assert.deepEqual(launcherLines(r.stderr), []);
});

test("an unset variable resolves through one vault-exec round", vaultTest, () => {
  const r = run(sandbox(), ["--vault", "KEY_A=secret-a"]);
  assertPassthrough(r);
  assert.equal(r.calls.length, 1);
  assert.match(r.calls[0], /^--optional --env KEY_A=secret-a -- /);
  assert.match(r.stderr, /stub-server: KEY_A=stub-secret-a/);
  assert.deepEqual(launcherLines(r.stderr), []);
});

// biome-ignore lint/suspicious/noTemplateCurlyInString: an unexpanded placeholder is the input under test
for (const literal of ["${KEY_A}", "${env:KEY_A}", ""]) {
  test(`the value ${JSON.stringify(literal)} counts as unset`, vaultTest, () => {
    const r = run(sandbox(), ["--vault", "KEY_A=secret-a"], { KEY_A: literal });
    assertPassthrough(r);
    assert.equal(r.calls.length, 1);
    assert.match(r.stderr, /stub-server: KEY_A=stub-secret-a/);
  });
}

test("only the missing names go to vault-exec", vaultTest, () => {
  const r = run(sandbox(), ["--vault", "KEY_A=secret-a", "--vault", "KEY_B=secret-b"], {
    KEY_A: "from-env",
  });
  assertPassthrough(r);
  assert.equal(r.calls.length, 1);
  assert.match(r.calls[0], /^--optional --env KEY_B=secret-b -- /);
  assert.match(r.stderr, /stub-server: KEY_A=from-env/);
  assert.match(r.stderr, /stub-server: KEY_B=stub-secret-b/);
});

test("a key vault-exec leaves unset never re-enters vault-exec", vaultTest, () => {
  const r = run(sandbox(), ["--vault", "KEY_A=secret-a"], { STUB_VAULT_MODE: "empty" });
  assertPassthrough(r);
  assert.equal(r.calls.length, 1);
  assert.match(r.stderr, /stub-server: KEY_A=<unset>/);
  assert.deepEqual(launcherLines(r.stderr), [
    "mcp-launcher: KEY_A unset after vault-exec; starting keyless",
  ]);
});

test("MCP_LAUNCHER_VAULT_TRIED=1 skips vault-exec", () => {
  const r = run(sandbox(), ["--vault", "KEY_A=secret-a"], { MCP_LAUNCHER_VAULT_TRIED: "1" });
  assertPassthrough(r);
  assert.deepEqual(r.calls, []);
  assert.deepEqual(launcherLines(r.stderr), [
    "mcp-launcher: KEY_A unset after vault-exec; starting keyless",
  ]);
});

test("no vault-exec warns once and starts keyless, dropping a literal placeholder", () => {
  // biome-ignore lint/suspicious/noTemplateCurlyInString: an unexpanded placeholder is the input under test
  const r = run(sandbox({ resolver: false }), ["--vault", "KEY_A=secret-a"], { KEY_A: "${KEY_A}" });
  assertPassthrough(r);
  assert.match(r.stderr, /stub-server: KEY_A=<unset>/);
  assert.deepEqual(launcherLines(r.stderr), [
    "mcp-launcher: KEY_A unset and vault-exec not found; starting keyless",
  ]);
});

test("a -- after the --vault pairs is dropped", () => {
  const r = run(sandbox(), ["--vault", "KEY_A=secret-a", "--"], { KEY_A: "from-env" });
  assertPassthrough(r);
  assert.match(r.stderr, /stub-server: KEY_A=from-env/);
});

test("without --vault the launcher dispatches unchanged", () => {
  const r = run(sandbox(), []);
  assertPassthrough(r);
  assert.deepEqual(r.calls, []);
  assert.deepEqual(launcherLines(r.stderr), []);
});

for (const spec of ["KEY_A", "KEY_A=", "1KEY=secret", "BAD-NAME=secret"]) {
  test(`--vault ${spec} is a usage error`, () => {
    const r = run(sandbox(), ["--vault", spec]);
    assert.equal(r.status, 2);
    assert.equal(r.stdout, "");
    assert.deepEqual(r.calls, []);
  });
}
