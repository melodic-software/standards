# Cloud environment

The canonical setup script for the organization's shared Claude Code cloud
environment (the **Melodic** environment at claude.ai/code). The exported
payload is [`setup.sh`](setup.sh); the consumer is the environment's setup
script field, which holds only the three-line bootstrap below, so the real
script lands here by reviewed pull request instead of by hand-editing an
account-scoped UI field.

Design (one paragraph): cloud environments are account-scoped and
repo-agnostic, and a setup script's result is cached as a filesystem snapshot,
the warm boot. So one shared environment installs the *union* of static
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

## Repo root resolution

The script resolves the checkout root explicitly instead of trusting the
cache build's working directory: a real build (SW2030, 2026-08-23, script
version 2026-08-15.3) ran with a CWD that was *not* the checkout, silently
no-opping the bootstrap and plugin steps. Resolution is `git rev-parse
--show-toplevel` from the build's CWD first, trusted only when the root
lies inside the platform checkout area so a stray git repo elsewhere can
never get its bootstrap baked. Failing that, the script probes for a single
git checkout under the container-user homes (the platform places it at
`/home/<container-user>/<repo>`). The log always says which way the root was
resolved (with the build's `PWD`), and an unresolved, ambiguous, or
distrusted root is a distinct `WARN`/notice line, never conflated with
"repo has no bootstrap".

## Repo bootstrap handoff

After the parallel toolchain tracks finish and the
[fleet plugin install](#plugin-install) has run, the script runs the resolved
checkout's committed `.claude/cloud-bootstrap.sh`, best-effort, with
`CLAUDE_CODE_REMOTE=true`, `CLAUDE_PROJECT_DIR` set to the checkout root,
and the checkout root as the working directory.
One name, no fallbacks: every fleet repo commits its generic repository setup
at exactly that path, and a repo without the file is a logged no-op. As with
every component change, a merged edit here reaches an environment only on
its next cache rebuild (see [Update lifecycle](#update-lifecycle)).

## Plugin install

Before the repo bootstrap, a generic, data-driven stage installs plugins from
one settings-shaped file: **the fleet list**,
[`fleet-plugins.json`](fleet-plugins.json) beside this script, the one place
the organization's cloud plugin set is declared. The script fetches it from
the same `raw.githubusercontent.com` path the bootstrap fetches this script
from, writes it into the snapshot at `/opt/melodic-fleet-plugins.json`
(falling back to `/tmp/melodic-fleet-plugins.json` with a logged `WARN` when
`/opt` is unwritable, mirroring the stamp), and installs it. Every snapshot
gets the fleet whatever repo it was built for, and the snapshot stays
repo-agnostic.

A repo's own `.claude/settings.json` carries only the deltas it declares
beyond the fleet (an extra marketplace, a plugin beyond the fleet, or a
`false` opt-out, which project scope applies over the user-scope install).
Those are not installed by this stage: the
[repo bootstrap](#repo-bootstrap-handoff) that runs next applies them as an
overlay on top of this list, from the snapshot copy (see the
[cloud-bootstrap component](../cloud-bootstrap/README.md)). That is why this
stage runs first — the bootstrap's plugin step skips outright when the fleet
list is absent, so a bootstrap running before the fetch would bake no deltas
at all and leave them to arrive only when the session bootstrap re-runs and
the operator resumes. The same bootstrap still runs at session start, where
it repairs drift between the snapshot and the repo's current declarations.

`extraKnownMarketplaces` entries are registered (`claude plugin marketplace
add`, skipping ones already registered) and every `enabledPlugins` entry set
to `true` is installed (`claude plugin install <id> --scope user -y`,
skipping ones already installed). Every step is best-effort with a `WARN`
line to the log; the whole stage skips cleanly when the `claude` CLI or `jq`
is unavailable, and a failed fleet fetch installs no plugins that build (the
next rebuild fetches the list again).

The fleet list is settings-shaped on purpose: `jq` expressions written for a
repo's settings file read it unchanged, and
[`distribution/check-plugin-baseline.sh`](../../distribution/check-plugin-baseline.sh)
uses it as the baseline every repo and the dotfiles seed are compared
against. Every entry in it is `true`; a `false` is a per-repo decision and
belongs in that repo's own file. To add a plugin to the fleet, add its entry
here in byte order (`setup.test.sh` checks both), then force a snapshot
rebuild (see [Update lifecycle](#update-lifecycle)).

The timing is load-bearing: Claude Code builds its plugin registry at
process start and never re-reads it, so only installs already in the
snapshot a session boots from are loaded at the session's first turn.
Consumer repos declare github-source marketplaces, whose install/update
semantics already handle versions. The commit-drift refresh logic in
claude-code-plugins' own hook is deliberately not replicated here; it is
specific to that repo's directory-source dogfooding.

## Calling contract (frozen)

The interface between this component and consuming repositories:

- The component runs the checked-out repo's `.claude/cloud-bootstrap.sh`,
  that exact path, with `CLAUDE_CODE_REMOTE=true` and `CLAUDE_PROJECT_DIR`
  set to the checkout root, best-effort. A missing file is a clean no-op.
- Every component step is best-effort (`|| true` semantics) and the script
  always exits 0: a failed step degrades the snapshot, never the
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

## The `gh` pin

`gh` is installed from its checksummed upstream release asset
(`github.com/cli/cli/releases`, `linux_amd64`), not from `apt`: Ubuntu's own
archive ships a years-stale `gh` (2.45.0 observed live in a cloud session),
and `cli.github.com` — the upstream apt repo — is not on the default
allowlist. The pinned version is **2.98.0**; it and the SHA-256 beside it are
the same pair
[`melodic-software/ci-runner`](https://github.com/melodic-software/ci-runner/blob/main/Dockerfile)
bakes into the CI runner image and `melodic-software/dotfiles` pins through
mise on local machines, so all three lanes run one `gh`. Bump the three
together, and authenticate a new asset against the checksums `cli/cli`
publishes for that release before recording its hash here.

The install is amd64-only, mirroring the runner image: the pinned hash covers
that one asset, and a non-x86_64 VM is a logged `WARN` skip rather than an
unverified download. Like every other step it is best-effort — `github.com` is
on the default allowlist, but the GitHub proxy's repository scope can `403`
release assets from repositories not attached to a session, and a silent miss
surfaces in the verification checklist rather than failing the build.

## Network prerequisite

The environment must use **Custom** network access with **"Also include
default list of common package managers"** checked, plus these hosts:
`dot.net`, `aka.ms`, `builds.dotnet.microsoft.com`,
`download.visualstudio.microsoft.com`. Trusted access 403-blocks the .NET
installer's redirect chain, verified live 2026-08-14
([claude-code-plugins#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654),
Blocker 1).

## Verification stamp

The script logs every step with a timestamp to
`/var/log/melodic-env-setup.log` (falling back to `/tmp`); the three
parallel install tracks each write to their own temp log, concatenated into
the main log under `--- track … ---` headers after the wait barrier so
concurrent output never interleaves. The completion stamp
`/opt/melodic-env-setup.done` (version + timestamp) is written as the
**last** action, falling back to `/tmp/melodic-env-setup.done` with a
logged `WARN` when `/opt` is unwritable, so an unwritable `/opt` cannot
masquerade as an unfinished build. Verification starts at the stamp: neither
file present means the cache build was interrupted before completion
(claude-code-plugins#2654, Blocker 2). Force a rebuild by making any edit
to the environment's script field. The script also removes its fetched temp
files (the installers and its own `/tmp` copy) so they never persist into
the snapshot.

## Update lifecycle

- Toolchain pins are read from the resolved checkout's own manifests when
  present: `global.json` (`sdk.version`) for .NET, `.node-version` for Node.
  A repo's bump therefore reaches its next cache rebuild with no manual sync. The
  fleet fallback pins in the script cover repos that declare neither (and
  the unresolved-root case); when the fleet's baseline moves, update the
  fallbacks and bump `SCRIPT_VERSION`. The Node fallback is lockstep-tested
  against this repository's own `.node-version` (the fleet pin) in
  `setup.test.sh`; the .NET fallback list has no in-repo manifest and stays
  a manual obligation. Either way the env copy is only a warm cache: each
  repo's bootstrap installs its exact pins repo-locally, so a stale warm
  cache costs build time, not correctness.
- The `gh` pin has no in-repo manifest either, and unlike the toolchains above
  it is not a warm cache: no repo bootstrap reinstalls `gh`, so this script is
  the only thing holding cloud sessions at the fleet version. Bump
  `GH_VERSION` and `GH_SHA256` in the same change as the CI runner image and
  the dotfiles mise pin. The version is lockstep-tested against this README in
  `setup.test.sh`.
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
the shared environment baseline, which now includes the fleet plugin list.
Repo-specific dependencies and plugin deltas belong to each repo's committed
`.claude/cloud-bootstrap.sh` and `.claude/settings.json` (templates in the
fleet guide above), never to this script.
