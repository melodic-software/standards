# Exact-materialization threat model

This model covers the desired-state manifest, its schema and validator, and the
read-only or file-copy operations in the distribution engine — the Node
implementation in [`sync-manifest.mjs`](sync-manifest.mjs), entered through
the stable exec-wrapper [`sync-manifest.sh`](sync-manifest.sh) (the retired
Bash implementation's path, kept so every caller's invocation stays
byte-stable). Authentication, target checkout
creation, commit creation, push, and pull-request creation belong to the
reusable workflow in `ci-workflows`; this engine deliberately performs none of
those actions.

The model follows OWASP's maintained threat-modeling loop and NIST SSDF's
requirements to protect source integrity, provenance, and release inputs.

## Security objectives and assets

- Only reviewed, indexed source bytes and Git modes can become managed output.
- A manifest cannot escape either repository, alias ownership, hide duplicate
  declarations, or omit a required component capability.
- Apply cannot follow a destination symlink or overwrite an untracked,
  non-regular, unmerged, or directory-shaped destination.
- All destinations pass preflight before the first copy, and locally owned
  files are never materialized.
- The engine does not delete, stage, commit, push, authenticate, or infer
  adoption from repository access.

Protected assets are canonical component bytes and executable modes, manifest
ownership and dependency declarations, downstream locally owned content,
target Git history, and the reviewed pull-request boundary that follows apply.

## Actors and trust boundaries

- A standards maintainer changes canonical sources, component mappings, and
  target classifications.
- A target maintainer reviews the materialization pull request and owns native
  integration.
- A pull-request contributor may attempt path traversal, source substitution,
  ambiguous YAML, ownership collision, or an unsafe target overwrite.
- The `ci-workflows` automation and its GitHub App cross an external
  authentication boundary after this engine returns.
- Git and core file utilities are trusted production tooling at their
  installed revisions. The Node runtime (pinned by the repository's
  `.node-version`, installed by SHA-pinned setup-node) and the exact-locked
  `yaml` parser are production tooling for the Node engine. Mike Farah `yq` v4
  left the production trust set at the Bash engine's retirement and is
  authoring-CI tooling only (suite fixture conversion, sibling lint jobs). The
  exact-locked Ajv tree is an authoring-CI boundary for independent JSON
  Schema validation only (`devDependencies`, excluded from production installs
  by `--omit=dev`).

The source worktree and target checkout are separate trust domains. The Git
index is the reviewed identity for source files and modes. The target index is
used to distinguish governed tracked destinations from untracked local files;
it does not authorize publication.

## Data flow

1. The caller selects a command, canonical source root, tracked manifest, and
   optional exact target filter or target checkout.
2. The production engine establishes single-document YAML, duplicate-key,
   structural, path, ownership, dependency, ordering, and source-index
   constraints through a pinned YAML-1.2 core parser configuration. Standards
   authoring CI independently checks the same manifest against the Draft
   2020-12 schema with Ajv (an independent parse — yq/Go converts the
   schema-path input; the engine's `yaml` parser reads the engine-path
   input) and runs the black-box contract suite, whose assert-equal cases
   pin every emitter's output bytes. (During the retired dual-gate window
   the suite additionally ran against the Bash engine, with a CI step
   byte-comparing the four read-only emitters — matrix, plan, mappings,
   dest-paths — across the two engines on the real manifest; validate and
   apply bytes were covered by the suite's assert-equal cases.)
3. `validate`, `matrix`, `plan`, and `mappings` emit diagnostics or derived
   output without changing either repository.
4. `apply` resolves the target to its physical Git root, requires one approved
   GitHub `origin` URL matching the selected manifest target, and preflights
   every destination against filesystem and target-index state.
5. Only after complete preflight, source bytes are copied and their reviewed
   `100644` or `100755` mode is reproduced. The external workflow may later
   inspect the diff and propose a reviewed pull request.

## Threats, controls, and evidence

| Threat | Control | Executable evidence |
| --- | --- | --- |
| A path escapes the repository, writes Git metadata, or contains control characters. | Both the authoring schema and the production engine reject C0 and DEL controls. The engine restricts source and destination paths to safe relative segments free of `.`/`..`, backslashes, drive roots, controls, and `.git`; destination prefix collisions are rejected. | Control-injection no-write, unsafe traversal, invalid path, and file/directory collision cases in [`sync-manifest.test.sh`](sync-manifest.test.sh). |
| Ambiguous YAML changes ownership or selection. | The manifest must be one YAML document with unique mapping keys and must satisfy a closed Draft 2020-12 schema. Names and selections are sorted and unique. | Duplicate-key, unknown-key, version, duplicate-selection, and uppercase-target cases in [`sync-manifest.test.sh`](sync-manifest.test.sh). |
| Two components claim one source or destination, or a target omits a dependency. | Validation enforces unique source and destination ownership, rejects destination prefix conflicts and dependency cycles, and requires each managed component's direct capabilities to be managed or locally owned. | Collision, missing-dependency, and dependency-cycle cases in [`sync-manifest.test.sh`](sync-manifest.test.sh). |
| Unreviewed or special source bytes are materialized. | Every manifest and source is exactly one tracked stage-zero regular Git file. Its worktree hash must equal the indexed object, and only regular or executable Git modes are accepted. | Untracked-source, dirty-source, index-mode, and production-target materialization cases in [`sync-manifest.test.sh`](sync-manifest.test.sh). |
| A destination symlink or local file redirects or loses data. | The physical target must be the Git root. Every parent and destination rejects symlinks and non-regular shapes; existing files must be tracked stage-zero regular files, while untracked collisions fail. | Untracked-destination atomicity and destination-symlink cases in [`sync-manifest.test.sh`](sync-manifest.test.sh). |
| A valid target is applied to the wrong checkout, or unavailable index evidence is treated as absence. | Apply requires exactly one strictly parsed normal GitHub `origin` whose normalized owner/repository matches the manifest target. Every `git ls-files` status is propagated before evidence is consumed. Origin identity detects accidental checkout mismatch; it does not authenticate the remote. | Missing/mismatched-origin and injected index-inspection-failure cases prove nonzero exit before any write. |
| A later invalid destination leaves an apparently complete partial update. | Apply gathers and preflights every destination before the first mutation. Any later copy failure stops the caller before pull-request creation. | The preflight-collision fixture asserts that none of the earlier destinations are created. |
| A filter broadens reconciliation to an unintended target. | Filters accept only exact known owner/repository names, reject empty and duplicate entries, and retain manifest order. Apply accepts exactly one known target. | Exact-filter, unknown, duplicate, empty-token, and earlier-target regression cases in [`sync-manifest.test.sh`](sync-manifest.test.sh). |
| Tool substitution changes parsing or validation. | The Node engine requires Git and the Node runtime pinned by `.node-version` and installed by SHA-pinned setup-node, with its single exact-locked production dependency (`yaml`) installed by `npm ci` under `--omit=dev --ignore-scripts`. Explicit-tag classification, merge-key rejection, and duplicate-key rejection are pinned parser configuration, not defaults. Separate authoring CI uses exact locked Ajv for an independent parse of the same manifest (yq/Go converts the schema-path input; the `yaml` parser reads the engine-path input — two parser families). | The contract suite and the automerge literal-spelling fixture in the `distribution` CI job; [`package-lock.json`](package-lock.json) SRI; the engine's command checks. The node-only runtime control relocates the production trio (wrapper, engine, locked deps) and proves the path never invokes a planted `yq` shim — the inversion of the retired Bash-era no-Node control. |

The current ownership and operating commands live in the
[distribution README](README.md) and [`sync-manifest.yml`](sync-manifest.yml).
They are not duplicated here.

## Residual and accepted risk

- Apply is designed for a clean, disposable target checkout but does not prove
  that the target worktree is globally clean. It may overwrite uncommitted
  bytes at an otherwise tracked destination. Supplying a developer worktree
  violates the operating contract and can lose local changes.
- Complete preflight prevents validation-time partial writes, not I/O failure
  during the copy loop. A disk, permission, or process failure can leave a
  partial worktree. The external workflow must discard the checkout and must
  not publish after a nonzero exit.
- Source hashes are checked before apply but are not locked against a concurrent
  local writer between validation and copy. The supported CI model uses an
  isolated checkout with no concurrent writers; other callers must provide the
  same isolation.
- Deselecting a component never deletes its old downstream files. This protects
  locally owned data but leaves stale-file discovery and coordinated retirement
  to a reviewed one-time change.
- The target origin is identity evidence, not proof that GitHub served or
  authenticated the checkout. The target index proves only tracked path shape;
  neither establishes that the downstream revision is current, protected, or
  authorized for publication.
  Checkout revision, credentials, commit, push, and pull-request review remain
  controls in `ci-workflows` and GitHub governance.
- The production engine trusts installed Git, the pinned Node runtime, and its
  exact-locked `yaml` dependency; authoring CI additionally trusts locked
  Node/Ajv. Locks, checksums, and `--ignore-scripts` reduce substitution risk
  but do not attest the runner host or every transitive input.
- The managed-files-guard PR check formerly ran the Bash engine against the
  yq preinstalled on the runner image — an unpinned-yq gap the Phase 6.2
  re-run recorded rather than introduced. The gap closed at the Bash engine's
  retirement: the guard's pinned ref advanced and its engine path runs Node
  under the same locked, script-suppressed install as the reusables.

No manifest classification accepts these model-level risks. Deviations from
the disposable-checkout and reviewed-PR contract require a separate design and
threat review.

## npm supply chain (production engine)

The Node engine puts npm on the production sync path; these are standing
controls, never derived from the current dependency tree's shape:

- **Production tree:** exactly one direct dependency — `yaml`, exact-pinned,
  zero transitive dependencies. The Ajv tree is authoring-only
  (`devDependencies`); production installs run `npm ci --omit=dev`.
- **Lifecycle scripts never execute:** every production `npm ci` passes
  `--ignore-scripts`. The sync job installs after App-token mint and beside
  the checkout it later applies from, so a dependency postinstall would
  otherwise run inside the credentialed job — the flag is load-bearing even
  while the tree has no scripts.
- **Integrity and provenance:** the committed lockfile (v3, SRI integrity
  hashes) ships in the reviewed standards checkout the reusable clones;
  `npm ci` refuses drift from it, bounding registry-substitution risk.
- **Runtime pin:** `engines` requires Node 24+; workflows install via
  SHA-pinned setup-node reading the repository's `.node-version`.
- **Update policy:** the nested Dependabot root covers `distribution/`, but a
  `yaml` bump is a production-parser change requiring human review — excluded
  from any current or future automerge policy.

## Review triggers

Re-run this threat model when a command gains mutation, deletion, staging,
commit, network, or authentication behavior; when path syntax, ownership,
dependency, target-selection, or locally owned semantics change; when a new
file type or Git mode is accepted; or when the external workflow changes its
checkout, credential, publication, or review boundary.

Parser, schema-draft, Git-index, `yq`, Ajv, symlink, or filesystem portability
changes also trigger review. Each new boundary has a fail fixture, and every
new mutation retains complete preflight or documents a transactional
replacement.

Re-run 2026-08-20 (standards-sync-audit Phase 6.2): the parser and `yq`
trigger rows fired for the engine Node port; this revision records the
outcome — the trust-set change, the dual-gate evidence, and the npm
supply-chain controls above.

## External authorities

- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [NIST SP 800-218, Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final)
- [Git `ls-files` documentation](https://git-scm.com/docs/git-ls-files)
- [JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12)
- [Mike Farah `yq` documentation](https://mikefarah.gitbook.io/yq/)
- [`yaml` package documentation](https://eemeli.org/yaml/)
