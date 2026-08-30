# Local-lane guards

Local invocation entrypoint for the four bespoke CI guards that gate in
`ci-workflows` but previously had no standards-owned local lane:
`comment-hygiene`, `exec-bit`, `machine-specific-paths`, and
`reference-integrity`.

This directory is PRODUCER-INTERNAL source plus its contract test. It is not
distributed. The original sync-component distribution (ADR-0004) was retired
by
[`docs/adr/0006-retire-local-lane-guards-distribution.md`](../../docs/adr/0006-retire-local-lane-guards-distribution.md):
adoption never happened, the enforcement surface consolidated in the
ci-workflows composite actions and repo-local wrappers, and the manifest
definition was removed. The drivers remain here as the standards-owned
reference implementation behind the ci-workflows action copies.

## Layout

| File | Role |
| --- | --- |
| `run-local-lane-guards.sh` | Dispatcher (`<guard>\|all`) |
| `scan-comment-hygiene.sh` | Full-tree comment-hygiene driver |
| `coarse-prefilter.sh` | Shared coarse `git grep` prefilter for that driver |
| `check-exec-bit.sh` | Shebang → git mode 100755 |
| `check-machine-specific-paths.sh` | Absolute user-home / checkout-root scan |
| `check-heading-cites.sh` | `file.md` "Anchor" prose citation resolver <!-- heading-cite-ignore-line --> |

Pattern **bodies** stay in their existing components: this driver sources
`../comment-hygiene/comment-hygiene-patterns.sh` and
`../path-detection/machine-path-patterns.sh`.

## Ownership boundary

- **standards** owns the local-lane entrypoint and these drivers as
  producer-internal reference source.
- **ci-workflows** owns the composite-action wrappers that gate CI. The
  action-bundled copies are the CI path and must not diverge in behavior
  from this component.
- Policy libraries for comment markers and path bodies remain the
  `comment-hygiene` and `path-detection` components.

## Local use

```sh
bash components/local-lane-guards/run-local-lane-guards.sh --help
bash components/local-lane-guards/run-local-lane-guards.sh exec-bit
bash components/local-lane-guards/run-local-lane-guards.sh all
```

Optional environment knobs mirror the composite actions (`PATHS`,
`EXTENSIONS`, `EXCLUDE`, `GLOBS`, `PATTERNS_FILE`).

`local-lane-guards.test.sh` proves the dispatcher contract and that each
driver fails closed on a planted temp-repo finding and passes a clean one.
