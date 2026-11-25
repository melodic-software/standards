# dependabot-automerge callers

Sync-managed thin callers for the `pr-automerge-dependabot.yml` reusable
workflow in `melodic-software/ci-workflows`
(`.github/workflows/pr-automerge-dependabot.yml@main`). The reusable arms
GitHub squash auto-merge on Dependabot non-major pull requests that satisfy the
merge tiers in the [dependabot-policy](../dependabot-policy/README.md), which
the reusable reads from this repository's `main`
(`components/dependabot-policy/policy.json`) when the target's
`docs/conventions/source-control.yaml` names `melodic-software/standards` as its
`standards_repository`.

Two files, one per `runner-policy` inventory, identical except for
`with.runner`, the workflow `name:` (each is its destination stem in Title
Case) and their headers:

| Manifest component | Source | Destination | `with.runner` |
| --- | --- | --- | --- |
| `dependabot-automerge-caller` | `dependabot-automerge.yml` | `.github/workflows/pr-automerge-dependabot-hosted.yml` | `ubuntu-24.04` |
| `dependabot-automerge-fleet-caller` | `dependabot-automerge-fleet.yml` | `.github/workflows/pr-automerge-dependabot.yml` | `melodic-ubuntu-24.04-x64` |

Neither requires another component: the policy (`fastTrack.own`,
`autoMerge.ecosystems`, `autoMerge.reviewOnly`) comes from standards, never from
a synced copy. The destinations differ because the manifest requires each
destination to have one owning component.

This pair is the fourth recorded exception to the rule that workflow callers
stay consumer-owned (`distribution/README.md`): 14 repositories previously
carried hand-copied 27–32 line callers that drifted in comments, key order, and
permission wording while invoking the identical reusable workflow.

## Admission evidence

Per [component lifecycle](../../docs/component-lifecycle.md#admission-evidence):

- **Live consumers**: 6 public targets (`melodic-software/.github`,
  `agent-plugins`, `ci-runner`, `claude-code-account-rotation`,
  `codex-plugins`, `cursor-plugins`) for `dependabot-automerge-caller`, and 8
  private fleet-enrolled targets (`agent-automations`, `architecture`,
  `claude-code-proxy`, `dotfiles`, `github-iac`, `knowledge-corpus`,
  `provisioning`, `songwriting`) for `dependabot-automerge-fleet-caller`.
  `ci-workflows` (hosts the reusable itself) and `medley` (carries an extra
  repo-local `automerge` job) stay `locally-owned`. `standards` is the manifest
  source, not a target, and keeps its repo-local caller with explicit
  `review-only-dependencies: '["yaml"]'`.
- **Owner and outcome**: owned by the `standards` maintainers; `ci-workflows`
  maintainers own the reusable workflow. Problem: 14 hand-maintained thin
  callers drifted across repositories (`melodic-software/control-hub#17`, Row
  5). Acceptance: every managing target receives byte-exact caller bytes from
  `standards-sync`, and each public target deletes its superseded
  `.github/workflows/pr-automerge-dependabot.yml` so only the managed caller
  runs. Rollback: move the component to `locally-owned` for a target, or remove
  it from the manifest; deselection never deletes consumer files.
- **Delivery boundary**: exact materialization of the thin caller, matching
  `claude-lanes`, `managed-files-guard`, and `lychee-online`. Execution logic
  stays in `ci-workflows` via `@main`; policy data stays in
  `dependabot-policy`.
- **Alternatives and overlap**: hand-maintained callers drifted across 9
  variants; a single caller across both visibilities is blocked for the same
  reason as `claude-lanes` (one literal `with.runner` cannot satisfy both
  public hosted-only and private fleet-enrolled `runner-policy` rules). No
  other component owns `.github/workflows/pr-automerge-dependabot*.yml`.
- **Operational fit**: all 14 targets already execute this exact reusable
  workflow on every pull request under the same permissions (`contents: write`,
  `pull-requests: write`) and runner labels (`ubuntu-24.04` /
  `melodic-ubuntu-24.04-x64`), with zero secrets forwarded and a 10-minute
  callee timeout. Failure behavior: the reusable fails closed on unreadable
  metadata or policy and disarms any previously armed non-qualifying pull
  request.
- **Upstream health**: first-party workflow in `melodic-software/ci-workflows`;
  no third-party dependency added here.
- **Legal and security fit**: first-party YAML under the repository's license,
  covered by `components/runner-policy/policy.json`'s reviewed
  `approvedReusableWorkflowContracts` entry for
  `melodic-software/ci-workflows/.github/workflows/pr-automerge-dependabot.yml`
  and audited by zizmor in `pr-audit-workflows`.
- **Update path**: the reusable floats on `@main` per org policy; caller-shape
  changes land in one PR here and fan out via `standards-sync`.
- **Verification**: `dependabot-automerge.test.sh` checks parsed YAML shape,
  sibling parity, manifest wiring, the absence of any `requires` edge, and
  materialization + `actionlint`; `runner-policy.test.mjs` proves hosted and
  fleet callers audit clean on every managing target and fail on the opposite
  visibility/enrollment.
