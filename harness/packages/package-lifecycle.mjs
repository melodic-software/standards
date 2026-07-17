import { spawnSync } from "node:child_process";
import { access, mkdir, mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

import semver from "semver";

const PACKAGE_REGISTRY = "https://npm.pkg.github.com";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed (${result.status})\n${result.stdout}${result.stderr}`,
    );
  }
  return result.stdout;
}

async function npm(args, cwd) {
  const npmCli = process.env.npm_execpath;
  if (npmCli) return run(process.execPath, [npmCli, ...args], { cwd });
  if (process.platform === "win32") {
    const bundledNpmCli = join(
      dirname(process.execPath),
      "node_modules",
      "npm",
      "bin",
      "npm-cli.js",
    );
    await access(bundledNpmCli);
    return run(process.execPath, [bundledNpmCli, ...args], { cwd });
  }
  return run("npm", args, { cwd });
}

async function manifest(directory) {
  return JSON.parse(await readFile(join(directory, "package.json"), "utf8"));
}

export async function discoverPublishablePackages(root) {
  const components = join(root, "components");
  const entries = await readdir(components, { withFileTypes: true });
  const packages = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isDirectory()) continue;
    const directory = join(components, entry.name);
    let value;
    try {
      value = await manifest(directory);
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    if (value.private === true) continue;
    if (value.publishConfig?.registry !== PACKAGE_REGISTRY) {
      throw new Error(
        `components/${entry.name}/package.json must be private or set publishConfig.registry to ${PACKAGE_REGISTRY}`,
      );
    }
    packages.push(`components/${entry.name}`);
  }
  return packages;
}

function releaseVersion(value, label) {
  if (semver.valid(value) !== value) {
    throw new Error(
      `${label} must be an exact semantic version; received ${JSON.stringify(value)}`,
    );
  }
  if (semver.prerelease(value) !== null) {
    throw new Error(`${label} must be a stable release version; prereleases are not published`);
  }
  return value;
}

async function pack(directory, destination) {
  await mkdir(destination, { recursive: true });
  const output = await npm(
    ["pack", "--json", "--ignore-scripts", "--pack-destination", destination],
    directory,
  );
  const result = JSON.parse(output);
  if (!Array.isArray(result) || result.length !== 1 || !result[0].filename) {
    throw new Error(`npm pack returned an unexpected result for ${directory}`);
  }
  const extracted = join(destination, "extracted");
  await mkdir(extracted);
  // Relative paths from `destination`, not absolute ones: GNU tar parses a
  // drive-letter path (C:\...) as a remote host:file archive, so an absolute
  // Windows path breaks under Git Bash's tar while bsdtar rejects the
  // --force-local flag that would disable that parsing.
  run("tar", ["-xzf", result[0].filename, "-C", "extracted"], { cwd: destination });
  return extracted;
}

async function files(directory, prefix = "") {
  const result = new Map();
  const entries = await readdir(directory, { withFileTypes: true });
  entries.sort((left, right) => left.name.localeCompare(right.name));
  for (const entry of entries) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      for (const [name, contents] of await files(path, relative)) result.set(name, contents);
    } else if (entry.isFile()) {
      let contents = await readFile(path);
      if (relative === "package/package.json") {
        const normalized = contents
          .toString("utf8")
          .replace(/("version"\s*:\s*)"(?:\\.|[^"\\])*"/, '$1"__VERSION__"');
        contents = Buffer.from(normalized);
      }
      result.set(relative, contents);
    } else {
      throw new Error(`packed payload contains unsupported entry ${relative}`);
    }
  }
  return result;
}

function payloadsEqual(left, right) {
  if (left.size !== right.size) return false;
  for (const [path, contents] of left) {
    if (!right.has(path) || !contents.equals(right.get(path))) return false;
  }
  return true;
}

export async function checkPackageLifecycle({ baselineDirectory, currentDirectory }) {
  const current = await manifest(currentDirectory);
  const currentVersion = releaseVersion(
    current.version,
    `${current.name ?? currentDirectory} version`,
  );

  if (!baselineDirectory) {
    const workspace = await mkdtemp(join(tmpdir(), "standards-package-lifecycle-"));
    try {
      await files(await pack(currentDirectory, join(workspace, "current")));
      return { name: current.name, version: currentVersion, status: "new" };
    } finally {
      await rm(workspace, { recursive: true, force: true });
    }
  }

  const baseline = await manifest(baselineDirectory);
  const baselineVersion = releaseVersion(
    baseline.version,
    `${baseline.name ?? baselineDirectory} baseline version`,
  );
  if (current.name !== baseline.name) {
    throw new Error(
      `package identity changed from ${JSON.stringify(baseline.name)} to ${JSON.stringify(current.name)}`,
    );
  }
  if (semver.lt(currentVersion, baselineVersion)) {
    throw new Error(
      `${current.name} version regressed from ${baselineVersion} to ${currentVersion}`,
    );
  }

  const workspace = await mkdtemp(join(tmpdir(), "standards-package-lifecycle-"));
  try {
    const baselinePayload = await files(await pack(baselineDirectory, join(workspace, "baseline")));
    const currentPayload = await files(await pack(currentDirectory, join(workspace, "current")));
    const changed = !payloadsEqual(baselinePayload, currentPayload);
    if (changed && !semver.gt(currentVersion, baselineVersion)) {
      throw new Error(
        `${current.name} packed payload changed without a version greater than ${baselineVersion}`,
      );
    }
    return {
      name: current.name,
      version: currentVersion,
      status: changed
        ? "changed"
        : semver.gt(currentVersion, baselineVersion)
          ? "version-only"
          : "unchanged",
    };
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
}

export function normalizePackageDirectory(root, input) {
  const normalizedRoot = resolve(root);
  const absolute = resolve(normalizedRoot, input);
  const fromRoot = relative(normalizedRoot, absolute);
  if (!fromRoot || fromRoot === ".." || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
    throw new Error(`package directory must be a child of the repository: ${input}`);
  }
  return fromRoot.replaceAll("\\", "/");
}

export function validateBaseRef(value) {
  if (!/^[0-9a-f]{40}$/iu.test(value) || /^0{40}$/u.test(value)) {
    throw new Error("package baseline must be a nonzero 40-character Git commit SHA");
  }
  return value;
}

export function parseArguments(argv, environment = process.env) {
  let baseRef = environment.PACKAGE_BASE_REF;
  const packageDirectories = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--base-ref") {
      baseRef = argv[index + 1];
      index += 1;
    } else {
      packageDirectories.push(argv[index]);
    }
  }
  if (!baseRef) throw new Error("provide --base-ref <git-ref> or PACKAGE_BASE_REF");
  return {
    baseRef: validateBaseRef(baseRef),
    packageDirectories,
  };
}

async function exportBaseline(root, baseRef, packageDirectory, destination) {
  const object = `${baseRef}:${packageDirectory.replaceAll("\\", "/")}/package.json`;
  const exists = spawnSync("git", ["cat-file", "-e", object], { cwd: root });
  if (exists.status !== 0) return undefined;

  const archive = join(destination, `${basename(packageDirectory)}.tar`);
  run("git", ["archive", "--format=tar", `--output=${archive}`, baseRef, "--", packageDirectory], {
    cwd: root,
  });
  // Same drive-letter constraint as the pack extraction above: keep tar's
  // arguments relative so GNU tar never sees a C:\ path it would treat as a
  // remote host:file archive.
  run("tar", ["-xf", basename(archive), "-C", "."], { cwd: destination });
  return join(destination, packageDirectory);
}

async function main() {
  const root = resolve(run("git", ["rev-parse", "--show-toplevel"]).trim());
  const { baseRef, packageDirectories } = parseArguments(process.argv.slice(2));
  run("git", ["cat-file", "-e", `${baseRef}^{commit}`], { cwd: root });
  const selectedPackages = packageDirectories.length
    ? packageDirectories
    : await discoverPublishablePackages(root);
  const normalizedPackages = selectedPackages.map((directory) =>
    normalizePackageDirectory(root, directory),
  );
  const workspace = await mkdtemp(join(tmpdir(), "standards-package-baseline-"));
  try {
    for (const packageDirectory of normalizedPackages) {
      const baselineDirectory = await exportBaseline(root, baseRef, packageDirectory, workspace);
      const result = await checkPackageLifecycle({
        baselineDirectory,
        currentDirectory: join(root, packageDirectory),
      });
      process.stdout.write(`${result.name}@${result.version}: ${result.status}\n`);
    }
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
