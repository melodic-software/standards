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
- **`allow`** — deterministic grants an unattended agent loop needs that auto mode's
  built-ins do not carry: the routine non-destructive working verbs (add, commit, non-force
  push, pull, checkout/switch, PR and issue CRUD, CI re-runs of already-merged workflow
  code via `gh run rerun`), test invocations (`pytest` forms), and
  the babysit lane's gate tooling. Read-only git/gh inspection and read-only lint tooling
  are deliberately absent: auto mode covers them without prompting through its built-in
  read-only handling (source of truth: `claude auto-mode defaults` and
  <https://code.claude.com/docs/en/auto-mode-config>), so floor entries for that set were
  dead weight. Force/destructive spellings stay covered by `deny`, which always wins.

The `${CLAUDE_PLUGIN_ROOT}` interpreter+script-path allow entries are interim shapes: the
end state is each script exposed as a bare wrapper on the plugin `bin/` PATH so the rule
names the command rather than the interpreter (trigger:
melodic-software/claude-code-plugins#843, the PATH gap fix). Until that lands, both quoted
and unquoted spellings stay pinned here alongside the bare wrappers that already exist.

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
