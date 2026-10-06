#!/usr/bin/env node

// Lockstep drift check (ADR-0008): `policy.json` is the canonical record of
// the fleet PR convention, but other copies of the contract exist and must
// change in lockstep with it — the ci-workflows `pr-contract` composite (the
// live gate every consumer runs inside its `ci-status` job), the
// source-control plugin's PreToolUse validator, the org `.github` PR
// template, and this repository's distributed
// `.claude/rules/pr-body-contract.md`. Letting any copy drift is exactly the
// failure #393 recorded (and claude-code-plugins#3205 repeated). This check
// also dereferences every consumer's pinned artifact and validates the
// contract AT THAT PIN, because a stale pin enforcing an older contract (the
// codex-plugins v0.9.1 case) is drift no source-copy diff can see.
//
// Phase 3 of the ci-perf program (github-iac#396) moves the fleet from the
// `pr-issue-linkage.yml` reusable to the `pr-contract` composite, one
// repository at a time. A consumer therefore runs one artifact or the other,
// never both, for the days that transition takes: the fleet scan detects
// which one a repository uses and checks the contract with the matching
// extractor, so a mixed fleet passes and a drifted artifact of either kind
// still fails.
//
// CLI mode fetches live sources over the GitHub contents API and exits
// non-zero on drift; every network failure is a distinct `fetch-error`
// failure, never a skip. Parsing and comparison logic is exported for the
// hermetic fixture tests in `lockstep-drift.test.mjs`.

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { parse as parseYaml } from "yaml";

import { parseUniqueJson } from "./pr-convention-policy.mjs";

const MODULE_DIRECTORY = import.meta.dirname;
const POLICY_PATH = path.join(MODULE_DIRECTORY, "policy.json");
const RULES_FILE_PATH = path.join(
  MODULE_DIRECTORY,
  "..",
  "..",
  ".claude",
  "rules",
  "pr-body-contract.md",
);

// Contents-API URLs, not raw.githubusercontent: several consumers are private
// repositories, and the API honors the token `LOCKSTEP_GITHUB_TOKEN` (or
// `GITHUB_TOKEN`) that the CI lane mints from the org GitHub App. Public
// sources still resolve unauthenticated.
const API_BASE = "https://api.github.com/repos/melodic-software";
const contentsUrl = (repo, ref, filePath) => `${API_BASE}/${repo}/contents/${filePath}?ref=${ref}`;

// The ci-workflows naming rename moves the composite; until every consumer
// repins, a pin may name either path. The renamed path comes first.
export const COMPOSITE_DIRECTORIES = [
  ".github/actions/pr-require-checks/check-contract",
  ".github/actions/pr-contract",
];
const REUSABLE_PATH = ".github/workflows/pr-issue-linkage.yml";

export const COPY_SOURCES = {
  hookValidator: contentsUrl(
    "claude-code-plugins",
    "main",
    "plugins/source-control/hooks/pr-linkage-validator.sh",
  ),
  orgTemplate: contentsUrl(".github", "main", ".github/PULL_REQUEST_TEMPLATE.md"),
};

// Every repository in the fleet, whether or not it is gated today.
export const CONSUMER_REPOSITORIES = [
  ".github",
  "agent-plugins",
  "ci-runner",
  "ci-workflows",
  "claude-code-plugins",
  "claude-code-proxy",
  "codex-plugins",
  "cursor-plugins",
  "dotfiles",
  "github-iac",
  "medley",
  "provisioning",
  "standards",
];

// There is no exemption: every repository above must run one of the two
// contract artifacts, and running neither is drift. agent-plugins,
// claude-code-proxy and cursor-plugins were carried as a non-failing report
// while they sat outside the org `ci-gate` ruleset; `sync-manifest.yml` records
// that github-iac#367 extended the ruleset to all three and that each carries
// the required contexts, so a lost caller there is as much a gate removal as
// anywhere else. Fail closed.

// The composite is called from the `ci-status` job, which lives in
// `pr-require-checks.yml` after the rename, `ci.yml` before it, and
// `ci-status.yml` in medley. Scanning these first, in this order, lets the
// common case short-circuit instead of reading a whole workflow directory.
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
    errors.push(error.message);
  }
}

// ---------------------------------------------------------------------------
// The `pr-contract` composite (the live gate, and every migrated consumer).
//
// `run.sh` states the section list as data: the analyzer's END block calls
// `section_report("<name>")` once per required section, in contract order.
// ---------------------------------------------------------------------------
export function parseCompositeSections(runShText, location) {
  const names = [...runShText.matchAll(/section_report\("([^"]+)"\)/g)].map((m) => m[1]);
  if (names.length === 0) {
    throw new DriftError(`${location}: no \`section_report("<name>")\` calls found in run.sh`);
  }
  return names;
}

// The composite's keyword and marker enforcement are executable awk regex
// literals, so they are validated FUNCTIONALLY the same way the reusable's
// were: extract each declared pattern and probe it with every policy
// keyword/marker. A keyword that survives only in a comment or an error
// message no longer passes.
export function parseCompositePatterns(runShText, location) {
  const keyword = runShText.match(/match\(chunk, \/(.+)\/\)\) break/);
  const marker = runShText.match(/tolower\(body\) ~ \/(.+)\/\) print "no-issue"/);
  if (!keyword || !marker) {
    throw new DriftError(
      `${location}: closing-keyword / no-issue-marker match expressions not found in run.sh`,
    );
  }
  // Both awk patterns are lowercase and match against text the analyzer has
  // already lowercased (`lower = tolower(line)` for the keyword scan,
  // `tolower(body)` in the anchor above for the marker). The probes below
  // lowercase to mirror that. If the lowercasing ever went away the extracted
  // pattern would become case-sensitive against raw text and reject the
  // documented capitalized forms, so its presence is asserted rather than
  // assumed — the composite's equivalent of the reusable's `i` flag.
  if (!/lower = tolower\(line\)/.test(runShText)) {
    throw new DriftError(
      `${location}: the closing-keyword scan no longer lowercases the line (\`lower = tolower(line)\`), so the extracted pattern is not the one the gate applies`,
    );
  }
  return { keyword: new RegExp(keyword[1]), marker: new RegExp(marker[1]) };
}

function parseActionYml(actionYmlText, location) {
  try {
    return parseYaml(actionYmlText);
  } catch (error) {
    throw new DriftError(`${location}: action.yml is not parsable YAML: ${error.message}`);
  }
}

// `action.yml`'s `inputs.types.default` is the composite's copy of
// `policy.json`'s `allowedTypes`: the title regex is built from it at runtime,
// and no caller in the fleet overrides it. Parsed as YAML rather than by
// regex so the anchor is the data key, not the shape of the description block
// above it.
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

// `inputs.require-scope.default` is the composite's copy of `policy.json`'s
// `title.requireScope`, and the title regex makes the scope group mandatory
// when it is `true`. A composite release that flipped it would reject every
// unscoped title fleet-wide while the section and type checks still reported
// agreement. YAML gives back a string for the quoted `'false'` the composite
// declares and a boolean for a bare `false`; both are accepted, anything else
// is drift rather than a coerced guess.
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

// ---------------------------------------------------------------------------
// The `pr-issue-linkage.yml` reusable (the predecessor, still pinned by every
// consumer that has not taken its Phase 3 pull request yet).
//
// The reusable declares its contract as a `requiredSections` array of
// `{ name: "...", guidance: "..." }` literals inside an actions/github-script
// step. The array literal is the narrowest stable surface to parse.
// ---------------------------------------------------------------------------
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
  // Accept any declared flag set rather than a literal `/i;`: ci-workflows made
  // CLOSING_KEYWORD global (`/gi;`, so every occurrence on a line can be
  // classified) and the old literal match turned a healthy gate into
  // "declarations not found" — a parse failure wearing a drift error's clothes.
  //
  // Flags are CAPTURED, not discarded, because they are behavior. Both bodies are
  // lowercase and depend on `i` to accept the documented capitalized keyword forms;
  // rebuilding the probe with a hardcoded `i` would silently pass a gate that had
  // dropped it and become case-sensitive, which is exactly the enforcement drift this check
  // exists to catch. `g` and `y` are the one exception, stripped below.
  const keyword = workflowText.match(/const CLOSING_KEYWORD =\s*\/(.+)\/([dgimsuvy]*);/);
  const marker = workflowText.match(/const NO_ISSUE_MARKER =\s*\/(.+)\/([dgimsuvy]*);/);
  if (!keyword || !marker) {
    throw new DriftError(
      `${location}: CLOSING_KEYWORD / NO_ISSUE_MARKER regex declarations not found`,
    );
  }
  // `g` and `y` make `.test()` stateful via lastIndex, and assertPatternsEnforce
  // probes each pattern once per policy keyword, so a retained `g` would make
  // every probe after the first read a moved cursor instead of the pattern.
  // Neither flag changes WHAT the pattern matches, so dropping them is safe.
  const probeFlags = (flags) => flags.replaceAll(/[gy]/g, "");
  return {
    keyword: new RegExp(keyword[1], probeFlags(keyword[2])),
    marker: new RegExp(marker[1], probeFlags(marker[2])),
  };
}

// ---------------------------------------------------------------------------
// The other two remote copies.
// ---------------------------------------------------------------------------

// The hook validator declares `REQUIRED_SECTIONS=(Summary Fix ...)`.
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

// The hook validator's enforcement is a pair of POSIX ERE strings, its
// `scan_linkage` transcription of the composite's `scan_line`; translate the
// POSIX classes they use and probe them the same way. The probes pad with
// spaces because NO_ISSUE_ERE guards with [^a-z0-9_] boundary classes. Both
// EREs are lowercase, so every `=~` against them must read a lowercased
// operand, as the composite's `tolower` is asserted: CLOSING_ERE only on
// `$chunk` (a slice of `lower="${line,,}"`), NO_ISSUE_ERE only on `$lower`
// (`${1,,}` wrapped in newlines). A match on the raw line is drift.
// NON_CLOSING_ERE is matched one line at a time against `$lower`, the same
// lowercased line CLOSING_ERE's `$chunk` is sliced from.
const VALIDATOR_OPERANDS = {
  // biome-ignore lint/suspicious/noTemplateCurlyInString: bash parameter expansions, not JS placeholders
  CLOSING_ERE: { operand: "chunk", sources: ['lower="${line,,}"', 'chunk="${lower:off}"'] },
  NO_ISSUE_ERE: { operand: "lower", sources: [`lower=$'\\n'"\${1,,}"$'\\n'`] },
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a bash parameter expansion, not a JS placeholder
  NON_CLOSING_ERE: { operand: "lower", sources: ['lower="${line,,}"'] },
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
  // Line-anchored, so the sibling NON_CLOSING_ERE declaration never matches.
  const keyword = shellText.match(/^CLOSING_ERE='([^']+)'/m);
  const marker = shellText.match(/^NO_ISSUE_ERE='([^']+)'/m);
  if (!keyword || !marker) {
    throw new DriftError(`${location}: CLOSING_ERE / NO_ISSUE_ERE declarations not found`);
  }
  assertValidatorOperand(shellText, "CLOSING_ERE", location);
  assertValidatorOperand(shellText, "NO_ISSUE_ERE", location);
  return { keyword: ereToJs(keyword[1]), marker: ereToJs(marker[1]) };
}

// ---------------------------------------------------------------------------
// Non-closing references and negated closers (`body.nonClosingMarkers` and
// `body.negatedClosers`). The composite and the hook both implement them; the
// hook's are a transcription of the composite's, so both copies are checked
// against the policy the same way.
// ---------------------------------------------------------------------------

// A declared pattern or helper proves nothing on its own: the copy must call
// it and act on the result, or the rule is dead code and a parse of its body
// is a false green. Each entry is one link of that chain, from the call site
// to the verdict, quoted from the live source.
const WIRING = {
  compositeNonClosing: [
    ["scan_line runs on every masked line", /scan_line\(masked\[i\]\)/],
    ["a marker match sets has_non_closing", /rest ~ \/.+\/\) \{\s*has_non_closing = 1/],
    ["has_non_closing is reported", /if \(has_non_closing\) print "non-closing"/],
    [
      "a non-closing report satisfies linkage",
      /if ! grep -qx 'closing' "\$analysis" &&\s*! grep -qx 'non-closing' "\$analysis" &&\s*! grep -qx 'no-issue' "\$analysis"; then/,
    ],
  ],
  compositeNegation: [
    ["scan_line runs on every masked line", /scan_line\(masked\[i\]\)/],
    [
      "negation_trigger is called on each closing reference and branched on",
      /trigger = negation_trigger\(line, start\)\s*\n\s*if \(trigger != ""\) \{/,
    ],
    [
      "a negated reference is recorded and never counted as closing",
      /if \(trigger != ""\) \{[\s\S]*?negated_count\+\+[\s\S]*?\}\s*\} else \{\s*has_closing = 1\s*\}/,
    ],
    ["negated references are reported", /print "negated\\t" negated_order\[i\]/],
    [
      "a negated report is a linkage error",
      /\[\[ "\$kind" == negated \]\][\s\S]*?linkage_errors\+=\("Negated closing reference/,
    ],
  ],
  validatorNonClosing: [
    ["a marker match counts as linkage", /\[\[ "\$lower" =~ \$NON_CLOSING_ERE \]\] && found=0/],
    ["scan_linkage returns success on linkage", /\(\(found == 0\)\) && return 0/],
    ["scan_linkage decides linkage", /scan_linkage "\$_plv_body" \|\| _plv_linked=1/],
  ],
  validatorNegation: [
    [
      "negation_trigger_to is called on each closing reference and only an empty result counts",
      /negation_trigger_to _plv_trigger "\$\{line:0:start\}"\s*\n\s*if \[\[ -z "\$_plv_trigger" \]\]; then\s*found=0\s*continue\s*fi/,
    ],
    ["a negated reference is recorded", /LINKAGE_NEGATED\+=\(/],
    [
      "a recorded negated reference is a linkage problem",
      /\(\(\$\{#LINKAGE_NEGATED\[@\]\} == 0\)\) \|\| \{[\s\S]*?LINKAGE_PROBLEMS\+=\("Negated closing reference/,
    ],
  ],
};

function assertWired(text, chain, location) {
  const missing = WIRING[chain].filter(([, pattern]) => !pattern.test(text));
  if (missing.length > 0) {
    throw new DriftError(
      `${location}: the rule is not wired in: ${missing.map(([link]) => link).join("; ")}`,
    );
  }
}

// The marker alternation is the first group of the pattern, after the `^`
// anchor and the hook's `{0,3}` indent allowance (the composite strips that
// indent before matching). A multi-word marker spells its gap as a blank-class
// run; it is read back as one space so it compares to the policy's spelling.
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
  assertValidatorOperand(shellText, "NON_CLOSING_ERE", location);
  assertWired(shellText, "validatorNonClosing", location);
  return {
    markers: nonClosingAlternation(declaration[1], location),
    pattern: ereToJs(declaration[1]),
  };
}

export function parseCompositeNonClosing(runShText, location) {
  const declaration = runShText.match(/rest ~ \/(.+)\/\) \{\s*has_non_closing = 1/);
  if (!declaration) {
    throw new DriftError(
      `${location}: the \`rest ~ /.../\` non-closing marker test (has_non_closing = 1) was not found in run.sh`,
    );
  }
  // `rest` is the lowercased line with up to three leading spaces removed;
  // without either step the extracted pattern is not the rule the gate applies.
  if (
    !runShText.includes("if (indent <= 3)") ||
    !runShText.includes("rest = tolower(substr(line, indent + 1))")
  ) {
    throw new DriftError(
      `${location}: the non-closing marker test no longer reads the lowercased, indent-stripped line (\`rest = tolower(substr(line, indent + 1))\` under \`indent <= 3\`)`,
    );
  }
  assertWired(runShText, "compositeNonClosing", location);
  return {
    markers: nonClosingAlternation(declaration[1], location),
    pattern: new RegExp(declaration[1]),
  };
}

// The awk program is single-quoted bash, so an apostrophe inside it is spelled
// `'"'"'`; read it back as the apostrophe awk sees.
const unquoteAwk = (text) => text.replaceAll(`'"'"'`, "'");

export function parseValidatorNegation(shellText, location) {
  const window = shellText.match(/\(\(n > (\d+)\)\) && first=\$\(\(n - (\d+)\)\)/);
  const affirmative = shellText.match(
    /\[\[ "\$lower" == (\w+) \]\] && \(\(i \+ 1 < n\)\) && \[\[ "\$\{words\[i \+ 1\],,\}" == (\w+) \]\] && continue/,
  );
  const cases = shellText.match(/case "\$lower" in\s*\n\s*([^\n)]+)\)/);
  if (!window || !affirmative || !cases) {
    throw new DriftError(
      `${location}: negation_trigger_to's window, "not only" exception, or trigger \`case\` not found`,
    );
  }
  if (window[1] !== window[2]) {
    throw new DriftError(
      `${location}: negation_trigger_to's window is inconsistent (n > ${window[1]}, first = n - ${window[2]})`,
    );
  }
  assertWired(shellText, "validatorNegation", location);
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

export function parseCompositeNegation(runShText, location) {
  const window = runShText.match(/first = \(count > (\d+)\) \? count - (\d+) : 1/);
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
  // awk is 1-indexed: `count - (W - 1)` through `count` is the last W words,
  // and `length(word) - (L - 1)` is the start of an L-character suffix.
  if (Number(window[2]) !== Number(window[1]) - 1) {
    throw new DriftError(
      `${location}: negation_trigger's window is inconsistent (count > ${window[1]}, first = count - ${window[2]})`,
    );
  }
  if (Number(suffix[1]) !== suffix[2].length - 1) {
    throw new DriftError(
      `${location}: negation_trigger's suffix test reads ${Number(suffix[1]) + 1} characters for the ${suffix[2].length}-character "${suffix[2]}"`,
    );
  }
  assertWired(runShText, "compositeNegation", location);
  return {
    triggerWords: [...triggers[1].matchAll(/lower == "(\w+)"/g)].map((m) => m[1]),
    triggerSuffixes: [suffix[2]],
    affirmativePhrases: [`${affirmative[1]} ${affirmative[2]}`],
    wordWindow: Number(window[1]),
  };
}

// ---------------------------------------------------------------------------
// Which artifact a consumer runs.
// ---------------------------------------------------------------------------

// Every pattern below anchors on a `uses:` entry with no `#` earlier on the
// line, so only a live call site counts. The same paths appear elsewhere in
// ci-workflows' own `ci.yml` as a lint `paths:` list and as a
// `bash .github/actions/pr-contract/run.test.sh` command, and a migration
// leaves commented-out call sites behind; either one would otherwise select an
// artifact the repository does not run and suppress the one it does.
const USES_PREFIX = String.raw`^[^#\n]*\buses:\s*`;
const COMPOSITE_DIRECTORY_GROUP = `(${COMPOSITE_DIRECTORIES.map((directory) =>
  directory.replaceAll(".", "\\."),
).join("|")})`;
// A `uses:` of the composite, pinned to a 40-hex ci-workflows SHA.
const COMPOSITE_PIN_PATTERN = new RegExp(
  `${USES_PREFIX}melodic-software/ci-workflows/${COMPOSITE_DIRECTORY_GROUP}@([0-9a-f]{40})`,
  "m",
);
// ci-workflows dogfoods its own composite through a local `./` reference,
// which carries no SHA — the artifact is that repository's own tree at `main`.
const COMPOSITE_LOCAL_PATTERN = new RegExp(
  `${USES_PREFIX}\\./${COMPOSITE_DIRECTORY_GROUP}(?=\\s|$)`,
  "m",
);
const REUSABLE_PIN_PATTERN = new RegExp(
  `${USES_PREFIX}\\S*pr-issue-linkage\\.yml@([0-9a-f]{40})`,
  "m",
);

// The composite wins over the reusable: during the Phase 3 transition
// ci-workflows carries both (its `pr-issue-linkage-self.yml` caller stays
// until 3.4), and the artifact that gates is the one inside `ci-status`.
export function detectArtifactPin(workflowText) {
  const pinned = workflowText.match(COMPOSITE_PIN_PATTERN);
  if (pinned) {
    return { kind: "composite", sha: pinned[2], directory: pinned[1] };
  }
  const local = workflowText.match(COMPOSITE_LOCAL_PATTERN);
  if (local) {
    return { kind: "composite", sha: "main", directory: local[1] };
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

// ---------------------------------------------------------------------------
// Comparisons.
// ---------------------------------------------------------------------------

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

// The declared marker alternation must be exactly the policy's set, and the
// pattern must behave as the policy describes: each marker links on a line of
// its own (bare or cross-repository reference, either case), and the same
// text mid-sentence or followed by prose does not.
function assertNonClosing({ markers, pattern }, policy, location) {
  const expected = policy.body.nonClosingMarkers.map((marker) => marker.toLowerCase());
  const difference = setDifference(markers, expected);
  const problems = difference === "" ? [] : [`markers ${difference}`];
  for (const marker of policy.body.nonClosingMarkers) {
    for (const accepted of [`${marker}: #12`, `${marker}: owner/repo#12`, `${marker}:#12  `]) {
      if (!pattern.test(accepted.toLowerCase())) {
        problems.push(`rejects "${accepted}"`);
      }
    }
    for (const rejected of [`see ${marker}: #12`, `${marker}: #12 and more`, `${marker} #12`]) {
      if (pattern.test(rejected.toLowerCase())) {
        problems.push(`accepts "${rejected}", which is not a marker on its own line`);
      }
    }
  }
  if (problems.length > 0) {
    throw new DriftError(`${location}: non-closing pattern ${problems.join(", ")}`);
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

// Order is not behavior here — the composite builds a regex alternation from
// the list — so the comparison is set-wise and the message names the exact
// divergence rather than printing two lists to diff by eye.
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

function assertMentionsAny(text, terms, location) {
  if (!terms.some((term) => text.includes(term))) {
    throw new DriftError(`${location}: mentions none of: ${terms.join(", ")}`);
  }
}

// The `pr-contract` composite masks fenced and indented code blocks and inline
// code spans before matching a PR body, so an escape an author copies verbatim
// from a backticked template is invisible to the gate and the PR draws the
// advisory `needs-issue-linkage` label with no visible cause (.github#135). The
// composite's masker cannot be shared: it is an awk program embedded in a bash
// composite in ci-workflows, read here only as fetched text, and it also masks
// HTML comments — which the org template uses as its guidance surface by
// design. This mirrors the composite's code-span and code-block rules only,
// deliberately leaving HTML comments rendered.
//
// Inline spans follow the composite's `has_closing_run`: a run of N backticks
// opens a span only when a run of exactly N appears later on the same line; an
// unmatched run is literal text. Block detection is suppressed inside an HTML
// comment, as the composite suppresses it, so a fenced example in the
// template's guidance comment cannot open a fence that swallows the rest of
// the file. Inline spans are still masked there, because that is where the
// backticked escape .github#135 removed was written.
export function maskCode(text) {
  let fenceChar = "";
  let fenceLength = 0;
  let commentOpen = false;
  return text
    .split("\n")
    .map((raw) => {
      const line = raw.replace(/\r$/, "");
      const blocksApply = !commentOpen;
      // Spaces only, as the composite counts them: a tab-indented line is
      // indented code to it, never a fence marker.
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
      // The same line with code-span content blanked rather than removed, so
      // its offsets still line up with the raw line's.
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

      // Comment state is tracked only on lines that reach here, because the
      // composite tracks it in the same character loop it never runs on a line
      // inside a code block. It is also asymmetric there, and mirrored as such:
      // an opener is honored only outside a code span, a closer anywhere. Both
      // offsets are read in the raw line's coordinate space so they compare.
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

// One drift verdict per copy; every check runs so a single invocation reports
// the whole divergence set instead of the first hit.
export function checkCopies(policy, texts) {
  const errors = [];
  const sections = policy.body.requiredSections;
  const run = (fn) => collect(errors, fn);
  run(() =>
    assertExactSections(
      parseCompositeSections(texts.gateRun, "gate composite"),
      sections,
      "gate composite",
    ),
  );
  run(() =>
    assertPatternsEnforce(
      parseCompositePatterns(texts.gateRun, "gate composite"),
      policy,
      "gate composite (enforcement patterns)",
      { lowercaseProbe: true },
    ),
  );
  run(() =>
    assertAllowedTypes(
      parseCompositeTypes(texts.gateAction, "gate composite"),
      policy.title.allowedTypes,
      "gate composite (title types)",
    ),
  );
  run(() =>
    assertRequireScope(
      parseCompositeRequireScope(texts.gateAction, "gate composite"),
      policy.title.requireScope,
      "gate composite (require-scope)",
    ),
  );
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
  // The rules file names the section headings in prose (backticked, inside
  // bullets), not as its own document headings — a mention check, not a
  // heading parse.
  run(() =>
    assertMentions(
      texts.rulesFile,
      sections.map((name) => `## ${name}`),
      "rules file (sections)",
    ),
  );
  run(() =>
    assertMentions(texts.rulesFile, policy.body.closingKeywords, "rules file (closing keywords)"),
  );
  // The rules file and the org PR template are guidance, not enforcement: each
  // must steer an author to at least one accepted opt-out marker, not
  // enumerate every accepted phrasing. Naming more than one gives the author a
  // choice the gate never asked for, and `policy.json` keeps the full accepted
  // set for the artifacts that do enforce it. The rules file names its marker
  // as prose markup and is never copied into a PR body, so it is matched as
  // written; the template is copied verbatim, so its marker is matched after
  // masking.
  run(() =>
    assertMentionsAny(texts.rulesFile, policy.body.noIssueMarkers, "rules file (no-issue markers)"),
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
  run(() =>
    assertNonClosing(
      parseCompositeNonClosing(texts.gateRun, "gate composite (non-closing markers)"),
      policy,
      "gate composite (non-closing markers)",
    ),
  );
  run(() =>
    assertNegation(
      parseCompositeNegation(texts.gateRun, "gate composite (negated closers)"),
      policy,
      "gate composite (negated closers)",
    ),
  );
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
  return errors;
}

function pinLabel(sha) {
  return sha === "main" ? "local at main" : `pin ${sha.slice(0, 7)}`;
}

// Validates the full contract at the pin — sections AND the executable
// keyword/marker patterns — so a pinned reusable whose section list matches
// current policy but whose keyword or marker enforcement is stale still
// reports drift. The non-closing and negated-closer rules are not checked
// here: the reusable is the transition-only predecessor, it gained them only
// late (ci-workflows#544) and states them in JavaScript this module has no
// extractor for, and the composite carries them at every pin since v0.20.0.
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

// The composite's equivalent: sections, enforcement patterns, the non-closing
// marker test and the negation rule from `run.sh`, allowed title types and
// `require-scope` from `action.yml`. Both title axes
// are checked at the pin because a consumer pinned to a pre-`security`
// composite would reject a `security:` title that policy allows, and one
// pinned to a `require-scope: true` composite would reject every unscoped
// title — drift the source-copy check on `main` cannot see.
export function checkPinnedComposite(policy, repo, sha, runShText, actionYmlText) {
  const location = `caller ${repo} ${pinLabel(sha)}`;
  const errors = [];
  const run = (fn) => collect(errors, fn);
  run(() =>
    assertExactSections(
      parseCompositeSections(runShText, location),
      policy.body.requiredSections,
      location,
    ),
  );
  run(() =>
    assertPatternsEnforce(parseCompositePatterns(runShText, location), policy, location, {
      lowercaseProbe: true,
    }),
  );
  run(() =>
    assertAllowedTypes(
      parseCompositeTypes(actionYmlText, location),
      policy.title.allowedTypes,
      location,
    ),
  );
  run(() =>
    assertRequireScope(
      parseCompositeRequireScope(actionYmlText, location),
      policy.title.requireScope,
      location,
    ),
  );
  run(() => assertNonClosing(parseCompositeNonClosing(runShText, location), policy, location));
  run(() => assertNegation(parseCompositeNegation(runShText, location), policy, location));
  return errors;
}

// One verdict per consumer over a resolved fleet. `kind: "none"` is a drift
// finding for every repository, with no exemption; `kind: "unresolved"` means
// the live loop already recorded a fetch failure for that repository and this
// pass adds nothing.
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
      errors.push(`caller ${repo}: no pr-contract composite step and no pr-issue-linkage caller`);
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

// ---------------------------------------------------------------------------
// Live mode.
// ---------------------------------------------------------------------------

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
      // A missing `.github/workflows` directory is a fact about the fleet, not
      // a transport failure: the repository simply runs no workflows.
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

// The live gate on ci-workflows `main`, at the first composite path that
// exists there. `readOrNull` returns null for a missing file.
export async function readGateComposite(readOrNull) {
  for (const directory of COMPOSITE_DIRECTORIES) {
    const gateRun = await readOrNull(contentsUrl("ci-workflows", "main", `${directory}/run.sh`));
    if (gateRun === null) {
      continue;
    }
    const actionUrl = contentsUrl("ci-workflows", "main", `${directory}/action.yml`);
    const gateAction = await readOrNull(actionUrl);
    if (gateAction === null) {
      throw new FetchError(`fetch-error: ${actionUrl}: HTTP 404`);
    }
    return { gateRun, gateAction };
  }
  throw new FetchError(
    `fetch-error: ci-workflows main has no composite at ${COMPOSITE_DIRECTORIES.join(" or ")}`,
  );
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

// Reads a repository's workflow directory and returns the artifact it runs.
// The composite short-circuits the scan; a reusable pin is remembered but the
// scan continues, because a repository mid-transition can carry both and the
// composite is the one that gates.
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

export async function runLiveCheck() {
  const policy = parseUniqueJson(await readFile(POLICY_PATH, "utf8"), POLICY_PATH);
  const cache = new Map();
  const cached = (fetcher) => async (url) => {
    if (!cache.has(url)) {
      cache.set(url, await fetcher(url));
    }
    return cache.get(url);
  };
  const cachedText = cached(fetchText);

  const texts = {
    ...(await readGateComposite(cached(fetchTextOrNull))),
    hookValidator: await cachedText(COPY_SOURCES.hookValidator),
    orgTemplate: await cachedText(COPY_SOURCES.orgTemplate),
    rulesFile: await readFile(RULES_FILE_PATH, "utf8"),
  };
  const errors = checkCopies(policy, texts);

  // A consumer whose fetch fails is reported and the loop continues, so one
  // unreachable private repository cannot mask drift findings collected from
  // the rest; any fetch-error still fails the run.
  const resolutions = new Map();
  for (const repo of CONSUMER_REPOSITORIES) {
    try {
      const found = await resolveConsumerArtifact(repo, cachedText);
      if (found.kind === "none") {
        resolutions.set(repo, found);
        continue;
      }
      if (found.kind === "composite") {
        // `main` means a local `./` reference: the artifact is that
        // repository's own tree, which for ci-workflows is the gate source
        // already fetched above (the cache makes this free).
        const source = found.sha === "main" ? repo : "ci-workflows";
        const ref = found.sha;
        resolutions.set(repo, {
          kind: "composite",
          sha: found.sha,
          runSh: await cachedText(contentsUrl(source, ref, `${found.directory}/run.sh`)),
          actionYml: await cachedText(contentsUrl(source, ref, `${found.directory}/action.yml`)),
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

// This block is the CLI entrypoint of a shebang script whose entire contract is
// what it prints and what it exits with, so stdout/stderr are the interface
// rather than stray debugging. noConsole is suppressed per call rather than
// repo-wide, which would blind the rule everywhere else in this component.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    const errors = await runLiveCheck();
    if (errors.length > 0) {
      for (const message of errors) {
        // biome-ignore lint/suspicious/noConsole: CLI drift output is this script's interface
        console.error(`drift: ${message}`);
      }
      process.exit(1);
    }
    // biome-ignore lint/suspicious/noConsole: CLI success line is this script's interface
    console.log("pr-convention lockstep: all copies and consumer pins match policy.json");
  } catch (error) {
    // biome-ignore lint/suspicious/noConsole: CLI failure output is this script's interface
    console.error(error.message);
    process.exit(1);
  }
}
