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
- **`allow`** — safe-everywhere commands an unattended agent loop needs without prompting:
  read-only git/gh inspection and the routine non-destructive working verbs (add, commit,
  non-force push, checkout/switch, PR and issue CRUD), plus fleet-standard lint/test
  tooling. Force/destructive spellings stay covered by `deny`, which always wins.

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

## Change discipline

Additions to `allow` require observed-usage evidence (recurring prompt patterns from real
sessions — the auto-mode tuning loop) or a reviewed unattended-lane need; additions to
`deny` ship on sight. Either lands as a reviewed change here and reaches consumers through
the ordinary sync PR.
