import assert from "node:assert/strict";
import test from "node:test";

import { checkCopies, checkPinnedComposite } from "./lockstep-drift.mjs";
import {
  assertOnlyBehavior,
  BOUNDED_SCAN_COMPOSITE_RUN,
  BOUNDED_SCAN_VALIDATOR,
  GOOD_COMPOSITE_ACTION,
  GOOD_COMPOSITE_RUN,
  goodTexts,
  LITERAL_REF_COMPOSITE_RUN,
  mutate,
  POLICY,
  SINGLE_LOOP_COMPOSITE_RUN,
} from "./lockstep-fixtures.mjs";

const checkConsumerPin = (runSh) =>
  checkPinnedComposite(POLICY, "ci-runner", "d".repeat(40), runSh, GOOD_COMPOSITE_ACTION);

test("a composite at a consumer pin passes when it matches policy", () => {
  assert.deepEqual(checkConsumerPin(GOOD_COMPOSITE_RUN), []);
});

test("a composite pin that still inlines the #N reference passes", () => {
  assert.deepEqual(checkConsumerPin(LITERAL_REF_COMPOSITE_RUN), []);
});

test("a composite pin with the bounded negation scan passes", () => {
  assert.deepEqual(checkConsumerPin(BOUNDED_SCAN_COMPOSITE_RUN), []);
  assert.deepEqual(
    checkCopies(POLICY, { ...goodTexts(), gateRun: BOUNDED_SCAN_COMPOSITE_RUN }),
    [],
  );
});

test("a composite with one report loop and a case per kind passes", () => {
  assert.deepEqual(checkCopies(POLICY, { ...goodTexts(), gateRun: SINGLE_LOOP_COMPOSITE_RUN }), []);
});

test("a single-loop composite that stops acting on the report is drift", () => {
  for (const [from, to, expected] of [
    [
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      '      negated) negated_quoted+="${negated_quoted:+, }',
      '      negated) : "',
      /a `negated` report is a linkage error/,
    ],
    [
      '    esac\n  done <"$analysis"',
      "    esac\n  done </dev/null",
      /a missing or empty section report/,
    ],
    [
      // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
      'section-empty) linkage_errors+=("The \\"## ${text}\\" section is empty.") ;;',
      "section-empty) : ;;",
      /a missing or empty section report/,
    ],
    [
      "grep -qxE 'closing|non-closing|no-issue'",
      "grep -qxE 'closing|no-issue'",
      /a `non-closing` report satisfies linkage/,
    ],
    ["jq -r .body <", "jq -r .title <", /the PR body is written to the analyzer's input/],
  ]) {
    const mutated = SINGLE_LOOP_COMPOSITE_RUN.replace(from, to);
    assert.notEqual(mutated, SINGLE_LOOP_COMPOSITE_RUN, `mutation did not apply: ${from}`);
    const errors = checkCopies(POLICY, { ...goodTexts(), gateRun: mutated });
    assert.ok(
      errors.some((e) => e.startsWith("gate composite (verdict): ") && expected.test(e)),
      `${from}: ${errors.join("; ")}`,
    );
  }
});

test("a hook validator with the bounded negation scan passes", () => {
  assert.deepEqual(
    checkCopies(POLICY, { ...goodTexts(), hookValidator: BOUNDED_SCAN_VALIDATOR }),
    [],
  );
});

// Each static anchor of the ci-workflows#815 shape, mutated away, is drift.
test("a bounded-scan composite that drifts from its static anchors is drift", () => {
  for (const [from, to, expected] of [
    [
      "++seen == 5) break",
      "++seen == 4) break",
      /negated-closer rule wordWindow is 4, policy says 5/,
    ],
    ['ch == ";" || ch == ",") break', 'ch == ";") break', /^gate composite \(behavior\): /],
    [
      "tail = substr(line, start, keyword_index - start)",
      "tail = substr(line, 1, keyword_index - 1)",
      /negation_trigger's window/,
    ],
    [
      'gsub(closing_regex, "\\n&\\n", marked)',
      'gsub(non_closing_regex, "\\n&\\n", marked)',
      /match expressions not found/,
    ],
    ["marked = lower\n", "marked = line\n", /match expressions not found/],
  ]) {
    const mutated = BOUNDED_SCAN_COMPOSITE_RUN.replace(from, to);
    assert.notEqual(mutated, BOUNDED_SCAN_COMPOSITE_RUN, `mutation did not apply: ${from}`);
    const errors = checkCopies(POLICY, { ...goodTexts(), gateRun: mutated });
    assert.ok(
      errors.some((e) => e.startsWith("gate composite") && expected.test(e)),
      `${from}: ${errors.join("; ")}`,
    );
  }
});

// From ci-workflows#733 the analyzer reads its reference grammar from the
// environment, so each link from run.sh's default to the analyzer is checked.
test("an issue-ref-pattern composite that loses its default is drift", () => {
  for (const [from, to] of [
    [/^DEFAULT_ISSUE_REF_PATTERN=.*$/m, "DEFAULT_ISSUE_REF_PATTERN="],
    ["export ISSUE_REF_PATTERN DEFAULT_ISSUE_REF_PATTERN", "export DEFAULT_ISSUE_REF_PATTERN"],
  ]) {
    const errors = mutate("gateRun", from, to);
    assert.deepEqual(errors, [
      "gate composite: run.sh reads ISSUE_REF_PATTERN but does not declare and export DEFAULT_ISSUE_REF_PATTERN as its fallback",
    ]);
    // Three checks read the default; a consumer pin reports the finding once.
    const pinned = checkConsumerPin(GOOD_COMPOSITE_RUN.replace(from, to));
    assert.equal(pinned.length, 1, pinned.join("; "));
    assert.match(pinned[0], /^caller ci-runner pin ddddddd: .*DEFAULT_ISSUE_REF_PATTERN/);
  }
});

test("an issue-ref-pattern default that drops the #N grammar is drift", () => {
  const errors = mutate(
    "gateRun",
    "DEFAULT_ISSUE_REF_PATTERN='([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+'",
    "DEFAULT_ISSUE_REF_PATTERN='[a-z]+-[0-9]+'",
  );
  assert.ok(
    errors.some((e) => e.startsWith("gate composite (enforcement patterns): ")),
    errors.join("; "),
  );
  assert.ok(
    errors.some((e) => e.startsWith("gate composite (behavior): ")),
    errors.join("; "),
  );
});

test("the default closing scan losing its optional colon is drift", () => {
  const errors = mutate("gateRun", ': "[ \\t]*:?[ \\t]*"', ': "[ \\t]+"');
  assertOnlyBehavior(errors, "gateRun", /should be closing, got no linkage/);
});

test("an action.yml issue-ref-pattern default that differs from run.sh is drift", () => {
  const texts = goodTexts();
  texts.gateAction = texts.gateAction.replace(
    "default: '([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+'",
    "default: '#[0-9]+'",
  );
  const errors = checkCopies(POLICY, texts);
  assert.equal(errors.length, 1, errors.join("; "));
  assert.match(errors[0], /^gate composite: action\.yml's .*differs from run\.sh/);
});

test("a composite pin predating the security type is drift at that pin", () => {
  const errors = checkPinnedComposite(
    POLICY,
    "ci-runner",
    "e".repeat(40),
    GOOD_COMPOSITE_RUN,
    GOOD_COMPOSITE_ACTION.replace(",security", ""),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /caller ci-runner pin eeeeeee/);
  assert.match(errors[0], /missing security/);
});
