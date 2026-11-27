import assert from "node:assert/strict";
import test from "node:test";

import {
  checkCopies,
  checkPinnedReusable,
  DriftError,
  parseValidatorPatterns,
} from "./lockstep-drift.mjs";
import { GOOD_GATE, GOOD_VALIDATOR, goodTexts, POLICY } from "./lockstep-fixtures.mjs";

test("stale reusable pin enforcing an older contract is reported", () => {
  const oldReusable = `
            const requiredSections = [
              { name: "Related", guidance: "r" },
            ];
`;
  // Two findings: the stale section list AND the missing enforcement-pattern
  // declarations (pre-pattern-era reusables lack the const declarations).
  const errors = checkPinnedReusable(POLICY, "ci-runner", "c".repeat(40), oldReusable);
  assert.equal(errors.length, 2);
  assert.match(errors[0], /caller ci-runner/);
  assert.match(errors[1], /caller ci-runner/);
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
