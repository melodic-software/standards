import assert from "node:assert/strict";
import test from "node:test";

import { checkCompositeBehavior, checkHookBehavior, linkageMatrix } from "./lockstep-behavior.mjs";
import {
  checkPinnedComposite,
  DriftError,
  parseCallerPin,
  parseCompositeNegation,
  parseCompositeNonClosing,
  parseCompositeSections,
  parseCompositeTypes,
  parseGateSections,
  parseValidatorNegation,
  parseValidatorSections,
} from "./lockstep-drift.mjs";
import {
  GOOD_COMPOSITE_ACTION,
  GOOD_COMPOSITE_RUN,
  LOCATION,
  mutate,
  POLICY,
} from "./lockstep-fixtures.mjs";

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

test("a run.sh that stops feeding the PR body through analyze_body is drift", () => {
  const invocation = '  analyze_body <"$scratch/body.txt" >"$analysis"\n';
  const cases = [
    [invocation, "  printf 'closing\\n' >\"$analysis\"\n", /analyze_body writes the report/],
    [invocation, '  analyze_body </dev/null >"$analysis"\n', /analyze_body writes the report/],
    [
      invocation,
      `${invocation}  printf 'closing\\n' >>"$analysis"\n`,
      /nothing else writes the report/,
    ],
    [
      `jq -r '.body // ""' <"$pr_json" >"$scratch/body.txt"`,
      `printf '' >"$scratch/body.txt"`,
      /the PR body is written to the analyzer's input/,
    ],
  ];
  for (const [from, to, expected] of cases) {
    const errors = mutate("gateRun", from, to);
    assert.equal(errors.length, 1, errors.join("; "));
    assert.match(errors[0], /^gate composite \(verdict\): /);
    assert.match(errors[0], expected);
  }
});

test("a run.sh whose report consumers stop reading the report or raising errors is drift", () => {
  const cases = [
    [
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '    negated_quoted+="\\"${text}\\" (trigger \\"${trigger}\\")"\n  done <"$analysis"',
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '    negated_quoted+="\\"${text}\\" (trigger \\"${trigger}\\")"\n  done </dev/null',
      /a `negated` report is a linkage error/,
    ],
    [
      '    *) ;;\n    esac\n  done <"$analysis"',
      "    *) ;;\n    esac\n  done </dev/null",
      /a missing or empty section report/,
    ],
    [
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '      linkage_errors+=("The \\"## ${name}\\" section is empty.")\n',
      "      :\n",
      /a missing or empty section report/,
    ],
    [
      "    ! grep -qx 'no-issue' \"$analysis\"; then\n    linkage_errors+=(",
      "    ! grep -qx 'no-issue' \"$analysis\"; then\n    : linkage_errors+=(",
      /a `non-closing` report satisfies linkage/,
    ],
    ["    linkage_result=fail\n", "    linkage_result=pass\n", /a linkage error fails the check/],
  ];
  for (const [from, to, expected] of cases) {
    const errors = mutate("gateRun", from, to);
    assert.equal(errors.length, 1, errors.join("; "));
    assert.match(errors[0], /^gate composite \(verdict\): /);
    assert.match(errors[0], expected);
  }
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
  assert.throws(() => parseCompositeTypes("name: Check Contract\n", "composite"), DriftError);
  assert.throws(() => parseGateSections("jobs: {}", "gate"), DriftError);
  assert.throws(() => parseValidatorSections("echo hi", "validator"), DriftError);
  assert.throws(() => parseCallerPin("uses: something-else", "caller"), DriftError);
  assert.throws(() => parseCompositeNonClosing("#!/usr/bin/env bash\n", "composite"), DriftError);
  assert.throws(() => parseCompositeNegation("#!/usr/bin/env bash\n", "composite"), DriftError);
  assert.throws(() => parseValidatorNegation("echo hi", "validator"), DriftError);
});
