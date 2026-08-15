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
at exactly that path, and a repo without the file is a logged no-op. As with
every component change, a merged edit here reaches an environment only on
its next cache rebuild (see [Update lifecycle](#update-lifecycle)).

## Plugin install

After the repo bootstrap, a generic, data-driven stage installs the plugins
the checkout declares — nothing more. If `.claude/settings.json` exists, its
`extraKnownMarketplaces` entries are registered (`claude plugin marketplace
add`, skipping ones already registered) and every `enabledPlugins` entry set
to `true` is installed (`claude plugin install <id> --scope user -y`,
skipping ones already installed). Every step is best-effort with a `WARN`
line to the log; the whole stage skips cleanly when the `claude` CLI or `jq`
is unavailable or the file declares no plugin keys. A repo that declares
nothing gets nothing.

The timing is load-bearing: Claude Code builds its plugin registry at
process start and never re-reads it, so only installs already in the
snapshot a session boots from are loaded at the session's first turn.
Consumer repos declare github-source marketplaces, whose install/update
semantics already handle versions — the commit-drift refresh logic in
claude-code-plugins' own hook is deliberately not replicated here; it is
specific to that repo's directory-source dogfooding.

## Calling contract (frozen)

The interface between this component and consuming repositories:

- The component runs the checked-out repo's `.claude/cloud-bootstrap.sh` —
  that exact path — with `CLAUDE_CODE_REMOTE=true` and `CLAUDE_PROJECT_DIR`
  set to the checkout root, best-effort. A missing file is a clean no-op.
- Every component step is best-effort (`|| true` semantics) and the script
  always exits 0 — a failed step degrades the snapshot, never the
  environment build.
- This interface is **frozen**: future changes may add to the component but
  never rename the entry-point path, remove or rename the environment
  variables, or make any step fail-closed.
- Division of responsibility: the component's installs are a **warm cache**;
  each repo's bootstrap is the **correctness guarantee**. Repos must not
  assume the component installed anything. This is what keeps component
  changes from ever breaking consumers.
- The component is repo-agnostic and must never contain secrets or
  repo-specific logic.

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
