# URL exclusion boundaries

Private repositories intentionally excluded from the unauthenticated online
lane:

- <https://github.com/melodic-software/claude-code-plugins>
- <https://github.com/melodic-software/dotfiles>
- <https://github.com/melodic-software/github-iac>
- <https://github.com/melodic-software/medley>
- <https://github.com/melodic-software/provisioning>
- <https://github.com/melodic-software/standards>
- <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/README.md>

The exact current public URLs that reject automated link checkers are excluded:

- <https://medium.com/@ziobrando/the-rise-and-fall-of-the-dungeon-master-c2d511eed12f>
- <https://help.miro.com/hc/en-us/articles/31624028247058>
- <https://isdown.app/status/anthropic>
- <https://www.npmjs.com/package/firecrawl-cli>
- <https://www.npmjs.com/package/@mirohq/miro-api>
- <https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html>

Other paths on those public hosts remain subject to checking:

- <https://medium.com/example>
- <https://help.miro.com/hc/en-us/articles/example>
- <https://isdown.app/status/example>
- <https://www.npmjs.com/package/example>
- <https://dev.mysql.com/doc/refman/8.4/en/example.html>

Public siblings and stale pre-transfer owner links remain subject to checking:

- <https://github.com/melodic-software/ci-runner>
- <https://github.com/kyle-sexton/provisioning>
- <https://raw.githubusercontent.com/melodic-software/ci-runner/main/README.md>
