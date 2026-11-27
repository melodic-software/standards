import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { renderTemplate } from "./contract-docs.mjs";
import {
  CONSUMER_REPOSITORIES,
  checkCopies,
  checkFleet,
  checkGeneratedTemplate,
  checkPinnedReusable,
  DriftError,
  detectArtifactPin,
  FetchError,
  MODES,
  maskCode,
  parseCallerPin,
  parseCompositeRequireScope,
  parseCompositeSections,
  parseCompositeTypes,
  parseGatePatterns,
  parseGateSections,
  parseMarkdownHeadings,
  parseMode,
  parseValidatorSections,
  REPORT_DIRECTORY,
  readGateComposite,
  requirePinScanToken,
  resolveConsumerArtifact,
  runPinScan,
} from "./lockstep-drift.mjs";
import {
  BACKTICKED_TEMPLATE,
  GOOD_COMPOSITE_ACTION,
  GOOD_COMPOSITE_RUN,
  GOOD_GATE,
  GOOD_TEMPLATE,
  GOOD_VALIDATOR,
  goodTexts,
  MODULE_DIRECTORY,
  POLICY,
} from "./lockstep-fixtures.mjs";

test("policy fixture agreement: every good fixture matches policy.json", () => {
  assert.deepEqual(checkCopies(POLICY, goodTexts()), []);
});

test("parsers extract the narrow surfaces", () => {
  assert.deepEqual(
    parseCompositeSections(GOOD_COMPOSITE_RUN, "composite"),
    POLICY.body.requiredSections,
  );
  assert.deepEqual(
    parseCompositeTypes(GOOD_COMPOSITE_ACTION, "composite"),
    POLICY.title.allowedTypes,
  );
  assert.equal(
    parseCompositeRequireScope(GOOD_COMPOSITE_ACTION, "composite"),
    POLICY.title.requireScope,
  );
  assert.deepEqual(parseGateSections(GOOD_GATE, "gate"), POLICY.body.requiredSections);
  assert.deepEqual(
    parseValidatorSections(GOOD_VALIDATOR, "validator"),
    POLICY.body.requiredSections,
  );
  assert.deepEqual(parseMarkdownHeadings(GOOD_TEMPLATE), POLICY.body.requiredSections);
  assert.equal(
    parseCallerPin(
      "uses: melodic-software/ci-workflows/.github/workflows/pr-issue-linkage.yml@0f8176e87e0be518f382664779655011bf95784a # v0.17.2",
      "caller",
    ),
    "0f8176e87e0be518f382664779655011bf95784a",
  );
});

// Mutation probes: one mutated copy per source must produce exactly that
// source's drift finding (the acceptance criterion's red-under-mutation).
test("mutated composite section list is reported", () => {
  const texts = goodTexts();
  texts.gateRun = texts.gateRun.replace('section_report("Fix")', 'section_report("Patch")');
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("gate composite:")).length, 1, errors.join("; "));
  assert.match(errors[0], /Patch/);
});

test("a composite type list that drops security is reported", () => {
  const texts = goodTexts();
  texts.gateAction = texts.gateAction.replace(",security", "");
  const errors = checkCopies(POLICY, texts).filter((e) =>
    e.includes("gate composite (title types"),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /missing security/);
});

test("a composite type list that adds a type policy does not allow is reported", () => {
  const texts = goodTexts();
  texts.gateAction = texts.gateAction.replace(",style", ",wip,style");
  const errors = checkCopies(POLICY, texts).filter((e) =>
    e.includes("gate composite (title types"),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /unexpected wip/);
});

// A composite that flipped `require-scope` would reject every unscoped title
// fleet-wide while the section and type checks still reported agreement.
test("a composite that flips require-scope away from policy is reported", () => {
  const texts = goodTexts();
  texts.gateAction = texts.gateAction.replace("default: 'false'", "default: 'true'");
  const errors = checkCopies(POLICY, texts).filter((e) => e.includes("require-scope"));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /require-scope is true, policy says false/);
});

// YAML gives a string for the quoted `'false'` the composite declares and a
// boolean for a bare `false`; both mean the same thing to Actions, and anything
// else is drift rather than a coerced guess.
test("require-scope accepts either YAML spelling and refuses a non-boolean", () => {
  assert.equal(
    parseCompositeRequireScope(
      GOOD_COMPOSITE_ACTION.replace("default: 'false'", "default: false"),
      "composite",
    ),
    false,
  );
  assert.throws(
    () =>
      parseCompositeRequireScope(
        GOOD_COMPOSITE_ACTION.replace("default: 'false'", "default: maybe"),
        "composite",
      ),
    DriftError,
  );
  assert.throws(
    () => parseCompositeRequireScope("name: Check Contract\ninputs:\n  types:\n", "composite"),
    DriftError,
  );
});

test("mutated validator section list is reported", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator.replace(
    "REQUIRED_SECTIONS=(Summary Fix Verification Related)",
    "REQUIRED_SECTIONS=(Summary Related)",
  );
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("hook validator:")).length, 1);
});

test("template missing a policy heading is reported", () => {
  const texts = goodTexts();
  texts.orgTemplate = texts.orgTemplate.replace("## Verification\n\n", "");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("org PR template:")).length, 1);
});

function templateMarkerErrors(orgTemplate) {
  return checkCopies(POLICY, { ...goodTexts(), orgTemplate }).filter((e) =>
    e.startsWith("org PR template (no-issue markers)"),
  );
}

test("a template naming one accepted no-issue marker is not drift; naming none is", () => {
  assert.deepEqual(
    templateMarkerErrors(GOOD_TEMPLATE.replace("No related issue:", "No linked issue:")),
    [],
  );
  assert.equal(
    templateMarkerErrors(
      GOOD_TEMPLATE.replace("No related issue: <reason>", "Say why there is none."),
    ).length,
    1,
  );
});

// The failure .github#135 removed: a marker present only inside an inline code
// span is masked away by the gate, so an author who copies it verbatim draws
// `needs-issue-linkage` with no visible cause. A substring check cannot see it.
test("a template whose only markers sit in code spans or code blocks is drift", () => {
  assert.equal(templateMarkerErrors(BACKTICKED_TEMPLATE).length, 1);
  assert.match(templateMarkerErrors(BACKTICKED_TEMPLATE)[0], /outside an inline code span/);

  // Code blocks only count outside the guidance comment, as they do for the
  // composite, so these two move the escape out of it.
  const outside = GOOD_TEMPLATE.replace("No related issue: <reason>", "").replace(
    "## Summary",
    "PLACEHOLDER\n\n## Summary",
  );
  const fenced = outside.replace("PLACEHOLDER", "```\nNo related issue: <reason>\n```");
  assert.equal(templateMarkerErrors(fenced).length, 1);

  const indented = outside.replace("PLACEHOLDER", "    No related issue: <reason>");
  assert.equal(templateMarkerErrors(indented).length, 1);

  // The same escape on a plain line there is not drift, so the two above fail
  // for the code block and nothing else.
  assert.deepEqual(templateMarkerErrors(outside.replace("PLACEHOLDER", "No related issue: x")), []);
});

test("the masker follows the composite's code-span rules", () => {
  // A run of N backticks opens a span only when a run of exactly N closes it
  // later on the same line; an unmatched run is literal text.
  assert.equal(maskCode("a `b` c"), "a  c");
  assert.equal(maskCode("a ` b c"), "a ` b c");
  assert.equal(maskCode("a ``b ` c`` d"), "a  d");
  // Indentation is counted in spaces only, as the composite counts it: a
  // tab-indented marker run is indented code, not a fence.
  assert.equal(maskCode("\t```\nkept\n```"), "\nkept\n");
  // HTML comments are deliberately left rendered: the org template's guidance
  // lives inside one, and that is where its escape is named.
  assert.match(maskCode("<!--\nNo related issue: <reason>\n-->"), /No related issue/);
  // Block detection is suppressed inside a comment, as it is for the composite:
  // an odd fence line in the guidance must not swallow the rest of the file.
  assert.match(maskCode("<!--\n```\n-->\nNo related issue: x\n"), /No related issue/);
  // A backticked escape inside a comment is still masked. That is the .github#135
  // shape, and the comment is where the old template wrote it.
  assert.doesNotMatch(maskCode("<!--\n`No related issue: x`\n-->"), /No related issue/);
  // A `<!--` inside a code span does not open a comment, so it cannot suppress
  // the block detection that masks the marker below it.
  assert.doesNotMatch(maskCode("a `<!--` b\n```\nNo related issue: x\n"), /No related issue/);
  // Nor does one inside a fence: the fence still closes on its own marker, and
  // the marker after it is ordinary text.
  assert.match(maskCode("```\n<!--\n```\nNo related issue: x\n"), /No related issue/);
  // A closer is asymmetric to an opener, as it is for the composite: it counts
  // even inside a code span, so the fence below it still opens.
  assert.doesNotMatch(
    maskCode("<!--\ntext `-->` more\n```\nNo related issue: x\n"),
    /No related issue/,
  );
  // Both delimiter offsets are read in the raw line's coordinate space, so a
  // masked span before them cannot make a closer look later than an opener
  // that follows it. Here the comment stays open and the fence never fires.
  assert.match(
    maskCode("<!--\n`example` --> <!--\n```\nNo related issue: x\n"),
    /No related issue/,
  );
});

test("rules file missing a section or keyword is reported", () => {
  const texts = goodTexts();
  texts.rulesFile = texts.rulesFile.replace("## Related", "## See also").replace("Resolves", "");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("rules file")).length, 2, errors.join("; "));
});

test("a rules file that names no non-closing marker is reported", () => {
  const texts = goodTexts();
  texts.rulesFile = texts.rulesFile.replace("a `Refs: #<issue>` line, ", "");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.length, 1, errors.join("; "));
  assert.match(
    errors[0],
    /^rules file \(non-closing markers\): mentions none of: Refs:, Relates to:/,
  );
  // The marker without the colon is not the form the gate reads.
  const colonless = goodTexts();
  colonless.rulesFile = colonless.rulesFile.replace("`Refs: #<issue>`", "`Refs #<issue>`");
  assert.equal(checkCopies(POLICY, colonless).length, 1);
});

test("composite keyword/marker regressions are caught functionally, not by mention", () => {
  // Keyword stem removed from the DECLARED pattern while the word survives in
  // prose: a mention check would pass; the functional probe must not.
  const noResolve = goodTexts();
  noResolve.gateRun = noResolve.gateRun
    .replace("|resolve|resolves|resolved", "")
    .concat("# resolve is still mentioned right here\n");
  assert.equal(
    checkCopies(POLICY, noResolve).filter((e) => e.includes("gate composite (enforcement")).length,
    1,
  );
  const noMarker = goodTexts();
  noMarker.gateRun = noMarker.gateRun.replace("(linked|related)", "(linked)");
  assert.equal(
    checkCopies(POLICY, noMarker).filter((e) => e.includes('marker "No related issue"')).length,
    1,
  );
});

// The composite's awk patterns are lowercase and match text the analyzer has
// already lowercased. Probing them with lowercased input is only correct while
// that lowercasing is there; a composite that dropped it would become
// case-sensitive against raw text and reject the capitalized keyword forms the
// contract documents. The extractor must
// refuse to certify it rather than probe a pattern the gate no longer applies.
test("a composite that stops lowercasing the line is drift, not a pass", () => {
  const texts = goodTexts();
  texts.gateRun = texts.gateRun.replace("lower = tolower(line)", "lower = line");
  const errors = checkCopies(POLICY, texts).filter((e) => e.includes("gate composite"));
  assert.equal(errors.length, 2, errors.join("; "));
  assert.match(errors[0], /no longer lowercases the line/);
  // Running it agrees: a capitalized keyword no longer closes.
  assert.match(errors[1], /^gate composite \(behavior\): .*"Closes #12" should be closing/);
});

// The composite's findings at one codex-plugins pin, with the good action.yml.

const COMPOSITE_DIRECTORY = ".github/actions/pr-require-checks/check-contract";
const COMPOSITE_STEP = `      - uses: melodic-software/ci-workflows/${COMPOSITE_DIRECTORY}@1234567890abcdef1234567890abcdef12345678 # v0.34.0`;
const REUSABLE_CALL =
  "    uses: melodic-software/ci-workflows/.github/workflows/pr-issue-linkage.yml@0f8176e87e0be518f382664779655011bf95784a # v0.17.2";

test("a consumer pinned to the check-contract composite is detected at its pin", () => {
  assert.deepEqual(detectArtifactPin(`jobs:\n  ci-status:\n${COMPOSITE_STEP}\n`), {
    kind: "composite",
    sha: "1234567890abcdef1234567890abcdef12345678",
  });
});

test("a consumer on the composite at main is detected at main, read from ci-workflows", () => {
  const step = `      - uses: melodic-software/ci-workflows/${COMPOSITE_DIRECTORY}@main`;
  assert.deepEqual(detectArtifactPin(`jobs:\n  ci-status:\n${step}\n`), {
    kind: "composite",
    sha: "main",
  });
});

test("a self-repository `$/` reference to the composite resolves to main", () => {
  assert.deepEqual(detectArtifactPin(`        uses: $/${COMPOSITE_DIRECTORY}\n`), {
    kind: "composite",
    sha: "main",
    local: true,
  });
});

test("a reusable consumer is detected at its pin", () => {
  assert.deepEqual(detectArtifactPin(`jobs:\n  linkage:\n${REUSABLE_CALL}\n`), {
    kind: "reusable",
    sha: "0f8176e87e0be518f382664779655011bf95784a",
  });
});

// `report-ci-status` runs `check-contract` through `$/` at the commit the caller
// pins, so its pin names the `check-contract` to check.
test("a consumer on report-ci-status is detected at its pin", () => {
  const step = `      - uses: melodic-software/ci-workflows/${REPORT_DIRECTORY}@ebd0e3bed99ae1365fcb4ef47ce97cfa745fcf2f # v0.76.0`;
  assert.deepEqual(detectArtifactPin(`jobs:\n  ci-status:\n${step}\n`), {
    kind: "composite",
    sha: "ebd0e3bed99ae1365fcb4ef47ce97cfa745fcf2f",
  });
});

test("a self-repository `$/` reference to report-ci-status resolves to main", () => {
  assert.deepEqual(detectArtifactPin(`        uses: $/${REPORT_DIRECTORY}\n`), {
    kind: "composite",
    sha: "main",
    local: true,
  });
  assert.equal(detectArtifactPin(`      # - uses: $/${REPORT_DIRECTORY}\n`), null);
});

test("the composite wins when a repository carries both mid-transition", () => {
  const both = `jobs:\n  linkage:\n${REUSABLE_CALL}\n  ci-status:\n${COMPOSITE_STEP}\n`;
  assert.equal(detectArtifactPin(both).kind, "composite");
});

// ci-workflows dogfoods its own composite through a local `./` or `$/` reference,
// which carries no SHA. The same path appears in that workflow as a lint
// `paths:` entry and as a `bash .../run.test.sh` command; neither is a call
// site, so the detector anchors on `uses:`.
test("a local composite reference resolves to main, and a bare path does not", () => {
  assert.deepEqual(
    detectArtifactPin(`      - name: Contract\n        uses: ./${COMPOSITE_DIRECTORY}\n`),
    { kind: "composite", sha: "main", local: true },
  );
  assert.equal(
    detectArtifactPin(
      `          paths: ${COMPOSITE_DIRECTORY} .github/actions/ci-status\n` +
        `      - run: bash ${COMPOSITE_DIRECTORY}/run.test.sh\n`,
    ),
    null,
  );
});

test("a workflow with neither artifact detects nothing", () => {
  assert.equal(detectArtifactPin("jobs:\n  build:\n    runs-on: ubuntu-24.04\n"), null);
});

// A migration leaves commented-out call sites behind. Selecting an artifact a
// repository does not run would suppress detection of the one it does, and a
// repository that had lost its last live caller would validate an unused
// artifact instead of reporting that it runs neither.
test("a commented-out call site is not a call site", () => {
  assert.equal(detectArtifactPin(`      # ${COMPOSITE_STEP.trim()}\n`), null);
  assert.equal(detectArtifactPin(`    # ${REUSABLE_CALL.trim()}\n`), null);
  assert.equal(
    detectArtifactPin(`      # - uses: ./${COMPOSITE_DIRECTORY}\n${REUSABLE_CALL}\n`).kind,
    "reusable",
  );
  assert.equal(detectArtifactPin(`      # - uses: $/${COMPOSITE_DIRECTORY}\n`), null);
});

// The ci-workflows rename moves the gate from `ci.yml` to
// `pr-require-checks.yml`. The scan reads that file before any other, so a
// repository calling the composite from there costs one read.
// Resolves ci-workflows over the given workflow files, recording each one read.
async function resolveWorkflows(files) {
  const reads = [];
  const found = await resolveConsumerArtifact(
    "ci-workflows",
    async (url) => {
      const name = url.match(/\.github\/workflows\/([^?]+)/)[1];
      reads.push(name);
      return files[name];
    },
    async () => Object.keys(files),
  );
  return { found, reads };
}

test("a composite called from pr-require-checks.yml is found on the first read", async () => {
  const { found, reads } = await resolveWorkflows({
    "build.yml": "jobs:\n  build:\n    runs-on: ubuntu-24.04\n",
    "pr-require-checks.yml": `jobs:\n  ci-status:\n        uses: ./${COMPOSITE_DIRECTORY}\n`,
    "lint.yml": "jobs:\n  lint:\n    runs-on: ubuntu-24.04\n",
  });
  assert.deepEqual(found, { kind: "composite", sha: "main", local: true });
  assert.deepEqual(reads, ["pr-require-checks.yml"]);
});

test("pr-require-checks.yml is read before ci.yml when both exist mid-rename", async () => {
  const { found, reads } = await resolveWorkflows({
    "ci.yml": `jobs:\n  ci-status:\n        uses: ./${COMPOSITE_DIRECTORY}\n`,
    "pr-require-checks.yml": `jobs:\n  ci-status:\n        uses: ./${COMPOSITE_DIRECTORY}\n`,
  });
  assert.deepEqual(found, { kind: "composite", sha: "main", local: true });
  assert.deepEqual(reads, ["pr-require-checks.yml"]);
});

// Serves the composite's files at `directory`; any other path reads as missing.
function gateReader(directory, files = ["run.sh", "action.yml"]) {
  return async (url) => {
    const file = files.find((name) => url.includes(`/${directory}/${name}?`));
    return file === undefined ? null : `${file} at ${directory}`;
  };
}

test("the gate composite is read from the check-contract path", async () => {
  assert.deepEqual(await readGateComposite(gateReader(COMPOSITE_DIRECTORY)), {
    gateRun: `run.sh at ${COMPOSITE_DIRECTORY}`,
    gateAction: `action.yml at ${COMPOSITE_DIRECTORY}`,
  });
});

test("a gate composite missing from ci-workflows main is a fetch error", async () => {
  await assert.rejects(
    readGateComposite(gateReader(".github/actions/elsewhere")),
    /fetch-error: .*check-contract\/run\.sh/,
  );
  await assert.rejects(
    readGateComposite(gateReader(COMPOSITE_DIRECTORY, ["run.sh"])),
    /fetch-error: .*check-contract\/action\.yml/,
  );
});

function fleetResolutions(overrides = {}) {
  const resolutions = new Map();
  for (const repo of CONSUMER_REPOSITORIES) {
    resolutions.set(repo, { kind: "reusable", sha: "a".repeat(40), reusable: GOOD_GATE });
  }
  // ci-workflows dogfoods the composite from its own tree.
  resolutions.set("ci-workflows", {
    kind: "composite",
    sha: "main",
    runSh: GOOD_COMPOSITE_RUN,
    actionYml: GOOD_COMPOSITE_ACTION,
  });
  for (const [repo, resolution] of Object.entries(overrides)) {
    resolutions.set(repo, resolution);
  }
  return resolutions;
}

const compositeAt = (sha, runSh = GOOD_COMPOSITE_RUN, actionYml = GOOD_COMPOSITE_ACTION) => ({
  kind: "composite",
  sha,
  runSh,
  actionYml,
});

test("a mixed fleet of composite and reusable consumers passes", () => {
  const errors = checkFleet(
    POLICY,
    fleetResolutions({
      "codex-plugins": compositeAt("4".repeat(40)),
      "github-iac": compositeAt("5".repeat(40)),
    }),
  );
  assert.deepEqual(errors, []);
});

// Fail-closed, with no per-repository exemption: github-iac#367 put every
// repository in the roster under the org `ci-gate` ruleset, so a repository
// running neither artifact is a gate removal wherever it happens.
test("a repository running neither artifact fails the fleet, whichever repository it is", () => {
  for (const repo of ["dotfiles", "agent-plugins", "claude-code-proxy", "cursor-plugins"]) {
    const errors = checkFleet(POLICY, fleetResolutions({ [repo]: { kind: "none" } }));
    assert.equal(errors.length, 1, `${repo} produces exactly one finding`);
    assert.match(errors[0], new RegExp(`caller ${repo}: no check-contract composite step`));
  }
});

test("types drift at one composite consumer fails the fleet", () => {
  const drifted = compositeAt(
    "6".repeat(40),
    GOOD_COMPOSITE_RUN,
    GOOD_COMPOSITE_ACTION.replace(",security", ""),
  );
  const errors = checkFleet(POLICY, fleetResolutions({ medley: drifted }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller medley pin 6666666: allowed title types missing security/);
});

test("require-scope drift at one composite consumer fails the fleet", () => {
  const drifted = compositeAt(
    "a1".repeat(20),
    GOOD_COMPOSITE_RUN,
    GOOD_COMPOSITE_ACTION.replace("default: 'false'", "default: 'true'"),
  );
  const errors = checkFleet(POLICY, fleetResolutions({ dotfiles: drifted }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller dotfiles pin a1a1a1a: require-scope is true, policy says false/);
});

test("sections drift at one composite consumer fails the fleet", () => {
  const drifted = compositeAt(
    "7".repeat(40),
    GOOD_COMPOSITE_RUN.replace('section_report("Verification")', 'section_report("Evidence")'),
  );
  const errors = checkFleet(POLICY, fleetResolutions({ provisioning: drifted }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller provisioning pin 7777777: section list/);
});

test("sections drift at one reusable consumer still fails the fleet", () => {
  const drifted = {
    kind: "reusable",
    sha: "8".repeat(40),
    reusable: GOOD_GATE.replace('"Fix"', '"Patch"'),
  };
  const errors = checkFleet(POLICY, fleetResolutions({ "ci-runner": drifted }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller ci-runner pin 8888888: section list/);
});

test("a repository whose fetch already failed is not double-reported", () => {
  const errors = checkFleet(POLICY, fleetResolutions({ standards: { kind: "unresolved" } }));
  assert.deepEqual(errors, []);
});

test("consumer roster covers all eighteen gated repositories", () => {
  assert.equal(CONSUMER_REPOSITORIES.length, 18);
  for (const repo of [
    "agent-automations",
    "agent-plugins",
    "azure-iac",
    "claude-code-account-rotation",
    "claude-code-proxy",
    "cursor-plugins",
    "knowledge-corpus",
    "songwriting",
  ]) {
    assert.ok(CONSUMER_REPOSITORIES.includes(repo), `${repo} is in the roster`);
  }
});

// Regression: ci-workflows made CLOSING_KEYWORD global so every occurrence on a
// line can be classified. The parser pinned the declaration to a literal `/i;`,
// so a healthy gate reported "declarations not found" — a parse failure that
// reads as drift.
test("a global declaration parses and still probes", () => {
  const globalGate = GOOD_GATE.replaceAll("/i;", "/gi;");
  const patterns = parseGatePatterns(globalGate, "gate");
  assert.ok(patterns.keyword.test("Closes #12"), "keyword body still probes");
  assert.ok(patterns.marker.test("No linked issue"), "marker body still probes");
  assert.equal(patterns.keyword.global, false, "g is stripped so .test() is stateless");
  assert.deepEqual(
    parseGatePatterns(globalGate, "gate").keyword.source,
    parseGatePatterns(GOOD_GATE, "gate").keyword.source,
    "same body extracted regardless of declared flags",
  );
});

// Tolerating flags must not blind the check to losing one. Both declared bodies
// are lowercase and rely on `i` to accept the documented capitalized keyword
// forms, so a gate that dropped `i` would silently become case-sensitive.
// Probing with a hardcoded `i` would pass it; the DECLARED flags catch it.
test("a reusable that drops the i flag is enforcement drift, not a pass", () => {
  const caseSensitiveGate = GOOD_GATE.replaceAll("/i;", "/g;");
  const patterns = parseGatePatterns(caseSensitiveGate, "gate");
  assert.equal(patterns.keyword.ignoreCase, false, "declared flags are preserved");
  assert.equal(patterns.keyword.test("Closes #12"), false, "capitalized form now rejected");
  const errors = checkPinnedReusable(POLICY, "dotfiles", "9".repeat(40), caseSensitiveGate);
  assert.equal(errors.length, 1, "drift is reported");
  assert.match(errors[0], /closing keyword "Closes"/);
});

// `g`/`y` are stripped because they make .test() advance lastIndex, and
// assertPatternsEnforce probes each pattern once per policy keyword.
test("a global probe does not go stateful across repeated keyword probes", () => {
  const patterns = parseGatePatterns(GOOD_GATE.replaceAll("/i;", "/gi;"), "gate");
  for (const keyword of POLICY.body.closingKeywords) {
    assert.ok(patterns.keyword.test(` ${keyword} #12 `), `${keyword} probes on every call`);
  }
});

// Mode selection: the copy check and the pin scan run separately.

test("the CLI takes exactly one known mode", () => {
  assert.deepEqual(MODES, ["copies", "pins"]);
  assert.equal(parseMode(["copies"]), "copies");
  assert.equal(parseMode(["pins"]), "pins");
  for (const argv of [[], ["all"], ["copies", "pins"], ["--mode=copies"]]) {
    assert.throws(
      () => parseMode(argv),
      /usage: lockstep-drift\.mjs <copies\|pins>/,
      argv.join(" "),
    );
  }
});

test("the pin scan needs a token and fails without one", async () => {
  for (const env of [{}, { LOCKSTEP_GITHUB_TOKEN: "", GITHUB_TOKEN: "" }]) {
    assert.throws(() => requirePinScanToken(env), FetchError);
    await assert.rejects(runPinScan(env), FetchError);
  }
  requirePinScanToken({ LOCKSTEP_GITHUB_TOKEN: "app-token" });
  requirePinScanToken({ GITHUB_TOKEN: "workflow-token" });
});

// End to end through the CLI: no mode, or a tokenless pin scan, exits non-zero
// before any network read, so neither can pass by skipping.
test("the CLI fails a missing mode and a tokenless pin scan", () => {
  const script = path.join(MODULE_DIRECTORY, "lockstep-drift.mjs");
  const run = (args) =>
    spawnSync(process.execPath, [script, ...args], {
      encoding: "utf8",
      env: { PATH: process.env.PATH },
    });
  const noMode = run([]);
  assert.equal(noMode.status, 1);
  assert.match(noMode.stderr, /usage: lockstep-drift\.mjs <copies\|pins>/);
  const pins = run(["pins"]);
  assert.equal(pins.status, 1);
  assert.match(pins.stderr, /needs LOCKSTEP_GITHUB_TOKEN or GITHUB_TOKEN/);
});

test("the org template must equal the branch render or a committed generated template", async () => {
  const committed = await readFile(path.join(MODULE_DIRECTORY, "PULL_REQUEST_TEMPLATE.md"), "utf8");
  const policy = JSON.parse(await readFile(path.join(MODULE_DIRECTORY, "policy.json"), "utf8"));
  assert.deepEqual(checkGeneratedTemplate(policy, committed, []), []);
  const edited = committed.replace("## Fix", "## Fix\n\nHand-added line.");
  assert.equal(checkGeneratedTemplate(policy, edited, []).length, 1);
  assert.equal(checkGeneratedTemplate(policy, edited, [committed]).length, 1);
  assert.equal(checkGeneratedTemplate(policy, `${committed}\n`, [committed]).length, 1);
});

test("a template change passes before its merge and while its sync is pending", async () => {
  const previous = await readFile(path.join(MODULE_DIRECTORY, "PULL_REQUEST_TEMPLATE.md"), "utf8");
  const base = JSON.parse(await readFile(path.join(MODULE_DIRECTORY, "policy.json"), "utf8"));
  const changed = {
    ...base,
    body: { ...base.body, sectionGuidance: { ...base.body.sectionGuidance, Fix: "Reworded." } },
  };
  // Before the merge: the branch renders the change; main and the org still hold the old bytes.
  assert.deepEqual(checkGeneratedTemplate(changed, previous, [previous]), []);
  // After the merge, before the .github sync lands: main holds both versions, the org the old one.
  assert.deepEqual(
    checkGeneratedTemplate(changed, previous, [renderTemplate(changed), previous]),
    [],
  );
  assert.equal(checkGeneratedTemplate(changed, previous, []).length, 1);
});
