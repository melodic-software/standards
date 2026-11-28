# Infrastructure as code

## Design and build

- Decide explicitly for each setting or job whether it is shared or host-specific. Discover host-specific values per host and keep them in one source of truth split by host key. Share common stores across environments on one machine and isolate only the per-host selection. Record on a host what deviates from its defaults and why.
- Build setup for every target OS and host with feature parity, recording fixable gaps even when low priority. Write Windows tooling for PowerShell 7, not legacy Windows PowerShell. When a tool's own behavior keeps undoing a setup, choose an approach that works with it.

## Build and operate

- Keep machine settings, tools and configuration in source control and apply them idempotently. Treat configuration outside version control as drift and remove it. Declare repositories and their settings (labels included) as code, and keep the source host's settings plane (rulesets, branch and tag rules, actions, secrets and variables) under observation.
- Sync and apply tooling reconciles drift without overwriting user or concurrent changes and never downgrades or uninstalls. It runs a status check first and stops when an apply would overwrite local changes, and otherwise runs non-interactively (assume-yes) and reports what failed.
- Tools that change machine state snapshot first and offer a reset that restores exactly the declared configuration, adding or removing nothing; a scorched-earth reset is an explicit opt-in, and a profile switcher may toggle or install but never uninstall.

## Build and review

- Prove setup reproducible by reapplying it from source-controlled scripts on a clean environment. Make setup rerunnable so it adopts new defaults, detects old conventions and offers migration.

## Operate

- Keep tools, plugins, models and their dependencies on their latest version on every machine through provisioning, with elevated installs in provisioning and user tooling in user config. Install through each tool's official manager, in the official installer's form. Declare prerequisites with preflight checks in one format, and raise a missing tool loudly instead of installing it silently or bundling copies that drift.
