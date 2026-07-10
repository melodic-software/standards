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
