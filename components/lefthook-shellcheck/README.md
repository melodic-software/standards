# Lefthook ShellCheck

Opt-in staged-shell-script feedback. `lefthook.yml` runs ShellCheck for staged
`.sh` and `.bash` files and lets ShellCheck discover the root `.shellcheckrc`.
Compose it with the `lefthook-base` component, which supplies the common strict
settings and root-aware glob matcher. This fragment owns execution only; the
`shellcheck` component owns policy.

`lefthook-shellcheck.test.sh` builds a temporary consumer, composes the managed fragment,
and proves both enforcement and the native `skip: true` opt-out.
