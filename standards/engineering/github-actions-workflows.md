# GitHub Actions workflow authoring

Organization-wide conventions for authoring GitHub Actions workflows that tooling alone does not decide: workflow dependency lockfiles, same-repository references, native step parallelism, and artifact/cache handling. Rules that an executable component already enforces are cited under [Mechanically enforced policy](#mechanically-enforced-policy), not restated here.

## Workflow dependency lockfile (`.github/workflows/actions.lock`)

Use GitHub's native workflow dependency lockfile (`.github/workflows/actions.lock`, [workflow dependency lockfiles](https://docs.github.com/en/actions/how-tos/security-for-github-actions/security-guides/using-third-party-actions), checked 2026-11-27) to bind step-level action references to full commit SHAs while keeping readable major vendor tags in workflow YAML:

- **Generate and update with `--no-narrow`.** Run `gh actions-lock --no-narrow --no-interactive` (or target specific workflows during incremental rollout) so official-vendor references keep their major tags in workflow YAML while `actions.lock` pins their resolved commit SHAs. Never edit `.github/workflows/actions.lock` by hand.
- **Verify lockfile freshness in CI.** Repositories onboarded to `actions.lock` verify that the lockfile matches the onboarded workflows (`gh actions-lock --verify`).
- **Respect the lockfile's scope boundary.** `actions.lock` pins step-level `uses:` references (including transitive composite actions). It does **not** lock cross-repository reusable workflow calls (`jobs.<job_id>.uses`). Onboarding a workflow that calls first-party step-level composite actions at `@main` (such as `melodic-software/ci-workflows/.github/actions/*@main`) freezes those step refs in `actions.lock`; keep such workflows out of incremental lockfile pilots until the repository adopts an explicit lock-refresh path for first-party actions.
- **Known `gh actions-lock` caveats (verified on `v0.5.1`).** `gh actions-lock` ignores `.github/dependabot.yml` `cooldown.exclude` filters and emits `local-action` warnings for runtime-staged checkout paths such as `./.base/*`.
- **Private-repository credential actions.** On private repositories enrolled in local fleet routing and onboarded to `.github/workflows/actions.lock`, a non-SHA `credentialActions` grant in `.github/runner-policy.json` (for example `actions/create-github-app-token@v3`) requires a matching full-SHA entry for that workflow and ref in `.github/workflows/actions.lock` ([`runner-policy` README](https://github.com/melodic-software/standards/blob/main/components/runner-policy/README.md#naming-the-managed-fleet-label-directly)). Dependabot updates `.github/workflows/actions.lock` natively on `github-actions` bumps without churning `.github/runner-policy.json`. While `.github/workflows/actions.lock` is absent, existing tag-grant behavior stays intact during incremental rollout.

## Same-repository references (`uses: $/...`)

Prefer GitHub's self-repository `$/` syntax over workspace-relative `./` whenever a workflow calls an action or reusable workflow from the same repository at the running commit:

- Use `uses: $/.github/actions/<action>` for same-repository composite actions and `uses: $/.github/workflows/<file>.yml` for repository-local reusable workflows. `$/` loads directly from the running commit without a preceding `actions/checkout` step and prevents ref drift.
- Keep `./.github/actions/...` (or `./.base/...`) **only** when a job intentionally checks out a different commit (such as `$MERGE_SHA^1` or a release tip SHA) or invokes a runtime-staged directory not present at the workflow's own commit.

## Native parallel steps (`parallel:`)

Use GitHub Actions' native `parallel:` step blocks to run independent, non-mutating steps concurrently inside one job (for example read-only linters, independent unit tests, or independent self-checks) without paying extra runner startup and checkout overhead:

- Keep steps sequential when they mutate shared workspace state, install overlapping toolchains on shared paths, or depend on outputs produced by an earlier step in the same group.
- Policy and naming gates inspect nested `parallel:` blocks recursively ([`runner-policy` README](https://github.com/melodic-software/standards/blob/main/components/runner-policy/README.md), [`github-actions-conventions` README](https://github.com/melodic-software/standards/blob/main/components/github-actions-conventions/README.md)).

## Artifacts and caching

- **Non-archived single-file reports (`archive: false`).** Set `archive: false` on `actions/upload-artifact@v7` for single-file, human-read artifacts (such as Markdown reports) so reviewers download the file directly without unzipping an extra archive.
- **Name the file on disk before upload when `archive: false` is set.** When `archive: false` is enabled, `actions/upload-artifact@v7` ignores the `name:` input and uploads the file under its on-disk basename. Write the file using a basename that matches the repository's `.github/artifact-retention.json` family pattern before invoking `upload-artifact@v7`.
- **Keep `actions/cache` on `@v6`.** Do not downgrade `actions/cache`, `actions/cache/restore`, or `actions/cache/save` below `@v6`.

## Mechanically enforced policy

These components own the enforceable rules for workflows; cite them rather than duplicating their rules:

| Concern | Owner |
| --- | --- |
| Runner labels, reusable workflow contracts, `localRoutingGrants`, `actions.lock` credential-action binding, and `pin-provenance-drift` | [`components/runner-policy/README.md`](https://github.com/melodic-software/standards/blob/main/components/runner-policy/README.md) |
| Workflow security audit (`unpinned-uses`, `dependabot-cooldown`, `actions.lock` and `parallel:` awareness) | [`components/zizmor/README.md`](https://github.com/melodic-software/standards/blob/main/components/zizmor/README.md) |
| Workflow syntax and fleet runner-label lint (`kjanat/actionlint` supporting `$/` and `parallel:`) | [`components/actionlint/README.md`](https://github.com/melodic-software/standards/blob/main/components/actionlint/README.md) |
| Workflow, job, step, and composite-action naming (`naming-lint`) | [`components/github-actions-conventions/README.md`](https://github.com/melodic-software/standards/blob/main/components/github-actions-conventions/README.md) |
| Dependabot schedule, cooldown, grouping, and auto-merge tiers | [`components/dependabot-policy/README.md`](https://github.com/melodic-software/standards/blob/main/components/dependabot-policy/README.md) |
| Pull-request workflow concurrency blocks | [`components/concurrency-policy/README.md`](https://github.com/melodic-software/standards/blob/main/components/concurrency-policy/README.md) |
