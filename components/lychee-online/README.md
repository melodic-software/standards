# lychee-online callers

Sync-managed callers for the weekly online link check, the `ci-workflows`
reusable `.github/workflows/maintenance-check-links-online.yml`
(ci-workflows#739). The reusable runs lychee with the network on over the
target's Markdown with its managed [`lychee.toml`](../lychee/README.md) and
its own `.lycheeignore`, writes the report to the job summary, fails red on a
broken link, and holds only the `GITHUB_TOKEN`. It opens no issue and posts
no comment, and it is not part of any `ci-status`.

## Opt-in

Two switches, each with one job:

- **Delivery**: a target gets a caller only when it manages its own
  `lychee-online-<repo>` component. The cron is the one value that differs
  per target, and the manifest has no per-target values or transforms
  (`distribution/README.md`), so each target has its own source file under
  `targets/`. Destinations must be unique across components, so each
  destination carries the repository name.
- **Schedule**: the org custom property `link-check-online` (`true_false`, no
  default; unset means off). The reusable reads it on a `schedule` run and
  skips unless it is `true`. A `workflow_dispatch` run always checks.

To opt a repository in: add its caller here and dispatch it once the sync
delivers it. When that run is green, or fails only on man7.org, link it on
ci-workflows#739 and set the property to `true`. A repository whose property
is unset gets no scheduled online run even if it carries a caller.

## Cron slots

Each target picks a minute and a weekday no other target uses, so targets do
not hit the same hosts at once.

| Target | Cron (UTC) | Source |
| --- | --- | --- |
| `claude-code-plugins` | `37 11 * * 2` (Tuesday 11:37) | `targets/claude-code-plugins.yml` |

## Pin

The caller pins the reusable by full SHA, and
`components/runner-policy/policy.json` carries the matching
`approvedReusableWorkflowContracts` entry, since `claude-code-plugins` runs the
runner-policy gate. These callers are not in the
`maintenance-repin-ci-workflows` cascade, and every consumer's Dependabot
ignores `melodic-software/ci-workflows/*`, so the pin moves by hand:

- **Owner**: `@kyle-sexton` (`.github/CODEOWNERS`).
- **Release source**: the
  [ci-workflows releases](https://github.com/melodic-software/ci-workflows/releases).
  Resolve a tag's commit with
  `gh api repos/melodic-software/ci-workflows/git/ref/tags/<tag>`, and
  dereference it if the ref is an annotated tag object.
- **Trigger**: each `chore/repin-claude-lanes` pull request that
  `.github/workflows/maintenance-repin-ci-workflows.yml` (daily) opens for a
  new ci-workflows release. Its reviewer runs the procedure below in the same
  review window.
- **Procedure**:
  1. Diff `.github/workflows/maintenance-check-links-online.yml` between the
     pinned commit and the new tag. If it is unchanged, a re-pin is optional.
  2. If the `workflow_call` inputs, secrets or permissions changed, update the
     contract's `allowedInputs`, `allowedSecrets` and
     `minimumCallerPermissions`.
  3. Move every target's caller pin (`@<sha> # <tag>`) and the
     `policy.json` contract key together, in one pull request.
  4. Run `node --test components/runner-policy/runner-policy.test.mjs`.

## Exceptions

Exact-URL `.lycheeignore` entries in the target, each with a dated reason,
only for pages proven alive that block the checker; shared ones go in the
managed `lychee.toml`. Per-host pacing (standards#775, removed in #776) did not
stop runner 429s, and a single red run on a github.com blob page 503 is not
proof of rot.
