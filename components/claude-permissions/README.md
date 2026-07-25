# claude-permissions

The fleet's reviewed Claude Code permission floor: one canonical `permissions.allow` /
`permissions.deny` set for agent sessions, distributed as data and composed into each
consumer's live settings by that consumer's own mechanism — never merged by the sync engine.

Boris Cherny's step-2 guardrail names the need verbatim: "Pre-approve common safe bash and
MCP commands in settings.json"
([source](https://docs.google.com/document/d/1R91ayvj7uvlxgNi--__2-Bf3w8x5r1nF-xIBN7ds8Ns/edit)).

## Shape

`claude-permissions.json` — one top-level `claudePermissions` object (a unique key, because
the primary consumer merges the file into a shared template-data namespace) carrying
`schemaVersion`, `allow`, and `deny`:

- **`deny`** — the safety floor: destructive git verbs (force-push, hard reset, clean,
  checkout/restore discards, forced branch deletion, `--no-verify` hook bypass) in both
  `Bash()` and `PowerShell()` rule spellings, bare and starred argument forms; the `gh api`
  DELETE surface for org/repo/security-critical resources; hook-disable environment
  prefixes; network-share mounts; and secret-material `Read()` patterns (key files, env
  files, credential stores) in both bare and `**/`-prefixed forms. The union is deliberately
  the STRICTEST observed form of each rule.
- **`allow`** — grants an unattended agent loop needs that no built-in mechanism carries:
  the routine non-destructive working verbs (add, commit, non-force push, pull,
  checkout/switch, PR and issue CRUD, CI re-runs of already-merged workflow code via
  `gh run rerun`), the babysit lane's gate tooling, and the read-only inspection commands
  Claude Code does *not* pre-approve — every `gh` verb (read-only ones included) and every
  third-party linter. Force/destructive spellings stay covered by `deny`, which always
  wins.

  **Test-suite invocations are deliberately absent.** A test runner executes whatever test
  files are on disk, and an agent session that can write files plus a blanket `pytest`
  grant compose into a general code-execution grant wearing a narrow name — no rule
  grammar can tell a test file the agent wrote this session from one the repository
  already had. Test runs are judged per session instead.

  **Read-only *git* inspection is deliberately absent.** Claude Code recognizes a built-in
  set of Bash commands as read-only and runs them without a permission prompt in every
  mode; the set is not configurable and covers "read-only forms of `git`"
  (<https://code.claude.com/docs/en/permissions>, "Read-only commands"). Floor entries for
  that set are dead weight in every mode, not just under auto. Verified 2026-07-24 on
  Claude Code 2.1.219 in `default` mode with zero settings loaded: `git status`,
  `git diff`, `git log`, `git show`, `git branch`, `git ls-files`, `git merge-base`, and
  `git rev-parse` all ran promptless through both the `Bash` and `PowerShell` tools.

  Membership is not unconditional, so this is cheap rather than free: the same doc section
  lists carve-outs that void the built-in handling even for a member — unquoted globs on
  commands carrying write-capable flags (`git` among them), Windows UNC paths, `cd` into a
  different directory before a `git` call, output redirection, and compound commands. An
  observed instance: `git status; echo "exit status: $?"` was denied while bare
  `git status` ran. Expect occasional prompts on exotic spellings of these verbs.

  **Membership is narrow, and it is command identity — not "looks read-only."** The same
  run denied every `gh` verb (`gh pr view`, `gh issue list`, `gh label list`, `gh pr list`,
  `gh repo view`, `gh run list`, `gh run view`, `gh search`), every linter (`actionlint`,
  `check-jsonschema`, `gitleaks`, `lychee`, `ruff check`, `shellcheck`, `typos`) — even
  bare `--version` and `--help` forms — and `claude plugin list`. Those rules are
  load-bearing. The documented list is explicitly non-exhaustive ("These include…"), so
  **membership must be tested, never inferred from a command being read-only in spirit.**

  **Scope limit — these grants are deterministic only outside auto mode.** Every allow
  entry on this floor is a shell rule (`Bash()` / `PowerShell()`), and a consumer setting
  `autoMode.classifyAllShell: true` suspends *all* shell allow rules
  (<https://code.claude.com/docs/en/auto-mode-config>). In such a session the classifier
  adjudicates each of these actions on its merits and the built-in "External System Writes"
  soft_deny consent-gates the gh write verbs; clearing that for an unattended lane needs a
  prose `autoMode.allow` entry in user or managed settings, which this component does not
  carry. Consumers that route all shell through the classifier must treat this floor as the
  non-auto fallback posture and provide lane grants in prose.

  `deny` is unaffected — `classifyAllShell` suspends allow rules only, so every deny entry
  stays pre-classifier and non-overridable in every mode.

  **The two scope limits above do not collide.** `classifyAllShell` suspends *allow rules*;
  the built-in read-only set is not an allow rule but a separate pre-permission-check step
  (<https://code.claude.com/docs/en/permission-modes> enumerates `permissions.allow` rules,
  read-only Bash commands, and `PreToolUse` hook approvals as three distinct categories),
  so it survives. Verified 2026-07-24 by timing the permission decision: with
  `classifyAllShell: true` in auto mode, an allow-ruled `bash --version` took a 1536 ms
  classifier round-trip while `git status`, `git log`, and `ls` resolved in 4–5 ms —
  bimodal, with nothing in between. This is why trimming read-only git costs nothing under
  the fleet default while trimming anything outside that set would reintroduce prompts.

The `${CLAUDE_PLUGIN_ROOT}` interpreter+script-path allow entries are interim shapes: the
end state is each script exposed as a bare wrapper on the plugin `bin/` PATH so the rule
names the command rather than the interpreter (trigger:
melodic-software/claude-code-plugins#843, the PATH gap fix). Until that lands, both quoted
and unquoted spellings stay pinned here — and bare-wrapper rules stay OUT: the plugin
`bin/` directory is not on the shell's PATH today, and the skill invokes each wrapper as
`bash "${CLAUDE_PLUGIN_ROOT}/bin/<wrapper>"` (claude-code-plugins `3fc72d351c`), so a rule
naming the bare command matches nothing and is dead weight until #843 makes the bare name
resolve. The end state also does not restore pre-classifier handling under
`classifyAllShell: true` — a bare wrapper is still a shell rule. It buys rule clarity and
the non-auto posture, not a classifier bypass.

## Composition model — data component, consumer-owned merge

The sync engine is byte-exact and this file is NOT a Claude Code settings file. No consumer
materializes it as `.claude/settings.json` (every fleet repo's tracked settings carries
repo-specific config an exact overwrite would destroy — verified 2026-07-20). Instead the
component follows the runner-policy handoff pattern: standards owns the invariant data
file; the consumer owns the runtime composition that reads it.

- **User layer (active)**: the dotfiles repository materializes this file into its chezmoi
  data tree and its `~/.claude/settings.json` modify-template unions the canonical rules
  with locally-accumulated ones on every apply. Local additions survive; the floor is
  always present.
- **Machine layer (deferred with trigger)**: materializing the same data through the
  provisioning repository into Claude Code's machine-level managed policy settings would
  make the floor unremovable per machine. Trigger: fleet machines operated by more than one
  person, or an org-enablement adoption — decide placement then against the then-current
  managed-settings precedence semantics.
- A repository needing a stricter or looser posture layers its own project settings; the
  deny floor is not relaxable below this component wherever it is composed in.

## Threat model — what the deny floor is and is not

The deny list pins the COMMON destructive and secret-reaching spellings. The rule grammar is
positional glob matching, so it cannot enumerate every flag permutation a shell command
admits (combined short flags, arbitrary flag positions, values smuggled inside arguments);
treating it as a sandbox is a category error. The floor is one defense-in-depth layer:
below it sit the permission classifier's own category safety checks, and around it sit the
remote-side protections (branch rulesets, force-push denial at the platform, lease-based
worktree isolation). The structural fix for spelling-permutation gaps is classifier-side
command decomposition — a recorded product-surface gap, not something more glob rules can
close. New spellings observed in real sessions land here on sight; adversarial enumeration
beyond the common forms is explicitly out of scope.

## Change discipline

Additions to `allow` require observed-usage evidence (recurring prompt patterns from real
sessions — the auto-mode tuning loop) or a reviewed unattended-lane need; additions to
`deny` ship on sight. Either lands as a reviewed change here and reaches consumers through
the ordinary sync PR.

Before proposing an `allow` addition from an observed prompt, check whether the prompting
session routes shell through the classifier. If it does, a rule here will not stop that
prompt — the fix is a prose `autoMode.allow` entry in the consumer's user or managed
settings. Reserve floor additions for grants that must hold in a non-auto session.

**Removals carry the heavier burden, and only one argument retires an entry: that Claude
Code's built-in read-only set covers the command in every mode.** That claim must be tested
before it is acted on, never inferred — from the command being read-only in spirit, from a
sibling command being covered, or from auto mode's classifier approving it. Auto-mode
coverage is specifically *not* an argument: it does not reach the lanes that never enter
auto mode (workflow subagents, which always run `acceptEdits`; headless `-p`/SDK runs,
where an unapproved call fails with nobody to answer the prompt; and explicitly non-auto
sessions), and under `classifyAllShell: true` it does not confer a pre-classifier
short-circuit on anything. The test:

```sh
claude -p 'Run this exact shell command and report nothing else: <command>' \
  --setting-sources "" --permission-mode default --output-format json
```

`--setting-sources ""` loads no ambient settings, so nothing but the built-in handling can
approve the call. A `permission_denials` entry means the rule is load-bearing and stays; an
empty array means the built-in set covers it and the entry is dead weight. Verify the
binary is on `PATH` first — a denial fires before execution, so an uninstalled tool and a
denied one look alike in the exit status but differ in `permission_denials`. Record the
result in the PR; a removal without one is not reviewable.
