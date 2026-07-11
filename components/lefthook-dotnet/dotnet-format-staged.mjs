#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, realpathSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const WORKSPACE_EXTENSIONS = new Set([".csproj", ".sln", ".slnx"]);

export function isInside(root, candidate) {
  const relative = path.relative(root, candidate);
  const win32Relative = path.win32.relative(root, candidate);
  return (
    !path.isAbsolute(relative) &&
    !path.win32.isAbsolute(win32Relative) &&
    (relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".."))
  );
}

function portableRelative(root, candidate) {
  return path.relative(root, candidate).split(path.sep).join("/");
}

function resolveRepositoryPath(root, candidate, label) {
  if (typeof candidate !== "string" || candidate.trim() === "") {
    throw new Error(`${label} must be a non-empty repository-relative path`);
  }
  if (
    path.isAbsolute(candidate) ||
    path.win32.isAbsolute(candidate) ||
    /^[A-Za-z]:/.test(candidate)
  ) {
    throw new Error(`${label} must be repository-relative, not absolute: ${candidate}`);
  }
  const resolved = path.resolve(root, candidate);
  if (!isInside(root, resolved)) {
    throw new Error(`${label} escapes the repository: ${candidate}`);
  }
  return resolved;
}

export function buildDotnetInvocation({ root = process.cwd(), workspace, files = [] } = {}) {
  const resolvedRoot = realpathSync(root);
  const resolvedWorkspace = resolveRepositoryPath(
    resolvedRoot,
    workspace,
    "DOTNET_FORMAT_WORKSPACE",
  );
  if (!existsSync(resolvedWorkspace) || !statSync(resolvedWorkspace).isFile()) {
    throw new Error(`DOTNET_FORMAT_WORKSPACE does not name a file: ${workspace}`);
  }
  const workspaceRealPath = realpathSync(resolvedWorkspace);
  if (!isInside(resolvedRoot, workspaceRealPath)) {
    throw new Error(`DOTNET_FORMAT_WORKSPACE resolves outside the repository: ${workspace}`);
  }
  if (!WORKSPACE_EXTENSIONS.has(path.extname(workspaceRealPath).toLowerCase())) {
    throw new Error(
      `DOTNET_FORMAT_WORKSPACE must name a .sln, .slnx, or .csproj file: ${workspace}`,
    );
  }

  const includedFiles = [];
  const seen = new Set();
  for (const file of files) {
    const resolved = resolveRepositoryPath(resolvedRoot, file, "staged file");
    if (!existsSync(resolved)) {
      continue;
    }
    const fileRealPath = realpathSync(resolved);
    if (!isInside(resolvedRoot, fileRealPath)) {
      throw new Error(`staged file resolves outside the repository: ${file}`);
    }
    if (!statSync(fileRealPath).isFile() || path.extname(fileRealPath).toLowerCase() !== ".cs") {
      throw new Error(`staged file must name an existing C# source file: ${file}`);
    }
    const normalized = portableRelative(resolvedRoot, resolved);
    if (!seen.has(normalized)) {
      includedFiles.push(normalized);
      seen.add(normalized);
    }
  }

  return {
    command: "dotnet",
    args: [
      "format",
      "whitespace",
      portableRelative(resolvedRoot, resolvedWorkspace),
      "--verify-no-changes",
      ...(includedFiles.length > 0 ? ["--include", ...includedFiles] : []),
    ],
    cwd: resolvedRoot,
    skip: includedFiles.length === 0,
  };
}

export function runDotnetFormat({
  root = process.cwd(),
  workspace = process.env.DOTNET_FORMAT_WORKSPACE,
  files = process.argv.slice(2),
  spawn = spawnSync,
} = {}) {
  const invocation = buildDotnetInvocation({ root, workspace, files });
  if (invocation.skip) {
    return 0;
  }
  const result = spawn(invocation.command, invocation.args, {
    cwd: invocation.cwd,
    shell: false,
    stdio: "inherit",
  });
  if (result.error) {
    throw result.error;
  }
  if (typeof result.status !== "number") {
    throw new Error(
      `dotnet format ended without an exit status${result.signal ? ` (${result.signal})` : ""}`,
    );
  }
  return result.status;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    process.exitCode = runDotnetFormat();
  } catch (error) {
    process.stderr.write(
      `dotnet-format-staged: ${error instanceof Error ? error.message : String(error)}\n`,
    );
    process.exitCode = 2;
  }
}
