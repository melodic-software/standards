import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  CLAUSE_DELIMITERS,
  checkCompositeBehavior,
  checkHookBehavior,
  GITHUB_CLOSING_KEYWORDS,
  linkageMatrix,
  MASKINGS,
  NON_DELIMITERS,
  UNTERMINATED_MASKINGS,
} from "./lockstep-behavior.mjs";
import {
  CONSUMER_REPOSITORIES,
  checkCopies,
  checkFleet,
  checkPinnedComposite,
  checkPinnedReusable,
  DriftError,
  detectArtifactPin,
  maskCode,
  parseCallerPin,
  parseCompositeNegation,
  parseCompositeNonClosing,
  parseCompositeRequireScope,
  parseCompositeSections,
  parseCompositeTypes,
  parseGatePatterns,
  parseGateSections,
  parseMarkdownHeadings,
  parseValidatorNegation,
  parseValidatorNonClosing,
  parseValidatorPatterns,
  parseValidatorSections,
  readGateComposite,
  resolveConsumerArtifact,
} from "./lockstep-drift.mjs";
import { parseUniqueJson } from "./pr-convention-policy.mjs";

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const POLICY = parseUniqueJson(
  await readFile(path.join(MODULE_DIRECTORY, "policy.json"), "utf8"),
  "policy.json",
);

// The two executable copies are vendored verbatim, because the behavioral
// layer runs them: the composite's run.sh from ci-workflows
// a932d486c5a4d0a959c42e60ff015f50cf2103f3 and the hook validator from
// claude-code-plugins 53d5c6a09dfb5890b9767b447a28ca10ba922173. The `.txt`
// suffix keeps the shell lint lanes off code this repository does not own.
// Refresh them when either upstream changes shape the tests depend on.
const readFixture = (name) =>
  readFile(path.join(MODULE_DIRECTORY, "fixtures", "lockstep", name), "utf8");
const GOOD_COMPOSITE_RUN = await readFixture("check-contract-run.sh.txt");
const GOOD_VALIDATOR = await readFixture("pr-linkage-validator.sh.txt");

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
// The live org template's shape since .github#135: one escape, plain text, on
// its own line inside the guidance comment an author reads and deletes. The
// comment placement is load-bearing — masking it the way the composite masks a
// PR body would leave the live template with no marker at all.
const GOOD_TEMPLATE = [
  "Closes #",
  "",
  "<!--",
  "Complete the `Closes #` line above with the issue number. If this PR closes",
  "no issue, replace that line with the escape and its reason, as plain text:",
  "",
  "No related issue: <reason>",
  "",
  "Write it without backticks: the gate masks inline code spans before matching.",
  "-->",
  "",
  "## Summary",
  "",
  "## Fix",
  "",
  "## Verification",
  "",
  "## Related",
  "",
].join("\n");
// The pre-#135 shape: both escapes present, but only ever inside inline code
// spans, so the composite sees neither.
const BACKTICKED_TEMPLATE = GOOD_TEMPLATE.replace(
  "No related issue: <reason>",
  "Use `No related issue: <reason>` or `No linked issue`.",
);
const GOOD_RULES = [
  "# PR body contract",
  "`Closes #<issue>` (`Fixes`/`Resolves`), a `Refs: #<issue>` line, or `No related issue: <reason>`.",
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
    () => parseCompositeRequireScope("name: pr-contract\ninputs:\n  types:\n", "composite"),
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

test("validator CLOSING_ERE is read from its own declaration, not NON_CLOSING_ERE", () => {
  const closing = GOOD_VALIDATOR.match(/^CLOSING_ERE=.*$/m)[0];
  const nonClosing = GOOD_VALIDATOR.match(/^NON_CLOSING_ERE=.*$/m)[0];
  const swapped = GOOD_VALIDATOR.replace(closing, "\0")
    .replace(nonClosing, closing)
    .replace("\0", nonClosing);
  assert.notEqual(swapped, GOOD_VALIDATOR);
  assert.match(parseValidatorPatterns(swapped, "validator").keyword.source, /^\(close/);
  assert.throws(
    () => parseValidatorPatterns(GOOD_VALIDATOR.replace(`${closing}\n`, ""), "v"),
    DriftError,
  );
});

test("validator that matches its EREs against un-lowercased text is drift", () => {
  // Each mutation is caught statically by name; running the hook confirms it
  // where a capitalized sample actually changes verdict.
  const mutations = [
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    ['    lower="${line,,}"', '    lower="$line"', "CLOSING_ERE", true],
    ['"$chunk" =~ $CLOSING_ERE', '"$line" =~ $CLOSING_ERE', "CLOSING_ERE", true],
    ['"$lower" =~ $NO_ISSUE_ERE', '"$1" =~ $NO_ISSUE_ERE', "NO_ISSUE_ERE", true],
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    ["${1,,}", "$1", "NO_ISSUE_ERE", true],
  ];
  for (const [from, to, name, behaves] of mutations) {
    const texts = goodTexts();
    texts.hookValidator = texts.hookValidator.replace(from, to);
    assert.notEqual(texts.hookValidator, GOOD_VALIDATOR, from);
    const errors = checkCopies(POLICY, texts);
    assert.ok(
      errors.every((error) => error.startsWith("hook validator")),
      errors.join("; "),
    );
    assert.match(errors[0], new RegExp(`^hook validator: .*no longer matches ${name} `), from);
    assert.equal(
      errors.some((error) => error.startsWith("hook validator (behavior): ")),
      behaves,
      `${from}: ${errors.join("; ")}`,
    );
  }
  // An extra raw-line match alongside the lowercased one is drift too.
  const texts = goodTexts();
  texts.hookValidator += '[[ "$line" =~ $CLOSING_ERE ]] || true\n';
  assert.equal(checkCopies(POLICY, texts).length, 1);
});

test("stale reusable pin with current sections but stale keyword enforcement is drift", () => {
  const staleKeywords = GOOD_GATE.replace("|resolve[sd]?", "");
  const errors = checkPinnedReusable(POLICY, "dotfiles", "b".repeat(40), staleKeywords);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /rejects closing keyword "Resolves"/);
});

// ---------------------------------------------------------------------------
// Non-closing references and negated closers (#647). Static extractors diff
// the declared data; the behavioral layer runs the vendored copies on a
// policy-generated matrix, so every mutation below that breaks behavior must
// surface as a `(behavior)` finding whatever source shape it takes.
// ---------------------------------------------------------------------------

const NEGATION_DATA_FIELDS = [
  "triggerWords",
  "triggerSuffixes",
  "affirmativePhrases",
  "wordWindow",
];
const negationData = (negatedClosers) =>
  Object.fromEntries(NEGATION_DATA_FIELDS.map((field) => [field, negatedClosers[field]]));

// Mutate one copy and return its findings, asserting the text really changed.
function mutate(copy, from, to) {
  const texts = goodTexts();
  texts[copy] = texts[copy].replace(from, to);
  assert.notEqual(texts[copy], goodTexts()[copy], `mutation did not apply: ${from}`);
  return checkCopies(POLICY, texts);
}

const LOCATION = { gateRun: "gate composite", hookValidator: "hook validator" };

function assertOnlyBehavior(errors, copy, expected) {
  assert.equal(errors.length, 1, errors.join("; "));
  assert.ok(errors[0].startsWith(`${LOCATION[copy]} (behavior): `), errors[0]);
  assert.match(errors[0], expected);
}

test("non-closing and negation parsers read the policy's values from both copies", () => {
  const expectedMarkers = POLICY.body.nonClosingMarkers.map((marker) => marker.toLowerCase());
  assert.deepEqual(parseValidatorNonClosing(GOOD_VALIDATOR, "hook").markers, expectedMarkers);
  assert.deepEqual(parseCompositeNonClosing(GOOD_COMPOSITE_RUN, "gate").markers, expectedMarkers);
  const expectedNegation = negationData(POLICY.body.negatedClosers);
  assert.deepEqual(parseValidatorNegation(GOOD_VALIDATOR, "hook"), expectedNegation);
  assert.deepEqual(parseCompositeNegation(GOOD_COMPOSITE_RUN, "gate"), expectedNegation);
});

test("the sample matrix covers every policy value, inside and just outside the window", () => {
  const matrix = linkageMatrix(POLICY);
  const lines = matrix.map(({ line }) => line);
  const { body } = POLICY;
  for (const term of [...body.closingKeywords, ...body.nonClosingMarkers, ...body.noIssueMarkers]) {
    assert.ok(
      lines.some((line) => line.includes(term)),
      term,
    );
  }
  const negated = matrix.filter(({ expect }) => expect.negated).map(({ expect }) => expect.negated);
  for (const word of body.negatedClosers.triggerWords) {
    assert.ok(negated.includes(word), word);
  }
  for (const suffix of body.negatedClosers.triggerSuffixes) {
    assert.ok(
      negated.some((word) => word.endsWith(suffix)),
      suffix,
    );
  }
  for (const delimiter of CLAUSE_DELIMITERS) {
    assert.ok(
      lines.some((line) => line.includes(`${delimiter} `)),
      delimiter,
    );
  }
  // Each trigger appears, for each closing keyword, once at the window's edge
  // (negated) and once a word further out (closing).
  const firstTrigger = body.negatedClosers.triggerWords[0];
  const atEdge = matrix.filter(({ line }) => line.startsWith(`${firstTrigger} alpha `));
  assert.deepEqual(
    atEdge.map(({ expect }) => [expect.negated, expect.closing]),
    body.closingKeywords.flatMap(() => [
      [firstTrigger, false],
      [null, true],
    ]),
  );
});

test("a composite with the negation call removed is behavioral drift", () => {
  const errors = mutate(
    "gateRun",
    "    trigger = negation_trigger(line, start)\n",
    '    trigger = ""\n',
  );
  assertOnlyBehavior(errors, "gateRun", /should be negated by "not", got closing/);
});

test("a hook whose negation helper never writes its result is behavioral drift", () => {
  // The trigger branch's write into the caller-named variable: without it the
  // helper still returns 0, the destination stays empty, and every negated
  // closer counts as a valid one.
  const errors = mutate("hookValidator", `      printf -v "$__plv_dest" '%s' "\${words[i]}"\n`, "");
  assertOnlyBehavior(errors, "hookValidator", /should be unlinked \+ negated by "not", got linked/);
});

test("a dropped non-closing marker is drift statically and behaviorally, in either copy", () => {
  const hook = mutate("hookValidator", "(refs|relates[[:blank:]]+to):", "(refs):");
  assert.equal(hook.length, 2, hook.join("; "));
  assert.match(
    hook[0],
    /^hook validator \(non-closing markers\): non-closing markers missing relates to/,
  );
  assert.match(
    hook[1],
    /^hook validator \(behavior\): .*"Relates to: #12" should be linked, got unlinked/,
  );

  const gate = mutate("gateRun", "(refs|relates[ \\t]+to):", "(refs):");
  assert.equal(gate.length, 2, gate.join("; "));
  assert.match(
    gate[0],
    /^gate composite \(non-closing markers\): non-closing markers missing relates to/,
  );
  assert.match(
    gate[1],
    /^gate composite \(behavior\): .*"Relates to: #12" should be non-closing, got no linkage/,
  );
});

test("a declared marker policy does not name is static drift", () => {
  const errors = mutate("hookValidator", "(refs|relates", "(refs|see|relates");
  assert.equal(errors.length, 1, errors.join("; "));
  assert.match(errors[0], /^hook validator \(non-closing markers\): .*unexpected see/);
});

test("a non-closing pattern that stops requiring its own line is behavioral drift", () => {
  const errors = mutate("hookValidator", "#[0-9]+[[:blank:]]*$'", "#[0-9]+'");
  assertOnlyBehavior(
    errors,
    "hookValidator",
    /"Refs: #12 and more" should be unlinked, got linked/,
  );
});

test("a policy marker no copy implements is drift in both copies, both ways", () => {
  const policy = structuredClone(POLICY);
  policy.body.nonClosingMarkers.push("Part of");
  const errors = checkCopies(policy, goodTexts());
  assert.equal(errors.length, 4, errors.join("; "));
  assert.match(errors[0], /^gate composite \(non-closing markers\): .*missing part of/);
  assert.match(errors[1], /^hook validator \(non-closing markers\): .*missing part of/);
  assert.match(errors[2], /^gate composite \(behavior\): .*"Part of: #12"/);
  assert.match(errors[3], /^hook validator \(behavior\): .*"Part of: #12"/);
});

// Each of these broke one link earlier review rounds had to find by reading
// source: the helper's input, a verdict, the exception, the window.
test("breaking how either copy reaches its verdict is behavioral drift", () => {
  const cases = [
    ["gateRun", "    words[count] = substr(tail, RSTART, RLENGTH)\n", "", /negated by/],
    [
      "gateRun",
      "  tail = substr(preceding, cut + 1)",
      "  tail = preceding",
      /"It is not\. Closes #12"/,
    ],
    [
      "gateRun",
      '  if (has_non_closing) print "non-closing"\n',
      "",
      /"Refs: #12" should be non-closing/,
    ],
    [
      "gateRun",
      "count - 4 : 1",
      "count - 5 : 1",
      /echo Closes #12" should be closing, got negated/,
    ],
    // An early return ahead of the intact "not only" exception line.
    [
      "gateRun",
      "    lower = tolower(word)\n",
      "    lower = tolower(word)\n    if (lower ~ /^not$/) return word\n",
      /"This not only closes #12" should be closing/,
    ],
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    ["hookValidator", 'tail="${2##*[.!?;,]}"', 'tail="$2"', /"It is not, Closes #12"/],
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    ["hookValidator", "  n=${#words[@]}", "  n=0", /negated by/],
    [
      "hookValidator",
      '[[ "$lower" =~ $NON_CLOSING_ERE ]] && found=0',
      '[[ "$lower" =~ $NON_CLOSING_ERE ]] && :',
      /"Refs: #12" should be linked, got unlinked/,
    ],
    [
      "hookValidator",
      '      if [[ -z "$_plv_trigger" ]]; then',
      "      if true; then",
      /should be unlinked \+ negated by "not", got linked/,
    ],
  ];
  for (const [copy, from, to, expected] of cases) {
    assertOnlyBehavior(mutate(copy, from, to), copy, expected);
  }
});

test("the sample matrix hides every kind of linkage in every masked shape", () => {
  const matrix = linkageMatrix(POLICY);
  const { closingKeywords, nonClosingMarkers, noIssueMarkers, negatedClosers } = POLICY.body;
  const negatedCloser = `This does ${negatedClosers.triggerWords[0]} ${closingKeywords[0].toLowerCase()} #12`;
  const hidden = [
    `${closingKeywords[0]} #12`,
    ...nonClosingMarkers.map((marker) => `${marker}: #12`),
    negatedCloser,
    `${noIssueMarkers[0]}: housekeeping`,
  ];
  const unlinked = { closing: false, nonClosing: false, noIssue: false, negated: null };
  for (const [name, mask] of MASKINGS) {
    for (const text of hidden) {
      const sample = matrix.find(({ line }) => line === mask(text));
      assert.ok(sample, `${name}: ${text}`);
      assert.deepEqual(sample.expect, unlinked, `${name}: ${text}`);
    }
    const beside = matrix.find(({ line }) => line.startsWith(`${mask(negatedCloser)}\n\n`));
    assert.ok(beside, `${name}: masked negated closer beside a marker`);
    assert.deepEqual(beside.expect, { ...unlinked, nonClosing: true }, name);
  }
  for (const [name, mask] of UNTERMINATED_MASKINGS) {
    for (const text of hidden) {
      const sample = matrix.find(({ line }) => line === mask(text));
      assert.ok(sample, `${name}: ${text}`);
      assert.deepEqual(sample.expect, unlinked, `${name}: ${text}`);
    }
  }
});

// The masked samples exist for these mutations: a copy that scans the raw
// body, or masks comments but not code, agrees with policy on every plain
// sample and differs only where linkage is hidden.
test("a copy that scans unmasked text is behavioral drift", () => {
  const raw = mutate(
    "hookValidator",
    'scan_linkage "$_plv_body" || _plv_linked=1',
    'scan_linkage "$1" || _plv_linked=1',
  );
  assertOnlyBehavior(raw, "hookValidator", /"<!-- Closes #12 -->" should be unlinked, got linked/);

  const commentsOnly = mutate(
    "hookValidator",
    'scan_linkage "$_plv_body" || _plv_linked=1',
    'scan_linkage "$_plv_stripped" || _plv_linked=1',
  );
  assertOnlyBehavior(
    commentsOnly,
    "hookValidator",
    /"```\\nCloses #12\\n```" should be unlinked, got linked/,
  );
  assert.doesNotMatch(commentsOnly[0], /<!--/);

  const texts = goodTexts();
  texts.gateRun = texts.gateRun
    .replace("  line = $0\n", "  line = $0\n  raw[NR] = line\n")
    .replace("    scan_line(masked[i])", "    scan_line(raw[i])");
  assert.equal((texts.gateRun.match(/raw\[/g) ?? []).length, 2, "mutation did not apply");
  assertOnlyBehavior(
    checkCopies(POLICY, texts),
    "gateRun",
    /"<!-- Closes #12 -->" should be no linkage, got closing/,
  );
});

test("every closing keyword is probed in every negation shape", () => {
  const lines = linkageMatrix(POLICY).map(({ line }) => line);
  const { closingKeywords, nonClosingMarkers, negatedClosers } = POLICY.body;
  const [firstTrigger] = negatedClosers.triggerWords;
  for (const keyword of closingKeywords) {
    const lower = keyword.toLowerCase();
    const shapes = [
      `${firstTrigger} alpha bravo charlie delta ${keyword} #12`,
      `${firstTrigger} alpha bravo charlie delta echo ${keyword} #12`,
      ...CLAUSE_DELIMITERS.map((delimiter) => `It is ${firstTrigger}${delimiter} ${keyword} #12`),
      ...NON_DELIMITERS.map((mark) => `It is ${firstTrigger}${mark} ${keyword} #12`),
      ...negatedClosers.affirmativePhrases.map((phrase) => `This ${phrase} ${lower} #12`),
      `This does ${firstTrigger} ${lower} #12\n${nonClosingMarkers[0]}: #13`,
      ...MASKINGS.map(([, mask]) => mask(`This does ${firstTrigger} ${lower} #12`)),
    ];
    for (const shape of shapes) {
      assert.ok(lines.includes(shape), shape);
    }
  }
});

// Each mutation below reads the policy correctly for the first closing
// keyword, the only one the matrix once probed for negation.
test("a copy that detects negation for one closing keyword only is behavioral drift", () => {
  const gate = mutate(
    "gateRun",
    "    trigger = negation_trigger(line, start)\n",
    '    trigger = (substr(lower, start, 5) == "close") ? negation_trigger(line, start) : ""\n',
  );
  assertOnlyBehavior(
    gate,
    "gateRun",
    /"not alpha bravo charlie delta Fixes #12" should be negated/,
  );

  const hook = mutate(
    "hookValidator",
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    '      negation_trigger_to _plv_trigger "${line:0:start}"\n',
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    '      _plv_trigger=""\n      [[ "$m" == close* ]] && negation_trigger_to _plv_trigger "${line:0:start}"\n',
  );
  assertOnlyBehavior(
    hook,
    "hookValidator",
    /"not alpha bravo charlie delta Fixes #12" should be unlinked \+ negated by "not", got linked/,
  );
});

test("a copy that recognizes the suffix on one word only is behavioral drift", () => {
  const gate = mutate(
    "gateRun",
    `    if (tolower(substr(word, length(word) - 2)) == "n'"'"'t") return word`,
    `    if (lower != "doesn'"'"'t") continue\n    if (tolower(substr(word, length(word) - 2)) == "n'"'"'t") return word`,
  );
  assertOnlyBehavior(gate, "gateRun", /"This won't closes #12" should be negated/);

  const hook = mutate(
    "hookValidator",
    `    case "$lower" in\n`,
    `    [[ "$lower" == *"n't" && "$lower" != "doesn't" ]] && continue\n    case "$lower" in\n`,
  );
  assertOnlyBehavior(hook, "hookValidator", /"This won't closes #12" should be unlinked/);
});

test("a copy that folds case on the suffix for one word only is behavioral drift", () => {
  const gate = mutate(
    "gateRun",
    `    if (tolower(substr(word, length(word) - 2)) == "n'"'"'t") return word`,
    `    if (word != lower && lower ~ /n'"'"'t$/ && lower != "doesn'"'"'t") continue\n    if (tolower(substr(word, length(word) - 2)) == "n'"'"'t") return word`,
  );
  assertOnlyBehavior(gate, "gateRun", /"This WON'T closes #12" should be negated/);

  const hook = mutate(
    "hookValidator",
    `    case "$lower" in\n`,
    `    [[ "\${words[i]}" != "$lower" && "$lower" == *"n't" && "$lower" != "doesn't" ]] && continue\n    case "$lower" in\n`,
  );
  assertOnlyBehavior(hook, "hookValidator", /"This WON'T closes #12" should be unlinked/);
});

test("punctuation outside the clause delimiters keeps the negation window open", () => {
  for (const mark of NON_DELIMITERS) {
    assert.ok(!CLAUSE_DELIMITERS.includes(mark), mark);
  }
  const { closingKeywords, negatedClosers } = POLICY.body;
  const [firstTrigger] = negatedClosers.triggerWords;
  const matrix = linkageMatrix(POLICY);
  for (const mark of NON_DELIMITERS) {
    const sample = matrix.find(
      ({ line }) => line === `It is ${firstTrigger}${mark} ${closingKeywords[0]} #12`,
    );
    assert.ok(sample, mark);
    assert.equal(sample.expect.negated, firstTrigger, mark);
    assert.equal(sample.expect.closing, false, mark);
  }
});

test("a copy that treats a colon as a clause delimiter is behavioral drift", () => {
  const gate = mutate("gateRun", 'ch == ";" || ch == ","', 'ch == ";" || ch == "," || ch == ":"');
  assertOnlyBehavior(
    gate,
    "gateRun",
    /"It is not: Closes #12" should be negated by "not", got closing/,
  );

  // biome-ignore lint/suspicious/noTemplateCurlyInString: bash parameter expansions, not JS placeholders
  const hook = mutate("hookValidator", 'tail="${2##*[.!?;,]}"', 'tail="${2##*[.!?;,:]}"');
  assertOnlyBehavior(
    hook,
    "hookValidator",
    /"It is not: Closes #12" should be unlinked \+ negated by "not", got linked/,
  );
});

test("a copy that stops at the first closing reference on a line is behavioral drift", () => {
  const gate = mutate("gateRun", "    offset = start + len - 1\n", "    offset = length(lower)\n");
  assertOnlyBehavior(
    gate,
    "gateRun",
    /"Closes #11 but does not closes #12" should be closing \+ negated by "not", got closing/,
  );
  assert.match(gate[0], /"This does not closes #12; Closes #11" should be closing \+ negated/);

  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  const hook = mutate("hookValidator", "      off=$((start + len))\n", "      off=${#lower}\n");
  assertOnlyBehavior(
    hook,
    "hookValidator",
    /"Closes #11 but does not closes #12" should be linked \+ negated by "not", got linked/,
  );
  assert.match(hook[0], /"This does not closes #12; Closes #11" should be linked \+ negated/);
});

// The policy spells three keywords, but GitHub closes on all nine forms.
test("a copy that negates only the policy's keyword spellings is behavioral drift", () => {
  const lines = linkageMatrix(POLICY).map(({ line }) => line);
  for (const form of GITHUB_CLOSING_KEYWORDS) {
    assert.ok(
      lines.some((line) => line.toLowerCase() === `${form} #12`),
      form,
    );
    assert.ok(lines.includes(`This does not ${form} #12`), form);
  }

  const gate = mutate(
    "gateRun",
    "    trigger = negation_trigger(line, start)\n",
    '    trigger = (substr(lower, start, len) ~ /^(closes|fixes|resolves)/) ? negation_trigger(line, start) : ""\n',
  );
  assertOnlyBehavior(
    gate,
    "gateRun",
    /"This does not close #12" should be negated by "not", got closing/,
  );

  const hook = mutate(
    "hookValidator",
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    '      negation_trigger_to _plv_trigger "${line:0:start}"\n',
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    '      _plv_trigger=""\n      [[ "$m" =~ ^(closes|fixes|resolves) ]] && negation_trigger_to _plv_trigger "${line:0:start}"\n',
  );
  assertOnlyBehavior(
    hook,
    "hookValidator",
    /"This does not close #12" should be unlinked \+ negated by "not", got linked/,
  );
});

// An opt-out does not excuse a negated closer: GitHub closes the issue anyway.
test("a copy that skips negation once a body opts out is behavioral drift", () => {
  const texts = goodTexts();
  texts.gateRun = texts.gateRun
    .replace(
      '  body = ""\n',
      '  for (i = 1; i <= line_count; i++) if (tolower(masked[i]) ~ /no (linked|related) issue/) opted_out = 1\n  body = ""\n',
    )
    .replace(
      "    trigger = negation_trigger(line, start)\n",
      '    trigger = opted_out ? "" : negation_trigger(line, start)\n',
    );
  assert.equal((texts.gateRun.match(/opted_out/g) ?? []).length, 2, "mutation did not apply");
  assertOnlyBehavior(
    checkCopies(POLICY, texts),
    "gateRun",
    /"No linked issue: housekeeping\\nThis does not closes #12" should be no-issue \+ negated by "not", got closing \+ no-issue/,
  );

  const hook = mutate(
    "hookValidator",
    '  LINKAGE_NEGATED=()\n  linkage::split_lines "$1"\n',
    // The hook's own no-issue test, as scan_linkage runs it after the loop;
    // `$$` is a literal `$` in a String.replace replacement.
    `  LINKAGE_NEGATED=()\n  [[ $$'\\n'"\${1,,}"$$'\\n' =~ $NO_ISSUE_ERE ]] && return 0\n  linkage::split_lines "$1"\n`,
  );
  assertOnlyBehavior(
    hook,
    "hookValidator",
    /"No linked issue: housekeeping\\nThis does not closes #12" should be linked \+ negated by "not", got linked/,
  );
});

test("the sample matrix crosses a negated closer with every kind of linkage", () => {
  const lines = linkageMatrix(POLICY).map(({ line }) => line);
  const { closingKeywords, nonClosingMarkers, noIssueMarkers } = POLICY.body;
  const others = [
    ...nonClosingMarkers.map((marker) => `${marker}: #13`),
    ...noIssueMarkers.map((marker) => `${marker}: housekeeping`),
  ];
  for (const keyword of closingKeywords) {
    const negated = `This does not ${keyword.toLowerCase()} #12`;
    for (const text of [`${keyword} #11`, ...others]) {
      assert.ok(lines.includes(`${text}\n${negated}`), `${text} then ${negated}`);
      assert.ok(lines.includes(`${negated}\n${text}`), `${negated} then ${text}`);
    }
  }
  for (const first of [`${closingKeywords[0]} #11`, ...others]) {
    for (const second of [`${closingKeywords[0]} #11`, ...others]) {
      if (first !== second) {
        assert.ok(lines.includes(`${first}\n${second}`), `${first} then ${second}`);
      }
    }
  }
});

test("the sample matrix varies case, apostrophes and the window's word rules", () => {
  const lines = linkageMatrix(POLICY).map(({ line }) => line);
  const { closingKeywords, nonClosingMarkers, noIssueMarkers, negatedClosers } = POLICY.body;
  for (const keyword of closingKeywords) {
    const lower = keyword.toLowerCase();
    for (const shape of [
      `${keyword.toUpperCase()} #12`,
      `${keyword}: #12`,
      `${keyword} #11\nThis does not ${lower} #12`,
      `This does not ${lower} #12\n${keyword} #11`,
      `not\n${keyword} #12`,
      ...negatedClosers.triggerWords.map((word) => `This ${word.toUpperCase()} ${lower} #12`),
      `This DOESN\u2019T ${lower} #12`,
      `This NOT ONLY ${lower} #12`,
      `This Not Only ${lower} #12`,
    ]) {
      assert.ok(lines.includes(shape), JSON.stringify(shape));
    }
  }
  for (const marker of [...nonClosingMarkers, ...noIssueMarkers]) {
    assert.ok(
      lines.some((line) => line.startsWith(marker.toUpperCase())),
      marker,
    );
  }
});

// Each copy folds case in several places and normalizes the typographic
// apostrophe; undoing any one of them must change a verdict on the matrix.
test("undoing any normalization step in either copy is behavioral drift", () => {
  const cases = [
    ["gateRun", "    lower = tolower(word)\n", "    lower = word\n", /"This NOT closes #12"/],
    [
      "gateRun",
      'tolower(words[i + 1]) == "only"',
      'words[i + 1] == "only"',
      /"This NOT ONLY closes #12" should be closing, got negated by "NOT"/,
    ],
    [
      "gateRun",
      `if (tolower(substr(word, length(word) - 2)) == "n'"'"'t")`,
      `if (substr(word, length(word) - 2) == "n'"'"'t")`,
      /"This DOESN'T closes #12" should be negated by "DOESN'T", got closing/,
    ],
    [
      "gateRun",
      `  gsub("\\342\\200\\231", "'"'"'", tail)\n`,
      "",
      /"This doesn\u2019t closes #12" should be negated by "doesn't", got closing/,
    ],
    [
      "gateRun",
      "    rest = tolower(substr(line, indent + 1))\n",
      "    rest = substr(line, indent + 1)\n",
      /"REFS: #12" should be non-closing, got no linkage/,
    ],
    [
      "gateRun",
      "  if (tolower(body) ~ /(^|",
      "  if (body ~ /(^|",
      /"No linked issue: housekeeping" should be no-issue, got no linkage/,
    ],
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    ["hookValidator", 'lower="${words[i],,}"', 'lower="${words[i]}"', /"This NOT closes #12"/],
    [
      "hookValidator",
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '[[ "${words[i + 1],,}" == only ]]',
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '[[ "${words[i + 1]}" == only ]]',
      /"This NOT ONLY closes #12" should be linked, got unlinked \+ negated by "NOT"/,
    ],
    [
      "hookValidator",
      `  tail="\${tail//$'\\xe2\\x80\\x99'/\\'}"\n`,
      "",
      /"This doesn\u2019t closes #12" should be unlinked \+ negated by "doesn't", got linked/,
    ],
    [
      "hookValidator",
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '    lower="${line,,}"\n',
      '    lower="$line"\n',
      /"CLOSES #12" should be linked/,
    ],
    [
      "hookValidator",
      `  lower=$'\\n'"\${1,,}"$'\\n'`,
      // `$$` is a literal `$` in a String.replace replacement; a bare `$'`
      // would splice in the rest of the file.
      `  lower=$$'\\n'"$1"$$'\\n'`,
      /"No linked issue: housekeeping" should be linked, got unlinked/,
    ],
  ];
  // A static extractor may name the same edit too; the behavioral finding
  // must be there either way, and nothing outside the mutated copy may fire.
  for (const [copy, from, to, expected] of cases) {
    const errors = mutate(copy, from, to);
    const behavior = errors.filter((error) => error.startsWith(`${LOCATION[copy]} (behavior): `));
    assert.equal(behavior.length, 1, errors.join("; "));
    assert.match(behavior[0], expected);
    for (const error of errors) {
      assert.ok(error.startsWith(LOCATION[copy]), error);
    }
  }
});

test("every sample body fills the policy's own required sections", () => {
  const tail = "\n\n## Summary\ns\n\n## Fix\nf\n\n## Verification\nv\n\n## Related\nr\n";
  for (const { line, body } of linkageMatrix(POLICY)) {
    assert.equal(body, `${line}${tail}`);
  }
  const policy = structuredClone(POLICY);
  policy.body.requiredSections = ["Motivation", "Test plan"];
  for (const { line, body } of linkageMatrix(policy)) {
    assert.equal(body, `${line}\n\n## Motivation\nm\n\n## Test plan\nt\n`);
  }
});

test("the window samples follow any schema-valid wordWindow", () => {
  const policy = structuredClone(POLICY);
  policy.body.negatedClosers.wordWindow = 40;
  const [trigger] = policy.body.negatedClosers.triggerWords;
  const [closer] = policy.body.closingKeywords;
  const edge = linkageMatrix(policy).filter(({ line }) =>
    new RegExp(`^${trigger} [a-z ]+ ${closer} #12$`).test(line),
  );
  const widths = edge.map(({ line }) => line.split(" ").length - 3).sort((a, b) => a - b);
  assert.deepEqual(widths, [39, 40]);
  for (const { line } of edge) {
    const words = line.split(" ").slice(1, -2);
    assert.equal(new Set(words).size, words.length, line);
    for (const word of words) {
      assert.match(word, /^[a-z]+$/);
    }
  }
});

test("a trigger list change is named statically and confirmed behaviorally", () => {
  const hook = mutate("hookValidator", " | intentionally", "");
  assert.equal(hook.length, 2, hook.join("; "));
  assert.match(
    hook[0],
    /^hook validator \(negated closers\): .*triggerWords missing intentionally/,
  );
  assert.match(hook[1], /^hook validator \(behavior\): .*negated by "intentionally"/);

  const gate = mutate(
    "gateRun",
    'lower == "without" ||',
    'lower == "without" || lower == "alpha" ||',
  );
  assert.ok(gate[0].startsWith("gate composite (negated closers): "), gate[0]);
  assert.match(gate[0], /unexpected alpha/);
  assert.ok(gate.some((error) => error.startsWith("gate composite (behavior): ")));
});

test("a run.sh that stops acting on the analyzer's report is drift", () => {
  const ignored = mutate("gateRun", '    [[ "$kind" == negated ]] || continue', "    continue");
  assert.equal(ignored.length, 1, ignored.join("; "));
  assert.match(ignored[0], /^gate composite \(verdict\): .*a `negated` report is a linkage error/);

  const unread = mutate("gateRun", "    ! grep -qx 'non-closing' \"$analysis\" &&\n", "");
  assert.equal(unread.length, 1, unread.join("; "));
  assert.match(
    unread[0],
    /^gate composite \(verdict\): .*a `non-closing` report satisfies linkage/,
  );
});

test("a composite pin without the non-closing or negation rules is drift at that pin", () => {
  const stale = GOOD_COMPOSITE_RUN.replace("(refs|relates[ \\t]+to):", "(refs):").replace(
    'lower == "deliberately" || ',
    "",
  );
  const errors = checkPinnedComposite(
    POLICY,
    "medley",
    "f".repeat(40),
    stale,
    GOOD_COMPOSITE_ACTION,
  );
  assert.equal(errors.length, 3, errors.join("; "));
  assert.match(errors[0], /^caller medley pin fffffff: non-closing markers missing relates to/);
  assert.match(errors[1], /^caller medley pin fffffff: negated-closer rule .*missing deliberately/);
  assert.match(errors[2], /^caller medley pin fffffff \(behavior\): /);
});

test("code the behavioral layer cannot run is drift, never a pass", () => {
  assert.throws(
    () => checkCompositeBehavior("#!/usr/bin/env bash\n", POLICY, "composite"),
    /no `analyze_body\(\) \{ awk '\.\.\.' \}` analyzer/,
  );
  assert.throws(() => checkHookBehavior("return 1\n", POLICY, "hook"), /does not source cleanly/);
  assert.throws(
    () => checkHookBehavior("true\n", POLICY, "hook"),
    /no longer defines linkage::problems/,
  );
  assert.throws(
    () => checkHookBehavior("linkage::problems() { exit 7; }\n", POLICY, "hook"),
    (error) => error instanceof DriftError && /harness exited 7/.test(error.message),
  );
});

test("the composite's analyzer runs sandboxed: system() is refused", () => {
  const escaping = GOOD_COMPOSITE_RUN.replace("END {\n", 'END {\n  system("echo escaped")\n');
  assert.notEqual(escaping, GOOD_COMPOSITE_RUN);
  assert.throws(
    () => checkCompositeBehavior(escaping, POLICY, "composite"),
    (error) => error instanceof DriftError && /analyzer exited 2/.test(error.message),
  );
});

test("the hook runs with no inherited environment", () => {
  // A probe library that reports what it can see: the lane token must not
  // reach code fetched from another repository.
  // The probe passes every body when it sees a clean environment and fails
  // every body when it sees the token or HOME, so a leak shows up as the very
  // first sample, a plain closing keyword, reported unlinked.
  process.env.LOCKSTEP_GITHUB_TOKEN = "must-not-leak";
  try {
    const probe = [
      "LINKAGE_PROBLEMS=()",
      "linkage::problems() {",
      "  LINKAGE_PROBLEMS=()",
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '  [[ -z "${LOCKSTEP_GITHUB_TOKEN:-}${GITHUB_TOKEN:-}${HOME:-}" ]] || LINKAGE_PROBLEMS=(leak)',
      "}",
    ].join("\n");
    assert.throws(
      () => checkHookBehavior(probe, POLICY, "hook"),
      (error) =>
        error instanceof DriftError &&
        /should be unlinked, got linked/.test(error.message) &&
        !error.message.includes('"Closes #12" should be linked'),
    );
  } finally {
    delete process.env.LOCKSTEP_GITHUB_TOKEN;
  }
});

test("unparsable sources throw DriftError, never pass silently", () => {
  assert.throws(() => parseCompositeSections("#!/usr/bin/env bash\n", "composite"), DriftError);
  assert.throws(() => parseCompositeTypes("name: pr-contract\n", "composite"), DriftError);
  assert.throws(() => parseGateSections("jobs: {}", "gate"), DriftError);
  assert.throws(() => parseValidatorSections("echo hi", "validator"), DriftError);
  assert.throws(() => parseCallerPin("uses: something-else", "caller"), DriftError);
  assert.throws(() => parseCompositeNonClosing("#!/usr/bin/env bash\n", "composite"), DriftError);
  assert.throws(() => parseCompositeNegation("#!/usr/bin/env bash\n", "composite"), DriftError);
  assert.throws(() => parseValidatorNegation("echo hi", "validator"), DriftError);
});

// ---------------------------------------------------------------------------
// Which artifact a consumer runs.
// ---------------------------------------------------------------------------

const COMPOSITE_STEP =
  "      - uses: melodic-software/ci-workflows/.github/actions/pr-contract@449157aaa8e30f7b1457305d8048ebe6168e174a # v0.20.0";
const REUSABLE_CALL =
  "    uses: melodic-software/ci-workflows/.github/workflows/pr-issue-linkage.yml@0f8176e87e0be518f382664779655011bf95784a # v0.17.2";

const LEGACY_DIRECTORY = ".github/actions/pr-contract";
const RENAMED_DIRECTORY = ".github/actions/pr-require-checks/check-contract";

test("a consumer pinned to the pr-contract composite is detected at its pin", () => {
  assert.deepEqual(detectArtifactPin(`jobs:\n  ci-status:\n${COMPOSITE_STEP}\n`), {
    kind: "composite",
    sha: "449157aaa8e30f7b1457305d8048ebe6168e174a",
    directory: LEGACY_DIRECTORY,
  });
});

test("a consumer pinned to the renamed check-contract composite is detected at its pin", () => {
  const step =
    "      - uses: melodic-software/ci-workflows/.github/actions/pr-require-checks/check-contract@1234567890abcdef1234567890abcdef12345678 # v0.34.0";
  assert.deepEqual(detectArtifactPin(`jobs:\n  ci-status:\n${step}\n`), {
    kind: "composite",
    sha: "1234567890abcdef1234567890abcdef12345678",
    directory: RENAMED_DIRECTORY,
  });
});

test("a local reference to the renamed composite resolves to main", () => {
  assert.deepEqual(detectArtifactPin(`        uses: ./${RENAMED_DIRECTORY}\n`), {
    kind: "composite",
    sha: "main",
    directory: RENAMED_DIRECTORY,
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
    { kind: "composite", sha: "main", directory: LEGACY_DIRECTORY },
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

// A migration leaves commented-out call sites behind. Selecting an artifact a
// repository does not run would suppress detection of the one it does, and a
// repository that had lost its last live caller would validate an unused
// artifact instead of reporting that it runs neither.
test("a commented-out call site is not a call site", () => {
  assert.equal(detectArtifactPin(`      # ${COMPOSITE_STEP.trim()}\n`), null);
  assert.equal(detectArtifactPin(`    # ${REUSABLE_CALL.trim()}\n`), null);
  assert.equal(
    detectArtifactPin(`      # - uses: ./.github/actions/pr-contract\n${REUSABLE_CALL}\n`).kind,
    "reusable",
  );
});

// The ci-workflows rename moves the gate from `ci.yml` to
// `pr-require-checks.yml`. The scan reads that file before any other, so a
// repository calling the composite from there costs one read.
test("a composite called from pr-require-checks.yml is found on the first read", async () => {
  const reads = [];
  const files = {
    "build.yml": "jobs:\n  build:\n    runs-on: ubuntu-24.04\n",
    "pr-require-checks.yml": `jobs:\n  ci-status:\n        uses: ./${RENAMED_DIRECTORY}\n`,
    "lint.yml": "jobs:\n  lint:\n    runs-on: ubuntu-24.04\n",
  };
  const found = await resolveConsumerArtifact(
    "ci-workflows",
    async (url) => {
      const name = url.match(/\.github\/workflows\/([^?]+)/)[1];
      reads.push(name);
      return files[name];
    },
    async () => Object.keys(files),
  );
  assert.deepEqual(found, { kind: "composite", sha: "main", directory: RENAMED_DIRECTORY });
  assert.deepEqual(reads, ["pr-require-checks.yml"]);
});

test("pr-require-checks.yml is read before ci.yml when both exist mid-rename", async () => {
  const reads = [];
  const files = {
    "ci.yml": `jobs:\n  ci-status:\n        uses: ./${LEGACY_DIRECTORY}\n`,
    "pr-require-checks.yml": `jobs:\n  ci-status:\n        uses: ./${RENAMED_DIRECTORY}\n`,
  };
  const found = await resolveConsumerArtifact(
    "ci-workflows",
    async (url) => {
      const name = url.match(/\.github\/workflows\/([^?]+)/)[1];
      reads.push(name);
      return files[name];
    },
    async () => Object.keys(files),
  );
  assert.deepEqual(found, { kind: "composite", sha: "main", directory: RENAMED_DIRECTORY });
  assert.deepEqual(reads, ["pr-require-checks.yml"]);
});

// ci-workflows `main` carries one composite path or the other across the
// rename; the copy check reads the renamed one when it exists.
function gateReader(directories) {
  return async (url) => {
    const directory = directories.find((candidate) => url.includes(`/${candidate}/`));
    if (directory === undefined) {
      return null;
    }
    return url.includes("/run.sh") ? `run.sh at ${directory}` : `action.yml at ${directory}`;
  };
}

test("the gate composite is read from the renamed path when it exists", async () => {
  assert.deepEqual(await readGateComposite(gateReader([RENAMED_DIRECTORY, LEGACY_DIRECTORY])), {
    gateRun: `run.sh at ${RENAMED_DIRECTORY}`,
    gateAction: `action.yml at ${RENAMED_DIRECTORY}`,
  });
});

test("the gate composite falls back to pr-contract before the rename", async () => {
  assert.deepEqual(await readGateComposite(gateReader([LEGACY_DIRECTORY])), {
    gateRun: `run.sh at ${LEGACY_DIRECTORY}`,
    gateAction: `action.yml at ${LEGACY_DIRECTORY}`,
  });
});

test("a gate composite missing at both paths is a fetch error", async () => {
  await assert.rejects(readGateComposite(gateReader([])), /fetch-error: .*pr-contract/);
});

// ---------------------------------------------------------------------------
// The fleet, mid-transition.
// ---------------------------------------------------------------------------

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
    assert.match(errors[0], new RegExp(`caller ${repo}: no pr-contract composite step`));
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

test("consumer roster covers all thirteen repositories", () => {
  assert.equal(CONSUMER_REPOSITORIES.length, 13);
  for (const repo of ["agent-plugins", "claude-code-proxy", "cursor-plugins"]) {
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
