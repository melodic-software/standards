# Lefthook ShellCheck

Staged-shell-script feedback for this repository's own root `lefthook.yml`,
which extends `lefthook.yml` alongside `lefthook-base`; the sync manifest no
longer distributes it. The fragment runs ShellCheck for staged `.sh` and
`.bash` files and lets ShellCheck discover the root `.shellcheckrc`. It owns
execution only; the `shellcheck` component owns policy.

Other repositories get ShellCheck from the melodic-software/claude-code-plugins
aggregate remote, which runs it with the standards `.shellcheckrc` for a
repository that names `standards_repository` and has no `.shellcheckrc` of its
own. There is no remote form here.

`lefthook-shellcheck.test.sh` builds a temporary consumer, composes the fragment,
and proves both enforcement and the native `skip: true` opt-out.
