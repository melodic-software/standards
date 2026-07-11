#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const WORKSPACE_EXTENSIONS = new Set([".csproj", ".sln", ".slnx"]);
const DEFAULT_CONFIG_PATH = ".lefthook/dotnet-format.json";

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

function hasControlCharacter(value) {
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0);
    return codePoint <= 0x1f || codePoint === 0x7f;
  });
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

function validateWorkspaceValue(candidate) {
  if (typeof candidate !== "string" || candidate.trim() === "") {
    throw new Error("workspace must be a non-empty repository-relative path");
  }
  if (
    path.isAbsolute(candidate) ||
    path.win32.isAbsolute(candidate) ||
    /^[A-Za-z]:/.test(candidate)
  ) {
    throw new Error(`workspace must be repository-relative, not absolute: ${candidate}`);
  }
  if (
    candidate !== candidate.trim() ||
    hasControlCharacter(candidate) ||
    /[<>:"|?*\\]/.test(candidate)
  ) {
    throw new Error(
      "workspace must use forward slashes and portable path characters without surrounding whitespace",
    );
  }
  return candidate;
}

export function loadDotnetFormatConfig({ root = process.cwd() } = {}) {
  const resolvedRoot = realpathSync(root);
  const resolvedConfig = resolveRepositoryPath(resolvedRoot, DEFAULT_CONFIG_PATH, "config path");
  if (!existsSync(resolvedConfig)) {
    throw new Error(`missing required ${DEFAULT_CONFIG_PATH}`);
  }
  const configRealPath = realpathSync(resolvedConfig);
  if (!isInside(resolvedRoot, configRealPath) || !statSync(configRealPath).isFile()) {
    throw new Error(`${DEFAULT_CONFIG_PATH} must be a regular file inside the repository`);
  }
  let value;
  try {
    value = JSON.parse(readFileSync(configRealPath, "utf8"));
  } catch (error) {
    throw new Error(
      `${DEFAULT_CONFIG_PATH} must contain valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${DEFAULT_CONFIG_PATH} must contain an object`);
  }
  const allowedKeys = new Set(["schemaVersion", "workspace"]);
  const unknownKeys = Object.keys(value).filter((key) => !allowedKeys.has(key));
  if (unknownKeys.length > 0) {
    throw new Error(
      `${DEFAULT_CONFIG_PATH} contains unknown keys: ${unknownKeys.sort().join(", ")}`,
    );
  }
  const missingKeys = [...allowedKeys].filter((key) => !Object.hasOwn(value, key));
  if (missingKeys.length > 0) {
    throw new Error(`${DEFAULT_CONFIG_PATH} is missing required keys: ${missingKeys.join(", ")}`);
  }
  if (value.schemaVersion !== 1) {
    throw new Error(`${DEFAULT_CONFIG_PATH}.schemaVersion must be 1`);
  }
  return { schemaVersion: 1, workspace: validateWorkspaceValue(value.workspace) };
}

export function buildDotnetInvocation({ root = process.cwd(), workspace, files = [] } = {}) {
  const resolvedRoot = realpathSync(root);
  const workspaceValue = validateWorkspaceValue(workspace);
  const resolvedWorkspace = resolveRepositoryPath(resolvedRoot, workspaceValue, "workspace");
  if (!existsSync(resolvedWorkspace) || !statSync(resolvedWorkspace).isFile()) {
    throw new Error(`workspace does not name a file: ${workspaceValue}`);
  }
  const workspaceRealPath = realpathSync(resolvedWorkspace);
  if (!isInside(resolvedRoot, workspaceRealPath)) {
    throw new Error(`workspace resolves outside the repository: ${workspaceValue}`);
  }
  if (!WORKSPACE_EXTENSIONS.has(path.extname(workspaceRealPath).toLowerCase())) {
    throw new Error(`workspace must name a .sln, .slnx, or .csproj file: ${workspaceValue}`);
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
  files = process.argv.slice(2),
  spawn = spawnSync,
} = {}) {
  const { workspace } = loadDotnetFormatConfig({ root });
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
