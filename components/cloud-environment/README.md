# Cloud environment

The canonical setup script for the organization's shared Claude Code cloud
environment (the **Melodic** environment at claude.ai/code). The exported
payload is [`setup.sh`](setup.sh); the consumer is the environment's setup
script field, which holds only the three-line bootstrap below, so the real
script lands here by reviewed pull request instead of by hand-editing an
account-scoped UI field.

Design (one paragraph): cloud environments are account-scoped and
repo-agnostic, and a setup script's result is cached as a filesystem snapshot
— the warm boot. So one shared environment installs the *union* of static
toolchains the fleet pins (.NET SDKs, Node 24, `gh`, PowerShell) inside the
~5-minute cache-build budget, while each repo owns its own setup in a
committed, idempotent `.claude/cloud-bootstrap.sh`.
The full fleet plan, per-repo templates, and verification
checklist live in
[claude-code-plugins `docs/CLOUD-FLEET-SETUP.md`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/CLOUD-FLEET-SETUP.md).

## Bootstrap (paste into the environment's setup script field)

```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/setup.sh \
  -o /tmp/melodic-env-setup.sh && bash /tmp/melodic-env-setup.sh
exit 0
```

`raw.githubusercontent.com` is on the platform's default allowlist, and this
repository is public, so the fetch works from any account's environment with
no credentials.

## Repo bootstrap handoff

After the parallel toolchain tracks finish, the script runs the checked-out
repo's committed `.claude/cloud-bootstrap.sh`, best-effort, with
`CLAUDE_CODE_REMOTE=true` and `CLAUDE_PROJECT_DIR` set to the checkout root.
One name, no fallbacks: every fleet repo commits its generic repository setup
— dependencies and plugin installs — at exactly that path, and a repo without
the file is a logged no-op.

Running the bootstrap at cache build is load-bearing for plugins: the
session's plugin registry is built at process start and never re-read, so
plugin installs must already be in the snapshot the session boots from. As
with every component change, a merged edit here reaches an environment only
on its next cache rebuild (see [Update lifecycle](#update-lifecycle)).

## Network prerequisite

The environment must use **Custom** network access with **"Also include
default list of common package managers"** checked, plus these hosts:
`dot.net`, `aka.ms`, `builds.dotnet.microsoft.com`,
`download.visualstudio.microsoft.com`. Trusted access 403-blocks the .NET
installer's redirect chain — verified live 2026-08-14
([claude-code-plugins#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654),
Blocker 1).

## Verification stamp

The script logs every step with a timestamp to
`/var/log/melodic-env-setup.log` (falling back to `/tmp`) and writes
`/opt/melodic-env-setup.done` (version + timestamp) as its **last** action.
Verification starts there: a missing stamp means the cache build was
interrupted before completion (claude-code-plugins#2654, Blocker 2) — force a
rebuild by making any edit to the environment's script field.

## Update lifecycle

- Toolchain pins (the .NET version list, the Node pin) duplicate the fleet's
  manifests by necessity — the script cannot read repos it is not running in.
  When a repo bumps `global.json` or `.node-version`, update the pin here and
  bump `SCRIPT_VERSION`.
- A merged change does **not** reach existing environments on its own: the
  snapshot rebuilds only on an edit to the environment's script/network
  fields or on ~7-day cache expiry. To pick up a new version immediately,
  make a trivial edit to the environment's script field (a comment character
  suffices) to force a rebuild, then confirm the stamp shows the new
  `SCRIPT_VERSION`.
- Rollback: environments keep booting from their cached snapshot until
  rebuilt, so reverting the commit and forcing a rebuild restores the prior
  state; in an emergency the bootstrap can pin a commit SHA in the raw URL
  instead of `main`.

The scope boundary holds as elsewhere in this repository: this component owns
the shared environment baseline only. Repo-specific dependencies and plugin
installs belong to each repo's committed `.claude/cloud-bootstrap.sh`
(templates in the fleet guide above), never to this script.
