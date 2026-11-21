import assert from "node:assert/strict";
import test from "node:test";

import { CLAUSE_DELIMITERS, linkageMatrix } from "./lockstep-behavior.mjs";
import {
  checkCopies,
  parseCompositeNegation,
  parseCompositeNonClosing,
  parseValidatorNegation,
  parseValidatorNonClosing,
} from "./lockstep-drift.mjs";
import {
  assertOnlyBehavior,
  BOUNDED_SCAN_COMPOSITE_RUN,
  BOUNDED_SCAN_VALIDATOR,
  GOOD_COMPOSITE_RUN,
  GOOD_VALIDATOR,
  goodTexts,
  mutate,
  negationData,
  POLICY,
} from "./lockstep-fixtures.mjs";

// Non-closing references and negated closers (#647). Static extractors diff
// the declared data; the behavioral layer runs the vendored copies on a
// policy-generated matrix, so every mutation below that breaks behavior must
// surface as a `(behavior)` finding whatever source shape it takes.

test("non-closing and negation parsers read the policy's values from both copies", () => {
  const expectedMarkers = POLICY.body.nonClosingMarkers.map((marker) => marker.toLowerCase());
  assert.deepEqual(parseValidatorNonClosing(GOOD_VALIDATOR, "hook").markers, expectedMarkers);
  assert.deepEqual(parseCompositeNonClosing(GOOD_COMPOSITE_RUN, "gate").markers, expectedMarkers);
  const expectedNegation = negationData(POLICY.body.negatedClosers);
  assert.deepEqual(parseValidatorNegation(GOOD_VALIDATOR, "hook"), expectedNegation);
  assert.deepEqual(parseValidatorNegation(BOUNDED_SCAN_VALIDATOR, "hook"), expectedNegation);
  assert.deepEqual(parseCompositeNegation(GOOD_COMPOSITE_RUN, "gate"), expectedNegation);
  assert.deepEqual(parseCompositeNegation(BOUNDED_SCAN_COMPOSITE_RUN, "gate"), expectedNegation);
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
