# Process conventions

Agent-agnostic operational standards for how work is tracked and moved, distinct from how code is written (`../engineering/`) or reviewed (`../review/`). These are reasoning-only: a person or agent reads them while triaging and running the tracker; nothing here is executed by a tool walking the tree.

| Convention | Owns |
|---|---|
| [issue-tracker.md](issue-tracker.md) | the house style for every issue: the filing rule, plain titles, label grammar, which native mechanism does which job, issue fields, holds and decision issues, and the infrastructure-as-code governance that keeps the taxonomy from drifting |
| [autonomy-binding.md](autonomy-binding.md) | the organization's binding instance for the autonomy contract set: each contract role mapped to its fleet repository, with the bound role-vocabulary version |
| [team-prompt-storage.md](team-prompt-storage.md) | shareable team prompts as committed `.claude/skills/` artifacts, default `disable-model-invocation: true`, reach tiers, and deep links as entrypoints |
| [upstream-contributions.md](upstream-contributions.md) | checking an external project's contribution policy before filing, and human-authored filing where AI-generated contributions are banned |
