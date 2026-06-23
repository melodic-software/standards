# Research — zizmor

Static analysis / security linter for GitHub Actions (supply-chain risks,
dangerous triggers, excessive permissions, template injection). Upstream CLI:
<https://github.com/zizmorcore/zizmor>; official action:
<https://github.com/zizmorcore/zizmor-action>; docs: <https://docs.zizmor.sh/>.

Built here as a **reusable workflow** (D1 — a whole-job security concern), wrapping
the SHA-pinned official action so consumers call one workflow.

## Versions

- zizmor CLI latest stable: **v1.26.1**, published 2026-06-21
  (`repos/zizmorcore/zizmor/releases/latest`, verified 2026-06-23). `medley`
  pins v1.24.1; the workflow defaults to v1.26.1 (advisory, so newer audits only
  add surfaced findings, never break a build).
- zizmor-action latest stable: **v0.5.7**, published 2026-06-21; full commit
  **`192e21d79ab29983730a13d1382995c2307fbcaa`** (lightweight tag). `medley`
  pins v0.5.6 @ `5f14fd0…` — superseded. Pin
  `zizmorcore/zizmor-action@192e21d79ab29983730a13d1382995c2307fbcaa # v0.5.7`.

## Action inputs (from `action.yml` @ v0.5.7)

| Input | Default | Meaning |
| --- | --- | --- |
| `inputs` | `.` | Whitespace-separated paths to audit (workflow + action files). |
| `online-audits` | `true` | Run online audits (uses `token`); false → `--no-online-audits`. |
| `persona` | `regular` | Audit persona: `regular`, `pedantic`, or `auditor`. |
| `min-severity` | (unset) | `unknown`/`informational`/`low`/`medium`/`high`. |
| `min-confidence` | (unset) | `unknown`/`low`/`medium`/`high`. |
| `version` | `latest` | zizmor version (`latest` or exact `X.Y.Z`); unknown → action fails. |
| `token` | `${{ github.token }}` | Token for online audits. |
| `advanced-security` | `true` | SARIF + upload to the Security tab via codeql-action. |
| `color` | `true` | Colorized CLI output. |
| `annotations` | `false` | Workflow annotations (`--format=github`). Mutually exclusive with `advanced-security: true`. |
| `config` | (unset) | Path to a custom `zizmor.yml` (`--config=`). |
| `fail-on-no-inputs` | `true` | If false, exit 0 (not 3) when no inputs collected (zizmor ≥ v1.21.0). |

`medley`'s advisory lane sets `inputs: .github/workflows`, `online-audits: true`,
`advanced-security: false`, `annotations: true`, `persona: regular`.

## Failure / advisory mechanism — KEY

There is **no `fail` input**. The action `exit`s with zizmor's exit code directly.
In **annotations mode** (`advanced-security: false`, `annotations: true` —
`medley`'s mode) zizmor returns exit **11–14** when findings exist, so the step
**fails**. To stay advisory the **caller must set `continue-on-error: true`** on
the step (no input does this). In SARIF mode (`advanced-security: true`) the
`--format=sarif` path **suppresses exit codes 11+**, so it does not fail on
findings — but that mode uploads SARIF and needs `security-events: write`.

Exit codes: `0` clean · `1` audit error · `2` arg error · `3` no inputs ·
`11/12/13/14` findings by highest severity (info/low/med/high; suppressed in SARIF).

## Personas

- `regular` (default) — high-signal, actionable security findings.
- `pedantic` — adds code-quality "code smells."
- `auditor` — most sensitive; everything incl. likely false positives.
- (There is **no** `auto` persona.)

## Config

zizmor auto-discovers an optional `zizmor.yml`/`zizmor.yaml` (searched
`.github/zizmor.yml` → `.github/zizmor.yaml` → repo-root variants), or takes
`--config`; `--no-config` skips it. It can disable audits, ignore findings,
remap severities. **Config-light:** `medley` supplies none and the lifted lane
needs none, so no `standards` module is required for this tool.

## SARIF / permissions

- **Annotations mode** (this workflow's v1 default) emits findings via workflow
  commands on stdout — **no `security-events: write`**, only `contents: read`.
  Online audits use the default `github.token` (read).
- **SARIF/advanced-security mode** uploads via the action's embedded
  `github/codeql-action/upload-sarif`, requiring job `security-events: write`.

## Design decisions for the reusable workflow

- **v1 = advisory annotations only.** Typed inputs `paths` (→ `inputs`, default
  `.github/workflows`), `version` (default `v1.26.1`), `online-audits` (bool,
  default true), `persona` (default `regular`), `fail-on-findings` (bool, default
  **false** = advisory). When `fail-on-findings` is false the action step carries
  `continue-on-error: true`; when true, it does not.
- **No SARIF/`advanced-security` in v1**, so the job needs only `contents: read`
  (least privilege; no `security-events: write`). Promotion to SARIF upload and/or
  blocking is a separate, later decision (the program keeps zizmor advisory on
  lift); it would be added open-closed as an opt-in input plus the matching
  permission, default-off.
- SHA-pin the nested action (D5).
