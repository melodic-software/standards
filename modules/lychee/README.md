# lychee module

Link checking via [lychee](https://github.com/lycheeverse/lychee).

## Contents

- `lychee.toml` — the ruleset: fragment checking (`include_fragments = "full"`),
  repo-agnostic path excludes, and URL excludes for the online lane (auth-walled
  hosts, loopback, placeholders). Shared by both CI lanes.

lychee is a single binary with no runner script. Two CI lanes in `ci-workflows`
consume this config:

- an **offline** composite action — runs `lychee --offline` so external URLs are
  skipped and only local file links and `#anchors` are verified on disk. It is
  deterministic, so it feeds the required `ci-status` check.
- an **online** advisory reusable workflow — checks external URLs on a schedule
  and files a tracking issue on failure. It is not a blocking gate, because
  external link health is inherently flaky (transient outages, anti-bot 403/429).

## Engine

Requires [lychee](https://github.com/lycheeverse/lychee) 0.24.2+.

## Adopt in a repo

1. Copy `lychee.toml` into the consuming repo — canonical home `modules/lychee/`.
2. Reference the `ci-workflows` lychee offline action from CI (its `config` input
   pointing at the copied ruleset), and optionally the online advisory workflow.

## Test

`fixtures/lychee/{good,bad}` exercise the offline checker; `lychee.test.sh`
asserts the good fixture's local links resolve and the bad fixture's broken
file/anchor references are flagged, via the shell harness
(`harness/shell/run-tests.sh`). The `bad` fixture is intentionally
non-conforming and excluded from the repo's own self-lint.
