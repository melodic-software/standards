# Lychee

Local link and Markdown-anchor validation with
[Lychee](https://github.com/lycheeverse/lychee). The exported payload is the
root-canonical [`lychee.toml`](../../lychee.toml).

The blocking `ci-workflows` action runs offline for deterministic local-file and
fragment checks. An online scheduled workflow may check external URLs
advisorially because network health is inherently transient.

Managed consumers do not edit the config. `fixtures/` and `lychee.test.sh`
prove valid links and missing file/fragment failures with Lychee 0.24.2+.

The online lane excludes explicitly inventoried private GitHub repository and
raw-content URLs whose auth boundary makes a calling repository's token receive
a 404. The inventory itself lives in the two `melodic-software/` alternations in
[`lychee.toml`](../../lychee.toml)'s `exclude` list. Read it there rather than
from a copy here. It is generated, not hand-edited:
[`private-repo-inventory.sh`](private-repo-inventory.sh) derives it from actual
repository visibility (`generate --write`, using the maintainer's `gh`
credential) and `check` fails when the two disagree, in the `lychee-fixtures`
CI lane for the direction a public token can see (an excluded repository that
went public; the alternations sorted and identical) and in the scheduled
`lychee-private-inventory` workflow for the direction it cannot (a new private
sync target missing from the list, read from the standards-sync App
installation). Private repositories outside the sync roster are the residual
the check reports as unverified. A new private repository therefore surfaces
as a tracking issue here within a day; fix it at this source, never in a
consumer's synced copy, which the next sync overwrites. Public
siblings and stale pre-transfer owner URLs remain checked. Public bot-blocking
exceptions are scoped to the exact URL, not the host: every other URL on
those hosts remains checked. The specific exceptions are inventoried alongside
the private-repo entries in [`lychee.toml`](../../lychee.toml)'s `exclude`
list. Lychee documents `exclude` values as URL regular expressions in its
[link-exclusion recipe][1].

[1]: https://lychee.cli.rs/recipes/excluding-links/
