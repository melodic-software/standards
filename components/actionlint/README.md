# actionlint

Lint policy for [actionlint](https://github.com/rhysd/actionlint) workflow
linting. The exported payload is the root-canonical
[`.github/actionlint.yaml`](../../.github/actionlint.yaml), which carries two
things: a `paths` ignore scoped to exactly the `concurrency.queue` syntax-check
false positive
([rhysd/actionlint#654](https://github.com/rhysd/actionlint/issues/654)) that
would otherwise fail every workflow using GitHub's GA queue serialization, and a
`self-hosted-runner.labels` allowlist naming the fleet runner labels Phase 4 of
the ci-perf program
([melodic-software/github-iac#378](https://github.com/melodic-software/github-iac/issues/378))
writes literally in `runs-on`, which actionlint would otherwise reject as
unknown labels.

Execution and the engine pin are owned by the actionlint action in
`ci-workflows`. `fixtures/` and `actionlint.test.sh` prove both halves against
that entrypoint: the queue workflow and a two-job fleet-label workflow lint
clean with the config, an unrelated violation and an undeclared fleet-shaped
label still fail alongside them, and a configless control run reproduces the
suppressed message and both label errors. The control case is the removal
tripwire: when rhysd/actionlint#654 ships in the pinned engine it fails, firing
the removal trigger recorded in the config instead of leaving a stale
suppression.
