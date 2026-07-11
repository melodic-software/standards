# Lefthook .NET

Opt-in staged C# whitespace verification. Compose this fragment with
`lefthook-base`, then add one consumer-owned data file at
`.lefthook/dotnet-format.json`:

```json
{
  "schemaVersion": 1,
  "workspace": "src/My Workspace.csproj"
}
```

The component owns one complete Lefthook [named job][1], including `run`,
`glob`, and `fail_text`; the consumer does not repeat or partially override
that job. The managed command never interpolates the workspace. The Node
wrapper reads the JSON file directly, validates exactly `schemaVersion` and
`workspace`, and rejects missing keys, unknown keys, malformed JSON, and schema
versions other than `1`.

The value is a repository-relative `.sln`, `.slnx`, or `.csproj` path. It is
required even when the repository currently has only one workspace, preventing
a later project or solution from silently changing hook behavior. It uses
forward slashes and portable path characters with no leading, trailing, or
control whitespace. Internal spaces and shell metacharacters remain ordinary
path data when those characters are otherwise portable, because the workspace
never enters a shell command.

The managed `dotnet-format-staged.mjs` wrapper validates both the configuration
and workspace stay inside the repository, rejects absolute, drive-qualified,
drive-relative, UNC, and cross-volume Windows paths, ignores deleted staged
files, normalizes existing C# paths relative to the repository root, and spawns
`dotnet` without a shell so workspace and staged-path spaces or shell
metacharacters remain argument data. It runs the equivalent of `dotnet format
whitespace <workspace> --verify-no-changes --include <files>`.

The containment checks use Node's platform-specific and `path.win32` semantics,
including the documented per-drive behavior and UNC handling in the
[`node:path` reference][2].

Analyzer builds remain in CI because they are too broad and expensive for a
per-file pre-commit lane. The wrapper's Node runtime comes from the required
`node-runtime` component.

[1]: https://github.com/evilmartians/lefthook/blob/v2.1.9/docs/configuration/jobs.md
[2]: https://nodejs.org/api/path.html
