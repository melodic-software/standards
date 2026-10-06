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

// Hermetic fixtures mirroring the narrowest parsed surface of each live copy.
// Written as arrays of plain strings so a backslash in an awk regex stays a
// backslash without template-literal escaping games.
const GOOD_COMPOSITE_RUN = [
  "analyze_body() {",
  "  awk '",
  // The live `negation_trigger`, verbatim but for its comments.
  "function negation_trigger(line, keyword_index,   preceding, cut, i, ch, tail, count, words, first, word, lower) {",
  "  preceding = substr(line, 1, keyword_index - 1)",
  "  cut = 0",
  "  for (i = length(preceding); i >= 1; i--) {",
  "    ch = substr(preceding, i, 1)",
  '    if (ch == "." || ch == "!" || ch == "?" || ch == ";" || ch == ",") {',
  "      cut = i",
  "      break",
  "    }",
  "  }",
  "  tail = substr(preceding, cut + 1)",
  `  gsub("\\342\\200\\231", "'"'"'", tail)`,
  "  count = 0",
  `  while (match(tail, /[A-Za-z][A-Za-z'"'"']*/)) {`,
  "    count++",
  "    words[count] = substr(tail, RSTART, RLENGTH)",
  "    tail = substr(tail, RSTART + RLENGTH)",
  "  }",
  "  first = (count > 5) ? count - 4 : 1",
  "  for (i = first; i <= count; i++) {",
  "    word = words[i]",
  "    lower = tolower(word)",
  '    if (lower == "not" && i < count && tolower(words[i + 1]) == "only") continue',
  '    if (lower == "not" || lower == "never" || lower == "no" || lower == "without" ||',
  '        lower == "deliberately" || lower == "intentionally") return word',
  `    if (tolower(substr(word, length(word) - 2)) == "n'"'"'t") return word`,
  "  }",
  '  return ""',
  "}",
  "",
  "function scan_line(line,   indent, rest, lower, offset, chunk) {",
  "  indent = 0",
  '  while (substr(line, indent + 1, 1) == " ") indent++',
  "  if (indent <= 3) {",
  "    rest = tolower(substr(line, indent + 1))",
  "    if (rest ~ /^(refs|relates[ \\t]+to):[ \\t]*([a-z0-9_.-]+\\/[a-z0-9_.-]+)?#[0-9]+[ \\t]*$/) {",
  "      has_non_closing = 1",
  "    }",
  "  }",
  "  lower = tolower(line)",
  "  offset = 0",
  "  while (1) {",
  "    chunk = substr(lower, offset + 1)",
  "    if (!match(chunk, /(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[ \\t]*:?[ \\t]*([a-z0-9_.-]+\\/[a-z0-9_.-]+)?#[0-9]+/)) break",
  "    offset = offset + RSTART + RLENGTH - 1",
  "    text = substr(line, start, len)",
  "    trigger = negation_trigger(line, start)",
  '    if (trigger != "") {',
  "      if (!(text in negated_trigger)) {",
  "        negated_count++",
  "        negated_order[negated_count] = text",
  "        negated_trigger[text] = trigger",
  "      }",
  "    } else {",
  "      has_closing = 1",
  "    }",
  "  }",
  "}",
  "END {",
  '  section_report("Summary")',
  '  section_report("Fix")',
  '  section_report("Verification")',
  '  section_report("Related")',
  "  for (i = 1; i <= line_count; i++) {",
  "    scan_line(masked[i])",
  "  }",
  "  for (i = 1; i <= negated_count; i++) {",
  '    print "negated\\t" negated_order[i] "\\t" negated_trigger[negated_order[i]]',
  "  }",
  '  if (has_closing) print "closing"',
  '  if (has_non_closing) print "non-closing"',
  '  if (tolower(body) ~ /(^|[^a-z0-9_])no (linked|related) issue([^a-z0-9_]|$)/) print "no-issue"',
  "}",
  "'",
  "}",
  // The live verdict lines that act on the analyzer's report, verbatim.
  "  while IFS=$'\\t' read -r kind text trigger; do",
  '    [[ "$kind" == negated ]] || continue',
  '    negated_quoted+="$text"',
  '  done <"$analysis"',
  '  if [[ -n "$negated_quoted" ]]; then',
  '    linkage_errors+=("Negated closing reference ($negated_quoted).")',
  "  fi",
  "  if ! grep -qx 'closing' \"$analysis\" &&",
  "    ! grep -qx 'non-closing' \"$analysis\" &&",
  "    ! grep -qx 'no-issue' \"$analysis\"; then",
  "    linkage_errors+=('Missing a native closing keyword.')",
  "  fi",
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
  "CLOSING_ERE='(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:blank:]]*:?[[:blank:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+'",
  "NON_CLOSING_ERE='^ {0,3}(refs|relates[[:blank:]]+to):[[:blank:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[[:blank:]]*$'",
  "NO_ISSUE_ERE='[^a-z0-9_]no (linked|related) issue[^a-z0-9_]'",
  // The live `negation_trigger_to`, verbatim.
  `_PLV_WORD_ERE="[A-Za-z][A-Za-z']*"`,
  "negation_trigger_to() {",
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '  local __plv_dest="$1" tail="${2##*[.!?;,]}" lower n first i',
  "  local -a words=()",
  `  printf -v "$__plv_dest" '%s' ""`,
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  "  tail=\"${tail//$'\\xe2\\x80\\x99'/\\'}\"",
  '  while [[ "$tail" =~ $_PLV_WORD_ERE ]]; do',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '    words+=("${BASH_REMATCH[0]}")',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '    tail="${tail#*"${BASH_REMATCH[0]}"}"',
  "  done",
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  "  n=${#words[@]}",
  "  first=0",
  "  ((n > 5)) && first=$((n - 5))",
  "  for ((i = first; i < n; i++)); do",
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '    lower="${words[i],,}"',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '    [[ "$lower" == not ]] && ((i + 1 < n)) && [[ "${words[i + 1],,}" == only ]] && continue',
  '    case "$lower" in',
  `    not | never | no | without | deliberately | intentionally | *"n't")`,
  `      printf -v "$__plv_dest" '%s' "\${words[i]}"`,
  "      return 0",
  "      ;;",
  "    *) ;;",
  "    esac",
  "  done",
  "}",
  // The live `scan_linkage` operand, call-site and verdict lines, verbatim.
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '    lower="${line,,}"',
  '    [[ "$lower" =~ $NON_CLOSING_ERE ]] && found=0',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '    while chunk="${lower:off}" && [[ "$chunk" =~ $CLOSING_ERE ]]; do',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  '      negation_trigger_to _plv_trigger "${line:0:start}"',
  '      if [[ -z "$_plv_trigger" ]]; then',
  "        found=0",
  "        continue",
  "      fi",
  '      LINKAGE_NEGATED+=("$text")',
  "    done",
  "  ((found == 0)) && return 0",
  `  lower=$'\\n'"\${1,,}"$'\\n'`,
  '  [[ "$lower" =~ $NO_ISSUE_ERE ]]',
  '  scan_linkage "$_plv_body" || _plv_linked=1',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash array length, not a JS placeholder
  "  ((${#LINKAGE_NEGATED[@]} == 0)) || {",
  '    LINKAGE_PROBLEMS+=("Negated closing reference ($_plv_negated).")',
  "  }",
  "REQUIRED_SECTIONS=(Summary Fix Verification Related)",
  "",
].join("\n");
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

test("validator CLOSING_ERE is read from its own declaration, not NON_CLOSING_ERE", () => {
  const [closing, nonClosing, ...rest] = GOOD_VALIDATOR.split("\n");
  const swapped = [nonClosing, closing, ...rest].join("\n");
  assert.match(parseValidatorPatterns(swapped, "validator").keyword.source, /^\(close/);
  assert.throws(() => parseValidatorPatterns([nonClosing, ...rest].join("\n"), "v"), DriftError);
});

test("validator that matches its EREs against un-lowercased text is drift", () => {
  const mutations = [
    // The per-line lowercasing feeds both line-scoped patterns.
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    ['lower="${line,,}"', 'lower="$line"', ["CLOSING_ERE", "NON_CLOSING_ERE"]],
    ['"$chunk" =~ $CLOSING_ERE', '"$line" =~ $CLOSING_ERE', ["CLOSING_ERE"]],
    ['"$lower" =~ $NO_ISSUE_ERE', '"$1" =~ $NO_ISSUE_ERE', ["NO_ISSUE_ERE"]],
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
    ["${1,,}", "$1", ["NO_ISSUE_ERE"]],
    ['"$lower" =~ $NON_CLOSING_ERE', '"$line" =~ $NON_CLOSING_ERE', ["NON_CLOSING_ERE"]],
  ];
  for (const [from, to, names] of mutations) {
    const texts = goodTexts();
    texts.hookValidator = texts.hookValidator.replace(from, to);
    assert.notEqual(texts.hookValidator, GOOD_VALIDATOR, from);
    const errors = checkCopies(POLICY, texts);
    assert.equal(errors.length, names.length, from);
    names.forEach((name, index) => {
      assert.match(
        errors[index],
        new RegExp(`^hook validator( \\([a-z -]+\\))?: .*no longer matches ${name} `),
        from,
      );
    });
  }
  // An extra raw-line match alongside the lowercased one is drift too.
  const texts = goodTexts();
  texts.hookValidator += '[[ "$line" =~ $CLOSING_ERE ]]\n';
  assert.equal(checkCopies(POLICY, texts).length, 1);
});

test("stale reusable pin with current sections but stale keyword enforcement is drift", () => {
  const staleKeywords = GOOD_GATE.replace("|resolve[sd]?", "");
  const errors = checkPinnedReusable(POLICY, "dotfiles", "b".repeat(40), staleKeywords);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /rejects closing keyword "Resolves"/);
});

// ---------------------------------------------------------------------------
// Non-closing references and negated closers (#647).
// ---------------------------------------------------------------------------

test("non-closing and negation parsers read the policy's values from both copies", () => {
  const expectedMarkers = POLICY.body.nonClosingMarkers.map((marker) => marker.toLowerCase());
  assert.deepEqual(parseValidatorNonClosing(GOOD_VALIDATOR, "hook").markers, expectedMarkers);
  assert.deepEqual(parseCompositeNonClosing(GOOD_COMPOSITE_RUN, "gate").markers, expectedMarkers);
  assert.deepEqual(parseValidatorNegation(GOOD_VALIDATOR, "hook"), POLICY.body.negatedClosers);
  assert.deepEqual(parseCompositeNegation(GOOD_COMPOSITE_RUN, "gate"), POLICY.body.negatedClosers);
});

const nonClosingErrors = (texts, copy) =>
  checkCopies(POLICY, texts).filter((e) => e.startsWith(`${copy} (non-closing markers)`));

test("a hook NON_CLOSING_ERE that drops a policy marker is drift", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator.replace("(refs|relates[[:blank:]]+to):", "(refs):");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.length, 1, errors.join("; "));
  assert.match(errors[0], /^hook validator \(non-closing markers\): .*missing relates to/);
  assert.match(errors[0], /rejects "Relates to: #12"/);
});

test("a hook NON_CLOSING_ERE that accepts a marker policy does not name is drift", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator.replace("(refs|relates", "(refs|see|relates");
  const errors = nonClosingErrors(texts, "hook validator");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /unexpected see/);
});

test("a hook NON_CLOSING_ERE that stops requiring its own line is drift", () => {
  const unanchoredEnd = goodTexts();
  unanchoredEnd.hookValidator = unanchoredEnd.hookValidator.replace(
    "#[0-9]+[[:blank:]]*$'",
    "#[0-9]+'",
  );
  const [endError] = nonClosingErrors(unanchoredEnd, "hook validator");
  assert.match(endError, /accepts "Refs: #12 and more"/);

  const unanchoredStart = goodTexts();
  unanchoredStart.hookValidator = unanchoredStart.hookValidator.replace(
    "NON_CLOSING_ERE='^ {0,3}(",
    "NON_CLOSING_ERE='(",
  );
  const [startError] = nonClosingErrors(unanchoredStart, "hook validator");
  assert.match(startError, /does not open with an anchored/);
});

test("a hook with no NON_CLOSING_ERE declaration is drift, not a pass", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator.replace(/^NON_CLOSING_ERE=.*\n/m, "");
  const errors = nonClosingErrors(texts, "hook validator");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /NON_CLOSING_ERE declaration not found/);
});

test("a policy marker no copy implements is drift in both copies", () => {
  const policy = structuredClone(POLICY);
  policy.body.nonClosingMarkers.push("Part of");
  const errors = checkCopies(policy, goodTexts());
  assert.equal(errors.length, 2, errors.join("; "));
  assert.match(errors[0], /^gate composite \(non-closing markers\): .*missing part of/);
  assert.match(errors[1], /^hook validator \(non-closing markers\): .*missing part of/);
});

test("composite non-closing drift is reported, including a lost lowercasing", () => {
  const dropped = goodTexts();
  dropped.gateRun = dropped.gateRun.replace("(refs|relates[ \\t]+to):", "(refs):");
  const [droppedError] = nonClosingErrors(dropped, "gate composite");
  assert.match(droppedError, /missing relates to/);

  const raw = goodTexts();
  raw.gateRun = raw.gateRun.replace(
    "rest = tolower(substr(line, indent + 1))",
    "rest = substr(line, indent + 1)",
  );
  const [rawError] = nonClosingErrors(raw, "gate composite");
  assert.match(rawError, /lowercased, indent-stripped line/);
});

test("hook negated-closer drift is reported field by field", () => {
  const texts = goodTexts();
  texts.hookValidator = texts.hookValidator
    .replace(" | intentionally", "")
    .replace(' | *"n\'t"', "")
    .replace("((n > 5)) && first=$((n - 5))", "((n > 3)) && first=$((n - 3))");
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.length, 1, errors.join("; "));
  assert.match(errors[0], /^hook validator \(negated closers\): /);
  assert.match(errors[0], /triggerWords missing intentionally/);
  assert.match(errors[0], /triggerSuffixes missing n't/);
  assert.match(errors[0], /wordWindow is 3, policy says 5/);
});

test("composite negated-closer drift is reported, and an off-by-one window is caught", () => {
  const extraWord = goodTexts();
  extraWord.gateRun = extraWord.gateRun.replace(
    'lower == "without" ||',
    'lower == "without" || lower == "maybe" ||',
  );
  const extraErrors = checkCopies(POLICY, extraWord);
  assert.equal(extraErrors.length, 1, extraErrors.join("; "));
  assert.match(extraErrors[0], /^gate composite \(negated closers\): .*unexpected maybe/);

  const skewed = goodTexts();
  skewed.gateRun = skewed.gateRun.replace("count - 4 : 1", "count - 5 : 1");
  const [skewedError] = checkCopies(POLICY, skewed);
  assert.match(skewedError, /window is inconsistent/);

  const noException = goodTexts();
  noException.gateRun = noException.gateRun.replace(/^.*== "only"\) continue\n/m, "");
  const [exceptionError] = checkCopies(POLICY, noException);
  assert.match(exceptionError, /"not only" exception/);
});

// A helper or pattern whose body matches policy is dead code unless the copy
// calls it and acts on what it returns; each mutation below leaves every
// declaration intact and breaks one link between the call site and the verdict.
test("a negation helper that is never called, or whose result is ignored, is drift", () => {
  const cases = [
    [
      "gateRun",
      "gate composite (negated closers)",
      "    trigger = negation_trigger(line, start)\n",
      '    trigger = ""\n',
      /negation_trigger is called/,
    ],
    [
      "gateRun",
      "gate composite (negated closers)",
      '    if (trigger != "") {',
      "    if (0) {",
      /negation_trigger is called/,
    ],
    [
      "gateRun",
      "gate composite (negated closers)",
      '    [[ "$kind" == negated ]] || continue',
      "    continue",
      /a negated report is a linkage error/,
    ],
    [
      "hookValidator",
      "hook validator (negated closers)",
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '      negation_trigger_to _plv_trigger "${line:0:start}"\n',
      "",
      /negation_trigger_to is called/,
    ],
    [
      "hookValidator",
      "hook validator (negated closers)",
      '      if [[ -z "$_plv_trigger" ]]; then',
      "      if true; then",
      /only an empty result counts/,
    ],
    [
      "hookValidator",
      "hook validator (negated closers)",
      '    LINKAGE_PROBLEMS+=("Negated closing reference',
      '    : ("Negated closing reference',
      /a recorded negated reference is a linkage problem/,
    ],
  ];
  for (const [copy, location, from, to, message] of cases) {
    const texts = goodTexts();
    texts[copy] = texts[copy].replace(from, to);
    assert.notEqual(texts[copy], goodTexts()[copy], from);
    const errors = checkCopies(POLICY, texts);
    assert.equal(errors.length, 1, `${from}: ${errors.join("; ")}`);
    assert.ok(errors[0].startsWith(`${location}: the rule is not wired in`), errors[0]);
    assert.match(errors[0], message, from);
  }
});

// The helpers' trigger lists can match policy while their input is gone: a
// negation_trigger that never fills words/count returns "" for every closer.
test("a negation helper that stops building its word list is drift", () => {
  const cases = [
    [
      "gateRun",
      "gate composite (negated closers)",
      "    words[count] = substr(tail, RSTART, RLENGTH)\n",
      "",
      /splits the clause into words/,
    ],
    [
      "gateRun",
      "gate composite (negated closers)",
      "  preceding = substr(line, 1, keyword_index - 1)",
      '  preceding = ""',
      /slices the line before the keyword/,
    ],
    [
      "gateRun",
      "gate composite (negated closers)",
      "  tail = substr(preceding, cut + 1)",
      "  tail = preceding",
      /cuts the slice at the previous/,
    ],
    [
      "gateRun",
      "gate composite (negated closers)",
      "    word = words[i]",
      '    word = ""',
      /tests each windowed word/,
    ],
    [
      "hookValidator",
      "hook validator (negated closers)",
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      'tail="${2##*[.!?;,]}"',
      'tail="$2"',
      /cuts its input at the previous/,
    ],
    [
      "hookValidator",
      "hook validator (negated closers)",
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '    words+=("${BASH_REMATCH[0]}")\n',
      "",
      /splits the clause into words/,
    ],
    [
      "hookValidator",
      "hook validator (negated closers)",
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      "  n=${#words[@]}",
      "  n=0",
      /splits the clause into words and counts them/,
    ],
  ];
  for (const [copy, location, from, to, message] of cases) {
    const texts = goodTexts();
    texts[copy] = texts[copy].replace(from, to);
    assert.notEqual(texts[copy], goodTexts()[copy], from);
    const errors = checkCopies(POLICY, texts);
    assert.equal(errors.length, 1, `${from}: ${errors.join("; ")}`);
    assert.ok(errors[0].startsWith(`${location}: the rule is not wired in`), errors[0]);
    assert.match(errors[0], message, from);
  }
});

test("a non-closing match that never reaches the linkage verdict is drift", () => {
  const cases = [
    [
      "gateRun",
      "gate composite (non-closing markers)",
      '  if (has_non_closing) print "non-closing"\n',
      "",
      /has_non_closing is reported/,
    ],
    [
      "gateRun",
      "gate composite (non-closing markers)",
      "    ! grep -qx 'non-closing' \"$analysis\" &&\n",
      "",
      /a non-closing report satisfies linkage/,
    ],
    [
      "hookValidator",
      "hook validator (non-closing markers)",
      '[[ "$lower" =~ $NON_CLOSING_ERE ]] && found=0',
      '[[ "$lower" =~ $NON_CLOSING_ERE ]] && :',
      /a marker match counts as linkage/,
    ],
  ];
  for (const [copy, location, from, to, message] of cases) {
    const texts = goodTexts();
    texts[copy] = texts[copy].replace(from, to);
    assert.notEqual(texts[copy], goodTexts()[copy], from);
    const errors = checkCopies(POLICY, texts).filter((e) => e.startsWith(location));
    assert.equal(errors.length, 1, `${from}: ${errors.join("; ")}`);
    assert.match(errors[0], /the rule is not wired in/);
    assert.match(errors[0], message, from);
  }
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
  assert.equal(errors.length, 2, errors.join("; "));
  assert.match(errors[0], /caller medley pin fffffff: non-closing pattern .*missing relates to/);
  assert.match(errors[1], /caller medley pin fffffff: negated-closer rule .*missing deliberately/);
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
