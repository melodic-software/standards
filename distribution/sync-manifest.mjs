#!/usr/bin/env node
// Validate and materialize the standards distribution manifest.
//
// Node port of the Bash+yq engine (standards-sync-audit Phase 6, ledger
// decision Q12). The CLI surface, stdout/stderr bytes, diagnostic text,
// check precedence, and exit codes are contract surface proven by
// distribution/sync-manifest.test.sh — change them only with the suite.
//
// Parser configuration is pinned (PLAN Phase 6 decision 6-A): YAML 1.2 core
// schema; merge keys NOT expanded (a plain `<<` key is detected and rejected,
// mirroring yq's !!merge tag); duplicate keys detected by an explicit
// whole-tree walk; the control-character class is POSIX [[:cntrl:]] =
// U+0000-U+001F plus U+007F exactly (never a Unicode Cc class, which also
// matches C1 and would silently widen the contract). The class and the NUL
// record separator are constructed from character codes so this source file
// itself carries no control bytes.

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { isAlias, isMap, isScalar, isSeq, parseAllDocuments } from "yaml";

const DEFAULT_MANIFEST = "distribution/sync-manifest.yml";
const NUL = String.fromCharCode(0);
const CONTROL_RE = new RegExp(`[${NUL}-${String.fromCharCode(31)}${String.fromCharCode(127)}]`);
const SPAWN_OPTS = { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 };

const USAGE = `Usage:
  sync-manifest.sh validate [--source-root DIR] [--manifest PATH]
  sync-manifest.sh matrix   [--source-root DIR] [--manifest PATH] [--targets CSV]
  sync-manifest.sh plan     [--source-root DIR] [--manifest PATH] [--targets CSV]
  sync-manifest.sh mappings   [--source-root DIR] [--manifest PATH] --target OWNER/REPO
  sync-manifest.sh dest-paths [--source-root DIR] [--manifest PATH] --target OWNER/REPO
  sync-manifest.sh apply      [--source-root DIR] [--manifest PATH] --target OWNER/REPO --target-root DIR

Commands:
  validate    Validate the schema, catalog, sources, and adoption graph.
  matrix      Emit only the filtered GitHub Actions matrix JSON.
  plan        Print the filtered, human-readable dry-run plan.
  mappings    Print Markdown bullets for one target's managed mappings.
  dest-paths  Print one managed destination path per line for machine use.
              Unknown targets exit 0 with no output (reusable PR-check no-op).
  apply       Copy one target's managed components and reproduce Git modes.

PATH is relative to source-root. --targets is a comma-separated exact
allowlist; empty selects every target in manifest order.
`;

function usage(stream) {
  stream.write(USAGE);
}

function die(message) {
  process.stderr.write(`error: ${message}\n`);
  process.exit(1);
}

function runGit(args) {
  return spawnSync("git", args, {
    ...SPAWN_OPTS,
    env: { ...process.env, LC_ALL: "C" },
  });
}

function requireCommand(name) {
  const probe = spawnSync(name, ["--version"], SPAWN_OPTS);
  if (probe.error) die(`required command not found: ${name}`);
}

// POSIX [:space:] only — JS String.prototype.trim also strips Unicode
// whitespace and would diverge from the Bash trim().
function trim(value) {
  return value.replace(/^[ \t\n\v\f\r]+/, "").replace(/[ \t\n\v\f\r]+$/, "");
}

function isSafeRepoPath(p) {
  if (!p) return false;
  if (p.startsWith("/")) return false;
  if (/^[A-Za-z]:/.test(p)) return false;
  if (p.includes("\\")) return false;
  if (p.endsWith("/")) return false;
  if (p.includes("//")) return false;
  if (CONTROL_RE.test(p)) return false;
  for (const segment of p.split("/")) {
    if (!segment || segment === "." || segment === "..") return false;
    if (!/^[A-Za-z0-9._-]+$/.test(segment)) return false;
    if (segment.toLowerCase() === ".git") return false;
  }
  return true;
}

function isDirectory(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function lstatOrNull(p) {
  try {
    return fs.lstatSync(p);
  } catch {
    return null;
  }
}

// realpathSync.native also expands Windows 8.3 short names (KYLESE~1 style),
// which plain realpathSync leaves alone — git rev-parse reports the long form,
// so both sides must normalize through the same resolver or the worktree-root
// equality check falsely fails on Windows dev machines.
function realPath(p) {
  return fs.realpathSync.native ? fs.realpathSync.native(p) : fs.realpathSync(p);
}

function canonicalGitRoot(requested) {
  if (!isDirectory(requested)) die(`Git root does not exist: ${requested}`);
  const physical = realPath(requested);
  const probe = runGit(["-C", physical, "rev-parse", "--show-toplevel"]);
  if (probe.error || probe.status !== 0) die(`not a Git worktree: ${requested}`);
  const gitRoot = realPath(probe.stdout.replace(/\r?\n$/, ""));
  if (physical !== gitRoot) {
    die(`path must be the Git worktree root (got ${physical}, root is ${gitRoot})`);
  }
  return physical;
}

// --- Git index plumbing -------------------------------------------------------
// One batched ls-files call and one batched hash-object call per root: the
// spawn-count contract in the suite asserts exactly one of each during a
// production validate.

let indexCacheRoot = "";
let indexEntryCache = new Map();
let indexEntryLoaded = new Set();
let worktreeHashCache = new Map();

function resetIndexCache() {
  indexCacheRoot = "";
  indexEntryCache = new Map();
  indexEntryLoaded = new Set();
  worktreeHashCache = new Map();
}

// Load Git index rows for one or more literal paths in a single ls-files call.
// Directory-shaped pathspecs may also select descendants; only rows whose
// recorded path exactly equals a requested path are attributed to that path.
function prefetchIndexEntries(root, paths) {
  if (paths.length === 0) return true;
  if (indexCacheRoot !== root) {
    resetIndexCache();
    indexCacheRoot = root;
  }
  const want = new Set();
  const toFetch = [];
  for (const p of paths) {
    if (indexEntryLoaded.has(p)) continue;
    want.add(p);
    toFetch.push(p);
    indexEntryLoaded.add(p);
    indexEntryCache.set(p, []);
  }
  if (toFetch.length === 0) return true;
  const result = runGit([
    "-C",
    root,
    "--literal-pathspecs",
    "-c",
    "core.quotePath=false",
    "ls-files",
    "--stage",
    "-z",
    "--",
    ...toFetch,
  ]);
  if (result.error || result.status !== 0) return false;
  for (const line of result.stdout.split(NUL)) {
    const tab = line.indexOf("\t");
    if (tab === -1) continue;
    const metadata = line.slice(0, tab);
    const recorded = line.slice(tab + 1);
    if (!want.has(recorded)) continue;
    indexEntryCache.get(recorded).push(metadata.split(" ").filter(Boolean));
  }
  return true;
}

function readExactIndexEntries(root, p) {
  if (indexCacheRoot !== root || !indexEntryLoaded.has(p)) {
    if (!prefetchIndexEntries(root, [p])) {
      die(`could not inspect Git index path: ${p}`);
    }
  }
  return indexEntryCache.get(p) ?? [];
}

function prefetchWorktreeHashes(root, paths) {
  if (paths.length === 0) return true;
  if (indexCacheRoot !== root) {
    resetIndexCache();
    indexCacheRoot = root;
  }
  const toHash = [];
  const claimed = new Set();
  for (const p of paths) {
    if (worktreeHashCache.has(p) || claimed.has(p)) continue;
    claimed.add(p);
    toHash.push(p);
  }
  if (toHash.length === 0) return true;
  const result = runGit(["-C", root, "hash-object", "--no-filters", "--", ...toHash]);
  if (result.error || result.status !== 0) return false;
  const hashes = result.stdout.split("\n").filter((line) => line !== "");
  if (hashes.length !== toHash.length) return false;
  for (let i = 0; i < toHash.length; i += 1) {
    worktreeHashCache.set(toHash[i], hashes[i]);
  }
  return true;
}

function assertTrackedRegularShape(root, p, purpose) {
  const entries = readExactIndexEntries(root, p);
  if (entries.length !== 1) {
    die(`${purpose} must be exactly one tracked stage-0 file: ${p}`);
  }
  const [mode, object, stage] = entries[0];
  if (stage !== "0") die(`${purpose} is unmerged in the Git index: ${p}`);
  if (mode !== "100644" && mode !== "100755") {
    die(`${purpose} must be a regular Git file (mode is ${mode}): ${p}`);
  }
  if (/^0+$/.test(object)) die(`${purpose} has no indexed object yet: ${p}`);
  const stat = lstatOrNull(path.join(root, p));
  if (!stat?.isFile() || stat.isSymbolicLink()) {
    die(`${purpose} must exist as a non-symlink regular worktree file: ${p}`);
  }
  return entries[0];
}

function trackedRegularMode(root, p, purpose) {
  const [mode, object] = assertTrackedRegularShape(root, p, purpose);
  let worktreeObject = worktreeHashCache.get(p);
  if (worktreeObject === undefined) {
    if (!prefetchWorktreeHashes(root, [p])) {
      die(`could not hash ${purpose} worktree file: ${p}`);
    }
    worktreeObject = worktreeHashCache.get(p);
  }
  if (worktreeObject === undefined) {
    die(`could not hash ${purpose} worktree file: ${p}`);
  }
  if (worktreeObject !== object) {
    die(`${purpose} worktree bytes differ from the indexed object: ${p}`);
  }
  return mode;
}

// --- YAML node helpers ----------------------------------------------------------

let manifestSource = "";
let manifestDoc = null;

function deref(node) {
  let current = node;
  while (isAlias(current)) current = current.resolve(manifestDoc);
  return current;
}

function rawScalarText(node) {
  if (typeof node.source === "string") return node.source;
  if (Array.isArray(node.range)) {
    return manifestSource.slice(node.range[0], node.range[1]);
  }
  return String(node.value);
}

// Mirror yq's tag resolution for the shapes the manifest contract names.
// A PLAIN `<<` key is !!merge (go-yaml resolves it that way even though this
// parser is configured with merge expansion off); quoted scalars are always
// !!str; int-vs-float is decided by the written form.
function tagOf(node) {
  const n = deref(node);
  if (n === null || n === undefined) return "!!null";
  if (isMap(n)) return "!!map";
  if (isSeq(n)) return "!!seq";
  if (!isScalar(n)) return "!!null";
  const { value } = n;
  const quoted = n.type !== undefined && n.type !== "PLAIN";
  if (!quoted && typeof value === "string" && rawScalarText(n) === "<<") {
    return "!!merge";
  }
  if (value === null) return "!!null";
  if (typeof value === "boolean") return "!!bool";
  if (typeof value === "bigint") return "!!int";
  if (typeof value === "number") {
    const raw = rawScalarText(n);
    if (/^[+-]?[0-9]+$/.test(raw) || /^0o[0-7]+$/.test(raw) || /^0x[0-9a-fA-F]+$/.test(raw)) {
      return "!!int";
    }
    return "!!float";
  }
  return "!!str";
}

function scalarKeyString(node) {
  const n = deref(node);
  if (isScalar(n)) return String(n.value);
  return String(n);
}

function mapItems(node) {
  return deref(node).items;
}

function findMapValue(mapNode, name) {
  for (const item of mapItems(mapNode)) {
    const key = deref(item.key);
    if (isScalar(key) && key.value === name) return item.value;
  }
  return undefined;
}

function mapHasKey(mapNode, name) {
  return findMapValue(mapNode, name) !== undefined;
}

// Whole-tree duplicate-mapping-key walk, mirroring yq's
// `[.. | select(tag == "!!map") | ((keys | length) == (keys | unique | length))] | all`.
function hasDuplicateMapKey(node) {
  const n = deref(node);
  if (isMap(n)) {
    const seen = new Set();
    for (const item of n.items) {
      const key = deref(item.key);
      const identity = isScalar(key)
        ? `${tagOf(key)} ${String(key.value)}`
        : `complex ${JSON.stringify(key.toJSON())}`;
      if (seen.has(identity)) return true;
      seen.add(identity);
      if (hasDuplicateMapKey(item.key)) return true;
      if (hasDuplicateMapKey(item.value)) return true;
    }
    return false;
  }
  if (isSeq(n)) {
    for (const item of n.items) {
      if (hasDuplicateMapKey(item)) return true;
    }
  }
  return false;
}

function assertSortedUnique(label, values) {
  const seen = new Set();
  let previous = "";
  let first = true;
  for (const value of values) {
    if (!value) die(`${label} contains an empty element`);
    if (seen.has(value)) die(`${label} contains duplicate '${value}'`);
    seen.add(value);
    if (!first && previous > value) {
      die(`${label} must be sorted ('${previous}' appears before '${value}')`);
    }
    first = false;
    previous = value;
  }
}

function validateRecordKeys(label, required, optional, keys) {
  let found = false;
  for (const key of keys) {
    if (key === required) {
      found = true;
      continue;
    }
    if (!optional.includes(key)) die(`${label} contains unknown key '${key}'`);
  }
  if (!found) die(`${label} is missing required key '${required}'`);
}

// --- Manifest validation --------------------------------------------------------

const componentNames = [];
const targetNames = [];
const componentExists = new Set();
const targetExists = new Set();
const filesByComponent = new Map();
const sourceModes = new Map();
const requiresByComponent = new Map();
const managedByTarget = new Map();
const localByTarget = new Map();
const automergeByTarget = new Map();

function checkRecordShell(kind, name, valueNode) {
  const node = deref(valueNode);
  if (tagOf(node) !== "!!map") die(`${kind} '${name}' must be a mapping`);
  let hasMerge = false;
  for (const item of node.items) {
    if (tagOf(item.key) === "!!merge") hasMerge = true;
  }
  if (hasMerge) die(`${kind} '${name}' merge keys are not supported`);
  const keyNodes = node.items.map((item) => deref(item.key));
  if (!keyNodes.every((key) => tagOf(key) === "!!str")) {
    die(`${kind} '${name}' keys must be strings`);
  }
  if (!keyNodes.every((key) => !CONTROL_RE.test(key.value))) {
    die(`${kind} '${name}' keys may not contain control characters`);
  }
  return { node, keys: keyNodes.map((key) => key.value) };
}

function stringSeqRows(seqNode) {
  return mapItems(seqNode).map((item) => deref(item));
}

function validateManifest(sourceRoot, manifest, manifestAbs) {
  const shape = lstatOrNull(manifestAbs);
  if (!shape?.isFile() || shape.isSymbolicLink()) {
    die(`manifest must exist as a non-symlink regular worktree file: ${manifest}`);
  }

  manifestSource = fs.readFileSync(manifestAbs, "utf8");
  const docs = parseAllDocuments(manifestSource, {
    version: "1.2",
    schema: "core",
    merge: false,
    uniqueKeys: false,
  });
  const parseErrors = docs.flatMap((doc) => doc.errors);
  if (docs.length !== 1 || parseErrors.length > 0) {
    die("manifest must be valid, single-document YAML");
  }
  manifestDoc = docs[0];
  const root = deref(manifestDoc.contents);
  if (tagOf(root) !== "!!map") die("manifest root must be a mapping");
  if (hasDuplicateMapKey(root)) die("manifest contains a duplicate mapping key");

  for (const item of root.items) {
    const key = scalarKeyString(item.key);
    if (key !== "version" && key !== "components" && key !== "targets") {
      die(`manifest root contains unknown key '${key}'`);
    }
  }
  for (const key of ["version", "components", "targets"]) {
    if (!mapHasKey(root, key)) die(`manifest root is missing '${key}'`);
  }
  const versionNode = deref(findMapValue(root, "version"));
  if (tagOf(versionNode) !== "!!int" || versionNode.value !== 2) {
    die("manifest version must be the integer 2");
  }
  const componentsNode = deref(findMapValue(root, "components"));
  if (tagOf(componentsNode) !== "!!map" || componentsNode.items.length === 0) {
    die("components must be a non-empty mapping");
  }
  const targetsNode = deref(findMapValue(root, "targets"));
  if (tagOf(targetsNode) !== "!!map" || targetsNode.items.length === 0) {
    die("targets must be a non-empty mapping");
  }
  if (!componentsNode.items.every((item) => tagOf(item.key) === "!!str")) {
    die("component names must be strings");
  }
  if (!componentsNode.items.every((item) => !CONTROL_RE.test(deref(item.key).value))) {
    die("component names may not contain control characters");
  }
  if (!targetsNode.items.every((item) => tagOf(item.key) === "!!str")) {
    die("target names must be strings");
  }
  if (!targetsNode.items.every((item) => !CONTROL_RE.test(deref(item.key).value))) {
    die("target names may not contain control characters");
  }

  for (const item of componentsNode.items) {
    componentNames.push(deref(item.key).value);
  }
  assertSortedUnique("component names", componentNames);
  for (const component of componentNames) {
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(component)) {
      die(`invalid component name '${component}' (expected lowercase kebab-case)`);
    }
    componentExists.add(component);
  }

  const destinationOwner = new Map();
  for (const item of componentsNode.items) {
    const component = deref(item.key).value;
    const { node, keys } = checkRecordShell("component", component, item.value);
    validateRecordKeys(`component '${component}'`, "files", ["requires"], keys);

    const filesNode = deref(findMapValue(node, "files"));
    if (tagOf(filesNode) !== "!!map" || filesNode.items.length === 0) {
      die(`component '${component}' files must be a non-empty mapping`);
    }
    const fileEntryNodes = filesNode.items.map((entry) => [deref(entry.key), deref(entry.value)]);
    if (!fileEntryNodes.every(([k, v]) => tagOf(k) === "!!str" && tagOf(v) === "!!str")) {
      die(`component '${component}' file sources and destinations must be strings`);
    }
    if (!fileEntryNodes.every(([k, v]) => !CONTROL_RE.test(k.value) && !CONTROL_RE.test(v.value))) {
      die(`component '${component}' file paths may not contain control characters`);
    }
    const fileRows = fileEntryNodes.map(([k, v]) => [k.value, v.value]);
    const fileSources = [];
    for (const [source] of fileRows) {
      if (!source) die(`component '${component}' has unsafe source path '${source}'`);
      fileSources.push(source);
    }
    assertSortedUnique(`component '${component}' file sources`, fileSources);
    const rows = [];
    for (const [source, destination] of fileRows) {
      if (!isSafeRepoPath(source)) {
        die(`component '${component}' has unsafe source path '${source}'`);
      }
      if (!isSafeRepoPath(destination)) {
        die(`component '${component}' has unsafe destination path '${destination}'`);
      }
      // A source MAY back multiple components: one canonical file fanning out
      // to per-destination components is the manifest's own answer to
      // consumers with different layouts. Destinations stay globally unique —
      // that is the write-conflict invariant.
      if (destinationOwner.has(destination)) {
        die(
          `destination '${destination}' is owned by both '${destinationOwner.get(destination)}' and '${component}'`,
        );
      }
      for (const [existing, owner] of destinationOwner) {
        if (destination.startsWith(`${existing}/`) || existing.startsWith(`${destination}/`)) {
          die(
            `destination '${destination}' in '${component}' has a file/directory conflict with '${existing}' in '${owner}'`,
          );
        }
      }
      destinationOwner.set(destination, component);
      rows.push([source, destination]);
    }
    filesByComponent.set(component, rows);

    requiresByComponent.set(component, []);
    if (keys.includes("requires")) {
      const requiresNode = deref(findMapValue(node, "requires"));
      if (tagOf(requiresNode) !== "!!seq" || requiresNode.items.length === 0) {
        die(`component '${component}' requires must be a non-empty sequence`);
      }
      const depNodes = stringSeqRows(requiresNode);
      if (!depNodes.every((dep) => tagOf(dep) === "!!str")) {
        die(`component '${component}' dependencies must be strings`);
      }
      if (!depNodes.every((dep) => !CONTROL_RE.test(dep.value))) {
        die(`component '${component}' dependencies may not contain control characters`);
      }
      const dependencies = depNodes.map((dep) => dep.value);
      assertSortedUnique(`component '${component}' dependencies`, dependencies);
      for (const dependency of dependencies) {
        if (!componentExists.has(dependency)) {
          die(`component '${component}' requires unknown component '${dependency}'`);
        }
        if (dependency === component) {
          die(`component '${component}' may not require itself`);
        }
        requiresByComponent.get(component).push(dependency);
      }
    }
  }

  const uniqueSources = [];
  const sourceSeen = new Set();
  for (const component of componentNames) {
    for (const [source] of filesByComponent.get(component)) {
      if (sourceSeen.has(source)) continue;
      sourceSeen.add(source);
      uniqueSources.push(source);
    }
  }
  resetIndexCache();
  if (!prefetchIndexEntries(sourceRoot, [manifest, ...uniqueSources])) {
    die(`could not inspect Git index path: ${manifest}`);
  }
  const hashPaths = [manifest];
  for (const source of uniqueSources) {
    const stat = lstatOrNull(path.join(sourceRoot, source));
    if (stat?.isFile() && !stat.isSymbolicLink()) hashPaths.push(source);
  }
  if (!prefetchWorktreeHashes(sourceRoot, hashPaths)) {
    die(`could not hash manifest worktree file: ${manifest}`);
  }
  trackedRegularMode(sourceRoot, manifest, "manifest");
  for (const component of componentNames) {
    for (const [source] of filesByComponent.get(component)) {
      const mode = trackedRegularMode(sourceRoot, source, `component '${component}' source`);
      sourceModes.set(source, mode);
    }
  }

  const visitState = new Map();
  const visitPath = [];
  const visitComponent = (component) => {
    const state = visitState.get(component);
    if (state === "done") return;
    if (state === "visiting") {
      // The Bash engine joins the cycle path with the FIRST character of its
      // multi-character IFS — a single space — then appends the closing arrow.
      die(`component dependency cycle: ${visitPath.join(" ")} -> ${component}`);
    }
    visitState.set(component, "visiting");
    visitPath.push(component);
    for (const dependency of requiresByComponent.get(component) ?? []) {
      visitComponent(dependency);
    }
    visitPath.pop();
    visitState.set(component, "done");
  };
  for (const component of componentNames) visitComponent(component);

  for (const item of targetsNode.items) {
    targetNames.push(deref(item.key).value);
  }
  assertSortedUnique("target names", targetNames);
  for (const target of targetNames) {
    if (!/^[a-z0-9][a-z0-9-]*\/[a-z0-9._-]+$/.test(target)) {
      die(`invalid target repository '${target}' (expected lowercase owner/repo)`);
    }
    targetExists.add(target);
  }

  for (const item of targetsNode.items) {
    const target = deref(item.key).value;
    const { node, keys } = checkRecordShell("target", target, item.value);
    validateRecordKeys(`target '${target}'`, "managed", ["locally-owned", "automerge"], keys);

    const managedNode = deref(findMapValue(node, "managed"));
    if (tagOf(managedNode) !== "!!seq" || managedNode.items.length === 0) {
      die(`target '${target}' managed must be a non-empty sequence`);
    }
    const managedNodes = stringSeqRows(managedNode);
    if (!managedNodes.every((entry) => tagOf(entry) === "!!str")) {
      die(`target '${target}' managed entries must be strings`);
    }
    if (!managedNodes.every((entry) => !CONTROL_RE.test(entry.value))) {
      die(`target '${target}' managed entries may not contain control characters`);
    }
    const managed = managedNodes.map((entry) => entry.value);
    assertSortedUnique(`target '${target}' managed components`, managed);

    let locallyOwned = [];
    if (keys.includes("locally-owned")) {
      const localNode = deref(findMapValue(node, "locally-owned"));
      if (tagOf(localNode) !== "!!seq" || localNode.items.length === 0) {
        die(`target '${target}' locally-owned must be a non-empty sequence when present`);
      }
      const localNodes = stringSeqRows(localNode);
      if (!localNodes.every((entry) => tagOf(entry) === "!!str")) {
        die(`target '${target}' locally-owned entries must be strings`);
      }
      if (!localNodes.every((entry) => !CONTROL_RE.test(entry.value))) {
        die(`target '${target}' locally-owned entries may not contain control characters`);
      }
      locallyOwned = localNodes.map((entry) => entry.value);
      assertSortedUnique(`target '${target}' locally-owned components`, locallyOwned);
    }

    // Absent means true: automerge is opt-out policy-as-data, so a target that
    // never mentions the key keeps the fleet-default armed behavior.
    let automergeValue = "true";
    if (keys.includes("automerge")) {
      const automergeNode = deref(findMapValue(node, "automerge"));
      if (tagOf(automergeNode) !== "!!bool") {
        die(`target '${target}' automerge must be a boolean`);
      }
      // Dual-engine window hardening (Phase 6.1 stress-test finding): yq's
      // @tsv emits a capitalized boolean verbatim into the matrix JSON while
      // this parser normalizes it — restrict the scalar to the two literal
      // spellings so both engines emit identical bytes.
      const raw = rawScalarText(automergeNode);
      if (raw !== "true" && raw !== "false") {
        die(`target '${target}' automerge must be the literal true or false`);
      }
      automergeValue = raw;
    }
    automergeByTarget.set(target, automergeValue);

    const selected = new Set();
    managedByTarget.set(target, []);
    localByTarget.set(target, []);
    for (const component of managed) {
      if (!componentExists.has(component)) {
        die(`target '${target}' manages unknown component '${component}'`);
      }
      selected.add(component);
      managedByTarget.get(target).push(component);
    }
    for (const component of locallyOwned) {
      if (!componentExists.has(component)) {
        die(`target '${target}' locally owns unknown component '${component}'`);
      }
      if (selected.has(component)) {
        die(`target '${target}' lists '${component}' as both managed and locally-owned`);
      }
      selected.add(component);
      localByTarget.get(target).push(component);
    }

    // A locally-owned implementation may satisfy a managed component's required
    // capability, but its own internal dependency closure remains downstream's.
    for (const component of managed) {
      for (const dependency of requiresByComponent.get(component) ?? []) {
        if (!selected.has(dependency)) {
          die(
            `target '${target}' manages '${component}' but does not select required '${dependency}'`,
          );
        }
      }
    }
  }

  // Every component must be reachable from at least one target selection —
  // directly managed or locally-owned, or inside the dependency closure of a
  // selected component. An unreferenced definition is dead weight the catalog
  // silently carries; delete it or adopt it.
  const reachable = new Set();
  const reachableQueue = [];
  for (const target of targetNames) {
    for (const component of [...managedByTarget.get(target), ...localByTarget.get(target)]) {
      if (reachable.has(component)) continue;
      reachable.add(component);
      reachableQueue.push(component);
    }
  }
  while (reachableQueue.length > 0) {
    const component = reachableQueue.pop();
    for (const dependency of requiresByComponent.get(component) ?? []) {
      if (reachable.has(dependency)) continue;
      reachable.add(dependency);
      reachableQueue.push(dependency);
    }
  }
  for (const component of componentNames) {
    if (!reachable.has(component)) {
      die(
        `component '${component}' is referenced by no target, directly or through a selected component's dependency closure`,
      );
    }
  }
}

// --- Selection and emitters -------------------------------------------------------

function selectTargets(filter) {
  if (!filter) return [...targetNames];
  const requested = new Set();
  for (const rawToken of filter.split(",")) {
    const token = trim(rawToken);
    if (!token) die("targets filter contains an empty repository name");
    if (!targetExists.has(token)) {
      die(`targets filter names unknown manifest target '${token}'`);
    }
    if (requested.has(token)) die(`targets filter contains duplicate '${token}'`);
    requested.add(token);
  }
  return targetNames.filter((target) => requested.has(target));
}

function emitMatrix(selected) {
  const rows = selected.map((target) => {
    const owner = target.slice(0, target.indexOf("/"));
    const repo = target.slice(owner.length + 1);
    return `{"repo":"${target}","repo_owner":"${owner}","repo_name":"${repo}","automerge":${automergeByTarget.get(target)}}`;
  });
  process.stdout.write(`{"include":[${rows.join(",")}]}\n`);
}

function emitManagedMappings(target) {
  for (const component of managedByTarget.get(target)) {
    for (const [source, destination] of filesByComponent.get(component)) {
      const mode = sourceModes.get(source);
      process.stdout.write(
        `- **${component}**: \`${source}\` → \`${destination}\` (mode \`${mode}\`)\n`,
      );
    }
  }
}

// Machine-readable companion to mappings: one destination path per line,
// sorted uniquely (code-unit order — destinations are ASCII by the safe-path
// contract, so this equals LC_ALL=C byte order), with no Markdown. Unknown
// targets are handled by the dest-paths dispatcher (exit 0, no output).
function emitManagedDestPaths(target) {
  const seen = new Set();
  for (const component of managedByTarget.get(target)) {
    for (const [, destination] of filesByComponent.get(component)) {
      seen.add(destination);
    }
  }
  const paths = [...seen].sort((a, b) => {
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
  });
  for (const destination of paths) process.stdout.write(`${destination}\n`);
}

function emitPlan(selected) {
  process.stdout.write("Distribution plan:\n");
  for (const target of selected) {
    process.stdout.write(`## ${target}\n`);
    process.stdout.write(`  automerge: ${automergeByTarget.get(target)}\n`);
    for (const component of managedByTarget.get(target)) {
      process.stdout.write(`  managed ${component}:\n`);
      for (const [source, destination] of filesByComponent.get(component)) {
        const mode = sourceModes.get(source);
        process.stdout.write(`    ${mode} ${source} -> ${destination}\n`);
      }
    }
    for (const component of localByTarget.get(target)) {
      process.stdout.write(`  locally-owned ${component} (not modified)\n`);
    }
  }
}

// --- Apply --------------------------------------------------------------------------

function verifyTargetIdentity(targetRoot, expected) {
  const result = runGit(["-C", targetRoot, "remote", "get-url", "--all", "origin"]);
  if (result.error || result.status !== 0) {
    die(`target checkout has no readable origin remote: ${expected}`);
  }
  const urls = result.stdout.split("\n").filter((line) => line !== "");
  if (urls.length !== 1) {
    die(`target checkout must have exactly one origin URL: ${expected}`);
  }
  const url = urls[0];
  const match =
    /^https:\/\/github\.com\/([A-Za-z0-9._-]+)\/([A-Za-z0-9._-]+)\/?$/.exec(url) ??
    /^git@github\.com:([A-Za-z0-9._-]+)\/([A-Za-z0-9._-]+)$/.exec(url) ??
    /^ssh:\/\/git@github\.com\/([A-Za-z0-9._-]+)\/([A-Za-z0-9._-]+)$/.exec(url);
  if (!match) die(`target origin is not an approved GitHub repository URL: ${url}`);
  let identity = `${match[1]}/${match[2]}`;
  identity = identity.replace(/\.git$/, "");
  if (identity.toLowerCase() !== expected) {
    die(`target origin identifies '${identity}', expected '${expected}'`);
  }
}

function preflightDestination(targetRoot, destination) {
  const parent = destination.includes("/")
    ? destination.slice(0, destination.lastIndexOf("/"))
    : "";
  if (parent) {
    let prefix = "";
    for (const segment of parent.split("/")) {
      prefix = prefix ? `${prefix}/${segment}` : segment;
      const stat = lstatOrNull(path.join(targetRoot, prefix));
      if (stat?.isSymbolicLink()) {
        die(`destination parent is a symlink: ${prefix}`);
      }
      if (stat && !stat.isDirectory()) {
        die(`destination parent is not a directory: ${prefix}`);
      }
      const entries = readExactIndexEntries(targetRoot, prefix);
      if (entries.length !== 0) {
        die(`destination parent is a tracked non-directory entry: ${prefix}`);
      }
    }
  }
  const stat = lstatOrNull(path.join(targetRoot, destination));
  if (stat?.isSymbolicLink()) die(`destination is a symlink: ${destination}`);
  const entries = readExactIndexEntries(targetRoot, destination);
  if (entries.length > 1) {
    die(`destination has multiple Git index entries: ${destination}`);
  }
  if (stat) {
    if (!stat.isFile()) {
      die(`destination exists but is not a regular file: ${destination}`);
    }
    if (entries.length !== 1) {
      die(`refusing to overwrite untracked destination: ${destination}`);
    }
    const [mode, , stage] = entries[0];
    if (stage !== "0" || (mode !== "100644" && mode !== "100755")) {
      die(`existing destination is not a tracked stage-0 regular file: ${destination}`);
    }
  } else if (entries.length !== 0) {
    die(`tracked destination is missing from the worktree: ${destination}`);
  }
}

function applyTarget(sourceRoot, target, targetRootRequested) {
  const targetRoot = canonicalGitRoot(targetRootRequested);
  verifyTargetIdentity(targetRoot, target);
  const components = managedByTarget.get(target);

  const indexPaths = [];
  const indexPathSeen = new Set();
  const queueDestinationIndexPath = (p) => {
    if (indexPathSeen.has(p)) return;
    indexPathSeen.add(p);
    indexPaths.push(p);
  };
  for (const component of components) {
    for (const [, destination] of filesByComponent.get(component)) {
      const parent = destination.includes("/")
        ? destination.slice(0, destination.lastIndexOf("/"))
        : "";
      if (parent) {
        let prefix = "";
        for (const segment of parent.split("/")) {
          prefix = prefix ? `${prefix}/${segment}` : segment;
          queueDestinationIndexPath(prefix);
        }
      }
      queueDestinationIndexPath(destination);
    }
  }
  if (indexPaths.length > 0) {
    if (!prefetchIndexEntries(targetRoot, indexPaths)) {
      die(`could not inspect Git index path: ${indexPaths[0]}`);
    }
  }
  // Validate all destinations before the first mutation. A later I/O error stops
  // the workflow before PR creation, so no partial component update is published.
  const sources = [];
  const destinations = [];
  const modes = [];
  for (const component of components) {
    for (const [source, destination] of filesByComponent.get(component)) {
      preflightDestination(targetRoot, destination);
      sources.push(source);
      destinations.push(destination);
      modes.push(sourceModes.get(source));
    }
  }
  for (let i = 0; i < sources.length; i += 1) {
    const destinationAbs = path.join(targetRoot, destinations[i]);
    fs.mkdirSync(path.dirname(destinationAbs), { recursive: true });
    fs.copyFileSync(path.join(sourceRoot, sources[i]), destinationAbs);
    if (modes[i] === "100644") fs.chmodSync(destinationAbs, 0o644);
    else if (modes[i] === "100755") fs.chmodSync(destinationAbs, 0o755);
    else die(`internal error: unsupported validated mode '${modes[i]}'`);
    process.stdout.write(`synced ${sources[i]} -> ${destinations[i]} (${modes[i]})\n`);
  }
}

// --- CLI ----------------------------------------------------------------------------

function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0) {
    usage(process.stderr);
    process.exit(2);
  }
  const command = argv.shift() ?? "";
  if (command === "-h" || command === "--help") {
    usage(process.stdout);
    process.exit(0);
  }
  if (!["validate", "matrix", "plan", "mappings", "dest-paths", "apply"].includes(command)) {
    usage(process.stderr);
    die(`unknown command '${command}'`);
  }

  const scriptDir = realPath(path.dirname(fileURLToPath(import.meta.url)));
  const rootProbe = runGit(["-C", scriptDir, "rev-parse", "--show-toplevel"]);
  let sourceRoot =
    rootProbe.error || rootProbe.status !== 0 ? "" : rootProbe.stdout.replace(/\r?\n$/, "");
  let manifest = DEFAULT_MANIFEST;
  let targetsFilter = "";
  let target = "";
  let targetRoot = "";
  // if/else rather than switch: the CI-pinned biome (2.5.1) misinfers every
  // case label on a switch over an argv-derived string as unreachable.
  while (argv.length > 0) {
    const argument = argv.shift() ?? "";
    if (argument === "--source-root") {
      if (argv.length < 1) die("--source-root requires a value");
      sourceRoot = argv.shift() ?? "";
    } else if (argument === "--manifest") {
      if (argv.length < 1) die("--manifest requires a value");
      manifest = argv.shift() ?? "";
    } else if (argument === "--targets") {
      if (argv.length < 1) die("--targets requires a value");
      targetsFilter = argv.shift() ?? "";
    } else if (argument === "--target") {
      if (argv.length < 1) die("--target requires a value");
      target = argv.shift() ?? "";
    } else if (argument === "--target-root") {
      if (argv.length < 1) die("--target-root requires a value");
      targetRoot = argv.shift() ?? "";
    } else if (argument === "-h" || argument === "--help") {
      usage(process.stdout);
      process.exit(0);
    } else {
      die(`unknown argument '${argument}'`);
    }
  }

  requireCommand("git");
  sourceRoot = canonicalGitRoot(sourceRoot);
  if (!isSafeRepoPath(manifest)) die(`unsafe manifest path '${manifest}'`);
  const manifestAbs = path.join(sourceRoot, manifest);

  if (command === "validate") {
    if (targetsFilter || target || targetRoot) {
      die("validate does not accept --targets, --target, or --target-root");
    }
  } else if (command === "matrix" || command === "plan") {
    if (target || targetRoot) {
      die(`${command} does not accept --target or --target-root`);
    }
  } else if (command === "mappings" || command === "dest-paths") {
    if (targetsFilter || targetRoot) {
      die(`${command} does not accept --targets or --target-root`);
    }
    if (!target) die(`${command} requires --target OWNER/REPO`);
  } else if (command === "apply") {
    if (targetsFilter) die("apply does not accept --targets");
    if (!target) die("apply requires --target OWNER/REPO");
    if (!targetRoot) die("apply requires --target-root DIR");
  } else {
    die(`internal error: unsupported command '${command}'`);
  }

  validateManifest(sourceRoot, manifest, manifestAbs);
  if (command === "validate") {
    process.stdout.write(
      `Manifest valid: ${componentNames.length} components, ${targetNames.length} targets\n`,
    );
  } else if (command === "matrix") {
    emitMatrix(selectTargets(targetsFilter));
  } else if (command === "plan") {
    emitPlan(selectTargets(targetsFilter));
  } else if (command === "mappings") {
    if (!targetExists.has(target)) die(`unknown manifest target '${target}'`);
    emitManagedMappings(target);
  } else if (command === "dest-paths") {
    // Unknown targets are a successful empty result so shared PR checks can
    // no-op outside the manifest. mappings/apply keep the hard error.
    if (targetExists.has(target)) emitManagedDestPaths(target);
  } else if (command === "apply") {
    if (!targetExists.has(target)) die(`unknown manifest target '${target}'`);
    applyTarget(sourceRoot, target, targetRoot);
  } else {
    die(`internal error: unsupported command '${command}'`);
  }
}

main();
