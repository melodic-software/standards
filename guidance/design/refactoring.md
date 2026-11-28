# Refactoring

## Design and build

- Give every piece of knowledge, rule and convention one canonical source that everything else points to, instead of copying or syncing it. Apply this beyond code: labels, configuration, CI workflow and pipeline definitions, and conventions shared across repositories. When two paths apply the same policy (a per-change check and a repository-wide sweep, or two entry points), both read that one source and stay in sync with the upstream defaults it derives from.

## Plan and build

- Generalize before the third copy when product context, upstream docs or meeting notes show the repetition is coming. Remove duplication across repositories first, then within them, incrementally.

## Plan and review

- Treat a very large file as a refactoring red flag for single-responsibility and testability problems. Give the file-size signal a research-backed default and a criterion for acting on it. In legacy code, file the files over the threshold as work items rather than refactoring them on the spot.

## Build

- Where a platform prevents truly shared code, keep one source and generate the copies by script, aiming to remove them entirely. Edit a synced file at its source, never the copy. Give every number and default a stated provenance, and derive two displays of one fact from one source.
- Keep a targeted fix narrow. Small cleanups in the lines it touches can ride along; structural refactoring goes in its own change. When revisiting something that will not be touched again for a long time, fix everything measurable.

## Build and review

- Delete unused code, config and features: keeping them is not free. Anything that may still have users, including ones a search does not show, is deprecated first with a replacement. Keep what a contract or regulation requires. Version control keeps the rest recoverable.

## Build and operate

- Clean up continuously and scoped to each change's diff, with a simplification pass on every change. Work through the rest of the codebase in sized chunks through a recurring, ordered playbook of hygiene passes, one change per sweep and one commit per pass.
