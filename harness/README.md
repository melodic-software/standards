# harness

Shared test infrastructure the modules rely on. Dependency-light by design: the shell harness needs only `bash`, `git`, and coreutils.

## Shell tests

Convention: a `*.test.sh` file lives next to the script it tests, sources the assertion library, and ends by exiting non-zero if any assertion failed.

```bash
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"
FAILED=0
CASE_NUM=0

assert_eq "label" expected "$actual"

[[ $FAILED -eq 0 ]] || exit 1
```

Run the whole suite (locally or in CI — same command):

```bash
bash harness/shell/run-tests.sh
```

Or run specific files:

```bash
bash harness/shell/run-tests.sh path/to/a.test.sh
```

`run-tests.sh` discovers every `*.test.sh` in the repo, runs each, and reports a per-file status plus a summary. A file passes when it exits 0; a file that exits 0 with a `SKIP:` marker and no `PASS:` lines counts as skipped.
