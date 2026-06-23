# Cross-platform review criteria

Diff-time checks for code, scripts, config, and filenames that work on one operating system but break on another. Severity labels are defined in [README.md](README.md). Apply this slice on any change touching filenames, shell scripts, path construction, process spawning, committed generated output, or docs with OS-specific examples.

**Gate question:** would a developer cloning this repo on Windows, macOS, or Linux get the same behavior without changing code or config? If no, it is a finding.

## Assumptions

- **No implicit OS** — behavior must not depend on which OS the author used. Flag code, scripts, and docs that assume a single platform, a default shell, or a preinstalled tool.
- **No implicit environment** — home-directory layout, drive letters, usernames, hostname, or machine-local install paths are not required for core workflows.
- **No implicit shell** — a script that requires a specific shell states that requirement explicitly, and the repo offers an equivalent path for the other supported shells where applicable.

## Filesystem and paths

- **Portable paths only** — resolve paths relative to a known anchor (the repo root, a config file, an environment variable). Never hardcode an absolute or platform-rooted path; construct paths with the platform's path API rather than concatenating separators.
- **Case and collision awareness** — Linux is case-sensitive; macOS and Windows usually are not. Two tracked files differing only in case collide. Path comparisons account for case-insensitive filesystems.
- **Safe filenames** — tracked names are valid on every target OS. Avoid the Windows-reserved characters (`: ? * < > | "` and backslash), reserved base names (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`), and trailing dots or spaces (silently stripped by Windows). A colon or backslash makes checkout fail on every Windows clone.
- **Path length and depth** — avoid designs that break legacy path limits or nest excessively on any target.
- **Link and permission tolerance** — do not assume symlinks, hard links, or executable bits behave identically everywhere.

## Text, encoding, and line endings

- **UTF-8 for text** — source, config, and machine-readable output default to UTF-8 unless a format mandates otherwise.
- **Consistent line endings** — the line-ending authority is the repo's `.gitattributes` (`modules/editorconfig/` ships the canonical base hygiene); flag scripts and pipelines that fail to tolerate the other convention when reading files, and never commit literal carriage-return line endings in source. A pipeline parsing tool output on Windows that does not strip carriage returns is a common injection of stray characters.
- **Locale-independent machine output** — timestamps, numbers, and sort order in logs and artifacts use fixed, invariant formats (ISO-8601, ordinal comparison), not locale defaults.

## Tools, processes, and committed artifacts

- **Declared dependencies** — every external CLI or runtime a change requires is documented and discoverable (a README, a bootstrap script, a CI image).
- **Graceful absence** — an optional tool fails with a clear message, not a cryptic platform error.
- **Multi-OS verification** — an OS-sensitive change is covered by a CI matrix, a container, or an explicit manual-verification note in the change.
- **Reproducible tree** — nothing committed should differ by host: caches, logs, per-user approvals, or absolute paths baked into generated files. Ask whether two developers on different OSes would produce the same diff from the same command.
- **Portable documentation** — use placeholders (`<repo-root>/`, `~/`) in docs; never embed a real username, drive letter, or machine-specific path in tracked instructions.
