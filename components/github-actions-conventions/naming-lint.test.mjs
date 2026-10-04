import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import Ajv2020 from "ajv/dist/2020.js";

import {
  ConfigurationError,
  checkActivityName,
  formatAnnotation,
  lintRepository,
  loadVocabulary,
  parseArguments,
  parseSlotName,
  validateVocabulary,
} from "./naming-lint.mjs";

const HERE = import.meta.dirname;
const ANALYZER = path.join(HERE, "naming-lint.mjs");
const vocabulary = await loadVocabulary();
const readJson = async (name) => JSON.parse(await readFile(path.join(HERE, name), "utf8"));
const temporaryRoots = [];

test.after(async () => {
  await Promise.all(temporaryRoots.map((root) => rm(root, { recursive: true, force: true })));
});

function workflow(name, jobIds) {
  const header = name === undefined ? "" : `name: ${name}\n`;
  const jobs = jobIds
    .map((id) => `  ${id}:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: "true"\n`)
    .join("");
  return `${header}on: pull_request\npermissions: {}\njobs:\n${jobs}`;
}

const ACTION = `name: fixture
description: Fixture action.
runs:
  using: composite
  steps:
    - run: "true"
      shell: bash
`;

// workflows: { "file.yml": source }, actions: ["dir", "lane/unit"]
async function repository({ workflows = {}, actions = [] }) {
  const root = await mkdtemp(path.join(tmpdir(), "naming-lint-"));
  temporaryRoots.push(root);
  await mkdir(path.join(root, ".github", "workflows"), { recursive: true });
  for (const [file, source] of Object.entries(workflows)) {
    await writeFile(path.join(root, ".github", "workflows", file), source);
  }
  for (const directory of actions) {
    await mkdir(path.join(root, ".github", "actions", directory), { recursive: true });
    await writeFile(path.join(root, ".github", "actions", directory, "action.yml"), ACTION);
  }
  return root;
}

const summary = (findings) => findings.map(({ level, rule, file }) => `${level} ${rule} ${file}`);

test("a repository that follows the conventions has no findings in enforcing mode", async () => {
  const root = await repository({
    workflows: {
      "pr-require-checks.yml": workflow("pr-require-checks", [
        "pr-run-checks",
        "check-links",
        "shellcheck",
        "ci-status",
      ]),
      "pr-review.yml": workflow("pr-review", ["pr-review"]),
      "pr-run-checks-go.yml": workflow("pr-run-checks-go", ["check-linux"]),
      "post-merge-detect-silent-revert.yml": workflow("post-merge-detect-silent-revert", [
        "detect-silent-revert",
      ]),
      "intake-triage.yaml": workflow("intake-triage", ["claude"]),
    },
    actions: [
      "pr-require-checks/aggregate-results",
      "pr-review/claude",
      "report-lane-outcome",
      "shellcheck",
    ],
  });
  assert.deepEqual(await lintRepository({ root, vocabulary, mode: "enforcing" }), []);
});

test("each convention breach is reported under its own rule", async () => {
  const root = await repository({
    workflows: {
      "ci.yml": workflow("ci", ["ci-status"]),
      "pr-gatekeep.yml": workflow("pr-gatekeep", ["check"]),
      "pr-review.yml": workflow("Claude Review", [
        "Build_Test",
        "pr-section-drift",
        "security-review",
      ]),
      "pr-require-checks.yml": workflow("pr-require-checks", ["check-links"]),
      "maintenance-sync-standards.yml": workflow(undefined, ["maintenance-sync-standards"]),
      "pr-review-security.yml": "jobs: [unclosed\n",
    },
    actions: [
      "comment-hygiene",
      "Check_Thing",
      "ci-status/aggregate-results",
      "pr-require-checks/results",
      "pr-require-checks/check-contract/extra",
    ],
  });
  const findings = await lintRepository({ root, vocabulary, mode: "enforcing" });
  assert.deepEqual(summary(findings).sort(), [
    "error action-directory .github/actions/Check_Thing/action.yml",
    "error action-directory .github/actions/ci-status/aggregate-results/action.yml",
    "error action-directory .github/actions/comment-hygiene/action.yml",
    "error action-directory .github/actions/pr-require-checks/check-contract/extra/action.yml",
    "error action-directory .github/actions/pr-require-checks/results/action.yml",
    "error gate-ci-status .github/workflows/pr-require-checks.yml",
    "error job-id-kebab .github/workflows/pr-review.yml",
    "error workflow-filename .github/workflows/ci.yml",
    "error workflow-filename .github/workflows/pr-gatekeep.yml",
    "error workflow-name .github/workflows/maintenance-sync-standards.yml",
    "error workflow-name .github/workflows/pr-review.yml",
    "error workflow-unparsable .github/workflows/pr-review-security.yml",
    "warning job-id-stage-word .github/workflows/pr-review.yml",
    "warning job-id-verb-first .github/workflows/pr-review.yml",
  ]);
  const kebab = findings.find((item) => item.rule === "job-id-kebab");
  // workflow("Claude Review", ...) puts the first job key on line 5.
  assert.equal(kebab.line, 5);
});

test("advisory mode reports the same findings as warnings and exits 0", async () => {
  const root = await repository({ workflows: { "ci.yml": workflow("ci", ["ci-status"]) } });
  const findings = await lintRepository({ root, vocabulary, mode: "advisory" });
  assert.deepEqual(summary(findings), ["warning workflow-filename .github/workflows/ci.yml"]);

  const run = (mode) =>
    new Promise((resolve) => {
      execFile(
        process.execPath,
        [ANALYZER, "--root", root, "--mode", mode, "--format", "github"],
        (error, stdout) => resolve({ code: error === null ? 0 : error.code, stdout }),
      );
    });
  const advisory = await run("advisory");
  assert.equal(advisory.code, 0);
  assert.match(advisory.stdout, /^::warning file=\.github\/workflows\/ci\.yml,line=1,/mu);
  const enforcing = await run("enforcing");
  assert.equal(enforcing.code, 1);
  assert.match(enforcing.stdout, /^::error file=\.github\/workflows\/ci\.yml,line=1,/mu);
});

test("annotations escape the characters the workflow command syntax reserves", () => {
  assert.equal(
    formatAnnotation({
      level: "error",
      rule: "workflow-name",
      file: "a,b:c.yml",
      line: 3,
      message: "50%\nnext",
    }),
    "::error file=a%2Cb%3Ac.yml,line=3,title=naming-lint workflow-name::50%25%0Anext",
  );
});

test("the OIDC negative-test name exception applies only in github-iac", async () => {
  const root = await repository({
    workflows: {
      "release-deploy-oidc-negative-test.yml": workflow("release-deploy-x", ["test"]),
    },
  });
  assert.deepEqual(
    await lintRepository({
      root,
      vocabulary,
      mode: "enforcing",
      repository: "melodic-software/github-iac",
    }),
    [],
  );
  const elsewhere = await lintRepository({
    root,
    vocabulary,
    mode: "enforcing",
    repository: "melodic-software/medley",
  });
  assert.deepEqual(summary(elsewhere), [
    "error workflow-name .github/workflows/release-deploy-oidc-negative-test.yml",
  ]);
});

test("every target name in the approved rename map passes the vocabulary", async () => {
  const map = await readJson("rename-map.json");
  const byRepo = Map.groupBy(map, (entry) => entry.repo);
  for (const [repo, entries] of byRepo) {
    const workflows = {};
    const actions = [];
    for (const entry of entries) {
      if (entry.to.startsWith("(")) {
        continue;
      }
      if (entry.kind === "action") {
        actions.push(entry.to.replace(/^\.github\/actions\//u, ""));
        continue;
      }
      const jobs = entry.job_renames.map((rename) => rename.to);
      if (entry.to.endsWith("/pr-require-checks.yml")) {
        jobs.push("ci-status");
      }
      workflows[path.basename(entry.to)] = workflow(
        entry.to_name,
        jobs.length > 0 ? jobs : ["test"],
      );
    }
    const root = await repository({ workflows, actions });
    const findings = await lintRepository({
      root,
      vocabulary,
      mode: "enforcing",
      repository: `melodic-software/${repo}`,
    });
    assert.deepEqual(findings, [], `${repo}: ${JSON.stringify(findings)}`);
  }
});

test("slot names the pull request pipeline model relies on parse as stage plus function", () => {
  // cant-fail-ok: these names are the contract the Automation Lanes pipeline
  // model refers to; dropping one breaks that model.
  for (const name of [
    "pr-refine",
    "pr-run-checks",
    "pr-require-checks",
    "pr-review",
    "pr-review-security",
    "pr-verify",
    "pr-explain",
    "pr-address-feedback",
    "pr-fix-ci",
    "pr-update",
    "pr-merge",
    "pr-automerge",
    "post-merge-verify",
    "post-merge-sweep-comments",
    "post-merge-detect-silent-revert",
  ]) {
    assert.notEqual(parseSlotName(name, vocabulary).function, undefined, name);
  }
  assert.deepEqual(parseSlotName("pr-run-checks-go", vocabulary), {
    stage: "pr",
    function: "run-checks",
    modifier: "go",
  });
  assert.equal(parseSlotName("pr-gatekeep", vocabulary).function, undefined);
});

test("activity names follow the grammar", () => {
  for (const name of [
    "simplify",
    "fix-docs",
    "run-tests",
    "claude",
    "check-intent",
    "address-feedback",
    "merge",
    "simplify#diff",
    "check-release-readiness",
  ]) {
    assert.equal(checkActivityName(name, vocabulary), undefined, name);
  }
  assert.match(checkActivityName("pr-explainer", vocabulary), /stage word `pr`/u);
  assert.match(checkActivityName("intent-check", vocabulary), /accepted verb/u);
  assert.match(checkActivityName("simplify#bogus", vocabulary), /mode `bogus`/u);
  assert.match(checkActivityName("claude#bogus", vocabulary), /mode `bogus`/u);
  assert.equal(checkActivityName("claude#diff", vocabulary), undefined);
  assert.match(checkActivityName("Fix_Docs", vocabulary), /does not match/u);
});

test("vocabulary.json and rename-map.json match their schemas", async () => {
  const ajv = new Ajv2020({ strict: true, validateFormats: false });
  for (const [data, schema] of [
    ["vocabulary.json", "vocabulary.schema.json"],
    ["rename-map.json", "rename-map.schema.json"],
  ]) {
    const validate = ajv.compile(await readJson(schema));
    assert.equal(
      validate(await readJson(data)),
      true,
      `${data}: ${ajv.errorsText(validate.errors)}`,
    );
  }
});

test("the vocabulary loader rejects cross-field drift the schema cannot express", async () => {
  const base = await readJson("vocabulary.json");
  const clone = () => structuredClone(base);

  const unknownStage = clone();
  unknownStage.functions.deploy = [];
  assert.throws(() => validateVocabulary(unknownStage), ConfigurationError);

  const nounFunction = clone();
  nounFunction.functions.pr.push({ name: "gate", status: "in-use" });
  assert.throws(() => validateVocabulary(nounFunction), /accepted verb/u);

  const nameWithoutValue = clone();
  delete nameWithoutValue.exemptions[0].expectedName;
  assert.throws(() => validateVocabulary(nameWithoutValue), /expectedName/u);

  const badShape = clone();
  badShape.stages[0].name = "Intake";
  assert.throws(() => validateVocabulary(badShape), /vocabulary.schema.json/u);

  for (const field of ["apps", "activityGrammar"]) {
    const badPattern = clone();
    badPattern[field].pattern = "^[a-z";
    assert.throws(
      () => validateVocabulary(badPattern),
      (error) =>
        error instanceof ConfigurationError &&
        error.message.includes(`${field}.pattern is not a valid regular expression`),
    );
  }
});

test("a malformed vocabulary file is a configuration error that names the file", async () => {
  const root = await repository({});
  const file = path.join(root, "vocabulary.json");
  // YAML's JSON schema accepts a single-quoted string; JSON.parse does not.
  await writeFile(file, `{"stages": 'x'}`);
  await assert.rejects(
    loadVocabulary(file),
    (error) => error instanceof ConfigurationError && error.message.includes(file),
  );
});

test("a missing vocabulary schema exits 2, not 1", async () => {
  const copy = await repository({});
  for (const name of ["naming-lint.mjs", "vocabulary.json"]) {
    await writeFile(path.join(copy, name), await readFile(path.join(HERE, name)));
  }
  await symlink(path.join(HERE, "node_modules"), path.join(copy, "node_modules"), "dir");
  const result = await new Promise((resolve) => {
    execFile(
      process.execPath,
      [path.join(copy, "naming-lint.mjs"), "--root", copy],
      (error, _stdout, stderr) => resolve({ code: error === null ? 0 : error.code, stderr }),
    );
  });
  assert.equal(result.code, 2);
  assert.match(result.stderr, /vocabulary\.schema\.json/u);
});

test("the README stage table lists the vocabulary's stages in order", async () => {
  const readme = await readFile(path.join(HERE, "README.md"), "utf8");
  const table = readme.split("<!-- stages:begin -->")[1]?.split("<!-- stages:end -->")[0];
  assert.ok(table, "README.md must carry the stages:begin/stages:end markers");
  const rows = [...table.matchAll(/^\| `([^`]+)` \| (.+) \|$/gmu)].map((match) => ({
    name: match[1],
    purpose: match[2],
  }));
  assert.deepEqual(rows, vocabulary.stages);
});

test("bad arguments are configuration errors", () => {
  assert.throws(() => parseArguments(["--mode", "strict"], {}), ConfigurationError);
  assert.throws(() => parseArguments(["--format", "xml"], {}), ConfigurationError);
  assert.equal(parseArguments([], { GITHUB_ACTIONS: "true" }).format, "github");
  assert.equal(parseArguments([], {}).format, "text");
});
