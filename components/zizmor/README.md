# zizmor

Audit policy for [zizmor](https://docs.zizmor.sh/), the GitHub Actions
security linter. The exported payload is the root-canonical
[`.github/zizmor.yml`](../../.github/zizmor.yml), which is also this
repository's own live config. It sets two rules:

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
  pin also satisfies `ref-pin`. While the org Actions setting requires every
  action pinned to a full commit SHA, GitHub still refuses a floating action
  ref at run time, so first-party and vendor actions keep their SHA pins until
  that setting is off.

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

## Verification

`zizmor.test.sh` runs zizmor against a scratch repository holding the config
and `fixtures/`. A first-party reusable and composite action on `@main`, a
GitHub action on a tag, a SHA-pinned third-party action, a tagged action from
each other vendor owner, and a Dependabot file with a 3-day cooldown audit
clean whether the input is `.`, `.github` or `.github/workflows`. A third-party
tag (`fixtures/bad/`) still fails. A configless control run flags the
first-party refs, the vendor tags and the cooldown; it fails once zizmor's
defaults change, which is the trigger to recheck this policy.
