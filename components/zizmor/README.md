# zizmor

Audit policy for [zizmor](https://docs.zizmor.sh/), the GitHub Actions
security linter. The exported payload is the root-canonical
[`.github/zizmor.yml`](../../.github/zizmor.yml), which is also this
repository's own live config. It sets two rules:

- `dependabot-cooldown` accepts a 3-day `cooldown.default-days`, the org floor
  in [dependabot-policy](../dependabot-policy/README.md) (`cooldownMinimumDays`),
  below zizmor's default of 7.
- `unpinned-uses` lets `melodic-software/*` refs float on a branch or tag
  (`ref-pin`), so the synced ci-workflows reusable-workflow callers can use
  `@main`, and keeps every other ref SHA-pinned (`hash-pin`, zizmor's
  default). First-party actions stay SHA-pinned anyway, because the org
  requires actions pinned to a full commit SHA; a SHA pin also satisfies
  `ref-pin`. `maintenance-repin-ci-workflows` moves those pins on each
  ci-workflows release.

Both rules only relax zizmor's defaults, so adopting the file cannot add a
finding to a target.

## Discovery

zizmor reads the file without a `--config` flag. Per its
[configuration docs](https://docs.zizmor.sh/configuration/) (as of 2026-10-29;
recheck when a target bumps zizmor): "If the input is within a Git repository,
`zizmor` performs directory discovery starting (and ending) at the repository
root", and that search tries `.github/zizmor.yml` first. Discovery behavior
"changed significantly in `v1.13.0` and again in `v1.29.0`", so consumers need
zizmor 1.29.0 or newer. A `--config` flag or `ZIZMOR_CONFIG` replaces local
discovery, so a consumer that sets either does not read this file.

## Ownership

Managed consumers do not edit the file; the managed-files guard flags a
downstream edit. A repository that needs an extra rule (for example
ci-workflows' `self-repository` ignore) owns its copy as `locally-owned`, per
[Escape hatches](../../distribution/ESCAPE-HATCHES.md#opting-a-repository-out-of-a-managed-component),
and keeps both blocks above.

## Fleet sweep

Each repository's `CI Status` audits its own pull requests. The scheduled
[`maintenance-audit-action-pins`](../../.github/workflows/maintenance-audit-action-pins.yml)
workflow also audits every non-archived `melodic-software` repository's default
branch against this file, which catches a ref that merged without that check.
It clones each repository at depth 1 with only the root files and `.github`,
and [`sweep.sh`](sweep.sh) runs zizmor offline over the workflows and actions
there with ignore comments disabled, keeping only `unpinned-uses` findings. A
finding fails the run with one `UNPINNED:` line per ref. The run opens no
issue. Composite actions outside `.github` and the repository root are not
read. Private repositories outside the standards-sync App installation are
visible to neither token, as in `maintenance-audit-org-architecture-pointer`.
`sweep.test.sh` covers the script.

## Verification

`zizmor.test.sh` runs zizmor against a scratch repository holding the config
and `fixtures/`. A workflow with a first-party reusable on `@main`, a SHA-pinned
first-party composite action and a SHA-pinned third-party action, and a Dependabot file with a
3-day cooldown, audit clean whether the input is `.`, `.github` or
`.github/workflows`. A third-party tag (`fixtures/bad/`) still fails. A
configless control run flags the first-party reusable and the cooldown; it fails
once zizmor's defaults change, which is the trigger to recheck this policy.
