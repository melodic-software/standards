# actionlint

Lint policy for actionlint workflow linting. The exported payload is the
root-canonical [`.github/actionlint.yaml`](../../.github/actionlint.yaml): a
`self-hosted-runner.labels` allowlist naming the fleet runner labels Phase 4 of
the ci-perf program
([melodic-software/github-iac#378](https://github.com/melodic-software/github-iac/issues/378))
writes literally in `runs-on`, which actionlint would otherwise reject as
unknown labels.

The engine is the [kjanat/actionlint](https://github.com/kjanat/actionlint)
fork, in CI and on every host. It accepts the `$/` same-release reference,
`concurrency.queue`, job-level `cache-mode` and the `issues` activity types
`field_added` and `field_removed` natively, so the config carries no ignore for
them; upstream [rhysd/actionlint](https://github.com/rhysd/actionlint) 1.7.12
rejects all four.

Execution and the engine pin are owned by the actionlint action in
`ci-workflows`. `fixtures/` and `actionlint.test.sh` prove the allowlist against
that entrypoint: a two-job fleet-label workflow lints clean with the config, an
undeclared fleet-shaped label still fails alongside it, and a configless control
run reproduces both label errors. The control case is the removal tripwire: it
fails once a fleet label becomes built-in, so the stale entry gets dropped.
