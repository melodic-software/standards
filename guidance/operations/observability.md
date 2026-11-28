# Observability

## Design

- Keep one telemetry collection path, and question any second tool that collects or shows the same thing.

## Design and build

- Nothing is a black box: applications and agent runs emit logs and telemetry that agents can read.

## Design and operate

- Give every local telemetry or log store retention, rotation and a size cap, and make it show the value it delivers, or it should not exist; check that collectors and dashboards do not degrade the workloads they observe.
- Consider a provider's official APIs as a direct data source for monitoring instead of reading its dashboards, where its terms allow.

## Build and operate

- Record host metadata and performance diagnostics alongside collected data, so runs can be audited, debugged and measured again against a baseline.
