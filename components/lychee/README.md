# Lychee

Local link and Markdown-anchor validation with
[Lychee](https://github.com/lycheeverse/lychee). The exported payload is the
root-canonical [`lychee.toml`](../../lychee.toml).

The blocking `ci-workflows` action runs offline for deterministic local-file and
fragment checks. External URLs are checked only by a manual online run, because
network health is inherently transient.

Managed consumers do not edit the config. `fixtures/` and `lychee.test.sh`
prove valid links and missing file/fragment failures with Lychee 0.24.2+.

A repository outside the sync keeps no copy: when the caller has no root
`lychee.toml`, the `lychee-offline` composite uses the canonical copy that
ci-workflows, a sync target, carries. The non-targets that rely on this are
listed with their reasons beside the `lychee` component in
[`sync-manifest.yml`](../../distribution/sync-manifest.yml).

Manual online runs exclude explicitly inventoried private GitHub repository and
raw-content URLs whose auth boundary makes an unauthenticated request receive
a 404. The inventory itself lives in the two `melodic-software/` alternations in
[`lychee.toml`](../../lychee.toml)'s `exclude` list. Read it there rather than
from a copy here. It is generated, not hand-edited:
[`private-repo-inventory.sh`](private-repo-inventory.sh) derives it from actual
repository visibility (`generate --write`, using the maintainer's `gh`
credential) and `check` fails when the two disagree, in the `lychee-fixtures`
CI lane for the direction a public token can see (an excluded repository that
went public; the alternations sorted and identical) and in the scheduled
`maintenance-audit-link-check-excludes` workflow for the direction it cannot (a new private
sync target missing from the list, read from the standards-sync App
installation). Private repositories outside the sync roster are the residual
the check reports as unverified, and no check catches one missing from the
list, so run `generate --write` whenever the org gains a private repository.
A new private sync target fails that scheduled workflow within a day; fix it at
this source, never in a consumer's synced copy, which the next sync overwrites. Public
siblings and stale pre-transfer owner URLs remain checked. Public bot-blocking
exceptions are scoped to the exact URL, not the host: every other URL on
those hosts remains checked. The specific exceptions are inventoried alongside
the private-repo entries in [`lychee.toml`](../../lychee.toml)'s `exclude`
list. Lychee documents `exclude` values as URL regular expressions in its
[link-exclusion recipe][1].

## Run the online check

From a consumer's root, with the pinned Lychee version:

```bash
GITHUB_TOKEN="$(gh auth token)" lychee --config lychee.toml --no-progress \
  --max-retries 2 './**/*.md'
```

In `standards` itself, add `--exclude-path '(^|/)components/lychee/fixtures/'`:
the fixtures hold placeholder URLs and intentionally broken links that the
offline test harness reads, so they are test data, not links to check.

The token lifts github.com's unauthenticated rate limit. A token that can read
a private repository makes Lychee report that repository's links OK without
checking the path, which is one more reason the private inventory above stays
an exclude list. Lychee also reads a `.lycheeignore` in the working directory
on top of `--config`, so a consumer's local file widens these excludes.

[1]: https://lychee.cli.rs/recipes/excluding-links/
