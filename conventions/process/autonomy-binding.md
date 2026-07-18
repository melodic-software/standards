# Autonomy fleet binding

The organization's binding instance for the autonomy contract set: each repository role the
contract names, mapped to the fleet repository that holds it. The role vocabulary itself is
owned by the `autonomy` plugin's `reference/role-topology.md` in the
[claude-code-plugins marketplace](https://github.com/melodic-software/claude-code-plugins);
this document binds those roles for this organization and is the only place fleet repository
names appear among the contract's artifacts.

Role-vocabulary version bound: **v0.1.0** (the `autonomy` plugin version that shipped the
topology contract). A role-vocabulary change upstream updates this document in the same
review cycle. Recheck the pin against the plugin's current `reference/role-topology.md` by
**2026-10-18** and quarterly thereafter (bump the date on each recheck); this dated trigger
exists because no automation compares the pinned version at setup time yet.

## Role bindings

| Contract role | Fleet instance |
|---|---|
| capability-distribution home | The `claude-code-plugins` marketplace ([melodic-software/claude-code-plugins](https://github.com/melodic-software/claude-code-plugins)) |
| CI-orchestration home | [melodic-software/ci-workflows](https://github.com/melodic-software/ci-workflows) |
| settings-as-code home | [melodic-software/github-iac](https://github.com/melodic-software/github-iac) |
| org-policy home | This repository (`melodic-software/standards`) |
| runner-execution home | **Unborn** — no repository holds this role; it is created only when the runner charter's build trigger fires (recorded in the autonomy work-package plans) |

## Consumption

This document is org binding DATA the autonomy setup capability reads at setup/bind time —
not a prose standard fetched at build or review time, so the `conventions/` copy-or-pointer
consumption model is preserved. A repo-local or user-global `org_policy_home` pointer names
this repository; setup fetches the document once per run (host CLI, the consumer's own
authentication) and PERSISTS the resolved values into the consuming repository's own tracked
binding, which is what builds, reviews, and later runs read. Per-value, that repo-local
binding overrides these org values (additive merge, later layer refines earlier — the ladder
semantics are owned by the plugin's `reference/binding-seam.md`, not restated here).
