const { execSync, spawn } = require("node:child_process");
const os = require("node:os");
const path = require("node:path");

const QUOTE_RE = /(\\*)"/g;
const TRAILING_BACKSLASHES_RE = /(\\+)$/;
const CMD_META_RE = /([()[\]%!^"`<>&|;, *?])/g;

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

// C runtime argv quoting (backslashes before a quote doubled, quote as \"), then each cmd metacharacter
// ^-escaped twice: https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments
function escapeCmdShimArg(arg) {
  const quoted = `"${arg.replace(QUOTE_RE, '$1$1\\"').replace(TRAILING_BACKSLASHES_RE, "$1$1")}"`;
  return quoted.replace(CMD_META_RE, "^^^$1");
}

function runNpx(npxArgs) {
  const isWindows = process.platform === "win32";
  const nodeDir = path.dirname(process.execPath);
  const npxBinary = path.join(nodeDir, isWindows ? "npx.cmd" : "npx");
  let child;
  if (isWindows) {
    // A .cmd needs cmd.exe; windowsVerbatimArguments stops Node re-quoting, and `shell: true` is DEP0190:
    // https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows
    const inner = `"${npxBinary}" ${npxArgs.map(escapeCmdShimArg).join(" ")}`;
    child = spawn("cmd.exe", ["/d", "/s", "/c", `"${inner}"`], {
      stdio: "inherit",
      windowsVerbatimArguments: true,
    });
  } else {
    child = spawn(npxBinary, npxArgs, { stdio: "inherit" });
  }
  attachLifecycle(child, "mcp-launcher-npx");
}

function gitRevParse(flag) {
  return execSync(`git rev-parse ${flag}`, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

function resolveWorktreeRoot() {
  let gitCommonDir;
  try {
    gitCommonDir = gitRevParse("--git-common-dir");
  } catch {
    process.stderr.write("mcp-launcher: not inside a git repository\n");
    process.exit(1);
  }

  try {
    return gitRevParse("--show-toplevel");
  } catch {
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
  const worktreeResolved = path.resolve(resolveWorktreeRoot());
  const serverDir = path.resolve(worktreeResolved, safeRelDir);
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

  const first = forwardArgs[0];
  if (first.startsWith("./") || first.startsWith("/") || first.includes("\\")) {
    process.stderr.write(
      `mcp-launcher: unrecognized server path: ${first} (expected npx flag/package or "mcp-servers/<dir>")\n`,
    );
    process.exit(1);
  }

  runNpx(forwardArgs);
}

module.exports = {
  attachLifecycle,
  dispatch,
  escapeCmdShimArg,
  resolveWorktreeRoot,
  runNpx,
  runRepo,
};
