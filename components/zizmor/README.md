# zizmor

Audit policy for [zizmor](https://docs.zizmor.sh/), the GitHub Actions
security linter. The policy is the root-canonical
[`.github/zizmor.yml`](../../.github/zizmor.yml), which is also this
repository's own live config; the sync does not copy it into other
repositories. It sets two rules:

- `dependabot-cooldown` accepts a 3-day `cooldown.default-days`, the org floor
  in [dependabot-policy](../dependabot-policy/README.md) (`cooldownMinimumDays`),
  below zizmor's default of 7.
- `unpinned-uses` lets first-party and official-vendor refs float on a branch
  or tag (`ref-pin`) and keeps every other ref SHA-pinned (`hash-pin`, zizmor's
  default), moved by Dependabot under the cooldown above. The `ref-pin` owners
  are `melodic-software`; GitHub's `actions`, `github` and `dependabot`;
  Microsoft's `microsoft`, `azure` and `Azure`; Anthropic's `anthropics`; and
  OpenAI's `openai`. zizmor matches owners case-sensitively, so each spelling
  in use has its own entry and any other spelling falls to `hash-pin`. A SHA
  pin also satisfies `ref-pin`. First-party refs use `@main` and vendor refs
  the vendor's major tag (owner decision, architecture owner-decisions L351).

Both rules only relax zizmor's defaults, so reading this file cannot add a
finding to a repository.

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

A repository keeps no copy. The `ci-workflows` `pr-audit-workflows` reusable
audits with the caller's own config when it has one and with this file
otherwise. A repository that needs an extra rule commits its own
`.github/zizmor.yml`, which wins, and keeps both blocks above.

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
and `fixtures/`. A first-party reusable and composite action on `@main`, a
GitHub action on a tag, a SHA-pinned third-party action, a tagged action from
each other vendor owner, and a Dependabot file with a 3-day cooldown audit
clean whether the input is `.`, `.github` or `.github/workflows`. A third-party
tag (`fixtures/bad/`) still fails. A configless control run flags the
first-party refs, the vendor tags and the cooldown; it fails once zizmor's
defaults change, which is the trigger to recheck this policy.
