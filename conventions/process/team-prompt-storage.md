# Team prompt storage

How the organization stores and shares reusable team prompts: the native artifact form, the default
invocation posture, the reach tiers that decide where a prompt lives, and how deep links relate to
committed skills. This is a reasoning-only convention — it owns *where and how* a shareable prompt
is authored and distributed across repositories; it does not own the prompt's body, the marketplace
migration gate, or Claude Code's product semantics. Those live in the repositories and upstream docs
this playbook cites rather than restates (see [`../engineering/reference-dont-duplicate.md`](../engineering/reference-dont-duplicate.md)).

Decided 2026-08-09 in [melodic-software/claude-code-plugins#2072](https://github.com/melodic-software/claude-code-plugins/issues/2072), grounded in same-day fetches of the Claude Code deep-links, skills, and settings documentation and validated by three independent review agents.

## A team prompt is a skill

Custom slash commands are merged into skills in Claude Code; the native storage form for a prebaked
team prompt is a committed `.claude/skills/<name>/SKILL.md` in the repository the prompt concerns.
Distribution is `git pull` — no registry, index, or catalog file. A prompt that only exists in chat
history, a wiki page, or an uncommitted local file is not a shareable team prompt under this
convention.

## Default `disable-model-invocation: true`

User-triggered prompts — the common case — set `disable-model-invocation: true` in frontmatter so
their description stays out of the model-facing skill listing (zero per-session context tax). A
model-invocable prompt is the exception: it must carry named stumble evidence explaining why the
model should discover and invoke it without an explicit user slash command.

**Spec-portability caveat.** `disable-model-invocation` is a Claude Code extension, not part of the
portable Agent Skills frontmatter surface. The live portable field set and upload-validator
behavior are upstream-owned — see [Agent Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview);
fetch the current spec at read time rather than treating any field count here as durable. Upload or
packaging paths that enforce the portable surface (for example claude.ai upload) fail hard on
extension fields. Spec-portable packaging is a separate, opt-in step that strips to the current
portable fields; do not treat Claude Code-only frontmatter as portable by default.

## Tiers by reach

Where a prompt is authored follows who it is for and who wins precedence:

| Reach | Location | Notes |
|---|---|---|
| Repo-specific | That repository's `.claude/skills/` | Default for prompts tied to one codebase or its workflows. |
| Personal cross-repo | `~/.claude/skills/`, symlink-managed via the dotfiles `add-dotfile` flow | For one maintainer's prompts that follow them across repositories; not org policy. |
| Org-authoritative | Enterprise skills location | The only tier that wins precedence over personal and project skills. |
| Org-external reusable | Plugin skills entering the marketplace | Genuinely repo-agnostic prompts meant for consumers outside one repository use the marketplace's normal migration gate — not a parallel catalog in `standards`. |

Pick the narrowest tier that fits. Promote upward only when reach genuinely expands; do not park
repo-specific prompts in org or marketplace tiers to avoid committing them where they belong.

## Deep links are an entrypoint, not a distribution channel

Deep links surface a committed skill for shells, dashboards, and non-GitHub surfaces. They do not
replace git as the distribution mechanism.

- **GitHub strips `claude-cli://`.** Links rendered on GitHub are inert; treat deep links as
  entrypoints on surfaces that preserve the scheme, not as something a README on GitHub can rely on
  to launch Claude Code.
- **`q` names the skill, never embeds a body.** An emitted link uses `q=%2F<name>` (the slash
  command / skill name). The prompt body lives only in the committed `SKILL.md`.
- **`repo=` for anything shared.** Shared prompts include a `repo=` parameter pointing at the
  repository that owns the skill. Branch, pull-request, or ref context belongs in the prompt text
  itself — not assumed from the reader's checkout or directory state.

Authoritative product semantics: [Claude Code skills](https://code.claude.com/docs/en/skills) and
[deep links](https://code.claude.com/docs/en/deep-links).

## Related

- [melodic-software/claude-code-plugins#2072](https://github.com/melodic-software/claude-code-plugins/issues/2072) — decision register that routed storage convention here.
- [`../engineering/shareable-artifact-design.md`](../engineering/shareable-artifact-design.md) — consumer tiers and explicit adoption for artifacts built to be shared (marketplace-bound prompts).
- [`../engineering/reference-dont-duplicate.md`](../engineering/reference-dont-duplicate.md) — why this playbook cites upstream docs and fleet locations instead of restating them.
- [`../engineering/deterministic-artifact-scaffolding.md`](../engineering/deterministic-artifact-scaffolding.md) — skill scaffolds remain product behavior; no org-wide skeleton catalog here.
