# Lychee

Local link and Markdown-anchor validation with
[Lychee](https://github.com/lycheeverse/lychee). The config is the
root-canonical [`lychee.toml`](../../lychee.toml), which the sync does not
copy into other repositories.

The blocking `ci-workflows` action runs offline for deterministic local-file and
fragment checks. External URLs are checked only by a manual online run, because
network health is inherently transient.

`fixtures/` and `lychee.test.sh` prove valid links and missing file/fragment
failures with Lychee 0.24.2+.

## Defaults, extensions and overrides

A repository keeps no copy. The `lychee-offline` composite and the online
`maintenance-check-links-online` reusable read this repository's `lychee.toml`
at run time, and a repository changes it only by stating its difference.
Lychee 0.24.0 and later read `--config` repeatedly and merge the files, later
ones winning ([CLI docs][2], read 2026-11-24); the readers pass this file
first and the repository's own second.

| Mode | What the repository commits | Result |
| --- | --- | --- |
| Default | nothing | this file alone |
| Extension | root `lychee.toml` with only the added `exclude`, `exclude_path` or `remap` entries | both files' entries apply; an array in the repository's file adds to this one's and cannot remove an entry from it |
| Partial override | root `lychee.toml` with only the changed scalar keys (`hidden`, `include_fragments`, `max_retries`, ...) | the repository's value wins; every other key stays this file's |
| Complete override | a ruleset at another path, passed as the reader's `config` input (`lychee-offline` `config:`, the reusable's `config:`) | that file alone; nothing here applies |

Precedence, lowest to highest: this file, the repository's root
`lychee.toml`, then command-line flags (a reader's `exclude` input becomes
`--exclude-path` and adds to both files' lists). A `.lycheeignore` in the
working directory adds URL excludes in every mode; it is the place for an
exact-URL exception one repository alone cites. `lychee.test.sh` proves the
extension, partial-override, complete-override and `.lycheeignore` cases
against this file.

A local check-cmd matches CI by passing the same files in the same order:
`--config "<standards checkout>/lychee.toml"`, then `--config lychee.toml` when
the repository has one.

Manual online runs exclude explicitly inventoried private GitHub repository and
raw-content URLs whose auth boundary makes an unauthenticated request receive
a 404. The inventory itself lives in the two `melodic-software/` alternations in
[`lychee.toml`](../../lychee.toml)'s `exclude` list. Read it there rather than
from a copy here. It is generated, not hand-edited:
[`private-repo-inventory.sh`](private-repo-inventory.sh) derives it from actual
repository visibility (`generate --write`, using the maintainer's `gh`
credential). `check`, in the `pr-require-checks` markdown-and-links job, fails
when an excluded repository went public and holds the two alternations sorted
and identical. A private repository missing from the list has no check: it
shows up as a 404 in the next online run, which names the repository. Run
`generate --write` when the org gains a private repository, or when an online
run reports one. Fix it at this source. Public siblings and stale pre-transfer owner
URLs remain checked. Public bot-blocking
exceptions are scoped to the exact URL, not the host: every other URL on
those hosts remains checked. The specific exceptions are inventoried alongside
the private-repo entries in [`lychee.toml`](../../lychee.toml)'s `exclude`
list. Lychee documents `exclude` values as URL regular expressions in its
[link-exclusion recipe][1]. Each `exclude` entry is a checker-side limit on a
link verified live, never a dead link silenced; the commit that adds an entry
records that verification.

## Status handling and fragment remaps

An online run accepts a 429, any 5xx and a timeout (`accept`,
`accept_timeouts`): none says whether the link is dead, while a 404, a 410 and
every other 4xx still fail. `accept` replaces Lychee's default set, so it
restates `100..=103` and `200..=299`. The cost: an accepted 429 or 5xx is final
on the first reply, so it is not retried and its fragment is not checked; the
online run's job summary lists those links, so a host that stays down is
noticed. Revisit accepting 5xx when
[lycheeverse/lychee#2324](https://github.com/lycheeverse/lychee/pull/2324)
ships in a release. The offline lane sends no request, so neither key changes it.

`remap` drops a fragment that exists only after the page's JavaScript runs
(GitHub comment and review anchors, PyPI's `#files`, docs.github.com GraphQL
reference entries), which Lychee reports as missing
([#1729](https://github.com/lycheeverse/lychee/issues/1729),
[#2128](https://github.com/lycheeverse/lychee/issues/2128)); the page itself is
still checked, and the first matching rule wins.

## Run the online check

From a consumer's root, with the pinned Lychee version and `STANDARDS_DIR` a
standards checkout (add `--config lychee.toml` after it when the consumer has
one):

```bash
GITHUB_TOKEN="$(gh auth token)" lychee --config "$STANDARDS_DIR/lychee.toml" \
  --no-progress --max-retries 2 './**/*.md'
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
[2]: https://lychee.cli.rs/guides/cli/#-c---config
