# Release versioning

## Build

- When a shared helper is copied into several packages, sync every copy together and bump each package's version.

## Build and operate

- Never revert a version number: when a branch and its base both bumped, apply the branch's bump level to the base's current version instead of stacking bumps and skipping a version.

## Operate

- Automate versioning, releases and changelogs with a bot so release bookkeeping never becomes a bottleneck.
