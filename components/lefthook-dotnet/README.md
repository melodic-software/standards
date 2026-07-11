# Lefthook .NET

Opt-in staged C# whitespace verification. Compose this fragment with
`lefthook-base`, then merge one explicit workspace into the inherited command
from the consumer's root `lefthook.yml`:

```yaml
pre-commit:
  commands:
    dotnet-format:
      env:
        DOTNET_FORMAT_WORKSPACE: Repository.sln
```

The value is a repository-relative `.sln`, `.slnx`, or `.csproj` path. It is
required even when the repository currently has only one workspace, preventing
a later project or solution from silently changing hook behavior.

The managed `dotnet-format-staged.mjs` wrapper validates the workspace stays
inside the repository, rejects absolute, drive-qualified, drive-relative, UNC,
and cross-volume Windows paths, ignores deleted staged files, normalizes
existing C# paths relative to the repository root, and spawns `dotnet` without
a shell so spaces and shell metacharacters remain argument data. It runs the
equivalent of `dotnet format whitespace <workspace> --verify-no-changes
--include <files>`.

The containment checks use Node's platform-specific and `path.win32` semantics,
including the documented per-drive behavior and UNC handling in the
[`node:path` reference][1].

Analyzer builds remain in CI because they are too broad and expensive for a
per-file pre-commit lane. The wrapper's Node runtime comes from the required
`node-runtime` component.

[1]: https://nodejs.org/api/path.html
