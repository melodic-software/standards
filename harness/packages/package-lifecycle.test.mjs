import assert from "node:assert/strict";
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { parse } from "yaml";

import {
  checkPackageLifecycle,
  discoverPublishablePackages,
  normalizePackageDirectory,
  parseArguments,
  validateBaseRef,
} from "./package-lifecycle.mjs";

async function packagePair(t, version = "1.2.3") {
  const workspace = await mkdtemp(join(tmpdir(), "standards-package-test-"));
  t.after(() => rm(workspace, { recursive: true, force: true }));
  const source = join(workspace, "source");
  const baseline = join(workspace, "baseline");
  const current = join(workspace, "current");
  await mkdir(source);
  await writeFile(
    join(source, "package.json"),
    `${JSON.stringify({ name: "@example/config", version, files: ["config.json"] }, null, 2)}\n`,
  );
  await writeFile(join(source, "config.json"), '{"strict":true}\n');
  await cp(source, baseline, { recursive: true });
  await cp(source, current, { recursive: true });
  return { baseline, current };
}

async function updateManifest(directory, update) {
  const path = join(directory, "package.json");
  const value = JSON.parse(await readFile(path, "utf8"));
  update(value);
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

test("accepts an unchanged packed payload", async (t) => {
  const pair = await packagePair(t);
  const result = await checkPackageLifecycle({
    baselineDirectory: pair.baseline,
    currentDirectory: pair.current,
  });
  assert.equal(result.status, "unchanged");
});

test("requires a greater version when the packed payload changes", async (t) => {
  const pair = await packagePair(t);
  await writeFile(join(pair.current, "config.json"), '{"strict":true,"newRule":true}\n');
  await assert.rejects(
    checkPackageLifecycle({ baselineDirectory: pair.baseline, currentDirectory: pair.current }),
    /packed payload changed without a version greater than 1\.2\.3/,
  );
});

test("accepts a greater version for a changed payload", async (t) => {
  const pair = await packagePair(t);
  await writeFile(join(pair.current, "config.json"), '{"strict":true,"newRule":true}\n');
  await updateManifest(pair.current, (value) => {
    value.version = "1.3.0";
  });
  const result = await checkPackageLifecycle({
    baselineDirectory: pair.baseline,
    currentDirectory: pair.current,
  });
  assert.equal(result.status, "changed");
});

test("accepts a greater version when only the version changes", async (t) => {
  const pair = await packagePair(t);
  await updateManifest(pair.current, (value) => {
    value.version = "1.2.4";
  });
  const result = await checkPackageLifecycle({
    baselineDirectory: pair.baseline,
    currentDirectory: pair.current,
  });
  assert.equal(result.status, "version-only");
});

test("ignores fixture-only changes outside the packed payload", async (t) => {
  const pair = await packagePair(t);
  await mkdir(join(pair.current, "fixtures"));
  await writeFile(join(pair.current, "fixtures", "example.json"), '{"not":"packed"}\n');
  const result = await checkPackageLifecycle({
    baselineDirectory: pair.baseline,
    currentDirectory: pair.current,
  });
  assert.equal(result.status, "unchanged");
});

test("rejects version regressions", async (t) => {
  const pair = await packagePair(t);
  await updateManifest(pair.current, (value) => {
    value.version = "1.2.2";
  });
  await assert.rejects(
    checkPackageLifecycle({ baselineDirectory: pair.baseline, currentDirectory: pair.current }),
    /version regressed/,
  );
});

test("rejects prerelease versions", async (t) => {
  const pair = await packagePair(t);
  await updateManifest(pair.current, (value) => {
    value.version = "1.3.0-rc.1";
  });
  await assert.rejects(
    checkPackageLifecycle({ baselineDirectory: pair.baseline, currentDirectory: pair.current }),
    /prereleases are not published/,
  );
});

test("rejects package identity changes", async (t) => {
  const pair = await packagePair(t);
  await updateManifest(pair.current, (value) => {
    value.name = "@example/different";
  });
  await assert.rejects(
    checkPackageLifecycle({ baselineDirectory: pair.baseline, currentDirectory: pair.current }),
    /package identity changed/,
  );
});

test("accepts a new stable 0.x package", async (t) => {
  const pair = await packagePair(t, "0.1.0");
  const result = await checkPackageLifecycle({ currentDirectory: pair.current });
  assert.equal(result.status, "new");
});

test("normalizes in-repository package paths and rejects escapes", () => {
  const root = join(tmpdir(), "repository");
  assert.equal(
    normalizePackageDirectory(root, join("components", "example")),
    "components/example",
  );
  assert.throws(() => normalizePackageDirectory(root, join("..", "outside")), /must be a child/);
  assert.throws(() => normalizePackageDirectory(root, root), /must be a child/);
});

test("discovers publishable component manifests in deterministic order", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "standards-package-discovery-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const [name, value] of [
    ["zeta", { name: "@example/zeta", publishConfig: { registry: "https://npm.pkg.github.com" } }],
    ["private", { name: "private", private: true }],
    [
      "alpha",
      { name: "@example/alpha", publishConfig: { registry: "https://npm.pkg.github.com" } },
    ],
  ]) {
    await mkdir(join(root, "components", name), { recursive: true });
    await writeFile(join(root, "components", name, "package.json"), JSON.stringify(value));
  }
  assert.deepEqual(await discoverPublishablePackages(root), [
    "components/alpha",
    "components/zeta",
  ]);
});

test("rejects a non-private component without the approved registry", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "standards-package-discovery-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, "components", "example"), { recursive: true });
  await writeFile(
    join(root, "components", "example", "package.json"),
    JSON.stringify({ name: "@example/config" }),
  );
  await assert.rejects(discoverPublishablePackages(root), /must be private or set publishConfig/);
});

test("publish workflow matrix and component triggers match discovered packages", async () => {
  const root = fileURLToPath(new URL("../../", import.meta.url));
  const packages = await discoverPublishablePackages(root);
  const workflow = parse(
    await readFile(
      new URL("../../.github/workflows/publish-packages.yml", import.meta.url),
      "utf8",
    ),
  );
  const names = packages.map((directory) => directory.slice("components/".length));
  assert.deepEqual(workflow.jobs.publish.strategy.matrix.component, names);
  assert.deepEqual(workflow.on.push.paths, [
    ...packages.map((directory) => `${directory}/**`),
    ".github/workflows/publish-packages.yml",
  ]);
});

test("requires a nonzero full commit SHA baseline", () => {
  const sha = "a".repeat(40);
  assert.equal(validateBaseRef(sha), sha);
  assert.deepEqual(parseArguments([], { PACKAGE_BASE_REF: sha }), {
    baseRef: sha,
    packageDirectories: [],
  });
  assert.deepEqual(parseArguments(["--base-ref", sha, "components/example"], {}), {
    baseRef: sha,
    packageDirectories: ["components/example"],
  });
  assert.throws(() => parseArguments([], {}), /provide --base-ref/);
  assert.throws(() => validateBaseRef("HEAD"), /nonzero 40-character/);
  assert.throws(() => validateBaseRef("0".repeat(40)), /nonzero 40-character/);
});
