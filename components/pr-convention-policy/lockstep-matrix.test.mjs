import assert from "node:assert/strict";
import test from "node:test";

import {
  CLAUSE_DELIMITERS,
  GITHUB_CLOSING_KEYWORDS,
  linkageMatrix,
  MASKINGS,
  NON_DELIMITERS,
  UNTERMINATED_MASKINGS,
} from "./lockstep-behavior.mjs";
import { checkCopies } from "./lockstep-drift.mjs";
import { assertOnlyBehavior, goodTexts, mutate, POLICY } from "./lockstep-fixtures.mjs";

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
