#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { parse as parseYaml } from "yaml";

import { renderTemplate } from "./contract-docs.mjs";
import {
  checkCompositeBehavior,
  checkHookBehavior,
  parseCompositeIssueRef,
  unquoteAwk,
} from "./lockstep-behavior.mjs";
import { parseUniqueJson } from "./pr-convention-policy.mjs";

const MODULE_DIRECTORY = import.meta.dirname;
const POLICY_PATH = path.join(MODULE_DIRECTORY, "policy.json");

const API_BASE = "https://api.github.com/repos/melodic-software";
const contentsUrl = (repo, ref, filePath) => `${API_BASE}/${repo}/contents/${filePath}?ref=${ref}`;

export const COMPOSITE_DIRECTORY = ".github/actions/pr-require-checks/check-contract";
const REUSABLE_PATH = ".github/workflows/pr-issue-linkage.yml";

export const COPY_SOURCES = {
  hookValidator: contentsUrl(
    "claude-code-plugins",
    "main",
    "plugins/source-control/hooks/pr-linkage-validator.sh",
  ),
  orgTemplate: contentsUrl(".github", "main", ".github/PULL_REQUEST_TEMPLATE.md"),
};

export const CONSUMER_REPOSITORIES = [
  ".github",
  "azure-iac",
  "ci-runner",
  "ci-workflows",
  "claude-code-account-rotation",
  "claude-code-plugins",
  "claude-code-proxy",
  "dotfiles",
  "github-iac",
  "knowledge-corpus",
  "medley",
  "provisioning",
  "songwriting",
  "standards",
];

const WORKFLOW_SCAN_PRIORITY = ["pr-require-checks.yml", "ci.yml", "ci-status.yml"];

export class DriftError extends Error {
  constructor(message) {
    super(message);
    this.name = "DriftError";
  }
}

export class FetchError extends Error {
  constructor(message) {
    super(message);
    this.name = "FetchError";
  }
}

function collect(errors, fn) {
  try {
    fn();
  } catch (error) {
    if (!(error instanceof DriftError)) {
      throw error;
    }
    if (!errors.includes(error.message)) {
      errors.push(error.message);
    }
  }
}

export function parseCompositeSections(runShText, location) {
  const names = [...runShText.matchAll(/section_report\("([^"]+)"\)/g)].map((m) => m[1]);
  if (names.length === 0) {
    throw new DriftError(`${location}: no \`section_report("<name>")\` calls found in run.sh`);
  }
  return names;
}

function compositeKeywordPattern(runShText, location) {
  const literal = runShText.match(/match\(chunk, \/(.+)\/\)\) break/);
  if (literal) {
    return literal[1];
  }
  const matchLoop = /match\(chunk, closing_regex\)\) break/.test(runShText);
  const gsubPass =
    /^\s*marked = lower$/m.test(runShText) &&
    /^\s*gsub\(closing_regex, "\\n&\\n", marked\)$/m.test(runShText) &&
    /^\s*count = split\(marked, pieces, "\\n"\)$/m.test(runShText);
  if (!matchLoop && !gsubPass) {
    return null;
  }
  const issueRef = parseCompositeIssueRef(runShText, location);
  const separator = runShText.match(/^\s*separator = custom \? "[^"]*" : "([^"]*)"$/m);
  const assembled = runShText.match(/^\s*closing_regex = "([^"]*)" separator ref$/m);
  const reference = /^\s*ref = "\(" ref "\)"$/m.test(runShText);
  if (issueRef === null || !separator || !assembled || !reference) {
    return null;
  }
  return `${assembled[1]}${separator[1]}(${issueRef})`;
}

export function parseCompositePatterns(runShText, location) {
  const keyword = compositeKeywordPattern(runShText, location);
  const marker = runShText.match(/tolower\(body\) ~ \/(.+)\/\) print "no-issue"/);
  if (!keyword || !marker) {
    throw new DriftError(
      `${location}: closing-keyword / no-issue-marker match expressions not found in run.sh`,
    );
  }
  if (!/lower = tolower\(line\)/.test(runShText)) {
    throw new DriftError(
      `${location}: the closing-keyword scan no longer lowercases the line (\`lower = tolower(line)\`), so the extracted pattern is not the one the gate applies`,
    );
  }
  return { keyword: new RegExp(keyword), marker: new RegExp(marker[1]) };
}

function parseActionYml(actionYmlText, location) {
  try {
    return parseYaml(actionYmlText);
  } catch (error) {
    throw new DriftError(`${location}: action.yml is not parsable YAML: ${error.message}`);
  }
}

export function parseCompositeTypes(actionYmlText, location) {
  const document = parseActionYml(actionYmlText, location);
  const declared = document?.inputs?.types?.default;
  if (typeof declared !== "string") {
    throw new DriftError(`${location}: action.yml declares no string \`inputs.types.default\``);
  }
  const types = declared
    .split(",")
    .map((type) => type.trim())
    .filter(Boolean);
  if (types.length === 0) {
    throw new DriftError(`${location}: the \`types\` input default is empty`);
  }
  return types;
}

export function parseCompositeRequireScope(actionYmlText, location) {
  const document = parseActionYml(actionYmlText, location);
  const declared = document?.inputs?.["require-scope"]?.default;
  if (declared === true || declared === "true") {
    return true;
  }
  if (declared === false || declared === "false") {
    return false;
  }
  if (declared === undefined) {
    throw new DriftError(`${location}: action.yml declares no \`inputs.require-scope.default\``);
  }
  throw new DriftError(
    `${location}: \`inputs.require-scope.default\` is not a boolean: ${JSON.stringify(declared)}`,
  );
}

export function assertCompositeIssueRefDefault(runShText, actionYmlText, location) {
  const issueRef = parseCompositeIssueRef(runShText, location);
  if (issueRef === null) {
    return;
  }
  const declared = parseActionYml(actionYmlText, location)?.inputs?.["issue-ref-pattern"]?.default;
  if (declared !== undefined && declared !== "" && declared !== issueRef) {
    throw new DriftError(
      `${location}: action.yml's \`issue-ref-pattern\` default ${JSON.stringify(declared)} differs from run.sh's DEFAULT_ISSUE_REF_PATTERN ${JSON.stringify(issueRef)}`,
    );
  }
}

export function parseGateSections(workflowText, location) {
  const arrayMatch = workflowText.match(/const requiredSections = \[([\s\S]*?)\n\s*\];/);
  if (!arrayMatch) {
    throw new DriftError(`${location}: no \`const requiredSections = [...]\` block found`);
  }
  const names = [...arrayMatch[1].matchAll(/name:\s*"([^"]+)"/g)].map((m) => m[1]);
  if (names.length === 0) {
    throw new DriftError(`${location}: requiredSections block carries no name: entries`);
  }
  return names;
}

export function parseGatePatterns(workflowText, location) {
  const keyword = workflowText.match(/const CLOSING_KEYWORD =\s*\/(.+)\/([dgimsuvy]*);/);
  const marker = workflowText.match(/const NO_ISSUE_MARKER =\s*\/(.+)\/([dgimsuvy]*);/);
  if (!keyword || !marker) {
    throw new DriftError(
      `${location}: CLOSING_KEYWORD / NO_ISSUE_MARKER regex declarations not found`,
    );
  }
  // `g` and `y` make `.test()` stateful via lastIndex, so repeated probes would read a moved cursor.
  // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/RegExp/test
  const probeFlags = (flags) => flags.replaceAll(/[gy]/g, "");
  return {
    keyword: new RegExp(keyword[1], probeFlags(keyword[2])),
    marker: new RegExp(marker[1], probeFlags(marker[2])),
  };
}

export function parseValidatorSections(shellText, location) {
  const match = shellText.match(/REQUIRED_SECTIONS=\(([^)]*)\)/);
  if (!match) {
    throw new DriftError(`${location}: no REQUIRED_SECTIONS=(...) declaration found`);
  }
  const names = match[1].split(/\s+/).filter(Boolean);
  if (names.length === 0) {
    throw new DriftError(`${location}: REQUIRED_SECTIONS declaration is empty`);
  }
  return names;
}

export function parseMarkdownHeadings(markdownText) {
  return [...markdownText.matchAll(/^## (.+)$/gm)].map((m) => m[1].trim());
}

const VALIDATOR_OPERANDS = {
  // biome-ignore lint/suspicious/noTemplateCurlyInString: bash parameter expansions, not JS placeholders
  CLOSING_ERE: { operand: "chunk", sources: ['lower="${line,,}"', 'chunk="${lower:off}"'] },
  NO_ISSUE_ERE: { operand: "lower", sources: [`lower=$'\\n'"\${1,,}"$'\\n'`] },
};

function assertValidatorOperand(shellText, name, location) {
  const { operand, sources } = VALIDATOR_OPERANDS[name];
  const uses = [...shellText.matchAll(new RegExp(`"\\$(\\w+)" =~ \\$${name}\\b`, "g"))];
  const lowercased =
    uses.length > 0 &&
    uses.every((use) => use[1] === operand) &&
    sources.every((source) => shellText.includes(source));
  if (!lowercased) {
    throw new DriftError(
      `${location}: scan_linkage no longer matches ${name} only against the lowercased \`$${operand}\` (${sources.join(", ")}), so the extracted pattern is not the one the hook applies`,
    );
  }
}

const ereToJs = (ere) =>
  new RegExp(ere.replaceAll("[[:space:]]", "\\s").replaceAll("[[:blank:]]", "[ \\t]"));

export function parseValidatorPatterns(shellText, location) {
  const keyword = shellText.match(/^CLOSING_ERE='([^']+)'/m);
  const marker = shellText.match(/^NO_ISSUE_ERE='([^']+)'/m);
  if (!keyword || !marker) {
    throw new DriftError(`${location}: CLOSING_ERE / NO_ISSUE_ERE declarations not found`);
  }
  assertValidatorOperand(shellText, "CLOSING_ERE", location);
  assertValidatorOperand(shellText, "NO_ISSUE_ERE", location);
  return { keyword: ereToJs(keyword[1]), marker: ereToJs(marker[1]) };
}

function nonClosingAlternation(pattern, location) {
  const group = pattern.match(/^\^(?: \{0,3\})?\(([^()]+)\):/);
  if (!group) {
    throw new DriftError(
      `${location}: the non-closing pattern does not open with an anchored \`^(<marker>|...):\` group: ${pattern}`,
    );
  }
  return group[1]
    .split("|")
    .map((marker) => marker.replaceAll(/\[\[:blank:\]\]\+|\[ \\t\]\+/g, " "));
}

export function parseValidatorNonClosing(shellText, location) {
  const declaration = shellText.match(/^NON_CLOSING_ERE='([^']+)'/m);
  if (!declaration) {
    throw new DriftError(`${location}: NON_CLOSING_ERE declaration not found`);
  }
  return { markers: nonClosingAlternation(declaration[1], location) };
}

export function parseCompositeNonClosing(runShText, location) {
  const declaration =
    runShText.match(/rest ~ \/(.+)\/\) \{\s*has_non_closing = 1/) ??
    (/rest ~ non_closing_regex\) \{\s*has_non_closing = 1/.test(runShText)
      ? runShText.match(/^\s*non_closing_regex = "([^"]*)" ref "[^"]*"$/m)
      : null);
  if (!declaration) {
    throw new DriftError(
      `${location}: the \`rest ~ /.../\` non-closing marker test (has_non_closing = 1) was not found in run.sh`,
    );
  }
  return { markers: nonClosingAlternation(declaration[1], location) };
}

export function assertCompositeVerdictReads(runShText, location) {
  const reportWrites = runShText.match(/>>?\s*"\$analysis"/g) ?? [];
  const links = [
    [
      "the PR body is written to the analyzer's input",
      /jq -r (?:'\.body \/\/ ""'|\.body) <"\$pr_json" >"\$scratch\/body\.txt"/,
    ],
    [
      "analyze_body writes the report run.sh reads",
      /analysis="\$scratch\/analysis\.txt"\s*\n\s*analyze_body <"\$scratch\/body\.txt" >"\$analysis"\n/,
    ],
    ["nothing else writes the report", { test: () => reportWrites.length === 1 }],
    [
      "a missing or empty section report is a linkage error",
      new RegExp(
        [
          String.raw`while IFS=\$'\\t' read -r kind name _rest; do\s*\n\s*case "\$kind" in\s*\n\s*section-missing\)\s*\n\s*linkage_errors\+=\("Missing a \\"## \$\{name\}\\" section\.[^\n]*\n\s*;;\s*\n\s*section-empty\)\s*\n\s*linkage_errors\+=\("The \\"## \$\{name\}\\" section is empty\."\)\s*\n\s*;;\s*\n\s*\*\) ;;\s*\n\s*esac\s*\n\s*done <"\$analysis"\n`,
          String.raw`while IFS=\$'\\t' read -r kind text trigger; do\s*\n\s*case "\$kind" in\s*\n\s*section-missing\) linkage_errors\+=\("Missing a \\"## \$\{text\}\\" section\.[^\n]*\n\s*section-empty\) linkage_errors\+=\("The \\"## \$\{text\}\\" section is empty\."\) ;;\s*\n(?:\s*negated\)[^\n]*\n)?\s*\*\) ;;\s*\n\s*esac\s*\n\s*done <"\$analysis"\n`,
        ].join("|"),
      ),
    ],
    [
      "a `non-closing` report satisfies linkage",
      /(?:if ! grep -qx 'closing' "\$analysis" &&\s*! grep -qx 'non-closing' "\$analysis" &&\s*! grep -qx 'no-issue' "\$analysis"|if ! grep -qxE 'closing\|non-closing\|no-issue' "\$analysis"); then\s*\n\s*linkage_errors\+=\((?:'Missing a native|"Missing a \$\{keyword_kind\}) closing keyword/,
    ],
    [
      "a `negated` report is a linkage error",
      new RegExp(
        [
          String.raw`negated_quoted=""\s*\n\s*while IFS=\$'\\t' read -r kind text trigger; do\s*\n\s*\[\[ "\$kind" == negated \]\] \|\| continue\n(?:(?!\bdone\b)[\s\S])*?done <"\$analysis"\n\s*\n\s*if \[\[ -n "\$negated_quoted" \]\]; then\s*\n\s*linkage_errors\+=\("Negated closing reference`,
          String.raw`negated_quoted=""\s*\n\s*while IFS=\$'\\t' read -r kind text trigger; do\s*\n\s*case "\$kind" in\s*\n(?:(?!\bdone\b)[\s\S])*?\n\s*negated\) negated_quoted\+=[^\n]*\n(?:(?!\bdone\b)[\s\S])*?done <"\$analysis"\n\s*\n\s*if \[\[ -n "\$negated_quoted" \]\]; then\s*\n\s*linkage_errors\+=\("Negated closing reference`,
        ].join("|"),
      ),
    ],
    [
      "a linkage error fails the check",
      /if \[\[ \$\{#linkage_errors\[@\]\} -gt 0 \]\]; then\s*\n\s*linkage_result=fail\n/,
    ],
  ];
  const missing = links.filter(([, pattern]) => !pattern.test(runShText));
  if (missing.length > 0) {
    throw new DriftError(
      `${location}: run.sh no longer acts on the analyzer's report: ${missing.map(([link]) => link).join("; ")}`,
    );
  }
}

export function parseValidatorNegation(shellText, location) {
  const window =
    shellText.match(/\(\(n > (\d+)\)\) && first=\$\(\(n - (\d+)\)\)/) ??
    shellText.match(/i >= 0 && \$\{#words\[@\]\} < (\d+);/);
  const affirmative = shellText.match(
    /\[\[ "\$lower" == (\w+) \]\] && \(\(i \+ 1 < n\)\) && \[\[ "\$\{words\[i \+ 1\],,\}" == (\w+) \]\] && continue/,
  );
  const cases = shellText.match(/case "\$lower" in\s*\n\s*([^\n)]+)\)/);
  if (!window || !affirmative || !cases) {
    throw new DriftError(
      `${location}: negation_trigger_to's window, "not only" exception, or trigger \`case\` not found`,
    );
  }
  const words = [];
  const suffixes = [];
  for (const alternative of cases[1].split("|").map((item) => item.trim())) {
    const suffix = alternative.match(/^\*"([^"]+)"$/);
    if (suffix) {
      suffixes.push(suffix[1]);
    } else if (/^[a-z]+$/.test(alternative)) {
      words.push(alternative);
    } else {
      throw new DriftError(
        `${location}: negation_trigger_to has a trigger alternative this check cannot read: ${alternative}`,
      );
    }
  }
  return {
    triggerWords: words,
    triggerSuffixes: suffixes,
    affirmativePhrases: [`${affirmative[1]} ${affirmative[2]}`],
    wordWindow: Number(window[1]),
  };
}

function compositeNegationWindow(runShText) {
  const lastWords = runShText.match(/first = \(count > (\d+)\) \? count - (\d+) : 1/);
  if (lastWords) {
    return lastWords;
  }
  const backward = runShText.match(/if \(in_word && has_letter && \+\+seen == (\d+)\) break/);
  if (backward && /^\s*tail = substr\(line, start, keyword_index - start\)$/m.test(runShText)) {
    return backward;
  }
  return null;
}

export function parseCompositeNegation(runShText, location) {
  const window = compositeNegationWindow(runShText);
  const affirmative = runShText.match(
    /if \(lower == "(\w+)" && i < count && tolower\(words\[i \+ 1\]\) == "(\w+)"\) continue/,
  );
  const triggers = runShText.match(
    /if \((lower == "\w+"(?:\s*\|\|\s*lower == "\w+")*)\) return word/,
  );
  const suffix = unquoteAwk(runShText).match(
    /if \(tolower\(substr\(word, length\(word\) - (\d+)\)\) == "([^"]+)"\) return word/,
  );
  if (!window || !affirmative || !triggers || !suffix) {
    throw new DriftError(
      `${location}: negation_trigger's window, "not only" exception, trigger words, or suffix test not found in run.sh`,
    );
  }
  return {
    triggerWords: [...triggers[1].matchAll(/lower == "(\w+)"/g)].map((m) => m[1]),
    triggerSuffixes: [suffix[2]],
    affirmativePhrases: [`${affirmative[1]} ${affirmative[2]}`],
    wordWindow: Number(window[1]),
  };
}

const USES_PREFIX = String.raw`^[^#\n]*\buses:\s*`;
export const REPORT_DIRECTORY = ".github/actions/pr-require-checks/report-ci-status";
const COMPOSITE_DIRECTORY_PATTERN = `(?:${[COMPOSITE_DIRECTORY, REPORT_DIRECTORY]
  .map((directory) => directory.replaceAll(".", "\\."))
  .join("|")})`;
const COMPOSITE_PIN_PATTERN = new RegExp(
  `${USES_PREFIX}melodic-software/ci-workflows/${COMPOSITE_DIRECTORY_PATTERN}@([0-9a-f]{40}|main)(?=[\\s"']|$)`,
  "m",
);
const COMPOSITE_LOCAL_PATTERN = new RegExp(
  `${USES_PREFIX}[.$]/${COMPOSITE_DIRECTORY_PATTERN}(?=\\s|$)`,
  "m",
);
const REUSABLE_PIN_PATTERN = new RegExp(
  `${USES_PREFIX}\\S*pr-issue-linkage\\.yml@([0-9a-f]{40})`,
  "m",
);

export function detectArtifactPin(workflowText) {
  const pinned = workflowText.match(COMPOSITE_PIN_PATTERN);
  if (pinned) {
    return { kind: "composite", sha: pinned[1] };
  }
  if (COMPOSITE_LOCAL_PATTERN.test(workflowText)) {
    return { kind: "composite", sha: "main", local: true };
  }
  const reusable = workflowText.match(REUSABLE_PIN_PATTERN);
  if (reusable) {
    return { kind: "reusable", sha: reusable[1] };
  }
  return null;
}

export function parseCallerPin(workflowText, location) {
  const match = workflowText.match(REUSABLE_PIN_PATTERN);
  if (!match) {
    throw new DriftError(`${location}: no 40-hex pr-issue-linkage.yml@<sha> pin found`);
  }
  return match[1];
}

function assertPatternsEnforce(patterns, policy, location, { lowercaseProbe = false } = {}) {
  const probe = (text) => (lowercaseProbe ? text.toLowerCase() : text);
  const missing = [];
  for (const keyword of policy.body.closingKeywords) {
    if (!patterns.keyword.test(probe(` ${keyword} #12 `))) {
      missing.push(`closing keyword "${keyword}"`);
    }
  }
  for (const marker of policy.body.noIssueMarkers) {
    if (!patterns.marker.test(probe(` ${marker}: none `))) {
      missing.push(`no-issue marker "${marker}"`);
    }
  }
  if (missing.length > 0) {
    throw new DriftError(`${location}: declared pattern rejects ${missing.join(", ")}`);
  }
}

function setDifference(actual, expected) {
  const parts = [];
  const missing = expected.filter((item) => !actual.includes(item));
  const unexpected = actual.filter((item) => !expected.includes(item));
  if (missing.length > 0) {
    parts.push(`missing ${missing.join(", ")}`);
  }
  if (unexpected.length > 0) {
    parts.push(`unexpected ${unexpected.join(", ")}`);
  }
  return parts.join("; ");
}

function assertNonClosing({ markers }, policy, location) {
  const expected = policy.body.nonClosingMarkers.map((marker) => marker.toLowerCase());
  const difference = setDifference(markers, expected);
  if (difference !== "") {
    throw new DriftError(`${location}: non-closing markers ${difference}`);
  }
}

function assertNegation(actual, policy, location) {
  const expected = policy.body.negatedClosers;
  const problems = [];
  for (const field of ["triggerWords", "triggerSuffixes", "affirmativePhrases"]) {
    const difference = setDifference(actual[field], expected[field]);
    if (difference !== "") {
      problems.push(`${field} ${difference}`);
    }
  }
  if (actual.wordWindow !== expected.wordWindow) {
    problems.push(`wordWindow is ${actual.wordWindow}, policy says ${expected.wordWindow}`);
  }
  if (problems.length > 0) {
    throw new DriftError(`${location}: negated-closer rule ${problems.join(", ")}`);
  }
}

function assertExactSections(actual, expected, location) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new DriftError(
      `${location}: section list [${actual.join(", ")}] != policy [${expected.join(", ")}]`,
    );
  }
}

function assertAllowedTypes(actual, expected, location) {
  const difference = setDifference(actual, expected);
  if (difference === "") {
    return;
  }
  throw new DriftError(
    `${location}: allowed title types ${difference} (declared: ${actual.join(", ")})`,
  );
}

function assertRequireScope(actual, expected, location) {
  if (actual !== expected) {
    throw new DriftError(`${location}: require-scope is ${actual}, policy says ${expected}`);
  }
}

function assertContainsSections(headings, expected, location) {
  const missing = expected.filter((name) => !headings.includes(name));
  if (missing.length > 0) {
    throw new DriftError(
      `${location}: missing policy section heading(s): ${missing.join(", ")} (found: ${headings.join(", ")})`,
    );
  }
}

function assertMentions(text, terms, location) {
  const missing = terms.filter((term) => !text.includes(term));
  if (missing.length > 0) {
    throw new DriftError(`${location}: does not mention: ${missing.join(", ")}`);
  }
}

export function maskCode(text) {
  let fenceChar = "";
  let fenceLength = 0;
  let commentOpen = false;
  return text
    .split("\n")
    .map((raw) => {
      const line = raw.replace(/\r$/, "");
      const blocksApply = !commentOpen;
      const indent = /^ */.exec(line)[0].length;
      const rest = line.slice(indent);
      const markerChar = rest[0];
      const markerRun = markerChar === "`" || markerChar === "~" ? runLength(rest, markerChar) : 0;
      const isMarker = indent <= 3 && markerRun >= 3;
      const info = isMarker ? rest.slice(markerRun) : "";

      if (blocksApply) {
        if (fenceChar !== "") {
          if (
            isMarker &&
            markerChar === fenceChar &&
            markerRun >= fenceLength &&
            /^[ \t]*$/.test(info)
          ) {
            fenceChar = "";
            fenceLength = 0;
          }
          return "";
        }
        if (isMarker && !(markerChar === "`" && info.includes("`"))) {
          fenceChar = markerChar;
          fenceLength = markerRun;
          return "";
        }
        if (line.startsWith("    ") || line.startsWith("\t")) return "";
      }

      let rendered = "";
      let scan = "";
      let position = 0;
      let inlineTicks = 0;
      while (position < line.length) {
        if (line[position] !== "`") {
          if (inlineTicks === 0) {
            rendered += line[position];
            scan += line[position];
          } else {
            scan += " ";
          }
          position += 1;
          continue;
        }
        let stop = position + 1;
        while (line[stop] === "`") stop += 1;
        const ticks = stop - position;
        const wasInline = inlineTicks !== 0;
        if (!wasInline && hasClosingRun(line, stop, ticks)) {
          inlineTicks = ticks;
        } else if (inlineTicks === ticks) {
          inlineTicks = 0;
        }
        const literal = !wasInline && inlineTicks === 0;
        if (literal) rendered += line.slice(position, stop);
        scan += literal ? line.slice(position, stop) : " ".repeat(ticks);
        position = stop;
      }

      const lastOpen = scan.lastIndexOf("<!--");
      const lastClose = line.lastIndexOf("-->");
      if (lastOpen > lastClose) commentOpen = true;
      else if (lastClose > lastOpen) commentOpen = false;
      return rendered;
    })
    .join("\n");
}

function runLength(text, character) {
  let n = 0;
  while (text[n] === character) n += 1;
  return n;
}

function hasClosingRun(line, start, ticks) {
  let column = start;
  while (column < line.length) {
    if (line[column] !== "`") {
      column += 1;
      continue;
    }
    let stop = column + 1;
    while (line[stop] === "`") stop += 1;
    if (stop - column === ticks) return true;
    column = stop;
  }
  return false;
}

function assertMentionsAnyRendered(text, terms, location) {
  const rendered = maskCode(text);
  if (!terms.some((term) => rendered.includes(term))) {
    throw new DriftError(
      `${location}: mentions none of the following outside an inline code span or code block: ${terms.join(", ")}`,
    );
  }
}

function compositeChecks(policy, runShText, actionYmlText, location, { labeled }) {
  const label = (suffix) => (labeled ? `${location} (${suffix})` : location);
  return {
    sections: () =>
      assertExactSections(
        parseCompositeSections(runShText, location),
        policy.body.requiredSections,
        location,
      ),
    patterns: () =>
      assertPatternsEnforce(
        parseCompositePatterns(runShText, location),
        policy,
        label("enforcement patterns"),
        { lowercaseProbe: true },
      ),
    types: () =>
      assertAllowedTypes(
        parseCompositeTypes(actionYmlText, location),
        policy.title.allowedTypes,
        label("title types"),
      ),
    requireScope: () =>
      assertRequireScope(
        parseCompositeRequireScope(actionYmlText, location),
        policy.title.requireScope,
        label("require-scope"),
      ),
    nonClosing: () =>
      assertNonClosing(
        parseCompositeNonClosing(runShText, label("non-closing markers")),
        policy,
        label("non-closing markers"),
      ),
    negation: () =>
      assertNegation(
        parseCompositeNegation(runShText, label("negated closers")),
        policy,
        label("negated closers"),
      ),
    issueRefDefault: () => assertCompositeIssueRefDefault(runShText, actionYmlText, location),
    behavior: () => checkCompositeBehavior(runShText, policy, `${location} (behavior)`, location),
    verdictReads: () => assertCompositeVerdictReads(runShText, `${location} (verdict)`),
  };
}

export function checkCopies(policy, texts) {
  const errors = [];
  const sections = policy.body.requiredSections;
  const run = (fn) => collect(errors, fn);
  const gate = compositeChecks(policy, texts.gateRun, texts.gateAction, "gate composite", {
    labeled: true,
  });
  run(gate.sections);
  run(gate.patterns);
  run(gate.types);
  run(gate.requireScope);
  run(() =>
    assertExactSections(
      parseValidatorSections(texts.hookValidator, "hook validator"),
      sections,
      "hook validator",
    ),
  );
  run(() =>
    assertContainsSections(parseMarkdownHeadings(texts.orgTemplate), sections, "org PR template"),
  );
  run(() => assertMentions(texts.orgTemplate, ["Closes"], "org PR template (closing keyword)"));
  run(() =>
    assertMentionsAnyRendered(
      texts.orgTemplate,
      policy.body.noIssueMarkers,
      "org PR template (no-issue markers)",
    ),
  );
  run(() =>
    assertPatternsEnforce(
      parseValidatorPatterns(texts.hookValidator, "hook validator"),
      policy,
      "hook validator (enforcement patterns)",
      { lowercaseProbe: true },
    ),
  );
  run(gate.nonClosing);
  run(gate.negation);
  run(() =>
    assertNonClosing(
      parseValidatorNonClosing(texts.hookValidator, "hook validator (non-closing markers)"),
      policy,
      "hook validator (non-closing markers)",
    ),
  );
  run(() =>
    assertNegation(
      parseValidatorNegation(texts.hookValidator, "hook validator (negated closers)"),
      policy,
      "hook validator (negated closers)",
    ),
  );
  run(gate.issueRefDefault);
  run(gate.behavior);
  run(gate.verdictReads);
  run(() => checkHookBehavior(texts.hookValidator, policy, "hook validator (behavior)"));
  return errors;
}

function pinLabel(sha) {
  return sha === "main" ? "at main" : `pin ${sha.slice(0, 7)}`;
}

export function checkPinnedReusable(policy, repo, sha, reusableText) {
  const location = `caller ${repo} ${pinLabel(sha)}`;
  const errors = [];
  const run = (fn) => collect(errors, fn);
  run(() =>
    assertExactSections(
      parseGateSections(reusableText, location),
      policy.body.requiredSections,
      location,
    ),
  );
  run(() => assertPatternsEnforce(parseGatePatterns(reusableText, location), policy, location));
  return errors;
}

export function checkPinnedComposite(policy, repo, sha, runShText, actionYmlText) {
  const location = `caller ${repo} ${pinLabel(sha)}`;
  const errors = [];
  const checks = compositeChecks(policy, runShText, actionYmlText, location, { labeled: false });
  for (const check of Object.values(checks)) {
    collect(errors, check);
  }
  return errors;
}

export function checkFleet(policy, resolutions) {
  const errors = [];
  for (const repo of CONSUMER_REPOSITORIES) {
    const resolution = resolutions.get(repo);
    if (resolution === undefined) {
      errors.push(`caller ${repo}: the fleet scan produced no artifact resolution`);
      continue;
    }
    if (resolution.kind === "unresolved") {
      continue;
    }
    if (resolution.kind === "none") {
      errors.push(
        `caller ${repo}: no check-contract composite step and no pr-issue-linkage caller`,
      );
      continue;
    }
    if (resolution.kind === "composite") {
      errors.push(
        ...checkPinnedComposite(
          policy,
          repo,
          resolution.sha,
          resolution.runSh,
          resolution.actionYml,
        ),
      );
      continue;
    }
    errors.push(...checkPinnedReusable(policy, repo, resolution.sha, resolution.reusable));
  }
  return errors;
}

function apiHeaders(accept) {
  const token = process.env.LOCKSTEP_GITHUB_TOKEN || process.env.GITHUB_TOKEN;
  const headers = { Accept: accept };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  return headers;
}

async function fetchWithRetry(url, accept, { notFoundIsNull = false } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(url, { headers: apiHeaders(accept) });
      if (response.ok) {
        return response;
      }
      if (notFoundIsNull && response.status === 404) {
        return null;
      }
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    if (attempt < 3) {
      await new Promise((resolve) => setTimeout(resolve, attempt * 2000));
    }
  }
  throw new FetchError(`fetch-error: ${url}: ${lastError.message}`);
}

async function fetchText(url) {
  const response = await fetchWithRetry(url, "application/vnd.github.raw+json");
  return await response.text();
}

async function fetchTextOrNull(url) {
  const response = await fetchWithRetry(url, "application/vnd.github.raw+json", {
    notFoundIsNull: true,
  });
  return response === null ? null : await response.text();
}

export async function readGateComposite(readOrNull) {
  const read = async (file) => {
    const url = contentsUrl("ci-workflows", "main", `${COMPOSITE_DIRECTORY}/${file}`);
    const text = await readOrNull(url);
    if (text === null) {
      throw new FetchError(`fetch-error: ${url}: HTTP 404`);
    }
    return text;
  };
  return { gateRun: await read("run.sh"), gateAction: await read("action.yml") };
}

async function fetchDirectory(url) {
  const response = await fetchWithRetry(url, "application/vnd.github+json", {
    notFoundIsNull: true,
  });
  if (response === null) {
    return [];
  }
  return await response.json();
}

function scanOrder(names) {
  const rank = (name) => {
    const index = WORKFLOW_SCAN_PRIORITY.indexOf(name);
    return index === -1 ? WORKFLOW_SCAN_PRIORITY.length : index;
  };
  return [...names].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
}

async function listWorkflowNames(repo) {
  const entries = await fetchDirectory(`${API_BASE}/${repo}/contents/.github/workflows?ref=main`);
  return entries
    .filter((entry) => entry.type === "file" && /\.ya?ml$/.test(entry.name))
    .map((entry) => entry.name);
}

export async function resolveConsumerArtifact(repo, cachedText, listNames = listWorkflowNames) {
  const names = await listNames(repo);
  let reusable = null;
  for (const name of scanOrder(names)) {
    const text = await cachedText(contentsUrl(repo, "main", `.github/workflows/${name}`));
    const found = detectArtifactPin(text);
    if (!found) {
      continue;
    }
    if (found.kind === "composite") {
      return found;
    }
    reusable ??= found;
  }
  return reusable ?? { kind: "none" };
}

export const MODES = ["copies", "pins"];

export function parseMode(argv) {
  if (argv.length !== 1 || !MODES.includes(argv[0])) {
    throw new Error(`usage: lockstep-drift.mjs <${MODES.join("|")}>`);
  }
  return argv[0];
}

export function requirePinScanToken(env) {
  if (!(env.LOCKSTEP_GITHUB_TOKEN || env.GITHUB_TOKEN)) {
    throw new FetchError(
      "fetch-error: the pin scan reads private gate callers and needs LOCKSTEP_GITHUB_TOKEN or GITHUB_TOKEN; neither is set",
    );
  }
}

async function readPolicy() {
  return parseUniqueJson(await readFile(POLICY_PATH, "utf8"), POLICY_PATH);
}

function cachedFetcher(fetcher) {
  const cache = new Map();
  return async (url) => {
    if (!cache.has(url)) {
      cache.set(url, await fetcher(url));
    }
    return cache.get(url);
  };
}

export function checkGeneratedTemplate(policy, orgTemplate, committedTemplates) {
  return orgTemplate === renderTemplate(policy) || committedTemplates.includes(orgTemplate)
    ? []
    : [
        "org PR template: matches neither this branch's generated template nor any version committed on standards main; change policy.json here and let the sync deliver it",
      ];
}

const GENERATED_TEMPLATE_PATH = "components/pr-convention-policy/PULL_REQUEST_TEMPLATE.md";
const TEMPLATE_HISTORY_DEPTH = 10;

async function readCommittedTemplates() {
  const response = await fetchWithRetry(
    `${API_BASE}/standards/commits?sha=main&path=${GENERATED_TEMPLATE_PATH}&per_page=${TEMPLATE_HISTORY_DEPTH}`,
    "application/vnd.github+json",
  );
  const commits = await response.json();
  return Promise.all(
    commits.map((commit) =>
      fetchText(contentsUrl("standards", commit.sha, GENERATED_TEMPLATE_PATH)),
    ),
  );
}

export async function runCopyCheck() {
  const policy = await readPolicy();
  const orgTemplate = await fetchText(COPY_SOURCES.orgTemplate);
  const committedTemplates = await readCommittedTemplates();
  return [
    ...checkCopies(policy, {
      ...(await readGateComposite(fetchTextOrNull)),
      hookValidator: await fetchText(COPY_SOURCES.hookValidator),
      orgTemplate,
    }),
    ...checkGeneratedTemplate(policy, orgTemplate, committedTemplates),
  ];
}

export async function runPinScan(env = process.env) {
  requirePinScanToken(env);
  const policy = await readPolicy();
  const cachedText = cachedFetcher(fetchText);
  const errors = [];

  const resolutions = new Map();
  for (const repo of CONSUMER_REPOSITORIES) {
    try {
      const found = await resolveConsumerArtifact(repo, cachedText);
      if (found.kind === "none") {
        resolutions.set(repo, found);
        continue;
      }
      if (found.kind === "composite") {
        const source = found.local ? repo : "ci-workflows";
        const ref = found.sha;
        resolutions.set(repo, {
          kind: "composite",
          sha: found.sha,
          runSh: await cachedText(contentsUrl(source, ref, `${COMPOSITE_DIRECTORY}/run.sh`)),
          actionYml: await cachedText(
            contentsUrl(source, ref, `${COMPOSITE_DIRECTORY}/action.yml`),
          ),
        });
        continue;
      }
      resolutions.set(repo, {
        kind: "reusable",
        sha: found.sha,
        reusable: await cachedText(contentsUrl("ci-workflows", found.sha, REUSABLE_PATH)),
      });
    } catch (error) {
      if (!(error instanceof FetchError) && !(error instanceof DriftError)) {
        throw error;
      }
      resolutions.set(repo, { kind: "unresolved" });
      errors.push(`caller ${repo}: ${error.message}`);
    }
  }

  errors.push(...checkFleet(policy, resolutions));
  return errors;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    const mode = parseMode(process.argv.slice(2));
    const errors = await (mode === "copies" ? runCopyCheck() : runPinScan());
    if (errors.length > 0) {
      for (const message of errors) {
        // biome-ignore lint/suspicious/noConsole: CLI drift output is this script's interface
        console.error(`drift: ${message}`);
      }
      process.exit(1);
    }
    // biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
    console.log(
      `pr-convention lockstep: every ${mode === "copies" ? "copy" : "consumer pin"} matches policy.json`,
    );
  } catch (error) {
    // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
    console.error(error.message);
    process.exit(1);
  }
}
