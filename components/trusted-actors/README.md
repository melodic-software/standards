# Trusted actors

`trusted-actors.json` is the one list of GitHub accounts whose text may reach
the prompt of a CI lane, a GitHub Actions job that runs Claude Code with a write
token. Each lane reads the list from the pull request's base commit and drops
every comment, review, and body written by an account not on it. Lanes match on
`id`, never on `login`: a login can be renamed or re-registered, a user id
cannot. `trusted-actors.schema.json` is the structural contract.

The sync materializes both files at `.github/standards/trusted-actors/` in each
consuming repository. How the lanes use the list is in the
[pr-pipeline convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md).

## Changing the list

This is a lane-power file: adding an account lets its text steer a lane that
holds write credentials. A human reviews and merges every change; no lane or bot
merges one.

To add an account, append one entry. Take `id` from the API, not from the
profile page:

```sh
gh api users/<login> --jq '[.id, .login, .type]'
```

URL-encode the brackets of an App bot login (`dependabot%5Bbot%5D`). `kind` is
`bot` when `type` is `Bot` or when an agent signs in as the account (`cursoragent`
is a `User` account listed as `bot`), and `human` for a person. A lane that grants
extra power to listed humans, such as `eval-browser-dispatch`, so excludes agent
identities.

Owner decision Q661 (2026-10-18) trusts Codex, GitHub Actions, Cursor, Claude and
the org's own GitHub Apps. Because `github-actions[bot]` and
`chatgpt-codex-connector[bot]` are listed, text either account writes reaches a
lane prompt. Add the bot user of each new App owned by `melodic-software`.
