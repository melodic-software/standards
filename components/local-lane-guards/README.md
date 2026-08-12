# Local-lane guards

Local invocation entrypoint for the four bespoke CI guards that gate in
`ci-workflows` but previously had no standards-owned local lane:
`comment-hygiene`, `exec-bit`, `machine-specific-paths`, and
`reference-integrity`.

This component is the distribution answer recorded in
[`docs/adr/0003-local-lane-guards-via-standards-component.md`](../../docs/adr/0003-local-lane-guards-via-standards-component.md)
(ci-workflows#190): one standards-owned bin/script, synced exact-file the same
way other shared lint primitives are — pointer-not-copy. Consumers invoke
`run-local-lane-guards.sh`; they do not copy driver logic into a repo-local
bin or a second composite-action runner.

## Layout

| File | Role |
| --- | --- |
| `run-local-lane-guards.sh` | Dispatcher (`<guard>\|all`) |
| `scan-comment-hygiene.sh` | Full-tree comment-hygiene driver |
| `coarse-prefilter.sh` | Shared coarse `git grep` prefilter for that driver |
| `check-exec-bit.sh` | Shebang → git mode 100755 |
| `check-machine-specific-paths.sh` | Absolute user-home / checkout-root scan |
| `check-heading-cites.sh` | `file.md` "Anchor" prose citation resolver |

Pattern **bodies** stay in their existing components — this driver sources
`../comment-hygiene/comment-hygiene-patterns.sh` and
`../path-detection/machine-path-patterns.sh`. That relative path is identical
in-source under `components/` and when materialized under `tools/shared/`
beside `comment-hygiene-tools` / `path-detection-tools`.

## Sync destinations

Stable downstream path (exact materialization):

`tools/shared/local-lane-guards/<file>`

Manifest component name: `local-lane-guards`. It `requires`
`comment-hygiene-tools` and `path-detection-tools` so the sibling pattern
libraries land before the drivers. Target adoption is a separate change —
this slice admits the component and sync metadata without rewriting
consumers.

## Ownership boundary

- **standards** owns the local-lane entrypoint and these drivers.
- **ci-workflows** owns the composite-action wrappers that gate CI today.
  A follow-up may re-point those actions at the synced drivers (or keep thin
  action wrappers that exec the same bytes); until then the action-bundled
  copies remain the CI path and must not diverge in behavior from this
  component.
- Policy libraries for comment markers and path bodies remain the
  `comment-hygiene` and `path-detection` components.

## Local use

```sh
bash tools/shared/local-lane-guards/run-local-lane-guards.sh --help
bash tools/shared/local-lane-guards/run-local-lane-guards.sh exec-bit
bash tools/shared/local-lane-guards/run-local-lane-guards.sh all
```

Optional environment knobs mirror the composite actions (`PATHS`,
`EXTENSIONS`, `EXCLUDE`, `GLOBS`, `PATTERNS_FILE`).

`local-lane-guards.test.sh` proves the dispatcher contract and that each
driver fails closed on a planted temp-repo finding and passes a clean one.
