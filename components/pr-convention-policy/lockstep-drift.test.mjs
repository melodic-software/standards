import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  CONSUMER_REPOSITORIES,
  checkCopies,
  checkFleet,
  checkPinnedComposite,
  checkPinnedReusable,
  DriftError,
  detectArtifactPin,
  parseCallerPin,
  parseCompositeSections,
  parseCompositeTypes,
  parseGatePatterns,
  parseGateSections,
  parseMarkdownHeadings,
  parseValidatorSections,
  UNSYNCED_REPOSITORIES,
} from "./lockstep-drift.mjs";
import { parseUniqueJson } from "./pr-convention-policy.mjs";

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const POLICY = parseUniqueJson(
  await readFile(path.join(MODULE_DIRECTORY, "policy.json"), "utf8"),
  "policy.json",
);

// Hermetic fixtures mirroring the narrowest parsed surface of each live copy.
// Written as arrays of plain strings so a backslash in an awk regex stays a
// backslash without template-literal escaping games.
const GOOD_COMPOSITE_RUN = [
  "analyze_body() {",
  "  awk '",
  "function scan_line(line,   lower, offset, chunk) {",
  "  lower = tolower(line)",
  "  offset = 0",
  "  while (1) {",
  "    chunk = substr(lower, offset + 1)",
  "    if (!match(chunk, /(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[ \\t]*:?[ \\t]*([a-z0-9_.-]+\\/[a-z0-9_.-]+)?#[0-9]+/)) break",
  "    offset = offset + RSTART + RLENGTH - 1",
  "  }",
  "}",
  "END {",
  '  section_report("Summary")',
  '  section_report("Fix")',
  '  section_report("Verification")',
  '  section_report("Related")',
  '  if (tolower(body) ~ /(^|[^a-z0-9_])no (linked|related) issue([^a-z0-9_]|$)/) print "no-issue"',
  "}",
  "'",
  "}",
  "",
].join("\n");

const GOOD_COMPOSITE_ACTION = [
  "name: pr-contract",
  "inputs:",
  "  require-scope:",
  "    description: Require a scope to always be present in the title.",
  "    default: 'false'",
  "  types:",
  "    description: >-",
  "      Comma-separated allowed Conventional Commits types. The default is the",
  "      twelve types policy.json declares.",
  "    default: build,chore,ci,docs,feat,fix,perf,refactor,revert,security,style,test",
  "runs:",
  "  using: composite",
  "",
].join("\n");

// The predecessor reusable. Still live at every consumer that has not taken
// its Phase 3 pull request yet, so its extractor keeps its own coverage.
const GOOD_GATE = `
      - name: Validate
        with:
          script: |
            const requiredSections = [
              { name: "Summary", guidance: "s" },
              { name: "Fix", guidance: "f" },
              { name: "Verification", guidance: "v" },
              { name: "Related", guidance: "r" },
            ];
            const CLOSING_KEYWORD =
              /\\b(close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\s*:?\\s*(?:[\\w.-]+\\/[\\w.-]+)?#\\d+\\b/i;
            const NO_ISSUE_MARKER = /\\bno (?:linked|related) issue\\b/i;
`;
const GOOD_VALIDATOR = [
  "KEYWORD_ERE='[^a-z0-9_](close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]*:?[[:space:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[^a-z0-9_]'",
  "NO_ISSUE_ERE='[^a-z0-9_]no (linked|related) issue[^a-z0-9_]'",
  "REQUIRED_SECTIONS=(Summary Fix Verification Related)",
  "",
].join("\n");
const GOOD_TEMPLATE =
  "Closes #\n\nOr `No related issue: <reason>` / `No linked issue`.\n\n## Summary\n\n## Fix\n\n## Verification\n\n## Related\n";
const GOOD_RULES = [
  "# PR body contract",
  "`Closes #<issue>` (`Fixes`/`Resolves`), or `No related issue: <reason>`.",
  "Sections: `## Summary`, `## Fix`, `## Verification`, `## Related`.",
].join("\n\n");

function goodTexts() {
  return {
    gateRun: GOOD_COMPOSITE_RUN,
    gateAction: GOOD_COMPOSITE_ACTION,
    hookValidator: GOOD_VALIDATOR,
    orgTemplate: GOOD_TEMPLATE,
    rulesFile: GOOD_RULES,
  };
}

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

test("rules file missing a section or keyword is reported", () => {
  const texts = goodTexts();
  texts.rulesFile = texts.rulesFile.replace("## Related", "## See also").replace("Resolves", "");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.filter((e) => e.startsWith("rules file")).length, 2, errors.join("; "));
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
// case-sensitive against raw text and reject `Closes #12`. The extractor must
// refuse to certify it rather than probe a pattern the gate no longer applies.
test("a composite that stops lowercasing the line is drift, not a pass", () => {
  const texts = goodTexts();
  texts.gateRun = texts.gateRun.replace("lower = tolower(line)", "lower = line");
  const errors = checkCopies(POLICY, texts).filter((e) => e.includes("gate composite"));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /no longer lowercases the line/);
});

test("a composite at a consumer pin passes when it matches policy", () => {
  assert.deepEqual(
    checkPinnedComposite(
      POLICY,
      "codex-plugins",
      "d".repeat(40),
      GOOD_COMPOSITE_RUN,
      GOOD_COMPOSITE_ACTION,
    ),
    [],
  );
});

test("a composite pin predating the security type is drift at that pin", () => {
  const errors = checkPinnedComposite(
    POLICY,
    "codex-plugins",
    "e".repeat(40),
    GOOD_COMPOSITE_RUN,
    GOOD_COMPOSITE_ACTION.replace(",security", ""),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller codex-plugins pin eeeeeee/);
  assert.match(errors[0], /missing security/);
});

test("stale reusable pin enforcing an older contract is reported", () => {
  const oldReusable = `
            const requiredSections = [
              { name: "Related", guidance: "r" },
            ];
`;
  // Two findings: the stale section list AND the missing enforcement-pattern
  // declarations (pre-pattern-era reusables lack the const declarations).
  const errors = checkPinnedReusable(POLICY, "codex-plugins", "c".repeat(40), oldReusable);
  assert.equal(errors.length, 2);
  assert.match(errors[0], /caller codex-plugins/);
  assert.match(errors[1], /caller codex-plugins/);
});

test("current pinned reusable contract passes", () => {
  assert.deepEqual(checkPinnedReusable(POLICY, "dotfiles", "a".repeat(40), GOOD_GATE), []);
});

test("validator keyword/marker regressions are caught functionally", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator
    .replace("|resolve[sd]?", "")
    .replace("(linked|related)", "(linked)");
  const errors = checkCopies(POLICY, texts).filter((e) =>
    e.includes("hook validator (enforcement"),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /"Resolves"/);
  assert.match(errors[0], /"No related issue"/);
});

test("stale reusable pin with current sections but stale keyword enforcement is drift", () => {
  const staleKeywords = GOOD_GATE.replace("|resolve[sd]?", "");
  const errors = checkPinnedReusable(POLICY, "dotfiles", "b".repeat(40), staleKeywords);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /rejects closing keyword "Resolves"/);
});

test("unparsable sources throw DriftError, never pass silently", () => {
  assert.throws(() => parseCompositeSections("#!/usr/bin/env bash\n", "composite"), DriftError);
  assert.throws(() => parseCompositeTypes("name: pr-contract\n", "composite"), DriftError);
  assert.throws(() => parseGateSections("jobs: {}", "gate"), DriftError);
  assert.throws(() => parseValidatorSections("echo hi", "validator"), DriftError);
  assert.throws(() => parseCallerPin("uses: something-else", "caller"), DriftError);
});

// ---------------------------------------------------------------------------
// Which artifact a consumer runs.
// ---------------------------------------------------------------------------

const COMPOSITE_STEP =
  "      - uses: melodic-software/ci-workflows/.github/actions/pr-contract@449157aaa8e30f7b1457305d8048ebe6168e174a # v0.20.0";
const REUSABLE_CALL =
  "    uses: melodic-software/ci-workflows/.github/workflows/pr-issue-linkage.yml@0f8176e87e0be518f382664779655011bf95784a # v0.17.2";

test("a composite consumer is detected at its pin", () => {
  assert.deepEqual(detectArtifactPin(`jobs:\n  ci-status:\n${COMPOSITE_STEP}\n`), {
    kind: "composite",
    sha: "449157aaa8e30f7b1457305d8048ebe6168e174a",
  });
});

test("a reusable consumer is detected at its pin", () => {
  assert.deepEqual(detectArtifactPin(`jobs:\n  linkage:\n${REUSABLE_CALL}\n`), {
    kind: "reusable",
    sha: "0f8176e87e0be518f382664779655011bf95784a",
  });
});

test("the composite wins when a repository carries both mid-transition", () => {
  const both = `jobs:\n  linkage:\n${REUSABLE_CALL}\n  ci-status:\n${COMPOSITE_STEP}\n`;
  assert.equal(detectArtifactPin(both).kind, "composite");
});

// ci-workflows dogfoods its own composite through a local `./` reference,
// which carries no SHA. The same path appears in that workflow as a lint
// `paths:` entry and as a `bash .../run.test.sh` command; neither is a call
// site, so the detector anchors on `uses:`.
test("a local composite reference resolves to main, and a bare path does not", () => {
  assert.deepEqual(
    detectArtifactPin("      - name: Contract\n        uses: ./.github/actions/pr-contract\n"),
    { kind: "composite", sha: "main" },
  );
  assert.equal(
    detectArtifactPin(
      "          paths: .github/actions/pr-contract .github/actions/ci-status\n" +
        "      - run: bash .github/actions/pr-contract/run.test.sh\n",
    ),
    null,
  );
});

test("a workflow with neither artifact detects nothing", () => {
  assert.equal(detectArtifactPin("jobs:\n  build:\n    runs-on: ubuntu-24.04\n"), null);
});

// ---------------------------------------------------------------------------
// The fleet, mid-transition.
// ---------------------------------------------------------------------------

function fleetResolutions(overrides = {}) {
  const resolutions = new Map();
  for (const repo of CONSUMER_REPOSITORIES) {
    resolutions.set(
      repo,
      UNSYNCED_REPOSITORIES.includes(repo)
        ? { kind: "none" }
        : { kind: "reusable", sha: "a".repeat(40), reusable: GOOD_GATE },
    );
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

test("a mixed fleet passes: composite consumers, reusable consumers, and the three unsynced", () => {
  const { errors, notes } = checkFleet(
    POLICY,
    fleetResolutions({
      "codex-plugins": compositeAt("4".repeat(40)),
      "github-iac": compositeAt("5".repeat(40)),
    }),
  );
  assert.deepEqual(errors, []);
  assert.equal(notes.length, UNSYNCED_REPOSITORIES.length);
  for (const repo of UNSYNCED_REPOSITORIES) {
    assert.ok(
      notes.some((note) => note.startsWith(`caller ${repo}:`)),
      `${repo} is reported, not failed`,
    );
  }
});

test("a gated repository running neither artifact fails, unlike the unsynced three", () => {
  const { errors, notes } = checkFleet(POLICY, fleetResolutions({ dotfiles: { kind: "none" } }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller dotfiles: no pr-contract composite step/);
  assert.equal(notes.length, UNSYNCED_REPOSITORIES.length);
});

test("types drift at one composite consumer fails the fleet", () => {
  const drifted = compositeAt(
    "6".repeat(40),
    GOOD_COMPOSITE_RUN,
    GOOD_COMPOSITE_ACTION.replace(",security", ""),
  );
  const { errors } = checkFleet(POLICY, fleetResolutions({ medley: drifted }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller medley pin 6666666: allowed title types missing security/);
});

test("sections drift at one composite consumer fails the fleet", () => {
  const drifted = compositeAt(
    "7".repeat(40),
    GOOD_COMPOSITE_RUN.replace('section_report("Verification")', 'section_report("Evidence")'),
  );
  const { errors } = checkFleet(POLICY, fleetResolutions({ provisioning: drifted }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller provisioning pin 7777777: section list/);
});

test("sections drift at one reusable consumer still fails the fleet", () => {
  const drifted = {
    kind: "reusable",
    sha: "8".repeat(40),
    reusable: GOOD_GATE.replace('"Fix"', '"Patch"'),
  };
  const { errors } = checkFleet(POLICY, fleetResolutions({ "ci-runner": drifted }));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller ci-runner pin 8888888: section list/);
});

test("a repository whose fetch already failed is not double-reported", () => {
  const { errors, notes } = checkFleet(
    POLICY,
    fleetResolutions({ standards: { kind: "unresolved" } }),
  );
  assert.deepEqual(errors, []);
  assert.equal(notes.length, UNSYNCED_REPOSITORIES.length);
});

test("consumer roster covers all thirteen repositories, three of them unsynced", () => {
  assert.equal(CONSUMER_REPOSITORIES.length, 13);
  assert.equal(UNSYNCED_REPOSITORIES.length, 3);
  for (const repo of UNSYNCED_REPOSITORIES) {
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
// are lowercase and rely on `i` to accept the documented capitalised keyword
// forms, so a gate that dropped `i` would silently become case-sensitive.
// Probing with a hardcoded `i` would pass it; the DECLARED flags catch it.
test("a reusable that drops the i flag is enforcement drift, not a pass", () => {
  const caseSensitiveGate = GOOD_GATE.replaceAll("/i;", "/g;");
  const patterns = parseGatePatterns(caseSensitiveGate, "gate");
  assert.equal(patterns.keyword.ignoreCase, false, "declared flags are preserved");
  assert.equal(patterns.keyword.test("Closes #12"), false, "capitalised form now rejected");
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
