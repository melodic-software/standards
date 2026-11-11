# Issue-body contract

[`contract.json`](contract.json) is the one record of what an org issue body holds, per issue
type (bug, feature, task, agent-ready work item): its fields and their headings, which are
required, the labels a new issue gets (the `needs-triage` floor), and its native issue type.
Everything that writes or checks an issue body reads it:

| Consumer | How it gets the contract |
| --- | --- |
| Org issue forms in `melodic-software/.github` `.github/ISSUE_TEMPLATE/` | [`issue-forms.mjs`](issue-forms.mjs) generates [`forms/`](forms/) from the contract; the sync (`issue-forms` component) materializes them byte-exact, with the contract beside them at `.github/standards/issue-body-contract/contract.json` for that repository's own drift check |
| `/bugs:write` | sync copy at `plugins/bugs/reference/issue-body-contract.json` in `claude-code-plugins` |
| `/work-items:track add`, `decompose`, `triage` | sync copy at `plugins/work-items/reference/issue-body-contract.json` in `claude-code-plugins` |

`config.yml` (blank issues off, the `SUPPORT.md` contact link) stays owned by
`melodic-software/.github`; the sync never touches it.

## Changing a form

Edit `contract.json`, run `node components/issue-body-contract/issue-forms.mjs write`, and commit
both. `npm run lint:issue-forms` fails CI when the committed forms differ from what the contract
generates; `npm run test:issue-forms` holds the generator and the contract rules. Keep each form's
file name: the sync never deletes, so a renamed form leaves the old one in the template chooser
until a pull request in the target removes it.

## Rules the contract keeps

- **Headings.** A form renders each field as `### <heading>`; a skill writes `## <heading>`. A
  body check accepts either level (`headingLevels`) and treats `emptyAnswer`, which a form writes
  for a skipped field, as missing under a required heading.
- **No role labels.** A form applies only the floor labels. `agent-ready` is granted at triage,
  never by a public form.
- **One form without a native type.** The agent-ready work item sets `nativeType: null`: triage
  picks Bug, Feature or Task. It is also what keeps the community profile counting the org's
  issue templates, which it stopped doing for every public repository once all three forms set
  `type:`. The generator refuses a contract in which every type sets one.
  - Pointer: the community page at `https://github.com/<owner>/<repo>/community` ("Issue
    templates" row), compared across public repositories whose forms all set `type:` and ones
    with at least one form or Markdown template that does not; the documented requirement is
    [About community profiles for public repositories](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories#using-the-community-profile-checklist-as-a-repository-maintainer).
  - As of: 2026-11-11.
  - Recheck trigger: a public org repository's community page shows "Issue templates" added
    while every form sets `type:`, or that docs section changes.

## Ownership

Owner: the standards maintainers. Rollback: revert the admitting pull request; the forms it
replaced remain in `melodic-software/.github` history, and the plugin copies fall back to the
skills' previous inline skeletons by reverting their pull request.
