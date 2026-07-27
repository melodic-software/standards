# actionlint

Suppression policy for [actionlint](https://github.com/rhysd/actionlint)
workflow linting. The exported payload is the root-canonical
[`.github/actionlint.yaml`](../../.github/actionlint.yaml): a `paths` ignore
scoped to exactly the `concurrency.queue` syntax-check false positive
([rhysd/actionlint#654](https://github.com/rhysd/actionlint/issues/654)) that
would otherwise fail every workflow using GitHub's GA queue serialization.

Execution and the engine pin are owned by the actionlint action in
`ci-workflows`. `fixtures/` and `actionlint.test.sh` prove the suppression
against that entrypoint: the queue workflow lints clean with the config, an
unrelated violation still fails alongside it, and a configless control run
reproduces the suppressed message. The control case is the removal tripwire —
when rhysd/actionlint#654 ships in the pinned engine it fails, firing the
removal trigger recorded in the config instead of leaving a stale suppression.
