import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { buildDotnetInvocation, isInside, runDotnetFormat } from "./dotnet-format-staged.mjs";

const roots = [];

async function fixture() {
  const root = await mkdtemp(path.join(tmpdir(), "dotnet-format-staged-"));
  roots.push(root);
  await mkdir(path.join(root, "src"), { recursive: true });
  await writeFile(path.join(root, "Repository.sln"), "\n");
  await writeFile(path.join(root, "src", "Application.csproj"), "<Project />\n");
  await writeFile(path.join(root, "src", "Program.cs"), "namespace Example;\n");
  await writeFile(path.join(root, "src", "space name.cs"), "namespace Example;\n");
  return root;
}

test.after(async () => {
  await Promise.all(roots.map((root) => rm(root, { force: true, recursive: true })));
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
    /DOTNET_FORMAT_WORKSPACE must be a non-empty/,
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
    workspace: "Repository.sln",
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
    workspace: "Repository.sln",
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
