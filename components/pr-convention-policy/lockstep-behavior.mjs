// Behavioral lockstep (#647): run each linkage implementation on a matrix of
// sample bodies generated from `policy.json` and compare its verdicts with the
// ones the policy predicts. A static parse of a copy's source proves the
// declared data matches; only running the copy proves the rule is wired from
// the declaration to the verdict, whatever shape the code takes.
//
// Trust boundary. The code executed here is fetched from org-owned
// repositories (ci-workflows, claude-code-plugins) over a read-only contents
// token, or read from this repository's fixtures. It still runs confined:
//   - the composite's analyzer is pure awk, run under `gawk --sandbox`, which
//     disables `system()`, command pipes, file redirection and extra input
//     files, so it can read only the sample body on stdin and print a verdict;
//   - the hook validator is a sourced bash library, run in `bash --noprofile
//     --norc` with an environment of PATH and LC_ALL only (no token, no HOME),
//     a timeout, and a scratch copy of the fetched file it cannot affect;
//   - neither process receives the lane's GitHub token.
// A missing `gawk` or `bash` is an error, never a skip.

import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// A cycle, deliberately: lockstep-drift.mjs imports this module, and nothing
// here touches DriftError until a check runs, after both have evaluated.
import { DriftError } from "./lockstep-drift.mjs";

export class BehaviorToolError extends Error {
  constructor(message) {
    super(message);
    this.name = "BehaviorToolError";
  }
}

const SANDBOX_ENV = { PATH: "/usr/bin:/bin" };
const TIMEOUT_MS = 10_000;
// The clause punctuation that resets the negation window. policy.json has no
// field for it; the README's `negatedClosers` paragraph and the schema's
// description name the same five characters.
export const CLAUSE_DELIMITERS = [".", "!", "?", ";", ","];
// Punctuation outside that set, which must leave the window open: a disclaimer
// before it still negates the keyword after it. An apostrophe is left out (it
// is part of a word, as in "doesn't"), and so are a backtick and `<`, which
// open masked Markdown.
export const NON_DELIMITERS = [":", "-", "(", ")", '"', "/", "[", "]", "*", "&"];
// The Markdown each copy masks before it scans, as wrappers around one line of
// linkage. Only shapes the two copies agree on: they part ways where a comment
// opener sits inside code (see the README's Behavioral lockstep section).
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
// GitHub's closing keywords, every inflection both copies accept. policy.json
// spells three of them and lists no inflections; GitHub's list is the one in
// "Linking a pull request to an issue" (docs.github.com, Using keywords in
// issues and pull requests), checked 2026-10; recheck when either copy's
// keyword pattern changes.
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

// `count` distinct words of letters only, so any schema-valid wordWindow can be
// probed: the named fillers first, then "filler" plus a base-26 letter suffix.
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

// One line of content under each required section, in policy order.
export function sectionsTail(requiredSections) {
  const sections = requiredSections.map(
    (section) => `\n\n## ${section}\n${section[0].toLowerCase()}`,
  );
  return `${sections.join("")}\n`;
}

// Every case is a few lines of linkage plus every required section, non-empty,
// so a verdict can only differ on linkage. `expect.negated` names the
// disclaimer word the policy says triggers, or null.
export function linkageMatrix(policy) {
  const { requiredSections, closingKeywords, nonClosingMarkers, noIssueMarkers, negatedClosers } =
    policy.body;
  const none = { closing: false, nonClosing: false, noIssue: false, negated: null };
  const cases = [];
  const add = (line, expect) => cases.push({ line, expect: { ...none, ...expect } });

  // Every term is matched without regard to case, a closing keyword anywhere
  // on a line (a list item or a quote included) with an optional colon and any
  // blanks before the reference, and only as a whole word before a whole
  // reference. A bare issue URL is not a reference to either copy.
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
  // A non-closing marker counts only as a whole line: colon required, any
  // blanks inside the marker and around the reference, any case, at most three
  // spaces of indent, and no list bullet or quote in front.
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
  // A no-issue marker counts anywhere in the body, in any case, as whole words.
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
  // One line of each kind of valid linkage, with the verdict it alone earns.
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
  // Every negation shape is probed with every closing keyword, so a copy that
  // wires negation to one keyword only cannot pass.
  const inside = fillers(wordWindow - 1).join(" ");
  const outside = fillers(wordWindow).join(" ");
  for (const closer of closingKeywords) {
    const lower = closer.toLowerCase();
    for (const trigger of triggers) {
      add(`${trigger} ${inside} ${closer} #12`.replace("  ", " "), { negated: trigger });
      add(`${trigger} ${outside} ${closer} #12`, { closing: true });
      // A trigger is matched without regard to case and reported as written.
      for (const cased of [trigger.toUpperCase(), capitalize(trigger)]) {
        add(`This ${cased} ${lower} #12`, { negated: cased });
      }
      // A typographic apostrophe (U+2019) reads as a straight one, and the
      // trigger is reported with the straight one.
      if (trigger.includes("'")) {
        for (const written of [trigger, trigger.toUpperCase()]) {
          add(`This ${written.replaceAll("'", "’")} ${lower} #12`, { negated: written });
        }
      }
    }
    // Only whole words trigger, the window counts words of letters (a hyphen
    // splits one, a bare reference is none), and it never crosses a line.
    add(`This ${firstTrigger}e ${lower} #12`, { closing: true });
    add(`This can${firstTrigger} ${lower} #12`, { closing: true });
    add(`${firstTrigger} ${outside.replace(" ", "-")} ${closer} #12`, { closing: true });
    const references = fillers(wordWindow).map((_, index) => `#${index + 1}`);
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
    // A negated closer is reported whatever valid linkage sits elsewhere, on
    // the line before or after it: a copy that settles the verdict on the
    // first linkage it finds, or skips negation once a body opts out, misses
    // it. GitHub still closes the issue either way.
    for (const { text, expect } of linkageLines(closer)) {
      add(`${text}\n${negatedCloser(closer)}`, { ...expect, negated: firstTrigger });
      add(`${negatedCloser(closer)}\n${text}`, { ...expect, negated: firstTrigger });
    }
    // Every closing reference on a line is judged, in order: a copy that
    // stops at the first match misses a negated closer after a valid one, or a
    // valid one after a negated closer.
    const bothWays = { closing: true, negated: firstTrigger };
    add(`${closer} #11 but does ${firstTrigger} ${lower} #12`, bothWays);
    add(`${negatedCloser(closer)}; ${closer} #11`, bothWays);
  }
  // A no-issue marker counts anywhere, so it can share the negated closer's
  // line; a non-closing marker must stand alone and cannot.
  for (const marker of noIssueMarkers) {
    const closer = closingKeywords[0];
    const negatedOnly = { noIssue: true, negated: firstTrigger };
    add(`${marker}; ${negatedCloser(closer).toLowerCase()}`, negatedOnly);
    add(`${negatedCloser(closer)}; ${marker.toLowerCase()}`, negatedOnly);
  }
  // Every two kinds of valid linkage together, in both orders, read as both.
  const linkage = linkageLines(closingKeywords[0]);
  for (const first of linkage) {
    for (const second of linkage) {
      if (first !== second) {
        add(`${first.text}\n${second.text}`, { ...first.expect, ...second.expect });
      }
    }
  }

  // Every inflection closes and is negated like the policy's spellings: a copy
  // that wires negation to those three alone would accept "does not close" in
  // front of a reference, which GitHub still closes. The policy's own
  // spellings already appear plain and upper-cased above.
  const spelled = closingKeywords.map((keyword) => keyword.toLowerCase());
  for (const form of GITHUB_CLOSING_KEYWORDS) {
    if (!spelled.includes(form)) {
      add(`${capitalize(form)} #12`, { closing: true });
      add(`${form.toUpperCase()} #12`, { closing: true });
    }
    add(`This does ${firstTrigger} ${form} #12`, { negated: firstTrigger });
  }

  // Linkage the rendered body does not show is not linkage: both copies mask
  // HTML comments and code before they scan, so a body whose only linkage is
  // masked has none, and a masked negated closer is never reported. Without
  // these samples every body reads the same raw and masked, and a copy that
  // scanned the raw body would still pass.
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
    // Code that hangs on a sample body is drift in that code, not a tool fault.
    if (result.error.code === "ETIMEDOUT") {
      throw new DriftError(
        `${location}: the ${what} did not finish within ${TIMEOUT_MS / 1000}s on the sample bodies`,
      );
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

// ---------------------------------------------------------------------------
// The composite: its analyzer is the awk program inside `analyze_body`.
// ---------------------------------------------------------------------------

export function extractCompositeAnalyzer(runShText, location) {
  const match = runShText.match(/^analyze_body\(\) \{\n {2}awk '\n([\s\S]*?)\n'\n\}$/m);
  if (!match) {
    throw new DriftError(
      `${location}: run.sh has no \`analyze_body() { awk '...' }\` analyzer to execute`,
    );
  }
  // Single-quoted bash spells an apostrophe `'"'"'`; awk sees the apostrophe.
  return match[1].replaceAll(`'"'"'`, "'");
}

export function runCompositeAnalyzer(program, body, location) {
  const result = run(
    "gawk",
    ["--sandbox", "--", program],
    { input: body, env: { ...SANDBOX_ENV, LC_ALL: "C.UTF-8" } },
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

// Most consumers pin the same few composite versions, so one run per distinct
// analyzer and policy serves them all.
const compositeMismatchCache = new Map();

export function checkCompositeBehavior(runShText, policy, location) {
  const program = extractCompositeAnalyzer(runShText, location);
  const key = `${JSON.stringify(policy.body)}\0${program}`;
  if (!compositeMismatchCache.has(key)) {
    const mismatches = [];
    for (const { line, body, expect } of linkageMatrix(policy)) {
      const actual = runCompositeAnalyzer(program, body, location);
      if (describe(actual) !== describe(expect)) {
        mismatches.push({ line, expected: describe(expect), actual: describe(actual) });
      }
    }
    compositeMismatchCache.set(key, mismatches);
  }
  reportMismatches(compositeMismatchCache.get(key), location);
}

// ---------------------------------------------------------------------------
// The hook: a sourced bash library whose aggregate verdict is
// `linkage::problems`, which fills LINKAGE_PROBLEMS. The harness feeds it the
// matrix NUL-separated and prints each body's problems, NUL-terminated.
// ---------------------------------------------------------------------------

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

// A negated reference is reported as `... (trigger "<word>") ...`; any other
// problem on a body whose sections are all filled is missing linkage.
function hookVerdict(record) {
  const problems = record.split("\n").filter(Boolean);
  const trigger = record.match(/\(trigger "([^"]+)"\)/);
  return {
    linked: problems.every((problem) => problem.includes('(trigger "')),
    negated: trigger ? trigger[1] : null,
  };
}

export function checkHookBehavior(shellText, policy, location) {
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
  const mismatches = [];
  matrix.forEach(({ line, expect }, index) => {
    const actual = hookVerdict(records[index]);
    const expected = {
      linked: expect.closing || expect.nonClosing || expect.noIssue,
      negated: expect.negated,
    };
    const show = (v) =>
      `${v.linked ? "linked" : "unlinked"}${v.negated ? ` + negated by "${v.negated}"` : ""}`;
    if (show(actual) !== show(expected)) {
      mismatches.push({ line, expected: show(expected), actual: show(actual) });
    }
  });
  reportMismatches(mismatches, location);
}
