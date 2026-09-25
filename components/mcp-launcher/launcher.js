#!/usr/bin/env node
// MCP package dispatch: cross-platform npx spawn OR worktree-scoped repo server.
//
// npx servers:  node launcher.js -y @scope/pkg …
// repo servers: node launcher.js mcp-servers/<name>/node node build/index.js
// keyed servers: node launcher.js --vault NAME=vault-secret-name [--vault …] <either form above>
//
// MCP hosts spawn fnm exec first (see README.md); set MCP_LAUNCHER_FNM_ACTIVE=1
// so this file does not double-wrap. Manual dev may invoke launcher.js
// directly — fnm wrap runs when fnm is on PATH.
//
// stdout is the MCP JSON-RPC channel: this file writes only to stderr.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { attachLifecycle, dispatch } = require("./dispatch.js");

const TRIED = "MCP_LAUNCHER_VAULT_TRIED";
const VAULT_SPEC_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*=.+$/;
const UNEXPANDED_PLACEHOLDER_PATTERN = /^\$\{.*\}$/;

function warn(message) {
  process.stderr.write(`mcp-launcher: ${message}\n`);
}

// Leading `--vault NAME=secret` pairs, and the args after them (an optional `--` ends the pairs).
function parseVault(args) {
  const specs = [];
  let rest = args;
  while (rest[0] === "--vault") {
    const spec = rest[1] ?? "";
    if (!VAULT_SPEC_PATTERN.test(spec)) {
      warn(`--vault requires NAME=vault-secret-name, got: ${spec}`);
      process.exit(2);
    }
    specs.push(spec);
    rest = rest.slice(2);
  }
  if (specs.length > 0 && rest[0] === "--") rest = rest.slice(1);
  return { specs, rest };
}

// Empty, or a placeholder the host passed through unexpanded (`${NAME}`, `${env:NAME}`).
function isSet(name) {
  const value = process.env[name];
  return Boolean(value) && !UNEXPANDED_PLACEHOLDER_PATTERN.test(value);
}

function findVaultExec() {
  const bin = path.join(os.homedir(), ".local", "bin");
  if (process.platform === "win32") {
    // `where` does not find a .ps1, so test for the file.
    const script = path.join(bin, "vault-exec.ps1");
    return fs.existsSync(script)
      ? { command: "pwsh", prefix: ["-NoProfile", "-File", script] }
      : null;
  }
  const script = path.join(bin, "vault-exec");
  try {
    fs.accessSync(script, fs.constants.X_OK);
    return { command: script, prefix: [] };
  } catch {
    return null;
  }
}

function fnmOnPath() {
  if (process.platform === "win32") {
    const result = spawnSync("where", ["fnm"], { encoding: "utf8", stdio: "pipe" });
    return result.status === 0;
  }
  const result = spawnSync("command", ["-v", "fnm"], {
    encoding: "utf8",
    stdio: "pipe",
    shell: true,
  });
  return result.status === 0;
}

function run(forwardArgs) {
  if (process.env.MCP_LAUNCHER_FNM_ACTIVE) {
    dispatch(forwardArgs);
  } else if (fnmOnPath()) {
    const fnmArgs = [
      "exec",
      "--version-file-strategy=recursive",
      "--",
      "node",
      __filename,
      ...forwardArgs,
    ];
    attachLifecycle(
      spawn("fnm", fnmArgs, {
        stdio: "inherit",
        env: { ...process.env, MCP_LAUNCHER_FNM_ACTIVE: "1" },
      }),
      "mcp-launcher",
    );
  } else {
    // No fnm and no parent fnm-exec wrap — fall back to ambient node.
    warn("fnm not on PATH — using ambient node");
    dispatch(forwardArgs);
  }
}

const { specs, rest } = parseVault(process.argv.slice(2));
const missing = specs.filter((spec) => !isSet(spec.split("=")[0]));
const resolver = missing.length > 0 && process.env[TRIED] !== "1" ? findVaultExec() : null;

if (resolver) {
  // One vault-exec round: the child carries TRIED=1, so it never re-enters here.
  const envArgs = missing.flatMap((spec) => ["--env", spec]);
  attachLifecycle(
    spawn(
      resolver.command,
      [
        ...resolver.prefix,
        "--optional",
        ...envArgs,
        "--",
        process.execPath,
        __filename,
        ...process.argv.slice(2),
      ],
      { stdio: "inherit", env: { ...process.env, [TRIED]: "1" } },
    ),
    "mcp-launcher-vault",
  );
} else {
  const names = missing.map((spec) => spec.split("=")[0]);
  if (names.length > 0) {
    const why =
      process.env[TRIED] === "1" ? "unset after vault-exec" : "unset and vault-exec not found";
    warn(`${names.join(", ")} ${why}; starting keyless`);
  }
  // A literal `${NAME}` must not reach the server as its key.
  for (const name of names) delete process.env[name];
  run(rest);
}
