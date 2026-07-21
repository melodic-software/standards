# Bash review overlay

Stack-specific review bars for shell scripts. The mechanically enforced posture
is owned by the [`shellcheck`][1] component (with staged-file feedback from
[`lefthook-shellcheck`][2]), which ships the repo's `.shellcheckrc` and so
enforces more than stock ShellCheck — double-bracket tests, `command -v` over
`which`, useless-`cat`, a default case, and errexit-suppression detection among
them. This overlay covers only reasoning-tier judgments ShellCheck does not make.
Severity labels are defined in [../README.md](../README.md).

Apply it to `.sh` and `.bash` files and to shell embedded where ShellCheck does
not run — a Dockerfile `RUN`, a CI or Compose `run:` block, a heredoc. Embedded
shell has no mechanical backstop, so every bar below carries full weight there;
extracting it into a co-located script (`code-quality.md` owns that bar) is what
brings it under ShellCheck.

## Failure handling

- **`set -e` is not a safety net** — errexit silently does not fire when the
  failing command sits in an `if`/`while` test, in a `&&`/`||` chain other than
  the last command, is inverted with `!`, or, for a function, runs inside
  `$(...)`. A script leaning on `set -e` to halt before a destructive or
  irreversible step is fragile; the safety-critical path checks the status
  explicitly (`if ! cmd; then …`). Important; Critical when an unguarded failure
  proceeds to a destructive or irreversible action. The mechanically detectable
  suppression cases belong to the component. See the [Set builtin][3] and
  [BashFAQ 105][4].
- **pipefail-aware pipelines** — without `set -o pipefail` a pipeline's status is
  only its last command's, so a mid-pipe failure (a download that dies feeding an
  extract that succeeds) is masked. A pipeline carrying real data sets `pipefail`
  or inspects `PIPESTATUS`, captured immediately before the next command
  overwrites it. Important; Critical when the masked failure feeds a destructive
  or publishing step. See the [Set builtin][3].
- **Masked failure in a command substitution on a critical path** — the component
  leaves the general `var=$(cmd)` return check off as too noisy, so a swallowed
  failure inside a substitution on a correctness- or safety-critical path is
  review's job: `backup=$(mktemp -d); cp -a "$src" "$backup"; rm -rf "$src"`
  destroys the source with no backup if `mktemp` failed — the copy to an empty
  destination fails silently and the removal still runs. Important; Critical on a
  destructive path. See [SC2312][5].

## Resources and safety

- **Cleanup on every exit path** — temporary files and directories are created
  with `mktemp` (never a predictable `/tmp/$$` name) and removed by a
  `trap … EXIT`, so an early exit or error does not leak them, least of all one
  holding sensitive data. Important when the temp may hold sensitive data or the
  script has early-exit paths; Suggestion for a trivially short-lived helper. See
  the [Google shell style guide][6] and [BashPitfalls][7].
- **Dangerous idioms** — flag the shell shape, then defer the principle: an
  `eval` or `bash -c` built from data not fully under the author's control
  (`security.md` owns injection); a `rm -rf` or `cd … && rm -rf ./*` on a
  variable path with no `${var:?}` or non-empty guard, beyond the
  empty-expansion case the component already catches; a `curl … | bash` running
  unpinned remote code (`security.md` owns supply chain). Critical on these
  paths. See [SC2115][8] for the shape it does cover.

## Portability and shape

- **Quote for intent, with arrays** — the component flags an unquoted expansion
  mechanically but cannot tell a bug from deliberate word-splitting. When
  splitting is genuinely intended, the fix is a bash array (`cmd "${args[@]}"`),
  not a `# shellcheck disable=SC2086`. A disable on an expansion carrying a path
  or filename is a latent defect. Important; Critical when the value is
  attacker- or environment-influenced. See the [Google shell style guide][6] and
  [BashPitfalls][7].
- **Right dialect for the shebang** — a script using bash-only features
  (`[[ ]]`, arrays, `local`, `${var//}`) under a `#!/bin/sh` shebang breaks on
  dash or ash. The component's `.shellcheckrc` sets `shell=bash`, which
  *overrides* shebang-based detection entirely, so a `#!/bin/sh` shebang alone
  does not make ShellCheck check it as POSIX sh — a genuinely POSIX script needs
  an explicit `# shellcheck shell=sh` directive for the check to fire. That
  directive is the review-relevant gap. `cross-platform.md` owns shell
  portability. Important.
- **Past the shell threshold** — a script that has grown non-straightforward
  control flow, nested data structures, or heavy string or arithmetic parsing
  should be rewritten in a structured language, not extended. Suggestion,
  escalating to Important when the script is a maintenance or security liability.
  `code-quality.md` owns the god-file and embedded-script bars. See the
  [Google shell style guide][6] on when to use shell.

## Date and time

The shared [date-time criteria](../date-time.md) own the semantic and storage
contract. This overlay owns only what a shell script should do itself.

- **Keep portable output explicit and UTC** — for a portable current timestamp,
  use a fixed locale and POSIX `date`, for example
  `LC_ALL=C date -u '+%Y-%m-%dT%H:%M:%SZ'`. GNU `date -d`, `--iso-8601`,
  `--rfc-3339`, `%s`, `%N`, and `%z` are extensions; each use needs a declared,
  tested compatible runtime rather than being treated as POSIX-portable. See
  POSIX [`date`][10] and GNU's [option][11] and [format guidance][12].
- **Do not make `date` a business-calendar engine** — reject natural-language
  input and ambiguous abbreviations on correctness-critical paths. Parsing,
  named-zone conversion, recurrence, or civil-time arithmetic belongs in a
  structured runtime with a documented time-zone library once it passes the
  shell threshold.
- **Do not inherit the machine's local zone** — when local reporting is truly
  required on a known platform, set `TZ` for the individual command and verify
  that the deployed system contains the requested IANA data. `TZ` chooses the
  conversion context; it does not make a missing database appear. Otherwise use
  `-u`.
- **Delegate elapsed-time correctness** — portable shell has no standard
  monotonic-clock interface. A timeout, retry budget, or deadline whose
  correctness must survive wall-clock adjustment belongs in a runtime with a
  documented monotonic API, not arithmetic over `date` output.

## Testing

- **Tests for non-trivial scripts** — a script with real branching, parsing, or a
  safety-critical or destructive path has tests that execute it. Framework and
  placement are repository-specific; a common external option is [bats-core][9].
  Rewriting past the shell threshold is the alternative when a script has outgrown
  shell. General coverage is owned by `testing.md`.

[1]: ../../../components/shellcheck/
[2]: ../../../components/lefthook-shellcheck/
[3]: https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
[4]: https://mywiki.wooledge.org/BashFAQ/105
[5]: https://github.com/koalaman/shellcheck/wiki/SC2312
[6]: https://google.github.io/styleguide/shellguide.html
[7]: https://mywiki.wooledge.org/BashPitfalls
[8]: https://github.com/koalaman/shellcheck/wiki/SC2115
[9]: https://github.com/bats-core/bats-core
[10]: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/date.html
[11]: https://www.gnu.org/software/coreutils/manual/html_node/Options-for-date.html
[12]: https://www.gnu.org/software/coreutils/manual/html_node/General-date-syntax.html
