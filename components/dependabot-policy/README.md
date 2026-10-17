# Dependabot policy

This module is the enforceable contract for the organization Dependabot
policy. It parses `.github/dependabot.yml` and checks that every `updates`
entry batches related bumps, soaks new releases before adopting them, and caps
open pull requests, so bot-pull-request bursts cannot overwhelm CI.

It is read-only: it reports findings and sets the process exit status. It never
edits `dependabot.yml` or opens a pull request.

In this source repository, run it from the repository root:

```sh
node components/dependabot-policy/dependabot-policy.mjs --root .
```

The distributed component lives at `.github/standards/dependabot-policy/` and
owns its own `package.json` and lockfile with exact `ajv` and `yaml` runtime
pins. `policy.json` carries the canonical values each repository converges to;
`policy.schema.json` and `dependabot-policy.schema.json` are the Draft 2020-12
structural authorities for that policy and for the repository exception file.
Consumers install and invoke that dependency root directly:

```sh
npm ci --prefix .github/standards/dependabot-policy
node .github/standards/dependabot-policy/dependabot-policy.mjs --root .
```

The `dependabot-policy` sync component ships `policy.json` alone to that
path, for a target whose Dependabot merge classifiers read it at the base
(claude-code-plugins reads `autoMerge.reviewOnly`).

## The standard

The canonical values live in [`policy.json`](policy.json). Each `updates` entry
in `.github/dependabot.yml` must:

- schedule on the standard interval (`weekly`);
- set `cooldown.default-days` to at least the minimum (`3`), so a compromised or
  yanked release is caught before adoption while security updates still bypass
  the soak;
- declare a `groups` block, so related bumps batch into one reviewed pull
  request instead of one per dependency;
- keep `open-pull-requests-limit` at or below the maximum (`5`); an omitted
  limit is accepted because GitHub's default is already the maximum.

One 3-day floor covers every ecosystem and every outside publisher, with no
exemption for any vendor action. The analyzer still accepts a narrow
`cooldown.exclude`; the fleet uses it only for its own `melodic-software/*`
actions, which this organization publishes. GitHub made 3 days Dependabot's
default in July 2026 and found that
malicious versions were pulled within hours of publication
([GitHub blog](https://github.blog/security/supply-chain-security/the-case-for-a-cooldown-why-dependabot-now-waits-before-issuing-version-updates/)),
so 3 days catches them while keeping bumps current. Security updates skip the
cooldown natively: the option applies only to version updates
([options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)).
The standard still sets the value explicitly rather than relying on the default.

## Merge tiers for Dependabot pull requests

No Dependabot pull request waits on a human. Each one takes one of two
tiers, and automated lanes merge both; the publisher tiers are data in the
`autoMerge` block of [`policy.json`](policy.json):

- **Auto tier.** Every update in the pull request is non-major: the first
  numeric version component does not change, and below 1.0 the second does
  not either. Every update in an `autoMerge.ecosystems` ecosystem
  (`github-actions`) comes from a publisher with `tier: auto` in
  `autoMerge.publishers` (`actions/*`, `github/*`, `anthropics/*`), each
  entry with the date it was `reviewed` and the `basis` for its tier.
  No update is a security-critical dependency (below). `ci-status` is not
  red, and the updates in the commit's
  `updated-dependencies` metadata agree with the title or the group's
  `Updates` lines. The pull request merges once `ci-status` passes, with no
  review. Every repository already trusts these publishers, who run the
  platform and the review agents, so a non-major release from them adds no
  new trust; the cooldown and `ci-status` catch a bad one.
- **Review tier.** Everything else: a major from any publisher, an action
  from an unlisted publisher or one listed with `tier: review`, a
  security-critical dependency, a red
  `ci-status`, or updates the lane cannot read. An AI review lane reads the
  update and its release notes as data and records one verdict bound to the
  head it reviewed: `merge`, `fix` (push a fix commit, then review again),
  `close` (close the pull request and propose a Dependabot `ignore` entry),
  or `escalate`. A security update is never closed. The merge lane merges a
  review-tier pull request only on a `merge` verdict at its current head,
  and only once `ci-status` passes there.

**Security-critical dependencies.** A dependency a threat model singles out
is listed in `autoMerge.reviewOnly`, each entry scoped by `repository`,
`ecosystem`, `directory` (as in `dependabot.yml`) and `dependency`, with the date it was
`reviewed`, its `basis`, and the threat-model `control` it answers to. An
update to a listed dependency is always review tier, whatever its version
change, and a `merge` verdict on it must cite that control and say what the
review checked against it.

Prefer removing review-tier actions over reviewing their bumps: replace a
community action with a vendor action or a `gh` or script step.

### Who merges

A repository whose default branch uses a merge queue merges through its
merge lane, which adds the pull request to the queue with a GitHub App
token. `GITHUB_TOKEN` cannot: "If the target branch uses a merge queue, the
built-in `GITHUB_TOKEN` cannot add pull requests to the queue. In this case,
you must authenticate the workflow with a personal access token or a GitHub
App token that has permission to merge"
([Automating Dependabot with GitHub Actions](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/automating-dependabot-with-github-actions)).
In [claude-code-plugins](https://github.com/melodic-software/claude-code-plugins)
the pr-merge lane merges both tiers and the pr-unblock lane writes the
review verdicts.

The ci-workflows `pr-automerge-dependabot.yml` reusable arms GitHub
auto-merge with `GITHUB_TOKEN` on auto-tier GitHub Actions bumps. It is valid
only in a repository without a merge queue. Until such a repository runs a
review lane, its review-tier pull requests stay open.

The reusable's `PUBLISHER_ALLOWLIST` constant copies the `tier: auto` keys
of `autoMerge.publishers`. [`automerge-lockstep.mjs`](automerge-lockstep.mjs)
fetches that reusable at every SHA its `runner-policy` contracts approve and
fails when the constant and those keys differ at any of them. It blocks from admission, with no report-only
period: it compares two files at fixed revisions, so a run either matches or
names the differing lists, and the admitting change's run against the pinned
reusable matched.

## What it checks

Per `updates` entry, keyed by `<package-ecosystem>:<directory>` (the plural
`directories` list is joined, so a multi-root entry has one key):

- `schedule-not-standard`: `schedule.interval` is not the standard interval.
- `cooldown-below-minimum`: `cooldown.default-days`, or any `semver-*-days`
  override, is missing or below the minimum.
- `cooldown-soak-bypassed`: a match-all `cooldown.exclude` (`"*"`) or a
  `cooldown.include` list defeats the soak even though `default-days` is set.
- `groups-missing`: no `groups` block covers version updates: a
  `security-updates`-only group or a group whose `exclude-patterns` is a
  match-all (`"*"`) does not batch regular bumps.
- `pr-limit-too-high`: `open-pull-requests-limit` exceeds the maximum.
- `pr-limit-disables-updates`: `open-pull-requests-limit` is `0`, which turns
  version updates off entirely rather than capping volume.
- `ignore-disables-updates`: an `ignore` rule for `dependency-name: "*"` with
  no version or update-type narrowing suppresses every update.
- `malformed-update-entry`: an `updates` item is not a mapping.
- `incomplete-update-entry`: an `updates` item omits `package-ecosystem` or
  `directory`/`directories`.

File-level: `dependabot-config-missing` when there is no `.github/dependabot.yml`
at all, `unsupported-version` when the config is not `version: 2`, and
`updates-missing` when the config declares no `updates` entries.

## Exceptions

The organization has a few deliberate, documented deviations: a root that
tracks the latest upstream release on a daily cadence with no soak, or a
single-tool ecosystem where grouping is a no-op. Each is recorded in a locally
owned `.github/dependabot-policy.json`:

```json
{
  "schemaVersion": 1,
  "exceptions": {
    "npm:/": {
      "reason": "tracks-upstream-release",
      "justification": "This root deliberately tracks the latest upstream release, so a weekly cadence and a cooldown soak would defeat its purpose.",
      "waives": ["schedule", "cooldown"]
    }
  }
}
```

An exception is keyed by the same `<ecosystem>:<directory>` as the entry it
covers. `reason` is one of `tracks-upstream-release` (which may waive `schedule`
and `cooldown`) or `single-tool-ecosystem` (which may waive `groups`); `waives`
lists the rules it suppresses, and each must fall within its reason's scope;
`justification` is required. Unknown reasons or waivers, a waiver outside its
reason's scope, unknown keys, and a missing justification fail closed at schema
time. An exception that names an entry that does not exist, or that waives a rule
the entry already satisfies, is
reported as `exception-inventory-drift`, so the inventory cannot silently widen
or rot. The `open-pull-requests-limit` cap is not waivable.

The file is optional: a repository whose entries all conform needs no
configuration, and its absence declares no exceptions.

## Security updates on sync-managed materializations

Dependabot's security-update jobs cannot fix a dependency inside a
sync-managed materialization (for example
`.github/standards/<component>/package-lock.json`): the managed path is
governed by the standards sync, not by the consumer repository, and the
generated fix is rejected. The observed failure mode is a security-update job
that retries and fails repeatedly against the managed manifest: expected
noise, not a hazard requiring an in-repo response.

The absorb path is upstream-bump-then-sync: this repository bumps the
affected dependency in the owning component, and `standards-sync` distributes
the fix to every consumer's managed materialization the same way it
distributes any other component change. A maintainer who sees a failing
security-update job against a managed manifest should expect it to resolve
once the next sync pull request merges. Opening one does not update the
consumer's default branch, so a sync that stays open, is blocked, or is never
raised leaves the managed manifest on the vulnerable version until it lands.
The failing job is noise only while that sync is progressing; if no upstream
bump or sync merge is forthcoming, escalate the alert rather than continuing
to ignore it.

Whether Dependabot's own scoping can suppress these doomed jobs while keeping
the underlying alert visible is an open decision, tracked on
[standards#256](https://github.com/melodic-software/standards/issues/256).

## Enforcement gate

The gate installs the component's locked runtime and runs the analyzer against
the repository. In this repository the `check-policies` CI job does exactly
that; a consumer adds the equivalent job in its own integration change:

```yaml
dependabot-policy:
  runs-on: ubuntu-24.04
  permissions:
    contents: read
  steps:
    - uses: actions/checkout@<REVIEWED_40_CHARACTER_SHA>
      with:
        persist-credentials: false
    - uses: actions/setup-node@<REVIEWED_40_CHARACTER_SHA>
      with:
        node-version-file: .node-version
        cache: npm
        cache-dependency-path: .github/standards/dependabot-policy/package-lock.json
    - run: npm ci --prefix .github/standards/dependabot-policy
    - run: node .github/standards/dependabot-policy/dependabot-policy.mjs --root .
```

The security boundaries, fail-closed behavior, and review triggers are in the
[threat model](THREAT-MODEL.md).
