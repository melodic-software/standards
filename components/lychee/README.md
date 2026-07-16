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
a 404. The current inventory is `melodic-software/claude-code-plugins`,
`dotfiles`, `github-iac`, `medley`, `provisioning`, and `standards`; public
siblings and stale pre-transfer owner URLs remain checked. Public bot-blocking
exceptions are path-scoped to the current Medium Dungeon Master article, Miro
article `31624028247058`, IsDown's Anthropic status page, and the npm package
pages for `firecrawl-cli` and `@mirohq/miro-api`; every other URL on those hosts
remains checked. Lychee documents `exclude` values as URL regular expressions
in its [configuration guide][1].

[1]: https://lychee.cli.rs/guides/config/#excluding-links
