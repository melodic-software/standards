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
`schemaVersion`, `allow`, `deny`, and `withdraw`:

- **`deny`** — the safety floor: destructive git verbs (force-push, hard reset, clean,
  checkout/restore discards, forced branch deletion, `--no-verify` hook bypass) in both
  `Bash()` and `PowerShell()` rule spellings, bare and starred argument forms; the `gh api`
  DELETE surface for org/repo/security-critical resources; hook-disable environment
  prefixes; network-share mounts; and secret-material `Read()` patterns (key files, env
  files, credential stores) in both bare and `**/`-prefixed forms. The union is deliberately
  the STRICTEST observed form of each rule.
- **`allow`** — grants an unattended agent loop needs that no built-in mechanism carries:
  the routine non-destructive working verbs (add, commit, non-force push, pull,
  checkout/switch, PR and issue CRUD), the babysit lane's gate tooling, and the read-only
  inspection commands
  Claude Code does *not* pre-approve — every `gh` verb (read-only ones included) and every
  third-party linter. Force/destructive spellings stay covered by `deny`, which always
  wins — with one deliberate carve-out, below.

  **Test-suite invocations are deliberately absent.** A test runner executes whatever test
  files are on disk, and an agent session that can write files plus a blanket `pytest`
  grant compose into a general code-execution grant wearing a narrow name — no rule
  grammar can tell a test file the agent wrote this session from one the repository
  already had. Test runs are judged per session instead.

  **`gh run rerun` is deliberately absent for the same shape of reason.** The verb takes a
  bare run id, and the CLI reruns whatever that id names — a run on an unmerged branch, a
  deployment, a release workflow — so a floor glob cannot restrict it to flaky CI on merged
  workflow code. Reruns are judged per session until a guarded wrapper validates the
  repository, workflow, event, and ref.

  **`git pull` is covered, with its hostile spellings denied.** The wildcard would
  otherwise pre-approve `git pull --no-verify` (git documents it as bypassing the pre-merge
  and commit-msg hooks) and `git pull --force`/`-f`/`+<refspec>` (a forced overwrite of the
  local ref, same as the fetch forms already denied), so `deny` carries the pull spellings
  of both families, args-before-flag forms included.

  **Read-only *git* inspection is deliberately absent.** Claude Code recognizes a built-in
  set of Bash commands as read-only and runs them without a permission prompt in every
  mode; the set is not configurable and covers "read-only forms of `git`"
  (<https://code.claude.com/docs/en/permissions>, "Read-only commands"). Floor entries for
  that set are dead weight in every mode, not just under auto. Verified 2026-07-24 on
  Claude Code 2.1.219 in `default` mode with zero settings loaded: `git status`,
  `git diff`, `git log`, `git show`, `git branch`, `git branch --list`, `git ls-files`,
  `git merge-base`, and `git rev-parse` — nine spellings — all ran promptless through both
  the `Bash` and `PowerShell` tools.

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
  the fleet default (`permissions.defaultMode: "auto"`) while trimming anything outside
  that set would reintroduce prompts.

The `${CLAUDE_PLUGIN_ROOT}` interpreter+script-path allow entries are interim shapes: the
end state is each script exposed as a bare wrapper on the plugin `bin/` PATH so the rule
names the command rather than the interpreter (trigger:
melodic-software/claude-code-plugins#843, the PATH gap fix). Until that lands, both quoted
and unquoted spellings stay pinned here — for the plugin scripts and equally for the two
guarded `bin/` wrappers, whose real invocation shape is
`bash "${CLAUDE_PLUGIN_ROOT}/bin/<wrapper>"` (claude-code-plugins `3fc72d351c`) — and
bare-wrapper rules stay OUT: the plugin `bin/` directory is not on the shell's PATH today,
so a rule naming the bare command matches nothing and is dead weight until #843 makes the
bare name resolve. The end state also does not restore pre-classifier handling under
`classifyAllShell: true` — a bare wrapper is still a shell rule. It buys rule clarity and
the non-auto posture, not a classifier bypass.

### `withdraw` — tombstones for rows retired from `allow`

`withdraw` names the rows this component has retired from `allow`. It exists because the
composition that carries this floor into a consumer's live settings **unions** it — so
locally-accumulated rules survive — and a union cannot subtract. A row that has ever reached a
machine's live allow list therefore stays granted by every later apply, however long ago this file
dropped it. Measured, not theorised: the auto-mode re-derivation above retired 18 rows and all 18
remained live on the operator's machine (melodic-software/dotfiles#337). Those 18 seed the array.

Entries are exact strings, never globs — a tombstone that quietly matched more than it names would
be a second eviction gap pointing the other way. They are append-only with one exception, the
regrant: a retired row otherwise stays named for as long as any machine might still hold it, with
no reliable signal for when that stops being true. The resulting growth is storage-only: the array
is consumed by the composer and never reaches a live settings file, so it does not enter the
auto-mode classifier's prompt the way `deny` does.

**Regrant lifecycle: `allow` and `withdraw` are disjoint, and a regrant deletes its tombstone.**
The composer subtracts `withdraw` after its union, so a row present in both arrays is evicted on
the next apply no matter how recently `allow` re-added it — a tombstone that outlives its removal
silently defeats the regrant. Re-granting a previously withdrawn row therefore means, in the same
reviewed PR: delete the row's tombstone from `withdraw` and add the row back to `allow`. The
disjointness invariant (no string appears in both arrays) is enforced by
`claude-permissions.test.sh` in CI, so a regrant that forgets its tombstone fails the build instead
of failing on the fleet. The two bare-wrapper tombstones below are the standing example: when
melodic-software/claude-code-plugins#843 makes the bare wrapper names resolve, the end state above
re-adds those rows to `allow` — and that PR deletes their tombstones as part of the same change.

**`withdraw` is `allow`-shaped only, and deliberately does not generalize to `deny`.** The two carry
opposite hazards. `allow` accretes through the union and needs a subtract path. `deny` does not, at
the active consumer: that composition force-sets `permissions.deny` from its own owned list before
unioning this floor into it, so the live array is rebuilt each apply and a `deny` removal here
already propagates. Nor should it gain one — dotfiles#337 records that a `deny` row is rendered into
the auto-mode classifier's own prompt as a circumvention instruction, so a lever that makes dropping
one easy weakens auto mode itself. Retiring a `deny` row stays an ordinary edit to `deny`.

### `--force-with-lease` is enforced by a hook, not by `deny`

`deny` covers the force spellings it can express, but not this one. Claude Code's Bash rules are
whole-string globs with `*` as the only metacharacter, and precedence is fixed at deny → ask →
allow, so a `deny` entry cannot carry an allowlist exception
([permissions](https://code.claude.com/docs/en/permissions)). That makes the distinction this
option needs inexpressible here. git leases against the remote-tracking ref for
`--force-with-lease` and `--force-with-lease=<refname>`, which
[git-push(1)](https://git-scm.com/docs/git-push) says is "trivially defeated if some background
process is updating refs in the background". A `--force-with-lease=<refname>:<expect>` is safe only
when `<expect>` is something git cannot resolve to a newer value — an object id, or the empty string
asserting the ref must not already exist. A movable name in that slot
(`--force-with-lease=refs/heads/main:origin/main`, `:HEAD`, `:@{u}`) is resolved when the push runs,
so a background fetch advances it first and the lease passes while clobbering unseen work: the same
hole the bare form has. One glob cannot separate an object id from a ref name in that position.

A blanket `deny` here would therefore have to reject the safe form too. The precise check lives in
the `guardrails` plugin's `block-dangerous-git` PreToolUse hook instead, which parses the argv,
requires an immutable `<expect>`, and also honors `--force-if-includes` and the last-wins
negations. The docs name a PreToolUse hook as the mechanism for exactly what globs cannot express.

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

**`withdraw` is advisory data, not a contract.** It sits on the same footing as every other key
here: the sync engine is byte-exact and merges nothing, so this component cannot make any consumer
act on a tombstone. A consumer that ignores the key is exactly where it was before the key
existed: the union still cannot subtract, and the retired row stays granted on every machine that
holds it. That residual is the price of the advisory framing, and the reason the key is documented
rather than assumed. A consumer that does compose it subtracts these rows *after* its union, keyed
to the tombstone string **itself** rather than to "absent from this floor": the narrower key lets a
genuinely machine-local grant survive untouched while the source of truth can still say "retire
this". The key is additive and optional, so `schemaVersion` stays at `1` — a consumer reading only
`allow` and `deny` parses this file unchanged.

Colocation is the point. The withdrawal decision is made here, in the same reviewed PR that removes
the entry and records why; carrying the tombstone here keeps cause and effect in one place and stops
each consumer re-authoring the same list by hand. The user layer already holds a hand-copied
duplicate of all 18 seeded rows — the drift this key exists to end.

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

**Removals carry the heavier burden, and exactly two arguments retire an entry.** The first:
Claude Code's built-in read-only set covers the command in every mode. The second: the rule is
proven non-resolving — its command name resolves to no executable on any fleet machine, so the
rule matches nothing and is dead weight; the evidence is a `command -v <name>` (or `Get-Command`)
failure recorded in the PR together with why the name is expected to stay unresolvable until a
named trigger (the two bare-wrapper tombstones seeded by this file are the standing example:
their names resolve only when melodic-software/claude-code-plugins#843 lands, which is also their
regrant trigger). A non-resolving removal still lands with its tombstone — the dead row is
harmless where it lingers, but the tombstone is what actually clears it from machines that hold
it. For the first argument, the claim must be tested
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

**A removal lands with its tombstone.** The same PR that drops a row from `allow` adds that exact
string to `withdraw`. A removal without one retires the row for fresh machines only and leaves it
granted on every machine that already holds it — spending the burden above on a withdrawal that
does not take effect where it matters.
