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
one settings-shaped file: **the fleet list**. The script fetches the
melodic-software marketplace catalog,
[`.claude-plugin/marketplace.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.claude-plugin/marketplace.json)
in claude-code-plugins, and enables every plugin whose catalog entry leaves
`defaultEnabled` unset or sets it `true`; any other value leaves the plugin
off. It writes the list into the snapshot at
`/opt/melodic-fleet-plugins.json`
(falling back to `/tmp/melodic-fleet-plugins.json` with a logged `WARN` when
`/opt` is unwritable, mirroring the stamp), and installs it. Every snapshot
gets the fleet whatever repo it was built for, and the snapshot stays
repo-agnostic.

A repo's own `.claude/settings.json` carries only the deltas it declares
beyond the fleet (an extra marketplace, a `true` opt-in to an off-by-default
plugin, or a `false` opt-out, which project scope applies over the user-scope
install).
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
is unavailable, and a failed catalog fetch installs no plugins that build (the
next rebuild fetches the catalog again).

The fleet list is settings-shaped so the repo bootstrap reads it with the
same `jq` expressions it uses on a repo's settings file. To add a plugin to or
remove one from the cloud fleet, change its `defaultEnabled` in the catalog,
then force a snapshot rebuild (see [Update lifecycle](#update-lifecycle)).

The timing is load-bearing: Claude Code builds its plugin registry at
process start and never re-reads it, so only installs already in the
snapshot a session boots from are loaded at the session's first turn.
Consumer repos declare github-source marketplaces, whose install/update
semantics already handle versions. The commit-drift refresh logic in
claude-code-plugins' own hook is deliberately not replicated here; it is
specific to that repo's directory-source dogfooding.

## Permission floor

After the repo bootstrap, the script composes the fleet's reviewed permission
floor, [`claude-permissions.json`](../claude-permissions/claude-permissions.json),
into the user settings file sessions boot with:
`${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`, the same user scope the
[plugin install](#plugin-install) writes. Locally, the dotfiles chezmoi
template composes this floor, but chezmoi never runs in a cloud session, so
without this step cloud sessions had no `deny` floor and none of the
unattended-loop `allow` grants
([claude-code-plugins#3172](https://github.com/melodic-software/claude-code-plugins/issues/3172)).

The floor is fetched from the same `raw.githubusercontent.com` host as the
plugin catalog, and the merge follows the dotfiles template:
`claudePermissions.allow` and `.deny` are unioned into the file's
`permissions.allow` and `permissions.deny`, then the floor's `withdraw`
tombstones are removed from `allow`. The file is never overwritten. Every
other key and every rule already in it survive, a missing file starts from
`{}`, and the result is written to a copy carrying the original's mode and
owner, then renamed over it. The step is best-effort like every other. A failed
fetch, a floor that is not `schemaVersion` 1 with string rows and a non-empty
`deny`, a settings file that is not a single JSON object, or a failed write
each log a `WARN` and leave the file as it was.

Running last means no later build step can replace the file. A floor change
merged in `claude-permissions` reaches an environment on its next cache
rebuild (see [Update lifecycle](#update-lifecycle)), with no change here.

## Key Vault resolver

[`vault-exec`](vault-exec) is the cloud counterpart of the workstation
resolver in the operator's dotfiles, with the same argv contract:
`vault-exec [--optional] --env NAME=secret-name [--env ...] -- <command> [args...]`.
It reads each secret from Key Vault, sets `NAME` in the command's environment,
and execs the command, so stdin, stdout and the exit code pass through. A
failed read exits 1 without running the command; with `--optional` it leaves
`NAME` unset, warns on stderr, and runs the command. Bad usage exits 2.
Diagnostics name the secret and the HTTP status, never the value.
Each read gets up to three 10-second attempts, retrying only transport errors
and HTTP 408, 429 and 5xx, and all reads in one run share a 45-second budget,
so the command starts or the run fails inside a 60-second launcher timeout.

After the permission floor, the script fetches `vault-exec` from the same
`raw.githubusercontent.com` path as this component and installs it, mode
0755, to `~/.local/bin/vault-exec` under the build's `HOME`, the path the
[mcp-launcher](../mcp-launcher/README.md) looks for. Each copy carries a marker
line; a `vault-exec` already there without it is left alone with a `WARN`.
The step is best-effort like every other.

Reads work only in a session whose environment has an
[API credential](https://code.claude.com/docs/en/cloud-environments#add-api-credentials)
of the OAuth 2.0 client-credentials type for `*.vault.azure.net` with scope
`https://vault.azure.net/.default`. The agent proxy adds the bearer token, so
`vault-exec` sends no auth header and no token or secret is stored in the VM.
The proxy does not serve setup-script requests
([requests that never get the credential](https://code.claude.com/docs/en/cloud-environments#requests-that-never-get-the-credential),
as of 2026-10-04), so the cache build can install `vault-exec` but never read a
secret with it.

Every name resolves in `kv-melo-devtools-prod`, the one vault the cloud
identity is granted. Set `VAULT_EXEC_VAULT` to read another vault.

## Page uploader

[`pages-publish`](pages-publish) uploads one rendered page to the operator's
page host through its upload route (`PUT <origin>/_upload` creates,
`PUT <origin>/_upload/<id>` replaces, `DELETE <origin>/_upload/<id>` removes):

```text
pages-publish <file> --visibility public|private [--id <id>]
pages-publish --delete <id> --visibility public|private
```

On success it prints one JSON line, `{"id":..., "visibility":..., "url":...}`,
built from the page URL the host returns; `--delete` prints nothing.

| Exit | Meaning |
|---|---|
| 0 | uploaded (or deleted: the host answered 204) |
| 2 | usage |
| 3 | the file is not a regular file under `${TMPDIR:-/tmp}` (after `realpath`), or carries no builder stamp `<!-- rv-gen:<name> sha256:<64 hex> -->` |
| 4 | credential-shaped content, found here before any network call or by the host (HTTP 422) |
| 5 | config missing or invalid, or not owned by the current user with mode 0600 |
| 6 | the token could not be resolved, or the upload or an HTTP answer failed |

**Config.** Operator values come only from
`<passwd home>/.config/pages-publish/config`, where `<passwd home>` is field 6
of `getent passwd "$(id -un)"`. `HOME`, `XDG_CONFIG_HOME` and every other
run-time variable are ignored, because a repository's settings can set
environment variables. The file holds `KEY=VALUE` lines (blank lines and `#`
comments allowed, any other key refused):

| Key | Value |
|---|---|
| `PUBLIC_ENDPOINT`, `PRIVATE_ENDPOINT` | `https://<host>` upload origin of each host |
| `PUBLIC_TOKEN_SECRET`, `PRIVATE_TOKEN_SECRET` | vault secret name of each host's bearer upload token |
| `PRIVATE_ACCESS_ID_SECRET`, `PRIVATE_ACCESS_KEY_SECRET` | vault secret names of the Access service-token pair the private host's upload path requires |

**Scan.** Before any network call the page bytes, builder stamp removed, are
matched against a fixed list of credential shapes (and `gitleaks dir` when
gitleaks is on `PATH`); a hit exits 4 and stderr names the shape and line,
never the match. A machine path (`/home/<user>/`, `/Users/<user>/`,
`C:\Users\`, `\\wsl`, `/mnt/<drive>/Users/`, `/root/`, a `-home-<user>-`
slug) or a `.local`, `.internal` or `.lan` hostname sends the page to the
private host. Each list also runs on a decoded copy, as the host's scan does:
tags stripped (so a token split across highlighter `<span>`s rejoins), HTML
entities decoded (`&#47;`, `&#x2F;`, `&sol;`, `&amp;` and the like), then
JSON/JS escapes undone (`\/`, `\\`, `\"`, `\uXXXX`, `\xHH`); a credential
found only there exits 4 naming the decoded line. The decoded copy is also
matched against the [path-detection](../path-detection/README.md) bodies,
which add a home path with no trailing slash, the forward-slash and 8.3
Windows forms, and Windows checkout roots. They are copied into the script
because setup installs it as one file, and its test fails when the copy and
the library differ. They skip the raw bytes, where a home path with an
escaped `&lt;user&gt;` placeholder would read as a real user. Only the listed
shapes are caught; the host's own scan is the binding one. When the
visibility sent differs from the one requested, `--id` is dropped and a new
page is created, and when the public host answers 409
`private-required` the upload is retried once as a private create. In both
cases the caller deletes the old id.

**Secrets.** `vault-exec --env` resolves the host's bearer token and, for the
private host only, the Access pair. They reach `curl` only as
`header = "..."` lines on its stdin (`--config -`), never in argv; the public
host never receives the Access headers. Requests are `https` only and send
`Content-Type: text/html; charset=utf-8`.

**Setup.** After `vault-exec`, the script installs `pages-publish` to
`~/.local/bin/pages-publish` the same way: a copy without the marker line is
left alone with `WARN pages-publish: <dest> is not ours`. After the repo
bootstrap, whatever its outcome, it writes two operator files from the
environment's variables, so they win over anything the bootstrap wrote:

- `RENDERED_VIEWS_MD`, when set, replaces
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rendered-views.md`.
- `PAGES_PUBLISH_PUBLIC_ENDPOINT`, `PAGES_PUBLISH_PRIVATE_ENDPOINT`,
  `PAGES_PUBLISH_PUBLIC_TOKEN_SECRET`, `PAGES_PUBLISH_PRIVATE_TOKEN_SECRET`,
  `PAGES_PUBLISH_PRIVATE_ACCESS_ID_SECRET` and
  `PAGES_PUBLISH_PRIVATE_ACCESS_KEY_SECRET`, when all six are set, become the
  config above, mode 0600, at the passwd-home path. A partial set logs a
  `WARN` naming the missing variables and writes no config.

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
  instead of `main`. The pin covers this script only: the plugin catalog, the
  permission floor, `vault-exec` and `pages-publish` are still fetched from `main`.

The scope boundary holds as elsewhere in this repository: this component owns
the shared environment baseline, which includes deriving the fleet plugin
list and composing the fleet permission floor.
Repo-specific dependencies and plugin deltas belong to each repo's committed
`.claude/cloud-bootstrap.sh` and `.claude/settings.json` (templates in the
fleet guide above), never to this script.
