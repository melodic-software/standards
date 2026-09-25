const { execSync, spawn } = require("node:child_process");
const os = require("node:os");
const path = require("node:path");

function attachLifecycle(child, label) {
  for (const sig of ["SIGINT", "SIGTERM"]) {
    process.on(sig, () => child.kill(sig));
  }
  child.on("exit", (code, signal) => {
    if (signal) {
      process.exit(128 + (os.constants.signals[signal] ?? 0));
    }
    process.exit(code ?? 1);
  });
  child.on("error", (err) => {
    process.stderr.write(`${label}: ${err.message}\n`);
    process.exit(1);
  });
}

function runNpx(npxArgs) {
  const isWindows = process.platform === "win32";
  const nodeDir = path.dirname(process.execPath);
  const npxBinary = isWindows ? path.join(nodeDir, "npx.cmd") : path.join(nodeDir, "npx");
  if (isWindows) {
    // On Windows, spawn `cmd /d /s /c` with the entire command line pre-quoted:
    //   cmd /d /s /c ""C:\Program Files\nodejs\npx.cmd" "arg1" "arg2""
    // cmd's /s flag with /c strips one outer quote pair, then parses the
    // remaining tokens. Each arg is independently double-quoted so paths
    // with spaces survive cmd tokenization (e.g., default Node install
    // under `C:\Program Files\nodejs\`).
    //
    // windowsVerbatimArguments: true prevents Node from re-escaping the
    // already-quoted args. Avoids the DEP0190 deprecation from
    // `{ shell: true }` + args array (Node ≥22 warns; CVE-2024-27980 fix
    // path).
    const inner = `"${npxBinary}" ${npxArgs.map((a) => `"${a}"`).join(" ")}`;
    attachLifecycle(
      spawn("cmd.exe", ["/d", "/s", "/c", `"${inner}"`], {
        stdio: "inherit",
        windowsVerbatimArguments: true,
      }),
      "mcp-launcher-npx",
    );
    return;
  }
  attachLifecycle(spawn(npxBinary, npxArgs, { stdio: "inherit" }), "mcp-launcher-npx");
}

function resolveWorktreeRoot() {
  let gitCommonDir;
  try {
    gitCommonDir = execSync("git rev-parse --git-common-dir", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    process.stderr.write("mcp-launcher: not inside a git repository\n");
    process.exit(1);
  }

  // Both layouts: --show-toplevel returns the current worktree root.
  // Standard clone: repo root. Bare-clone hub: the specific worktree CWD is in.
  // This keeps each worktree isolated — MCP servers resolve from their own checkout.
  try {
    return execSync("git rev-parse --show-toplevel", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    // Fallback for edge cases (bare repo CWD, detached worktree)
    return path.resolve(gitCommonDir, "..");
  }
}

function assertRepoRelativeDir(relDir) {
  const slashNormalized = relDir.replace(/\\/g, "/");
  if (path.isAbsolute(slashNormalized) || slashNormalized.split("/").includes("..")) {
    process.stderr.write(`mcp-launcher: repo path must be relative without '..': ${relDir}\n`);
    process.exit(1);
  }
  return path.normalize(relDir).replace(/\\/g, "/");
}

function runRepo(relDir, command, cmdArgs) {
  if (!relDir || !command) {
    process.stderr.write("Usage: launcher.js <relative-dir> <command> [args...]\n");
    process.exit(1);
  }

  const safeRelDir = assertRepoRelativeDir(relDir);
  const worktreeRoot = resolveWorktreeRoot();
  const serverDir = path.resolve(worktreeRoot, safeRelDir);
  const worktreeResolved = path.resolve(worktreeRoot);
  if (serverDir !== worktreeResolved && !serverDir.startsWith(`${worktreeResolved}${path.sep}`)) {
    process.stderr.write(`mcp-launcher: repo path escapes worktree root: ${relDir}\n`);
    process.exit(1);
  }
  const executable = command === "node" ? process.execPath : command;

  attachLifecycle(
    spawn(executable, cmdArgs, { cwd: serverDir, stdio: "inherit" }),
    "mcp-launcher-repo",
  );
}

function dispatch(forwardArgs) {
  if (forwardArgs.length === 0) {
    process.stderr.write(
      "mcp-launcher: missing args (npx flags or mcp-servers/<dir> <command> …)\n",
    );
    process.exit(1);
  }

  if (forwardArgs[0].startsWith("mcp-servers/")) {
    const [relDir, command, ...cmdArgs] = forwardArgs;
    runRepo(relDir, command, cmdArgs);
    return;
  }

  // npx mode: first arg must be either an npx flag (-y, -p, --package, etc.)
  // or a bare package spec (no leading "./", "/", or backslash). Surface a
  // clear diagnostic from the launcher layer rather than letting npx produce
  // a confusing ENOENT downstream when an unrecognized path slips through.
  const first = forwardArgs[0];
  if (first.startsWith("./") || first.startsWith("/") || first.includes("\\")) {
    process.stderr.write(
      `mcp-launcher: unrecognized server path: ${first} (expected npx flag/package or "mcp-servers/<dir>")\n`,
    );
    process.exit(1);
  }

  runNpx(forwardArgs);
}

module.exports = { attachLifecycle, dispatch, resolveWorktreeRoot, runNpx, runRepo };
