import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

import { DriftError } from "./lockstep-drift.mjs";

export class BehaviorToolError extends Error {
  constructor(message) {
    super(message);
    this.name = "BehaviorToolError";
  }
}

const SANDBOX_ENV = { PATH: "/usr/bin:/bin" };
const TIMEOUT_MS = 10_000;
export const CLAUSE_DELIMITERS = [".", "!", "?", ";", ","];
export const NON_DELIMITERS = [":", "-", "(", ")", '"', "/", "[", "]", "*", "&"];
export const SUFFIX_HOSTS = ["wo", "ca", "is", "should"];
export const MASKINGS = [
  ["an HTML comment", (text) => `<!-- ${text} -->`],
  ["a multi-line HTML comment", (text) => `<!--\n${text}\n-->`],
  ["a backtick fence", (text) => `\`\`\`\n${text}\n\`\`\``],
  ["a tilde fence with an info string", (text) => `~~~text\n${text}\n~~~`],
  ["an indented code block", (text) => `    ${text}`],
  ["a tab-indented code block", (text) => `\t${text}`],
  ["inline code", (text) => `See \`${text}\` here`],
  ["inline code of two backticks", (text) => `\`\`${text}\`\``],
];
export const UNTERMINATED_MASKINGS = [
  ["an unclosed HTML comment", (text) => `<!--\n${text}`],
  ["an unclosed backtick fence", (text) => `\`\`\`\n${text}`],
  ["an unclosed tilde fence", (text) => `~~~\n${text}`],
];
// GitHub's closing keywords, every inflection both copies accept.
// https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue
export const GITHUB_CLOSING_KEYWORDS = [
  "close",
  "closes",
  "closed",
  "fix",
  "fixes",
  "fixed",
  "resolve",
  "resolves",
  "resolved",
];
const FILLERS = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india"];

function fillers(count) {
  return Array.from({ length: count }, (_, index) => {
    if (index < FILLERS.length) {
      return FILLERS[index];
    }
    let suffix = "";
    for (let rest = index - FILLERS.length; ; rest = Math.floor(rest / 26) - 1) {
      suffix = String.fromCharCode(97 + (rest % 26)) + suffix;
      if (rest < 26) {
        break;
      }
    }
    return `filler${suffix}`;
  });
}

const capitalize = (word) => `${word[0].toUpperCase()}${word.slice(1)}`;
const capitalizeWords = (phrase) => phrase.split(" ").map(capitalize).join(" ");

export function sectionsTail(requiredSections) {
  const sections = requiredSections.map(
    (section) => `\n\n## ${section}\n${section[0].toLowerCase()}`,
  );
  return `${sections.join("")}\n`;
}

export function linkageMatrix(policy) {
  const { requiredSections, closingKeywords, nonClosingMarkers, noIssueMarkers, negatedClosers } =
    policy.body;
  const none = { closing: false, nonClosing: false, noIssue: false, negated: null };
  const cases = [];
  const add = (line, expect) => cases.push({ line, expect: { ...none, ...expect } });

  for (const keyword of closingKeywords) {
    const lower = keyword.toLowerCase();
    add(`${keyword} #12`, { closing: true });
    add(`${keyword} owner/repo#12`, { closing: true });
    add(`${keyword.toUpperCase()} #12`, { closing: true });
    add(`${keyword}: #12`, { closing: true });
    add(`${keyword}#12`, { closing: true });
    add(`${keyword}\t#12`, { closing: true });
    add(`${keyword} #12\r`, { closing: true });
    add(`- ${keyword} #12`, { closing: true });
    add(`> ${keyword} #12`, { closing: true });
    add(`x${lower} #12`, {});
    add(`${keyword} #12x`, {});
    add(`${keyword} https://github.com/owner/repo/issues/12`, {});
  }
  for (const marker of nonClosingMarkers) {
    add(`${marker}: #12`, { nonClosing: true });
    add(`   ${marker}: owner/repo#12`, { nonClosing: true });
    add(`See ${marker}: #12 for context`, {});
    add(`${marker}: #12 and more`, {});
    add(`${marker.toUpperCase()}: #12`, { nonClosing: true });
    add(`${marker}:#12`, { nonClosing: true });
    add(`${marker}: #12 \t`, { nonClosing: true });
    add(`${marker}: #12\r`, { nonClosing: true });
    add(`${marker} #12`, {});
    add(`- ${marker}: #12`, {});
    add(`> ${marker}: #12`, {});
    if (marker.includes(" ")) {
      add(`${marker.replaceAll(" ", " \t")}: #12`, { nonClosing: true });
    }
  }
  for (const marker of noIssueMarkers) {
    add(`${marker}: housekeeping`, { noIssue: true });
    add(`${marker.toUpperCase()}: housekeeping`, { noIssue: true });
    add(`There is ${marker.toLowerCase()} here`, { noIssue: true });
    add(`${marker}s here`, {});
  }

  const { wordWindow, affirmativePhrases } = negatedClosers;
  const triggers = [
    ...negatedClosers.triggerWords,
    ...negatedClosers.triggerSuffixes.map((suffix) => `does${suffix}`),
  ];
  const [firstTrigger] = negatedClosers.triggerWords;
  const negatedCloser = (closer) => `This does ${firstTrigger} ${closer.toLowerCase()} #12`;
  const linkageLines = (closer) => [
    { text: `${closer} #11`, expect: { closing: true } },
    ...nonClosingMarkers.map((marker) => ({
      text: `${marker}: #13`,
      expect: { nonClosing: true },
    })),
    ...noIssueMarkers.map((marker) => ({
      text: `${marker}: housekeeping`,
      expect: { noIssue: true },
    })),
  ];
  const inside = fillers(wordWindow - 1).join(" ");
  const outside = fillers(wordWindow).join(" ");
  for (const closer of closingKeywords) {
    const lower = closer.toLowerCase();
    for (const trigger of triggers) {
      add(`${trigger} ${inside} ${closer} #12`.replace("  ", " "), { negated: trigger });
      add(`${trigger} ${outside} ${closer} #12`, { closing: true });
      for (const cased of [trigger.toUpperCase(), capitalize(trigger)]) {
        add(`This ${cased} ${lower} #12`, { negated: cased });
      }
      if (trigger.includes("'")) {
        for (const written of [trigger, trigger.toUpperCase()]) {
          add(`This ${written.replaceAll("'", "’")} ${lower} #12`, { negated: written });
        }
      }
    }
    for (const suffix of negatedClosers.triggerSuffixes) {
      for (const host of SUFFIX_HOSTS) {
        const word = `${host}${suffix}`;
        for (const cased of [word, word.toUpperCase(), capitalize(word)]) {
          add(`This ${cased} ${lower} #12`, { negated: cased });
          if (cased.includes("'")) {
            add(`This ${cased.replaceAll("'", "’")} ${lower} #12`, { negated: cased });
          }
        }
      }
    }
    add(`This ${firstTrigger}e ${lower} #12`, { closing: true });
    add(`This can${firstTrigger} ${lower} #12`, { closing: true });
    add(`${firstTrigger} ${outside.replace(" ", "-")} ${closer} #12`, { closing: true });
    const references = Array.from({ length: wordWindow }, (_, index) => `#${index + 1}`);
    add(`${firstTrigger} ${references.join(" ")} ${closer} #12`, { negated: firstTrigger });
    add(`${firstTrigger}\n${closer} #12`, { closing: true });
    for (const delimiter of CLAUSE_DELIMITERS) {
      add(`It is ${firstTrigger}${delimiter} ${closer} #12`, { closing: true });
    }
    for (const mark of NON_DELIMITERS) {
      add(`It is ${firstTrigger}${mark} ${closer} #12`, { negated: firstTrigger });
    }
    for (const phrase of affirmativePhrases) {
      for (const cased of [phrase, phrase.toUpperCase(), capitalizeWords(phrase)]) {
        add(`This ${cased} ${lower} #12`, { closing: true });
      }
    }
    for (const { text, expect } of linkageLines(closer)) {
      add(`${text}\n${negatedCloser(closer)}`, { ...expect, negated: firstTrigger });
      add(`${negatedCloser(closer)}\n${text}`, { ...expect, negated: firstTrigger });
    }
    const bothWays = { closing: true, negated: firstTrigger };
    add(`${closer} #11 but does ${firstTrigger} ${lower} #12`, bothWays);
    add(`${negatedCloser(closer)}; ${closer} #11`, bothWays);
  }
  for (const marker of noIssueMarkers) {
    const closer = closingKeywords[0];
    const negatedOnly = { noIssue: true, negated: firstTrigger };
    add(`${marker}; ${negatedCloser(closer).toLowerCase()}`, negatedOnly);
    add(`${negatedCloser(closer)}; ${marker.toLowerCase()}`, negatedOnly);
  }
  const linkage = linkageLines(closingKeywords[0]);
  for (const first of linkage) {
    for (const second of linkage) {
      if (first !== second) {
        add(`${first.text}\n${second.text}`, { ...first.expect, ...second.expect });
      }
    }
  }

  const spelled = closingKeywords.map((keyword) => keyword.toLowerCase());
  for (const form of GITHUB_CLOSING_KEYWORDS) {
    if (!spelled.includes(form)) {
      add(`${capitalize(form)} #12`, { closing: true });
      add(`${form.toUpperCase()} #12`, { closing: true });
    }
    add(`This does ${firstTrigger} ${form} #12`, { negated: firstTrigger });
  }

  const maskedLines = [
    `${closingKeywords[0]} #12`,
    ...nonClosingMarkers.map((marker) => `${marker}: #12`),
    ...closingKeywords.map(negatedCloser),
    `${noIssueMarkers[0]}: housekeeping`,
  ];
  for (const [, mask] of MASKINGS) {
    for (const text of maskedLines) {
      add(mask(text), {});
    }
    for (const closer of closingKeywords) {
      add(`${mask(negatedCloser(closer))}\n\n${nonClosingMarkers[0]}: #13`, { nonClosing: true });
    }
  }
  for (const [, mask] of UNTERMINATED_MASKINGS) {
    for (const text of maskedLines) {
      add(mask(text), {});
    }
  }
  const tail = sectionsTail(requiredSections);
  return cases.map((sample) => ({ ...sample, body: `${sample.line}${tail}` }));
}

function describe(verdict) {
  const parts = [];
  if (verdict.closing) parts.push("closing");
  if (verdict.nonClosing) parts.push("non-closing");
  if (verdict.noIssue) parts.push("no-issue");
  if (verdict.negated) parts.push(`negated by "${verdict.negated}"`);
  return parts.length === 0 ? "no linkage" : parts.join(" + ");
}

function reportMismatches(mismatches, location) {
  if (mismatches.length === 0) {
    return;
  }
  const shown = mismatches
    .slice(0, 6)
    .map(
      ({ line, expected, actual }) =>
        `${JSON.stringify(line)} should be ${expected}, got ${actual}`,
    );
  const more =
    mismatches.length > shown.length ? `; and ${mismatches.length - shown.length} more` : "";
  throw new DriftError(
    `${location}: linkage behavior differs from policy on ${mismatches.length} sample bod${mismatches.length === 1 ? "y" : "ies"}: ${shown.join("; ")}${more}`,
  );
}

function run(command, args, options, location, what) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    env: SANDBOX_ENV,
    timeout: TIMEOUT_MS,
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  });
  if (result.error) {
    if (result.error.code === "ETIMEDOUT") {
      throw new DriftError(
        `${location}: the ${what} did not finish within ${TIMEOUT_MS / 1000}s on the sample bodies`,
      );
    }
    if (result.error.code === "EPIPE" && result.status !== null) {
      return result;
    }
    if (result.error.code === "ENOENT") {
      throw new BehaviorToolError(
        `${location}: behavioral lockstep needs \`${command}\` on PATH to run the ${what}; install it (the CI lane does)`,
      );
    }
    throw new BehaviorToolError(`${location}: the ${what}: ${result.error.message}`);
  }
  return result;
}

export const unquoteAwk = (text) => text.replaceAll(`'"'"'`, "'");

export function extractCompositeAnalyzer(runShText, location) {
  const match = runShText.match(/^analyze_body\(\) \{\n {2}awk '\n([\s\S]*?)\n'\n\}$/m);
  if (!match) {
    throw new DriftError(
      `${location}: run.sh has no \`analyze_body() { awk '...' }\` analyzer to execute`,
    );
  }
  return unquoteAwk(match[1]);
}

export function parseCompositeIssueRef(runShText, location) {
  if (!runShText.includes('ENVIRON["ISSUE_REF_PATTERN"]')) {
    return null;
  }
  const declaration = runShText.match(/^DEFAULT_ISSUE_REF_PATTERN='([^']+)'$/m);
  const wired =
    // biome-ignore lint/suspicious/noTemplateCurlyInString: bash, not a JS template
    runShText.includes('ISSUE_REF_PATTERN="${ISSUE_REF_PATTERN:-$DEFAULT_ISSUE_REF_PATTERN}"') &&
    /^export ISSUE_REF_PATTERN DEFAULT_ISSUE_REF_PATTERN$/m.test(runShText);
  if (!declaration || !wired) {
    throw new DriftError(
      `${location}: run.sh reads ISSUE_REF_PATTERN but does not declare and export DEFAULT_ISSUE_REF_PATTERN as its fallback`,
    );
  }
  return declaration[1];
}

export function runCompositeAnalyzer(program, body, location, issueRef = null) {
  const refEnv =
    issueRef === null ? {} : { ISSUE_REF_PATTERN: issueRef, DEFAULT_ISSUE_REF_PATTERN: issueRef };
  const result = run(
    "gawk",
    ["--sandbox", "--", program],
    { input: body, env: { ...SANDBOX_ENV, LC_ALL: "C.UTF-8", ...refEnv } },
    location,
    "analyzer",
  );
  if (result.status !== 0) {
    throw new DriftError(
      `${location}: the analyzer exited ${result.status ?? result.signal} on a sample body: ${result.stderr.trim()}`,
    );
  }
  const lines = result.stdout.split("\n");
  const negated = lines.filter((line) => line.startsWith("negated\t"));
  return {
    closing: lines.includes("closing"),
    nonClosing: lines.includes("non-closing"),
    noIssue: lines.includes("no-issue"),
    negated: negated.length > 0 ? negated[0].split("\t")[2] : null,
  };
}

const compositeMismatchCache = new Map();

export function checkCompositeBehavior(runShText, policy, location, wiringLocation = location) {
  const program = extractCompositeAnalyzer(runShText, location);
  const issueRef = parseCompositeIssueRef(runShText, wiringLocation);
  const key = `${JSON.stringify(policy.body)}\0${program}\0${issueRef}`;
  if (!compositeMismatchCache.has(key)) {
    const mismatches = [];
    for (const { line, body, expect } of linkageMatrix(policy)) {
      const actual = runCompositeAnalyzer(program, body, location, issueRef);
      if (describe(actual) !== describe(expect)) {
        mismatches.push({ line, expected: describe(expect), actual: describe(actual) });
      }
    }
    compositeMismatchCache.set(key, mismatches);
  }
  reportMismatches(compositeMismatchCache.get(key), location);
}

const HOOK_HARNESS = [
  "export LC_ALL=C",
  'source "$1" >/dev/null 2>&1 || exit 90',
  "declare -F linkage::problems >/dev/null || exit 91",
  "while IFS= read -r -d '' body; do",
  '  linkage::problems "$body" || true',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: bash, not a JS template
  "  ((${#LINKAGE_PROBLEMS[@]} == 0)) || printf '%s\\n' \"${LINKAGE_PROBLEMS[@]}\"",
  "  printf '\\0'",
  "done",
].join("\n");

function hookVerdict(record) {
  const problems = record.split("\n").filter(Boolean);
  const trigger = record.match(/\(trigger "([^"]+)"\)/);
  return {
    linked: problems.every((problem) => problem.includes('(trigger "')),
    negated: trigger ? trigger[1] : null,
  };
}

const hookMismatchCache = new Map();

export function checkHookBehavior(shellText, policy, location) {
  const key = `${JSON.stringify(policy.body)}\0${shellText}`;
  if (!hookMismatchCache.has(key)) {
    hookMismatchCache.set(key, runHookMatrix(shellText, policy, location));
  }
  reportMismatches(hookMismatchCache.get(key), location);
}

function runHookMatrix(shellText, policy, location) {
  const matrix = linkageMatrix(policy);
  const directory = mkdtempSync(path.join(tmpdir(), "pr-lockstep-hook-"));
  let result;
  try {
    const hookPath = path.join(directory, "pr-linkage-validator.sh");
    writeFileSync(hookPath, shellText);
    result = run(
      "bash",
      ["--noprofile", "--norc", "-c", HOOK_HARNESS, "lockstep-harness", hookPath],
      { input: `${matrix.map(({ body }) => body).join("\0")}\0`, cwd: directory },
      location,
      "validator",
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
  if (result.status === 90) {
    throw new DriftError(`${location}: the validator does not source cleanly in bash`);
  }
  if (result.status === 91) {
    throw new DriftError(`${location}: the validator no longer defines linkage::problems`);
  }
  const records = result.stdout.split("\0");
  if (result.status !== 0 || records.length !== matrix.length + 1) {
    throw new DriftError(
      `${location}: the validator harness exited ${result.status ?? result.signal} after ${records.length - 1} of ${matrix.length} sample bodies: ${result.stderr.trim()}`,
    );
  }
  const show = (v) =>
    `${v.linked ? "linked" : "unlinked"}${v.negated ? ` + negated by "${v.negated}"` : ""}`;
  const mismatches = [];
  matrix.forEach(({ line, expect }, index) => {
    const actual = hookVerdict(records[index]);
    const expected = {
      linked: expect.closing || expect.nonClosing || expect.noIssue,
      negated: expect.negated,
    };
    if (show(actual) !== show(expected)) {
      mismatches.push({ line, expected: show(expected), actual: show(actual) });
    }
  });
  return mismatches;
}
