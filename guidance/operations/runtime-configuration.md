# Runtime configuration

## Design

- Resolve configuration through layers, from tool defaults through team, repository and folder to user and local, applying the user layer by default. A synced shared standard is the default fallback, with native ways to override it partly or wholly or to extend it, the same for every sync mechanism.
- Prefer one base configuration covering the whole catalog, with each scope recording only its enable and disable differences, so no second hand-kept list can drift.
- Keep independent settings decoupled: one switch per behavior, never tied to another mode such as interactive versus unattended.
- Put configuration and secret stores behind a provider interface so each user brings their own, and make the render destination and whether data may leave the machine preferences settable per project and folder.

## Design and build

- Make everything configurable and extensible per consumer, limits included, and hard-code nothing about one user, machine, organization or repository. Keep tunable content (curated lists, focus prompts) outside the code, with a shipped default and a consumer override that points at their own folder or repository.
- Ship deliberate, evidence-based defaults that are easy to override. In a tool's own config, leave settings at its defaults and set a value only to override one, for a concrete reason.
- Put config values in dedicated schema-validatable files and agent instructions in natural-language Markdown, never config fenced inside prose.

## Build and review

- Tools must apply configured preferences (ignoring them is a bug). Flag differences between managed settings and defaults for reconciliation instead of overwriting them, and accept a recommended change only if it does no harm globally.
