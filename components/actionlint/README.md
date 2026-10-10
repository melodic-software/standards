# actionlint

Lint policy for [actionlint](https://github.com/rhysd/actionlint) workflow
linting. The exported payload is the root-canonical
[`.github/actionlint.yaml`](../../.github/actionlint.yaml): a
`self-hosted-runner.labels` allowlist naming the fleet runner labels Phase 4 of
the ci-perf program
([melodic-software/github-iac#378](https://github.com/melodic-software/github-iac/issues/378))
writes literally in `runs-on`, which actionlint would otherwise reject as
unknown labels.

The config also carries a scoped `paths` ignore for the `$/` same-release
reference (`uses: $/.github/actions/<name>`) that reusables use for sibling
actions. actionlint 1.7.12 rejects it with `ref is missing`; the ignore matches
only that message for a `$/` path, so a ref-less `owner/repo/path` still fails.
actionlint cannot resolve the local action, so `with:` input validation is lost
for `$/` steps. Remove the ignore when
[rhysd/actionlint#732](https://github.com/rhysd/actionlint/issues/732) ships
and the pinned actionlint is bumped.

A second scoped ignore admits GitHub's GA `concurrency.queue` key, which
actionlint 1.7.12 rejects with `unexpected key "queue" for "concurrency"
section` ([rhysd/actionlint#654](https://github.com/rhysd/actionlint/issues/654)).
claude-code-plugins `pr-refine.yml` uses `queue: max` for its per-PR write
queue. Remove the ignore when #654 ships and the pinned actionlint is bumped.

Execution and the engine pin are owned by the actionlint action in
`ci-workflows`. `fixtures/` and `actionlint.test.sh` prove the allowlist against
that entrypoint: a two-job fleet-label workflow lints clean with the config, an
undeclared fleet-shaped label still fails alongside it, and a configless control
run reproduces both label errors. The control case is the removal tripwire: it
fails once a fleet label becomes built-in, so the stale entry gets dropped.
The `$/` cases follow the same shape: a `$/` workflow lints clean, a ref-less
`owner/repo/path` still fails, and a configless control run reports the `$/`
reference, which fails once actionlint accepts it natively. The queue cases
match: a queue workflow lints clean, an unrelated unexpected key still fails,
and a configless control run reports the queue message.
