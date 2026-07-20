import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildDotnetInvocation,
  isInside,
  loadDotnetFormatConfig,
  runDotnetFormat,
} from "./dotnet-format-staged.mjs";

const roots = [];
const LEFTHOOK_CLI = fileURLToPath(
  new URL("../../node_modules/lefthook/bin/index.js", import.meta.url),
);

function configPath(root) {
  return path.join(root, ".lefthook", "dotnet-format.json");
}

async function writeConfig(root, value) {
  const source = typeof value === "string" ? value : `${JSON.stringify(value, null, 2)}\n`;
  await writeFile(configPath(root), source);
}

function assertSpawnSucceeded(result) {
  assert.equal(
    result.status,
    0,
    [result.error?.message, result.stdout, result.stderr].filter(Boolean).join("\n"),
  );
}

function runLefthook(root, args, environment = {}) {
  const result = spawnSync(process.execPath, [LEFTHOOK_CLI, ...args], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      LEFTHOOK_CONFIG: "lefthook.yml",
      NO_COLOR: "1",
      ...environment,
    },
    shell: false,
  });
  assertSpawnSucceeded(result);
  return result.stdout.trim();
}

async function fixture() {
  const root = await mkdtemp(path.join(tmpdir(), "dotnet-format-staged-"));
  roots.push(root);
  await mkdir(path.join(root, ".lefthook"), { recursive: true });
  await mkdir(path.join(root, "src"), { recursive: true });
  await writeFile(path.join(root, "Repository.sln"), "\n");
  await writeFile(path.join(root, "src", "Application.csproj"), "<Project />\n");
  await writeFile(path.join(root, "src", "My Workspace.csproj"), "<Project />\n");
  await writeFile(path.join(root, "src", "Program.cs"), "namespace Example;\n");
  await writeFile(path.join(root, "src", "space name.cs"), "namespace Example;\n");
  await writeConfig(root, { schemaVersion: 1, workspace: "Repository.sln" });
  return root;
}

test.after(async () => {
  await Promise.all(roots.map((root) => rm(root, { force: true, recursive: true })));
});

test("pinned Lefthook validates, dumps, and runs the production config contract", async () => {
  const root = await fixture();
  const workspace = "src/My Workspace;$(not-run).csproj";
  await writeFile(path.join(root, workspace), "<Project />\n");
  await writeConfig(root, { schemaVersion: 1, workspace });
  const gitInit = spawnSync("git", ["init", "--quiet"], {
    cwd: root,
    encoding: "utf8",
    shell: false,
  });
  assertSpawnSucceeded(gitInit);
  await writeFile(
    path.join(root, ".lefthook", "base.yml"),
    await readFile(new URL("../lefthook-base/lefthook.yml", import.meta.url), "utf8"),
  );
  await writeFile(
    path.join(root, ".lefthook", "dotnet.yml"),
    await readFile(new URL("./lefthook.yml", import.meta.url), "utf8"),
  );
  await writeFile(
    path.join(root, ".lefthook", "dotnet-format-staged.mjs"),
    await readFile(new URL("./dotnet-format-staged.mjs", import.meta.url), "utf8"),
  );
  await writeFile(
    path.join(root, "lefthook.yml"),
    `extends:
  - .lefthook/base.yml
  - .lefthook/dotnet.yml
`,
  );

  const packageJson = JSON.parse(
    await readFile(new URL("../../package.json", import.meta.url), "utf8"),
  );
  assert.equal(runLefthook(root, ["version"]), packageJson.devDependencies.lefthook);
  assert.match(runLefthook(root, ["validate", "--verbose"]), /All good/);

  const config = JSON.parse(runLefthook(root, ["dump", "--format", "json"]));
  const dotnetJobs = config["pre-commit"].jobs.filter(({ name }) => name === "dotnet-format");
  assert.equal(dotnetJobs.length, 1);
  assert.equal(dotnetJobs[0].run, "node .lefthook/dotnet-format-staged.mjs {staged_files}");
  assert.deepEqual(dotnetJobs[0].glob, ["**/*.cs"]);
  assert.equal(
    dotnetJobs[0].fail_text,
    "Whitespace/layout drift or invalid dotnet-format.json. Run: dotnet format whitespace <workspace> --include <files>",
  );
  assert.equal(config.templates, undefined);
  assert.equal(config["pre-commit"].commands?.["dotnet-format"], undefined);

  const fakeBin = path.join(root, "fake-bin");
  await mkdir(fakeBin);
  const fakeDotnet = path.join(fakeBin, process.platform === "win32" ? "dotnet.exe" : "dotnet");
  if (process.platform === "win32") {
    await copyFile(process.execPath, fakeDotnet);
  } else {
    await symlink(process.execPath, fakeDotnet);
  }
  await writeFile(
    path.join(root, "format"),
    `require("node:fs").writeFileSync(
  "dotnet-args.json",
  JSON.stringify(process.argv.slice(2)),
);
`,
  );
  runLefthook(root, ["run", "pre-commit", "--job", "dotnet-format", "--file", "src/Program.cs"], {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
  });
  assert.deepEqual(JSON.parse(await readFile(path.join(root, "dotnet-args.json"), "utf8")), [
    "whitespace",
    workspace,
    "--verify-no-changes",
    "--include",
    "src/Program.cs",
  ]);
});

test("loads only the strict versioned consumer config", async () => {
  const root = await fixture();
  assert.deepEqual(loadDotnetFormatConfig({ root }), {
    schemaVersion: 1,
    workspace: "Repository.sln",
  });

  await rm(configPath(root));
  assert.throws(() => loadDotnetFormatConfig({ root }), /missing required.*dotnet-format\.json/);

  for (const [value, message] of [
    ["{", /must contain valid JSON/],
    [[], /must contain an object/],
    [{ schemaVersion: 2, workspace: "Repository.sln" }, /schemaVersion must be 1/],
    [
      { schemaVersion: 1, workspace: "Repository.sln", unexpected: true },
      /contains unknown keys: unexpected/,
    ],
    [{ schemaVersion: 1 }, /missing required keys: workspace/],
    [{ workspace: "Repository.sln" }, /missing required keys: schemaVersion/],
    [{ schemaVersion: 1, workspace: "" }, /workspace must be a non-empty/],
    [{ schemaVersion: 1, workspace: [] }, /workspace must be a non-empty/],
    [
      { schemaVersion: 1, workspace: "src/line\nbreak.csproj" },
      /workspace must use forward slashes/,
    ],
  ]) {
    await writeConfig(root, value);
    assert.throws(() => loadDotnetFormatConfig({ root }), message, JSON.stringify(value));
  }
});

test("configured unsafe workspaces fail before dotnet is spawned", async () => {
  const root = await fixture();
  for (const [workspace, message] of [
    ["../outside.sln", /workspace escapes the repository/],
    [String.raw`C:\outside\Repository.sln`, /workspace must be repository-relative/],
    ["src", /workspace does not name a file/],
    ["src/Program.cs", /workspace must name a .sln, .slnx, or .csproj/],
    [" src/Application.csproj", /workspace must use forward slashes/],
    [String.raw`src\Application.csproj`, /workspace must use forward slashes/],
  ]) {
    await writeConfig(root, { schemaVersion: 1, workspace });
    let called = false;
    assert.throws(
      () =>
        runDotnetFormat({
          root,
          files: ["src/Program.cs"],
          spawn: () => {
            called = true;
            return { status: 0 };
          },
        }),
      message,
      workspace,
    );
    assert.equal(called, false, workspace);
  }
});

test("builds one explicit-workspace invocation with normalized staged paths", async () => {
  const root = await fixture();
  const invocation = buildDotnetInvocation({
    root,
    workspace: "Repository.sln",
    files: ["src/Program.cs", "src/space name.cs", "src/Program.cs"],
  });
  assert.equal(invocation.command, "dotnet");
  assert.deepEqual(invocation.args, [
    "format",
    "whitespace",
    "Repository.sln",
    "--verify-no-changes",
    "--include",
    "src/Program.cs",
    "src/space name.cs",
  ]);
  assert.equal(invocation.skip, false);
});

test("fails closed when the workspace is absent or not an explicit supported file", async () => {
  const root = await fixture();
  assert.throws(
    () => buildDotnetInvocation({ root, files: ["src/Program.cs"] }),
    /workspace must be a non-empty/,
  );
  assert.throws(
    () =>
      buildDotnetInvocation({
        root,
        workspace: "src",
        files: ["src/Program.cs"],
      }),
    /does not name a file/,
  );
  assert.throws(
    () =>
      buildDotnetInvocation({
        root,
        workspace: "../outside.sln",
        files: ["src/Program.cs"],
      }),
    /escapes the repository/,
  );
  for (const candidate of [" src/Application.csproj", String.raw`src\Application.csproj`]) {
    assert.throws(
      () => buildDotnetInvocation({ root, workspace: candidate, files: ["src/Program.cs"] }),
      /workspace must use forward slashes/,
      candidate,
    );
  }
});

test("rejects Windows drive-qualified, drive-relative, UNC, and cross-volume paths", async () => {
  const root = await fixture();
  for (const candidate of [
    String.raw`C:\repo\Repository.sln`,
    "D:foo",
    String.raw`\\server\share\Repository.sln`,
  ]) {
    assert.throws(
      () =>
        buildDotnetInvocation({
          root,
          workspace: candidate,
          files: ["src/Program.cs"],
        }),
      /must be repository-relative, not absolute/,
      candidate,
    );
    assert.throws(
      () =>
        buildDotnetInvocation({
          root,
          workspace: "Repository.sln",
          files: [candidate],
        }),
      /must be repository-relative, not absolute/,
      `staged file: ${candidate}`,
    );
  }
});

test("uses Windows semantics for Windows-shaped absolute paths on every host", () => {
  for (const [root, candidate, expected] of [
    [String.raw`C:\repo`, String.raw`C:\repo`, true],
    [String.raw`C:\repo`, String.raw`C:\repo\src\Program.cs`, true],
    [String.raw`C:\repo`, "C:/repo/src/Program.cs", true],
    [String.raw`C:\repo`, String.raw`C:\repository\Program.cs`, false],
    [String.raw`C:\repo`, String.raw`C:\outside\Program.cs`, false],
    [String.raw`C:\repo`, String.raw`D:\repo\Program.cs`, false],
    [String.raw`\\server\share\repo`, String.raw`\\server\share\repo\src\Program.cs`, true],
    [String.raw`\\server\share\repo`, String.raw`\\server\other\repo\Program.cs`, false],
  ]) {
    assert.equal(isInside(root, candidate), expected, `${root} -> ${candidate}`);
  }
});

test("rejects mixed path flavors and non-absolute containment inputs", () => {
  assert.equal(isInside(String.raw`C:\repo`, "/repo/src/Program.cs"), false);
  assert.equal(isInside("/repo", String.raw`C:\repo\src\Program.cs`), false);
  assert.equal(isInside("repo", "repo/src/Program.cs"), false);
  assert.equal(isInside("/repo", "repo/src/Program.cs"), false);
});

test("uses native semantics for native absolute paths", () => {
  const nativeRoot = path.resolve(path.parse(process.cwd()).root, "repo");
  assert.equal(isInside(nativeRoot, nativeRoot), true);
  assert.equal(isInside(nativeRoot, path.join(nativeRoot, "src", "Program.cs")), true);
  assert.equal(
    isInside(nativeRoot, path.resolve(nativeRoot, "..", "outside", "Program.cs")),
    false,
  );

  assert.equal(isInside("/repo", "/repo/src/Program.cs"), true);
  assert.equal(isInside("/repo", "/repository/Program.cs"), false);
  assert.equal(isInside("/repo", "/outside/Program.cs"), false);
});

test("accepts valid repository-relative workspace and staged-file paths", async () => {
  const root = await fixture();
  assert.equal(isInside(root, path.join(root, "src", "Program.cs")), true);
  assert.doesNotThrow(() =>
    buildDotnetInvocation({
      root,
      workspace: "src/Application.csproj",
      files: ["src/Program.cs"],
    }),
  );
});

test("ignores staged deletions without falling back to whole-workspace formatting", async () => {
  const root = await fixture();
  const invocation = buildDotnetInvocation({
    root,
    workspace: "Repository.sln",
    files: ["src/Deleted.cs"],
  });
  assert.equal(invocation.skip, true);
  let called = false;
  const status = runDotnetFormat({
    root,
    files: ["src/Deleted.cs"],
    spawn: () => {
      called = true;
      return { status: 0 };
    },
  });
  assert.equal(status, 0);
  assert.equal(called, false);
});

test("spawns dotnet without a shell and propagates its status", async () => {
  const root = await fixture();
  let captured;
  const status = runDotnetFormat({
    root,
    files: ["src/space name.cs"],
    spawn: (command, args, options) => {
      captured = { command, args, options };
      return { status: 7 };
    },
  });
  assert.equal(status, 7);
  assert.equal(captured.command, "dotnet");
  assert.deepEqual(captured.args.slice(-2), ["--include", "src/space name.cs"]);
  assert.equal(captured.options.shell, false);
  assert.equal(captured.options.cwd, path.resolve(root));
});
