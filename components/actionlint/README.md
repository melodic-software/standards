# actionlint

Lint policy for [actionlint](https://github.com/rhysd/actionlint) workflow
linting. The exported payload is the root-canonical
[`.github/actionlint.yaml`](../../.github/actionlint.yaml): a
`self-hosted-runner.labels` allowlist naming the fleet runner labels Phase 4 of
the ci-perf program
([melodic-software/github-iac#378](https://github.com/melodic-software/github-iac/issues/378))
writes literally in `runs-on`, which actionlint would otherwise reject as
unknown labels.

Execution and the engine pin are owned by the actionlint action in
`ci-workflows`. `fixtures/` and `actionlint.test.sh` prove the allowlist against
that entrypoint: a two-job fleet-label workflow lints clean with the config, an
undeclared fleet-shaped label still fails alongside it, and a configless control
run reproduces both label errors. The control case is the removal tripwire: it
fails once a fleet label becomes built-in, so the stale entry gets dropped.
