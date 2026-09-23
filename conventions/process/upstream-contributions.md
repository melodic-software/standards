# Upstream contributions

How a bug report, feature request, or pull request is filed against a project this organization
does not own. Some projects ban AI-generated contributions outright and ban the contributor who
breaks the rule; filing agent-written text there costs the human their standing in that project.

## Check the policy before filing

Before filing anything upstream, read the target project's contribution policy: `CONTRIBUTING.md`
and `CODE_OF_CONDUCT.md` in the repository root, `docs/`, or `.github/` (GitHub accepts contribution
guidelines in any of the three), and the issue and pull-request templates, which can carry the rule
in a comment. A root-only check misses policies kept under `.github/`.

## When the project bans AI-generated contributions

- **A human writes and files it personally.** The report, issue, comment, or pull request is
  authored and submitted by the human, in their own words. An agent does not file it and does not
  draft the text that gets submitted, including a draft the human then edits.
- **An agent may gather facts into a private note.** Versions, reproduction steps, and code
  locations an agent verified can go into a note kept for the human. The note is not submitted,
  quoted, or pasted upstream. The human re-verifies each fact before relying on it; this is the
  organization's line, not permission granted by the project, and a project whose policy reaches
  AI-assisted research as well is honored as written.
- **When the policy is ambiguous**, treat it as a ban.

## Example

chezmoi bans LLM contributions in its
[`CONTRIBUTING.md`](https://github.com/twpayne/chezmoi/blob/593166436bf621259efb33d12ebeecd7bae17329/.github/CONTRIBUTING.md)
("If you use an LLM ... to make any kind of contribution then you will immediately be banned
without recourse"), its
[`CODE_OF_CONDUCT.md`](https://github.com/twpayne/chezmoi/blob/593166436bf621259efb33d12ebeecd7bae17329/.github/CODE_OF_CONDUCT.md),
and a comment at the top of its
[bug report template](https://github.com/twpayne/chezmoi/blob/593166436bf621259efb33d12ebeecd7bae17329/.github/ISSUE_TEMPLATE/03_bug_report.md).
All three live under `.github/`. Gentoo's council has forbidden contributing content created with
the assistance of natural-language-processing AI tools since 2024-04-14
([AI policy](https://wiki.gentoo.org/wiki/Project:Council/AI_policy)).

## Sources

Checked 2026-09. The chezmoi links are pinned to the commit read; recheck the live files before
relying on the quoted wording.

- chezmoi: `.github/CONTRIBUTING.md`, `.github/CODE_OF_CONDUCT.md`, and
  `.github/ISSUE_TEMPLATE/03_bug_report.md`, linked above
- Gentoo: [Project:Council/AI policy](https://wiki.gentoo.org/wiki/Project:Council/AI_policy)
- GitHub Docs: [Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)
