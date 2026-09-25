# MCP launcher

A cross-platform stdio entry for project MCP servers, and the one place a
keyed server resolves its key. The exported payload is
[`launcher.js`](launcher.js) and [`dispatch.js`](dispatch.js), materialized to
each consuming repository's `tools/mcp-launcher/` by
[`distribution/sync-manifest.yml`](../../distribution/sync-manifest.yml).

The same project entry works locally and in cloud sessions: a cloud session
supplies the key as an environment variable, a workstation resolves it from
Key Vault through `vault-exec`, and a machine with neither starts the server
without it.

## What it does

`node launcher.js [--vault NAME=vault-secret-name ...] <server>`, where
`<server>` is either:

- npx arguments (`-y @scope/package@pin …`). On Windows `npx.cmd` runs through
  `cmd /d /s /c`, because a bare `npx` in an MCP config fails there without
  `shell: true`.
- `mcp-servers/<dir> <command> [args…]`, a server in the repository, run from
  the current worktree's root.

Each `--vault NAME=secret` is decided in this order:

1. **Set.** `NAME` is non-empty and not an unexpanded placeholder
   (`${NAME}`, `${env:NAME}`, anything matching `^\$\{.*\}$`). The server
   starts directly. This is the cloud path.
2. **Already tried.** `MCP_LAUNCHER_VAULT_TRIED=1`: this process is the one
   `vault-exec` started and the key is still missing. It warns once and starts
   the server without the key. This guard is what stops a
   launcher → `vault-exec` → launcher loop.
3. **Resolver present.** The launcher re-runs itself once through
   `vault-exec --optional --env NAME=secret -- <node> <launcher.js> <same args>`
   with `MCP_LAUNCHER_VAULT_TRIED=1` set. Only the names still missing are
   passed. The resolver is:
   - Windows: `%USERPROFILE%\.local\bin\vault-exec.ps1`, launched through
     `pwsh -NoProfile -File`. `where` does not find a `.ps1`, so the launcher
     tests for the file.
   - Linux and macOS: `~/.local/bin/vault-exec`, when it is executable.
4. **Otherwise** it warns once and starts the server without the key.

A name that ends up missing is removed from the server's environment, so a
literal `${NAME}` never reaches the server as its key.

stdout is the MCP JSON-RPC channel. The launcher writes only to stderr, and
stdin, stdout and the exit code pass through untouched.

A bad `--vault` value (not `NAME=secret`, or a name that is not an
environment-variable name) exits 2.

## Adopting it

Select `mcp-launcher` for the repository in
[`distribution/sync-manifest.yml`](../../distribution/sync-manifest.yml). The
entries below assume the synced path `tools/mcp-launcher/launcher.js`, `fnm`
on the PATH, and a `.node-version` or `.nvmrc` in the repository. `fnm exec`
gives GUI hosts the repository's Node without a shell profile, and
`MCP_LAUNCHER_FNM_ACTIVE=1` tells the launcher not to wrap itself in `fnm`
again.

Claude Code, `.mcp.json` (Grok reads the same file). The `:-` default keeps
Claude from warning about a missing variable locally:

```json
"perplexity": {
  "type": "stdio",
  "command": "fnm",
  "args": ["exec", "--version-file-strategy=recursive", "--", "node", "tools/mcp-launcher/launcher.js",
           "--vault", "PERPLEXITY_API_KEY=perplexity-api-key", "-y", "@perplexity-ai/mcp-server@0.9.0"],
  "env": {
    "MCP_LAUNCHER_FNM_ACTIVE": "1",
    "PERPLEXITY_API_KEY": "${PERPLEXITY_API_KEY:-}"
  }
}
```

Cursor, `.cursor/mcp.json`: the same entry, with Cursor's own
interpolation syntax for the key:

```json
"env": {
  "MCP_LAUNCHER_FNM_ACTIVE": "1",
  "PERPLEXITY_API_KEY": "${env:PERPLEXITY_API_KEY}"
}
```

Codex, `.codex/config.toml`. Codex filters a stdio server's environment to
its allowlist, so the key is passed through by name with `env_vars`:

```toml
[mcp_servers.perplexity]
command = "fnm"
args = ["exec", "--version-file-strategy=recursive", "--", "node", "tools/mcp-launcher/launcher.js",
        "--vault", "PERPLEXITY_API_KEY=perplexity-api-key", "-y", "@perplexity-ai/mcp-server@0.9.0"]
env_vars = ["PERPLEXITY_API_KEY"]

[mcp_servers.perplexity.env]
MCP_LAUNCHER_FNM_ACTIVE = "1"
```

The secret name after `=` is the `vault-exec` secret name, never the value.
In a cloud session, set the variable in that surface's own environment or
secret store; the launcher then never looks for `vault-exec`.

## Tests

[`launcher.test.mjs`](launcher.test.mjs) runs on Windows and Linux with
`node --test components/mcp-launcher/launcher.test.mjs`. Stubs stand in for everything
external, and no test reads a real secret:

- [`fixtures/vault-exec`](fixtures/vault-exec) (Linux and macOS) and
  [`fixtures/vault-exec.ps1`](fixtures/vault-exec.ps1) (Windows) keep the real
  argv contract, set each name to `stub-<secret>` or leave it unset, and log
  every call. A nested call exits 99, so a broken loop guard fails the test
  instead of recursing.
- [`fixtures/stub-server.js`](fixtures/stub-server.js) echoes stdin to stdout
  and exits with a chosen code.

Each test installs the stub under a temporary home (`HOME`, `USERPROFILE`) and
runs the launcher against a server in a temporary git repository. The Windows
resolver cases skip when `pwsh` is not installed. CI runs the suite on Linux.
