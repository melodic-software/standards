#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, realpathSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const WORKSPACE_EXTENSIONS = new Set([".csproj", ".sln", ".slnx"]);

function isWindowsShapedAbsolute(value) {
  return (
    path.win32.isAbsolute(value) &&
    (/^[A-Za-z]:[\\/]/.test(value) || /^\\/.test(value) || /^\/\/[^/]+\/[^/]+(?:\/|$)/.test(value))
  );
}

function isRelativeInside(pathApi, root, candidate) {
  const relative = pathApi.relative(root, candidate);
  return (
    !pathApi.isAbsolute(relative) &&
    (relative === "" || (!relative.startsWith(`..${pathApi.sep}`) && relative !== ".."))
  );
}

export function isInside(root, candidate) {
  const rootIsWindows = isWindowsShapedAbsolute(root);
  const candidateIsWindows = isWindowsShapedAbsolute(candidate);
  if (rootIsWindows || candidateIsWindows) {
    return rootIsWindows && candidateIsWindows && isRelativeInside(path.win32, root, candidate);
  }
  if (!path.isAbsolute(root) || !path.isAbsolute(candidate)) {
    return false;
  }
  return isRelativeInside(path, root, candidate);
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
