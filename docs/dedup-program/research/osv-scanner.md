# Research — osv-scanner

Google's dependency vulnerability scanner (cross-references OSV.dev advisories
across many ecosystems). Upstream CLI: <https://github.com/google/osv-scanner>;
official action + reusable workflows:
<https://github.com/google/osv-scanner-action>; docs:
<https://google.github.io/osv-scanner/>.

Built here as a **reusable workflow** (D1 — a whole-job dependency-scan concern
with job-level `permissions`, scheduling, SARIF), wrapping Google's own
SHA-pinned reusable workflows so consumers call one workflow.

## Versions

- Action latest stable: **v2.3.8**, full commit
  **`9a498708959aeaef5ef730655706c5a1df1edbc2`** (lightweight tag;
  `repos/google/osv-scanner-action/releases/latest`, verified 2026-06-23).
  `medley`'s pin is still latest and correct.
- CLI bundled by the action `v2.3.8` is **v2.3.8** (the action image pins
  `ghcr.io/google/osv-scanner-action:v2.3.8`; action and CLI version in lockstep).
  The standalone CLI latest is **v2.4.0**, but the action repo had not cut a
  v2.4.0 tag as of 2026-06-23, so pinning the action gets CLI v2.3.8.

## Google's two reusable workflows (wrapped, SHA-pinned)

Both live in the action repo and declare a single `osv-scan` job on
`ubuntu-latest`.

`.github/workflows/osv-scanner-reusable.yml` — **full-tree / non-PR** scan
(`-r ./`, reports all vulns). `workflow_call` inputs: `scan-args` (string,
default `-r\n./`), `results-file-name` (string, `results.sarif`),
`download-artifact` (string), `upload-sarif` (bool, `true`), `fail-on-vuln`
(bool, `true`), `matrix-property` (string), `checkout-submodules` (bool, `false`),
`ref` (string). Outputs: `results`.

`.github/workflows/osv-scanner-reusable-pr.yml` — **PR-diff** scan (checks out
base + head, reports only newly-introduced vulns; needs `fetch-depth: 0`). Same
inputs **minus** `download-artifact` and `ref`. Outputs: `old-results`,
`new-results`.

`medley` passes `scan-args` (`-r ./`), `upload-sarif: false`, `fail-on-vuln:
false`, split across two caller jobs by `github.event_name`.

## Permissions — KEY parse-time constraint

Both Google workflows **statically declare**, at file level:

```yaml
permissions:
  actions: read          # required by codeql-action/upload-sarif (codeql-action#2117)
  contents: read         # checkout
  security-events: write # upload-sarif → code scanning
```

`upload-sarif: false` only gates the upload **step** at runtime; it does **not**
remove the declared permission. GitHub validates a called workflow's declared
permissions against the caller's grant at **parse time**, so the caller **must
grant `security-events: write` (plus `actions: read`, `contents: read`) even when
`upload-sarif` is false** — it cannot be dropped without failing validation.

Permissions do **not** inherit across a reusable-workflow chain (they may only be
maintained or reduced). So **our** wrapping job re-declares the full set, **and**
a consumer calling our workflow must grant the same set on its caller job.

Nesting: GitHub allows up to 10 levels (caller → ours → Google's = 3, fine).
Inputs/secrets are forwarded explicitly at each hop (no inheritance).

## Config

osv-scanner optionally reads an `osv-scanner.toml` (ignore specific vuln IDs /
configure scanning). **Config-light:** `medley` ships none and the lifted lane
needs none, so no `standards` module is required for this tool.

## Design decisions for the reusable workflow

- Two jobs gated by `github.event_name == 'pull_request'`: PR events call
  Google's `-pr.yml` (newly-introduced vulns only), all other events call the
  full-tree workflow. This mirrors `medley`.
- Typed inputs forwarded to Google's workflow: `scan-args` (string, default
  `-r\n./`), `fail-on-vuln` (bool, default **false** = advisory), `upload-sarif`
  (bool, default **false**), `results-file-name`, `checkout-submodules`. Defaults
  set advisory explicitly (Google defaults both `true`).
- Each calling job declares `permissions: { actions: read, contents: read,
  security-events: write }` (mandatory at parse time per above). The consumer
  grants the same; the `ci-status` gateway stays consumer-local (D2).
- SHA-pin both Google reusable workflows at `9a498708…` (D5).

### Dogfood note

This repo carries no dependency manifests (no lockfiles/`*.csproj`/`requirements`),
so an osv-scanner run here has nothing to resolve. The dogfood value is proving
the wrapper's **wiring** (inputs forward, permissions parse, advisory posture
holds), not finding vulns. Verify the empty-tree exit behavior on the PR's own CI
run and, if a no-package error surfaces, gate the dogfood accordingly rather than
inventing a manifest.
