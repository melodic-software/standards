# harness

Shared contract-test infrastructure for components. Dependency-light by design: the shell harness needs only `bash`, `git`, and coreutils.

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

`lib.sh` provides the full assertion set — equality, containment, exit code, file presence, line and row counts, command-failure, and `skip_suite`/`skip_case`. Its header documents each and the parameter-order convention.

## Package lifecycle tests

[`packages/README.md`](packages/README.md) documents the packed-payload and
version-lifecycle harness used by publishable component packages.
