# ShellCheck

Static analysis policy for Bash scripts with
[ShellCheck](https://www.shellcheck.net/). The exported payload is the
root-canonical [`.shellcheckrc`](../../.shellcheckrc). It selects high-value
optional checks individually instead of enabling every subjective optional
rule.

Execution is owned by the ShellCheck action in `ci-workflows`; the separate
`lefthook-shellcheck` component adds staged-file feedback. `fixtures/` and
`shellcheck.test.sh` prove both default and config-enabled diagnostics with
ShellCheck 0.11.0+.

## Defaults, extensions and overrides

The ci-workflows `shellcheck` composite and the melodic-software/claude-code-plugins lefthook remote (for a repository whose `docs/conventions/source-control.yaml` names `standards_repository`) read this file at run time. ShellCheck reads one config and has no include or extends, so a repository's own file replaces this one whole; with none, the readers pass this file (`--rcfile`).

| Mode | What the repository commits | Result |
| --- | --- | --- |
| Default | nothing | this file alone |
| Extension | per-finding suppressions: `# shellcheck disable=SCxxxx` directives | this file plus the suppressions |
| Complete override | its own `.shellcheckrc` (any, in the repository) | that file alone; nothing here applies |

A partial override has no native mechanism; a repository that needs one copies this file and edits it.
