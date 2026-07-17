# Melodic Software standards

The normative source of shared repository-quality policy and engineering
conventions. Change shared standards here; consuming repositories receive the
result through native references/packages or reviewed synchronization pull
requests. A downstream repository owns only its product behavior, project
scope, and explicit local exceptions.

## Ownership boundaries

- This repository owns lint, hygiene, analyzer, text, runtime-pin,
  hook-adapter, and review policy.
- [`melodic-software/ci-workflows`](https://github.com/melodic-software/ci-workflows)
  owns reusable GitHub Actions execution.
- the relevant `github-iac` repository owns organization/repository governance
  expressible as infrastructure as code.
- consumers compose these capabilities and own repository-specific behavior.

The accepted architecture is recorded in
[`docs/adr/0001-federated-component-distribution.md`](docs/adr/0001-federated-component-distribution.md).

## Repository shape

- `components/<capability>/` — one cohesive source slice per independently
  adoptable capability: documentation, contract tests, fixtures, and any
  package metadata live with the policy they prove.
- root tool configs — canonical files for tools that require or naturally
  discover a repository-root path. They exist exactly once; the corresponding
  component slice documents and tests them.
- `conventions/` — reasoning-only engineering, review, and process standards
  that cannot be reduced honestly to deterministic tooling.
- `distribution/` — explicit mappings for exact-file synchronization when no
  native reference mechanism fits.
- `harness/` — shared infrastructure for component contract tests.
- `docs/adr/` — durable, repository-specific architecture decisions.

`biome.jsonc` and `lefthook.yml` are genuine standards-repository adapters:
they add this repository's scope/composition while referencing component
policy. They are not duplicated policy sources.

## Component model

A component is the smallest capability with one normative owner and one update
lifecycle. It may export one file or an atomic group of heterogeneous files.
Tests, fixtures, and maintainer documentation stay upstream unless a consumer
operationally needs them.

Admission, update, and retirement evidence follow the
[`docs/component-lifecycle.md`](docs/component-lifecycle.md) contract. A tool
without a live consumer remains a consumer-local experiment rather than an
orphan catalog component.

`components/runner-policy/` owns the YAML-aware GitHub Actions routing contract:
public work remains hosted, enrolled private jobs use only an approved selector,
and every hosted exception and privileged local-routing grant is explicit
machine-readable inventory.

`components/go-analysis/` owns the exact golangci-lint v2 analyzer allowlist and
suppression contract. The root `.golangci.yml` is its canonical exported policy;
reusable execution remains owned by `melodic-software/ci-workflows`.

Delivery preference is: platform control plane, native package/reference,
tool-native extension, exact-file synchronization, then explicit local
ownership. There is no generic templating or partial-merge layer and no
downstream receipt/header bookkeeping. Managed files are read-only downstream;
a reusable change flows upstream first.

## Validation

CI dogfoods every root policy, runs each component's contract tests, validates
the composed Lefthook adapter, and aggregates blocking lanes into `ci-status`.
Locally, install all three pinned Node dependency roots, then run:

```bash
npm ci
npm ci --prefix components/runner-policy
npm ci --prefix distribution
```

Run the local gates with:

```bash
npm run lint:md
npm run lint:hooks
npm run test:lefthook-dotnet
npm run test:packages
npm run test:runner-policy
npm run lint:runner-policy
bash harness/shell/run-tests.sh harness/shell/lib.test.sh
```

Individual component tests skip cleanly when their external engine is absent;
CI installs pinned engines and runs the complete suite.
