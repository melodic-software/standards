# standards-sync-audit

## Brief

### TLDR

Six-lane deep audit of the standards distribution/sync system found the engine byte-perfect but the governance around it stale: fleet automerge disarmed past its recorded restore trigger (~65 human merges/week), an AGENTS.md component that reaches Claude Code in zero repos and clobbered bespoke content four times in six weeks, five fully-built components with zero adopters, a sync caller pinned 123 commits behind, and genuine overengineering rooted in a hollow Bash+yq purity constraint. Sixteen decisions were interviewed, adversarially validated by three fresh-context agents (two same-vendor, one cross-vendor Codex), and locked. Remediation is phased below.

### Goal

Execute the locked decision set: restore automerge safely (canary + proven watchdog), retire the agent-orientation component, clean up zero-adopter components, bring pins current, run the hygiene wave, cut consumer friction, expand the sync fleet by one batched App grant (claude-code-proxy, codex-plugins, cursor-plugins), and later port the engine to Node.

### Constraints

- Exact-set App attestation: any roster change is an atomic two-sided operation (manifest edit + org-owner grant); grant-first per github-iac's documented procedure; a skew window reds out the whole fleet — schedule nothing sync-dependent inside it.
- Every new target enters with explicit `automerge: false` (omitted defaults to TRUE and would bypass the canary).
- Re-pinning any ci-workflows reusable caller requires appending the new `path@SHA` to `components/runner-policy/policy.json` in the same PR.
- The zero-target validator rule (schema + engine + mjs lockstep) lands LAST in the component-cleanup series.
- Managed-file deselection never deletes downstream: agent-orientation retirement requires explicit per-target PRs (blank, not delete).
- ADR convention forbids renumbering accepted ADRs — the 0003 dedupe carries an explicit collision carve-out note.
- No commits to main; all work via branches + PRs per repo convention.

### Acceptance criteria

Phased execution contract — one phase at a time: plan, implement, verify, close.

- **Phase 0 — hygiene + pins (standards repo, one PR series):** stale manifest comments fixed (caller-pin version claim removed or made durable; automerge rationale re-cut to the real gate; medley rationale rewritten — pyright/dotnet overwrite claims are false, ruff is the only true overwrite); distribution/README agent-orientation source claims fixed (sequenced with Phase 1 to avoid double rewrite); medley's 8 diverged counterpart files recorded as commented `locally-owned` entries; ADR 0003→0004 renumber + convention carve-out; 7 missing nested Dependabot entries added fleet-wide; REVIEW-CREDENTIAL.md compressed with `[!CAUTION]` fences preserved + historical note in ci-workflows PLAN.md; coarse-prefilter.sh header fixed without silently retiring the superset contract; ci-workflows actionlint flipped to managed; canonical `.node-version` bumped to 24.19.0 then ci-workflows adopts node-runtime (5 inline pins → `node-version-file`); sync.yml + watchdog caller re-pinned with policy.json SHA appends; repin automation `LANE_PATHS` extended to sync-family callers; songwriting's 2 drifted files hand-fixed once (keep MD024 nested override).
- **Phase 1 — automerge restore:** `.github` target re-armed; watchdog workflow-dispatch test mode built (synthetic stuck candidate + disposable tracking issue proving create/update/close/fail paths); fleet re-armed only after that proof passes.
- **Phase 2 — agent-orientation retirement:** component moved to locally-owned everywhere then manifest entry retired; per-target PRs blank AGENTS.md (not delete); claude-code-plugins CLOUD-SESSIONS.md link fixed; opt-out procedure re-homed in the new escape-hatch doc; PR body remains the just-in-time warning.
- **Phase 3 — component cleanup:** manifest entries deleted for concurrency-policy, dependabot-policy, pin-comment-convention, pr-convention-policy (all stay as producer-internal lint); superseding ADR for pr-convention-policy-as-data; escape-hatch doc shipped (consolidated exception-surface index, `--target`/`--target-root`, `LEFTHOOK=0` incl. PowerShell shape, reconciled with agent deny rules); org-default PULL_REQUEST_TEMPLATE fixed in melodic-software/.github (4 sections, bare-dash hole closed); pr-issue-linkage fleet re-pin to ≥v0.14.x (6/8 repos currently enforce only `## Related`); zero-target validator rule lands last.
- **Phase 4 — fleet expansion (one grant window):** claude-code-proxy + codex-plugins + cursor-plugins added as targets with explicit `automerge: false`, per-target component sets (ccproxy: ruff locally-owned; hygiene set for the marketplaces), 3 new `TARGET_VISIBILITY` entries, `sync-manifest.test.sh` arity assertions updated, github-iac README roster mirror updated, claude-lane-sandbox rationale mirrored into manifest; knowledge-corpus stays deferred (LFS structural blocker recorded).
- **Phase 5 — local-lane-guards staged migration:** per-guard parity analysis vs medley/ci-workflows/ccp forks; medley wrappers or locally-owned entries; one guard at a time; comment-hygiene-tools disposition rides this.
- **Phase 6 — engine Node port:** full 921-line black-box contract suite green against the Node engine; threat-model re-run; explicit disposition of the no-Node control + its test; npm supply-chain assessment.

### Captured assumptions

- User is the org owner and can perform the App grant and secrets actions personally (Q9 — approved without correction; correction invited).
- No timeline or budget constraint on the remediation phases; no cut candidate is sacred.
- Repin App secrets are provisioned and working (verified live 2026-08-16: set 2026-08-09, daily green runs).

### Out-of-scope

- songwriting fleet adoption (github-iac ADR-0006 stands; hand-fix only).
- knowledge-corpus adoption (structural LFS blocker; no extend mechanism exists).
- runner-policy SHA-allowlist split (deferred; append-only list, premise half-false).
- Syncing CLAUDE.md anywhere (unhobble rebuild rule governs).
- SYNC-MANAGED header comments in managed files (infeasible: byte-exact engine, false-at-source, format-hostile destinations).
- New PULL_REQUEST_TEMPLATE sync component (org-default fix dominates).

### Deferred questions

(none — register clean: 16/16 answered)

## Plan

Phase-tag vocabulary in this file: `[PENDING]` → `[DOING]` → `[DONE]` — PENDING stands in for the planning convention's usual first tag because this repo's comment-hygiene gate rejects warning-marker keywords in tracked files.

Planned 2026-08-16 against standards main @ `4be9696`, ci-workflows main @ `4763713`. Facts verified this session by four read-only explorers (line numbers below are current at these SHAs). Drift since audit: standards gained cloud-bootstrap component (#397-#399) — no Phase 0 impact beyond shifted line numbers; #399 added 12 lines to `components/agent-orientation/orientation.md` (Phase 2 concern, noted for that phase).

Standards grounding: repo's own ADR convention (`docs/adr/README.md:15-24`), pin-comment shape (`# <shortsha> <date>` as in `sync.yml:33`), conventional-commit subjects per git log. Commit convention: branch + PR per repo; no commits to main.

### Phase 0.1: standards hygiene PR (S1 — no behavior change) [DONE]

Branch `chore/sync-audit-phase0-hygiene` off main. All edits in standards; no sync-behavior change.

1. **Caller-pin comment made durable** — `distribution/sync-manifest.yml:33-39`: remove the stale "pinned at the v0.12.0 release SHA (734158c4 …)" claim (actual pins have moved 4x). Rewrite to a durable form that names no version/SHA literal: pins live in the caller workflows and `components/runner-policy/policy.json`; keep the drift-history rationale (medley `reopened` trigger, skip-actors, pin skew).
2. **Automerge rationale re-cut** — `distribution/sync-manifest.yml:308-311`: current text cites standards#273/#274 (both closed 2026-08-04) as the restore trigger — stale. Rewrite to the real gate: disarmed pending a watchdog workflow-dispatch test mode proving the tracking-issue create/update/close/fail paths (Phase 1 of `docs/topics/standards-sync-audit/PLAN.md`); `.github` canary re-arms first.
3. **Medley rationale corrected** — `sync-manifest.yml:477-486`: dotnet-analysis comment claims root overwrite of `Directory.Build.props` — false (payload maps to `eng/dotnet-analysis/…`, manifest:177-180); pyright comment claims `target-version` overwrite — `target-version` is a ruff key, not pyright, and pyright payload lands under `.github/standards/pyright/`. Rewrite both: real rationale is medley doesn't consume those destination paths (no overwrite possible; adopting would land unused payloads); ruff (line 488) is the only true root-file overwrite — give it its own accurate comment.
4. **Medley diverged counterparts recorded** — add 7 components to medley's `locally-owned:` list (manifest:470-488), each with a comment noting the diverged local copy at the exact canonical destination (recorded 2026-08-16, audit): `repository-text` (.editorconfig 204L vs 67; .gitattributes 290L vs 61), `typos` (_typos.toml 174L vs 58), `markdownlint` (74L vs 41), `editorconfig-checker` (40L vs 33; requires repository-text), `shellcheck` (65L vs 63), `psscriptanalyzer` (138L vs 141 — slightly stale copy), `comment-hygiene-tools` (tools/shared/comment-hygiene/comment-hygiene-patterns.sh 212L vs 133; medley holds 4 additional local files the component doesn't ship). Comment syntax per existing example at manifest:399-405. Keep lists alphabetical.
5. **distribution/README source claims fixed** — `distribution/README.md:53-62`: "currently just `README.md`" is false (root holds README, REVIEW.md, 0-byte AGENTS.md, 0-byte CLAUDE.md); "a future `REVIEW.md` or `AGENTS.md` component" is DOUBLY false — agent-orientation exists (manifest:23-25, source `components/agent-orientation/orientation.md`) AND review-instructions exists (maps `REVIEW.md: REVIEW.md`, managed in 5 targets). `README.md:339-346`: "when `standards`' … `AGENTS.md` gains a criterion" misdirects — the agent-orientation source is the component file, not root AGENTS.md. Fix all with wording that survives Phase 2 retirement (describe source locations factually; Phase 2 rewrites these sections again).
6. **ADR renumber + carve-out** — `git mv docs/adr/0003-local-lane-guards-via-standards-component.md docs/adr/0004-local-lane-guards-via-standards-component.md` (0004 verified free). Sweep the 2 standards inbound refs: `components/local-lane-guards/README.md:9`, `components/local-lane-guards/run-local-lane-guards.sh:5`. TWO MORE refs live in ci-workflows (`docs/topics/local-lane-guards.md:6` absolute GitHub URL; `README.md:222` "standards ADR-0003") — those ride the 0.7 ci-workflows PR (after this renumber merges; lychee there is offline so the 404 would rot silently otherwise). Add collision carve-out note to `docs/adr/README.md` beside lines 17-18 ("Never reuse, renumber, or rename an accepted ADR"): one-time exception recorded — two ADRs were accepted the same day under 0003; the later (local-lane-guards) moved to 0004; links updated; content untouched.
7. **coarse-prefilter header fixed** — `components/local-lane-guards/coarse-prefilter.sh:2-3,16`: cites `scan-tree.sh` and `superset-test.sh`, neither exists in this repo. Real sourcer is `scan-comment-hygiene.sh:30-32`. Rewrite header to name the actual consumer. KEEP the CONTRACT paragraph lines 9-15 verbatim; REWRITE line 16 ("superset-test.sh enforces this contract") to name the real enforcer — downstream consumers' contract tests (e.g. medley's `scan-tree.test.sh` fork).
8. **REVIEW-CREDENTIAL.md compressed** — `distribution/REVIEW-CREDENTIAL.md`: 274 lines → compress prose outside the `[!CAUTION]` block; the single fence (lines 24-87, 64-line blockquote incl. embedded table with `>` prefixes) is preserved VERBATIM. No semantic loss on directives.
9. **pr-convention-policy README obligation paragraph: SKIPPED** — the durable-fix candidate (mirror runner-policy README:81-86's Dependabot obligation) is deliberately not added: Phase 3 deletes the component's manifest entry; adding consumer-obligation prose now is churn.

**Comment-prose hazard:** standards CI runs comment-hygiene over `#`-leading lines including sync-manifest.yml (`ci.yml` comment-hygiene job; patterns ban the warning-marker keywords (the to-do/fix-me family) and `owner/repo#N`, `fixes/closes/resolves #N`, bare `issue N` forms — `components/comment-hygiene/comment-hygiene-patterns.sh:56-119`). New comment prose must avoid issue-reference shapes — say "the audit topic (docs/topics/standards-sync-audit/)" not "standards#318".

**Sync-wave note:** `docs/adr/README.md` is a managed payload of `architecture-decisions` (sole target: medley) — a medley sync PR opens after S1 merges; hand-merge it and verify its diff is the carve-out paragraph only.

**Sanity Check:**

- `grep -n "734158c4\|v0.12.0" distribution/sync-manifest.yml` → empty.
- `grep -n "standards#274\|standards#273" distribution/sync-manifest.yml` → empty.
- `yq '.targets."melodic-software/medley"' distribution/sync-manifest.yml | grep -c "Directory.Build.props"` → 0 (false overwrite claim gone; the component `files:` mapping at manifest:179 legitimately keeps the string elsewhere).
- `yq '.targets."melodic-software/medley"."locally-owned" | length' distribution/sync-manifest.yml` → 15 (8 existing + 7 added, sorted — validator enforces sorted-unique).
- `ls docs/adr/ | grep -c "^0003"` → 1; `ls docs/adr/ | grep -c "^0004"` → 1; `grep -rn "0003-local-lane-guards" --exclude-dir=.git --exclude-dir=.work . | grep -v "docs/topics/standards-sync-audit/PLAN.md"` → empty (this plan's own instruction text legitimately names the old path); the 2 remaining ci-workflows refs tracked in 0.7.
- `grep -n "scan-tree.sh\|superset-test.sh" components/local-lane-guards/coarse-prefilter.sh` → only the rewritten line 16-equivalent naming downstream forks (no claim a local file enforces); `grep -c "CONTRACT" components/local-lane-guards/coarse-prefilter.sh` → ≥1.
- `sed -n '24p' distribution/REVIEW-CREDENTIAL.md` still `> [!CAUTION]`; fence region (old 24-87) byte-identical against pre-edit extract; total line count < 274.
- Standards CI green — named gates this PR trips: manifest validator (`distribution/sync-manifest.sh`), comment-hygiene, typos, markdown, offline lychee (`include_fragments = "full"` — heading anchors in edited docs must resolve), editorconfig, pin-comment-convention, local-lane-guards.

### Phase 0.2: node pin bump + ci-workflows adoption manifest changes (S2) [DONE]

Branch `chore/sync-audit-phase0-node-pin` off main, after S1 merges (both touch sync-manifest.yml).

1. **Canonical `.node-version`: 24.18.0 → 24.19.0**, PLUS the four coupled literals in `components/cloud-environment/setup.sh` (lines 91, 99, 100, 101, 103: Track C comment, `nvm install`, `nvm alias`, two log lines) — `components/cloud-environment/setup.test.sh:39-48` hard-asserts the script pin equals `.node-version` and runs in standards CI (cloud-environment job); bumping the root file alone reds the PR. This matches ci-workflows' current inline 24.19.0 (5 sites) and honors ci-workflows' own drift-check doctrine (`tool-version-drift-check.yml:462-472`: raise the fleet pin first; never run past it — ci-workflows is currently past it).
2. **ci-workflows target: add `node-runtime`** to `managed:` (manifest:337-355, insert between markdownlint and path-detection-action). No App grant needed — target block already exists; attested set unchanged. Sync will land `.node-version` in ci-workflows, which also activates the existing no-op branch in its `.claude/cloud-bootstrap.sh:79-80` (desirable: VM gets the pinned node).
3. **ci-workflows actionlint flipped to managed** — move `- actionlint` from `locally-owned:` into `managed:` as the FIRST entry (validator enforces sorted lists; it sorts before `cloud-bootstrap`); DELETE the now-empty `locally-owned:` key entirely (validator rejects an empty sequence: `sync-manifest.sh:711` "must be a non-empty sequence when present") and the discharged 2-line comment (manifest:351-352). Verified safe: `diff` of canonical `.github/actionlint.yaml` vs ci-workflows' copy is comment-prose only; nothing in ci-workflows pins the config content (action.yml auto-discovers; no test references it). Also update the component-def exclusion comment (manifest:7-19): drop ONLY the implicit ci-workflows coverage — after the flip, actionlint stays locally-owned in THREE targets (medley, ci-runner, github-iac — github-iac's `GovernanceTopologyTests` rationale is load-bearing, keep its bullet) plus the standards-source and `.github` no-workflows bullets.

**Sync-wave note:** this PR triggers human-merged sync PRs — node bump to the 5 existing node-runtime targets, plus `.node-version` (new) + `actionlint.yaml` (prose overwrite) to ci-workflows. All automerge-disarmed; merge them by hand as they open.

**Sanity Check:**

- `cat .node-version` → `24.19.0`; `grep -rn "24\.18\.0" --exclude-dir=.git --exclude-dir=.work .` → empty.
- `bash` run of `components/cloud-environment/setup.test.sh` (repo's documented harness) green.
- `yq '.targets."melodic-software/ci-workflows".managed' distribution/sync-manifest.yml` contains `actionlint` (first) and `node-runtime`; `yq '.targets."melodic-software/ci-workflows" | has("locally-owned")'` → `false`.
- `yq` extraction: exactly 3 targets still list actionlint locally-owned (medley, ci-runner, github-iac); component-def comment names all three.
- Standards CI green; subsequent sync PRs show only expected deltas (spot-check ci-workflows sync PR diff: `.node-version` = `24.19.0` new file, `actionlint.yaml` comment prose only).

### Phase 0.3: ci-workflows node-version-file adoption (C1) [DONE]

In ci-workflows, branch `chore/adopt-node-version-file`, after the S2 sync PR into ci-workflows is merged (needs `.node-version` present).

**Brief deviation (evidence-based, surfaced for approval):** Brief says "5 inline pins → `node-version-file`". Infeasible as written: sites 1-3 (`biome|markdown|tsc/action.yml` `default: 24.19.0`) are composite-action INPUTS consumed by other repos — removing them breaks the cross-repo API — and `tool-version-drift-check.yml:210-217` hard-fails if `markdown/action.yml`'s default vanishes. Revised shape:

1. Convert the 2 direct pins to `node-version-file: .node-version`: `.github/workflows/ci.yml:573`, `.github/workflows/selector-conformance.yml:93` (neither covered by the drift guard today).
2. Keep the 3 composite input defaults (already 24.19.0 — now matching canonical after S2).
3. Extend `tool-version-drift-check.yml` with one new assertion: `markdown/action.yml` `node-version` default == repo `.node-version` content — closing the loop so canonical bump + sync + composite-default bump stay lockstep. ALSO add `.node-version` to the workflow's `push.paths:` allowlist (otherwise a future synced bump waits for the daily cron). Note: this workflow is ADVISORY (header: "NOT in any ci-status gate; never blocks a merge") and has NO `pull_request` trigger — it cannot "pass on the PR".

**Sanity Check:**

- `grep -rn "node-version: 24" .github/workflows/` → empty (both direct pins converted).
- `grep -c "node-version-file" .github/workflows/ci.yml .github/workflows/selector-conformance.yml` → 1 each.
- `grep -n "24.19.0" .github/actions/*/action.yml` → exactly 3 (defaults intact).
- New drift assertion verified by a `workflow_dispatch` run of tool-version-drift-check on the merged branch (or executing the assertion's script block locally) — green.
- Full ci-workflows CI green on the PR.

### Phase 0.4: sync-family caller re-pins + repin-automation extension (S3) [DONE]

Branch `chore/sync-audit-phase0-repins` in standards, LAST in the series (pins capture post-C1 ci-workflows HEAD, maximizing the hardening picked up — incl. `--retry-all-errors` for the observed 08-12 exit-56 class).

1. **Pre-flight contract diff** (per pre-flight consumer check): for both reusables, diff `on.workflow_call` inputs/secrets between the old pin and the new target SHA — `standards-sync.yml` (`8202e03` → current HEAD) and `standards-sync-stuck-automerge-alert.yml` (`ed6d410` → current HEAD). If the contract changed, the policy.json entry is edited to match, not blind-copied; if caller inputs must change, that edit rides this PR.
2. **Re-pin callers**: `.github/workflows/sync.yml:33` and `.github/workflows/standards-sync-stuck-automerge-alert.yml:42`. Pin TARGET: prefer the newest ci-workflows RELEASE TAG containing both the retry hardening and C1 — pin-comment convention (`components/pin-comment-convention/README.md:9-15`) makes `# vX.Y.Z` primary and shortsha/date "legal but discouraged", and ci-workflows cuts release tags. If no tag covers C1 yet, either dispatch a ci-workflows release first or pin HEAD with the `# <shortsha> <date>` fallback AND record why in the PR body.
3. **policy.json appends (SAME PR — hard constraint)**: add the new `path@SHA` keys to `approvedReusableWorkflowContracts` in `components/runner-policy/policy.json` — copy-forward from the existing entries at lines 269-277 (`standards-sync.yml@8202e03…`) and 582-595 (`…alert.yml@ed6d410…`), adjusted per the pre-flight diff. Match `JSON.stringify(policy, null, 2)` formatting of neighbors.
4. **Repin automation extension — REVISED (naive LANE_PATHS append breaks the scheduled repin run):** `repin-policy-lockstep.mjs:158-166` copy-forwards one `oldSha`→`newSha` pair across ALL `LANE_PATHS` entries and THROWS on a missing `path@oldSha` key; the claude lanes share one pin (`7107b348…`) while the sync family sits at two different SHAs — appending the paths as-is makes the next scheduled `claude-lanes-repin` run throw on `standards-sync.yml@7107b348…`. Also `laneUnchanged` is a single boolean across all paths (`:236-246`), and `repin-callers.sh:159,186-189` only edits `components/claude-lanes/*.yml` and hard-fails on diffs outside `LANE_DIR`. Deliverable: refactor to per-path pin resolution (e.g. `{path, callerFile}` entries, old SHA read from each caller file) as its own commit with `claude-lanes` test updates AND a dry-run proof; FALLBACK if the refactor balloons past a focused commit — drop the extension from this PR entirely (no partial edit; the partial IS the breaking change) and file a tracker work item for it.
5. **runner-policy README rollout record (repo convention — the lockstep script's own human-checklist names it):** append the rollout-record paragraphs for both bumps to `components/runner-policy/README.md` following the existing narrative at :709/:729/:740 ("The live pin is now …"). Historical paragraphs stay untouched.
6. **runner-policy tests**: check `runner-policy.test.mjs`/fixtures for old-pin assertions (verified: fixtures use synthetic SHAs, likely no-op — confirm before push).

**Sanity Check:**

- `grep -n "ci-workflows" .github/workflows/sync.yml .github/workflows/standards-sync-stuck-automerge-alert.yml` → both show the new pin; neither shows `8202e03` nor `ed6d410`.
- `components/runner-policy/README.md` contains the new pin SHA/tag in a dated rollout paragraph; earlier `8202e03`/`ed6d410` paragraphs unchanged.
- Repo's documented test harness green locally on runner-policy + claude-lanes suites; runner-policy CI lane green on the PR.
- If extension delivered: dry-run of `repin-policy-lockstep.mjs` with current SHAs exits 0 (no throw); if fallback taken: `git diff` shows zero changes under `components/claude-lanes/` and a tracker item URL is recorded in the PR body.
- Post-merge: one manually dispatched sync dry-run completes green with the new pin.

### Phase 0.5: Dependabot entries fleet-wide (5 parallel PRs) [DONE]

Independent of 0.1-0.4; parallel-safe (disjoint repos). Exactly 7 missing entries confirmed by probe (dependabot.yml is NOT sync-managed anywhere — all per-repo PRs):

| Repo | Add | Style notes (match local convention — full templates in probe report) |
|---|---|---|
| claude-code-plugins | `/.github/standards/pr-convention-policy` | copy existing runner-policy entry verbatim, swap directory; update header-comment root enumeration |
| dotfiles | `/.github/standards/pr-convention-policy` | keep `javascript` label (load-bearing: explicit labels replace defaults), `commit-message.prefix: build`, per-root named group |
| github-iac | `/.github/standards/runner-policy` + `/.github/standards/pr-convention-policy` | flow-seq labels, `prefix: build`; update "Four ecosystems" header prose |
| medley | `/.github/standards/pr-convention-policy` | quoted scalars, `prefix: "chore"` + `include: "scope"`; ALSO fix pre-existing defect: existing runner-policy entry lacks the required `groups` block (dependabot-policy standard `groups-missing`) — add it in the same PR |
| provisioning | `/.github/standards/runner-policy` + `/.github/standards/pr-convention-policy` | flow-seq labels, `prefix: build`; update "Two ecosystems" header prose |

Every added entry carries the mandatory field set (dependabot-policy README:31-41): `schedule.interval: weekly`, `cooldown.default-days: 7`, a `groups` block covering version updates, `open-pull-requests-limit` ≤ 5 (or omitted).

Sequencing note (accepted churn, per Brief's locked "7 entries"): 5 of 7 cover pr-convention-policy, whose MANIFEST entry Phase 3 deletes — but deselection never deletes downstream files, so the lockfiles persist and coverage stays live.

**Sanity Check (per repo):** fetch merged `dependabot.yml`, assert the new `directory` strings present; YAML parses (`yq` exit 0); repo CI green (dotfiles/medley run dependabot-policy-style checks where present).

### Phase 0.6: songwriting one-time hand-fix PR [DONE]

Independent; parallel-safe. songwriting has NO manifest target block (dropped outright, manifest:81-85) — hand-fix, not adoption.

1. Replace `.gitattributes` (2 lines) wholesale with canonical (61 lines) — songwriting's one functional line is byte-identical to canonical line 7; nothing lost.
2. Replace root `.markdownlint-cli2.jsonc` (32 lines) with canonical (41 lines), THEN re-apply two deliberate local deltas: (a) re-add `"MD055": { "style": "consistent" }` with a one-line comment marking it a repo-local override (canonical lacks it; silent drop would change behavior); (b) re-add a corrected one-line pointer comment naming `songs/.markdownlint-cli2.jsonc` (the current pointer says "songwriting/ subtree" — wrong path).
3. `songs/.markdownlint-cli2.jsonc` UNTOUCHED — the MD024:false nested override the Brief protects survives by construction (root canonical already carries `MD024: siblings_only` verbatim; no hand-merge exists).
4. PR body notes: (a) this is a content copy, NOT repository-text conformance — songwriting has no `.editorconfig` (the component is an atomic two-file payload); no future audit may assume the full payload landed. (b) The copied `$schema` pin (markdownlint-cli2 v0.23.2) is authoring-only and enforced by a test only in standards — in songwriting it is a frozen literal with no maintenance obligation.

**Sanity Check:** `gh api` post-merge: `.gitattributes` 61 lines incl. binary patterns; root markdownlint config contains `$schema` pin + `MD055` + `songs/` pointer; `songs/.markdownlint-cli2.jsonc` blob SHA unchanged from pre-PR.

### Phase 0.7: ci-workflows doc corrections (C2) [DONE]

After S1 merges (cites its PR number; ADR file renamed). Small ci-workflows docs PR, two concerns:

1. **REVIEW-CREDENTIAL historical note** — the stale claim is the Phase 1 evidence in `docs/topics/claude-review-lanes/PLAN.md`: the Sanity Check at :352-354 and its recorded result `grep -ci "public" … == 27` (locate by content — the sole `REVIEW-CREDENTIAL` grep-count line in the Phase 1 evidence block opening at :359; line numbers may drift). Append the correction ADJACENT to that claim (dated note at the end of the Phase 1 evidence block — NOT 1,800 lines away in Phase 5, and Phase 5 is `[DOING]`, an append there can collide with in-flight edits): the count described the file pre-compression; standards PR <S1#> compressed it; the recorded count is verified-at-the-time evidence, not a live invariant.
2. **ADR-0003 cross-repo refs** (renumber landed in S1): fix `docs/topics/local-lane-guards.md:6` (absolute GitHub URL → `0004-…`) and `README.md:222` ("standards ADR-0003" → "standards ADR-0004"). ci-workflows' lychee is offline-only — these 404s would never be caught by CI.

**Sanity Check:**

- `grep -c "REVIEW-CREDENTIAL" docs/topics/claude-review-lanes/PLAN.md` → exactly +1 vs pre-edit count (count delta, not absolute); the new dated note sits inside the Phase 1 evidence block.
- `grep -rn "0003-local-lane-guards\|ADR-0003" --exclude-dir=.git .` → empty in ci-workflows.
- `git diff --stat` = 3 files, additions/substitutions only; ci-workflows CI green.

### Phase 1.1: watchdog test mode — ci-workflows reusable + tests [DONE]

Branch in ci-workflows. Facts verified 2026-08-17 (explorer deep-read of the 651-line reusable at v0.14.2; suite `.github/scripts/standards-sync-stuck-automerge-alert.test.cjs`, 1326 lines, ~50 cases, extracting inline scripts by exact step name + `^ {10}script: |` indentation — the scan step's block sits at exactly that indent, so a test-mode branch INSIDE it needs no rename/reindent).

1. **Two new `workflow_call` inputs**: `test-mode` (boolean, default false) and `test-synthetic-candidates` (**type: string**, default `'1'` — string on BOTH sides deliberately: dispatch inputs arrive as strings, and a number type would meet an empty string on cron runs; `Number()` it inside the scan script; `0` stays expressible because the fallback is an explicit empty-string test, never `|| 1`, which would swallow the falsy `0` that drives the close-path proof). Document both in the reusable's input comments and extend the watchdog bullet's description in ci-workflows README (~:329-356; narrative only — no test gates input↔README agreement).
2. **Scan step test branch**: when test-mode, SKIP real target probing and fabricate `Number(test-synthetic-candidates)` candidates (fixed fake repo/PR URLs, above-threshold ages, bodies clearly labeled SYNTHETIC + run URL): 2 → one armed-stuck + one unarmed; 1 → armed-stuck only; 0 → all-clear (drives the close path). Everything downstream (report file, outputs, issue write, deliberate fail) runs UNCHANGED. The branch must be off when the env var is **undefined** — every existing test case runs without it.
3. **Marker/title divergence in test mode across ALL FIVE literal sites** (scan:429 marker; lookup:532-533 marker+title; create:594 title; close:604 marker) via env computed from the input: test marker `<!-- ci-workflows:standards-sync-stuck-automerge-alert:v1:test -->`, test title `[Test] standards-sync auto-merge PR(s) needing attention`. Production values byte-unchanged when test-mode false. Makes medley test issues invisible to the production lookup — the hourly cron and a dispatched test cannot collide.
4. **Names frozen**: job name (reusable:118) and step name "Fail so the scheduled run notifies" (reusable:643) stay byte-identical (the standards caller's classifier reads them — its own matcher bug is fixed in 1.2).
5. **Tests — four structural pins + new coverage**: (a) the scan-script env allowlist at test.cjs:79-87 fixes exactly seven env keys and restores only those in `finally` — the new env var(s) must join both lists or they leak across ~48 cases; (b) `network-timeout-policy.test.cjs:32-36` asserts curl-budget literals occur exactly once in this workflow file (edits near the yq install must not duplicate them); (c) keep the three named structural pins green (required tracking-issue input; guard-first; unconditional issue-token mint); (d) NEW: raw-YAML-text assertions over the workflow string (already read at test.cjs:17) that production and test marker/title agree across all five sites and lookup-title ≡ create-title in both modes — the harness's script-extraction cannot see the YAML `env:`/`with:` sites, and its own `ISSUE_TITLE` constant at test.cjs:763 is STALE (never matched the workflow's real title) — fix/re-anchor it; (e) test-mode branch cases per candidate count incl. off-on-undefined.
6. **Stale comment re-cut** (rides this PR): reusable :192-193 claims "`automerge: false` is a deliberate opt-out (the Phase 3d rollout window sets it fleet-wide)" — false once 1.5 lands; reword to the durable form (per-target opt-out; fleet default armed).

**Sanity Check:**

- `node --test .github/scripts/standards-sync-stuck-automerge-alert.test.cjs` green (old + new cases); `node --test .github/scripts/network-timeout-policy.test.cjs` green.
- `yq '.on.workflow_call.inputs | keys'` includes test-mode + test-synthetic-candidates; `yq '.on.workflow_call.inputs.test-synthetic-candidates.type'` → `string`.
- Job/step names byte-identical to v0.14.2 (`diff` of extracted names against the tag).
- Full ci-workflows CI green on the PR.

### Phase 1.2: standards caller — classifier fix, dispatch threading, re-pin [DONE]

Branch in standards, after 1.1 merges.

1. **FIX the classify-alert-failure matcher (live defect, empirically proven 2026-08-17):** caller:80 matches the alert job name by exact equality, but the jobs API returns reusable jobs PREFIXED — `"alert / Detect standards-sync auto-merge PRs that cannot merge themselves"` (verified live, run 32039984123). The match has never hit; every non-success alert run would misroute to `infrastructure-failure=true` and fire liveness falsely. Fix: match by suffix/contains on `"/ Detect standards-sync auto-merge PRs that cannot merge themselves"` (accept both bare and prefixed forms). Caller-local job — no policy entry, no contract cost. The step-name match at caller:88 is correct as-is (steps API names are unprefixed).
2. **Dispatch threading — real shape**: `workflow_dispatch.inputs`: `test-mode` (boolean, default false) + `test-synthetic-candidates` (string, default `'1'`). `with:` keys CANNOT be conditionally omitted — pass defaulted expressions on EVERY run (cron included): `test-mode: ${{ github.event.inputs.test-mode == 'true' }}` and `test-synthetic-candidates: ${{ github.event.inputs.test-synthetic-candidates == '' && '1' || github.event.inputs.test-synthetic-candidates }}` (explicit empty test — `||` alone would swallow `'0'`). A schedule event has no inputs → expressions resolve to false/'1' → production behavior byte-equivalent.
3. **Pre-merge proof (de-risking, verify then use):** `workflow_dispatch` can target a non-default ref (`gh workflow run … --ref <branch> -f …`) since the workflow exists on main. FIRST STEP of this phase: verify GitHub validates `-f` inputs against the branch's definition. If yes → run ALL THREE 1.3 dispatches against the PR branch BEFORE merging; main's hourly cron is never exposed to an unproven passthrough. If no → merge, then an immediate default-input dispatch is the first post-merge action (proves the cron shape before the next `17 * * *` tick).
4. **Add a `concurrency:` group to the caller** (`group: standards-sync-stuck-automerge-alert`, `cancel-in-progress: false`) — today a dispatched test and the hourly cron can run concurrently; two same-marker creates would permanently jam the fail-closed lookup.
5. **Re-pin** the caller to the post-1.1 ci-workflows ref (release tag preferred; else HEAD SHA + recorded reason). **policy.json SAME-PR**: new `path@SHA` entry, `allowedInputs` = existing five + the two new inputs (runner-policy.mjs:1153 rejects any `with:` key absent from the contract — confirmed the same-PR need is real). runner-policy README rollout paragraph per convention.
6. **Stale comment re-cut**: caller :20-21 ("inert for the duration of a rollout window that opts every target out") — false once 1.5 lands; reword durable.
7. Preserve: `tracking-issue-repository: medley` (private-name republication rationale), runner, both secrets, `permissions: contents: read`, the `17 * * * *` cron.

**Sync-wave note:** policy.json is a synced payload — this PR opens human-merged sync PRs in the 5 runner-policy targets (claude-code-plugins, dotfiles, github-iac, medley, provisioning). Fleet still disarmed; merge by hand.

**Sanity Check:**

- `node --test components/runner-policy/runner-policy.test.mjs` green; manifest validator green; runner-policy CI lane green on the PR.
- Caller grep: new pin present; both dispatch inputs declared; `concurrency` group present; classifier uses suffix/contains match (grep shows no bare exact-equality on the job name).
- One schedule-shaped invocation proven (per item 3's branch check or the immediate post-merge default dispatch): run completes with production behavior (no test branch taken).

### Phase 1.3: execute the proof (operational — no code) [DONE]

Three dispatches of the standards caller, in order (against the 1.2 PR branch if item 3's check holds, else post-merge). PRE-FLIGHT: assert no open issue in medley carries the v1:test marker (a leftover would jam the fail-closed lookup — close it by hand first).

1. `test-mode=true, candidates=2` → run FAILS deliberately; test issue CREATED in medley (v1:test marker, `[Test]` title, 2 synthetic rows); `classify-alert-failure` → `infrastructure-failure=false` and `liveness` skipped — now a real assertion (the 1.2 matcher fix makes it reachable); if it still misroutes, STOP: one re-run after diagnosis, then escalate.
2. `test-mode=true, candidates=1` → same issue UPDATED (1 row).
3. `test-mode=true, candidates=0` → issue CLOSED with the recovery comment; run succeeds.

**Abort path:** if the sequence stops before dispatch-3 for any reason, close the test issue BY HAND before any re-run (two open marker-issues = permanent lookup jam). Expected side effect, not a defect: medley's `issue-labeling.yml` fires on the test issue (governed runner run + a no-issue-type nag comment) — identical treatment to the production alert issue.

Record run URLs + issue URL + per-dispatch classifier verdicts as the proof artifact (append here).

**PROOF ARTIFACT (2026-08-17, executed pre-merge against the 1.2 branch — the branch-ref dispatch check held):**

- Test issue: melodic-software/medley#1856 (created → updated → closed `completed` with the recovery comment; timeline authored by melodic-standards-sync[bot]).
- Dispatch 1 (`candidates=2`, run 32044893913): issue CREATED with 2 SYNTHETIC rows; run failed deliberately; liveness skipped. Exposed latent defect #2 (below).
- Dispatch 2 (`candidates=1`, run 32045258184): issue UPDATED to 1 row; run failed deliberately; classifier SUCCESS with `infrastructure-failure=false`; liveness SKIPPED — the full deliberate-failure routing proven.
- Dispatch 3 (`candidates=0`, run 32045329964): run SUCCESS; issue CLOSED `state_reason=completed`.
- THREE latent classifier defects found and fixed by this proof, each of which would have corrupted the first real alert after re-arm: (1) exact-equality job-name match vs the API's prefixed form (fixed in 1.2's first commit, suffix match); (2) missing `actions: read` permission — the jobs API 404'd under contents:read-only (fixed: job-level permission + loud fallback); (3) the step read targeted a nonexistent `/actions/jobs/<id>/steps` endpoint — steps come embedded in the jobs listing (fixed: extracted from `jobs_json`).

**Sanity Check:** medley test-issue timeline shows create → update → close by melodic-standards-sync[bot]; dispatch-1 concluded failure with `infrastructure-failure=false` and liveness skipped; dispatch-3 concluded success; no open v1:test issue remains; production lookup untouched (no open production-marker issue).

### Phase 1.4: canary — re-arm melodic-software/.github [DOING]

Standards manifest PR after 1.3 proof passes.

1. Remove `automerge: false` from the `.github` target (restores the opt-out default = armed). Verified safe 2026-08-17: all four required contexts fire on every PR (bare `pull_request`, no paths filters), `strict_required_status_checks_policy: false`, squash triple-aligned, arming mutation + Workflows grant proven live under v0.14.2. Thread-resolution rule is ACTIVE but no automated lane opens threads there — a human comment-as-review would block an armed PR, which is precisely the armed-BLOCKED condition the now-proven watchdog reports.
2. Re-cut the fleet-automerge header comment (manifest:313-319): canary armed; fleet pending the recorded proof (cite 1.3 evidence).
3. **Trigger (decision D-P1-1):** `.github` is byte-in-sync — the flip alone opens no PR, and 1.2's policy.json wave does NOT reach it (runner-policy is not in its component set). Default: wait for the next organic canonical change to any of its 7 components (recent cadence: 5 sync PRs/week there), TIME-BOXED at 7 days — if no organic trigger lands, proceed to 1.5 on the 1.3 proof alone (the Brief's gate is the proof, not the canary merge). Do NOT manufacture a canonical change (it would fan PRs fleet-wide).
4. Observe the first armed PR end-to-end: arms on open, merges itself when the four contexts pass. Known flake mode (watchdog-owned): a concurrency-cancelled `do-not-merge` landing last leaves the PR armed-BLOCKED — reported within the hour.

**Sanity Check:** `yq '.targets."melodic-software/.github" | has("automerge")'` → false; next `.github` sync PR shows `autoMergeRequest.enabledAt` set within its run; PR merges without human action OR a watchdog issue appears (both = canary working).

### Phase 1.5: fleet re-arm [PENDING]

Standards manifest PR, gated on the 1.3 proof (canary-armed observation desirable; 1.4's 7-day box governs).

1. Remove `automerge: false` from the remaining 7 targets (restore the opt-out default fleet-wide).
2. Final header re-cut: armed fleet-wide; watchdog proven (cite proof); per-target opt-out remains available for staged rollout windows.

**Sanity Check:** `yq '[.targets[] | select(has("automerge"))] | length' distribution/sync-manifest.yml` → 0 (tests the data, not prose — the re-cut comment may legitimately mention the literal); manifest validator green (absent key = true is schema-optional, verified: schema:64, engine :723-732, engine tests cover both forms); next sync wave's PRs arm (spot-check one private + one public target for `autoMergeRequest.enabledAt`); human sync-merge load trends to zero over the following week.

### Phase 2 — agent-orientation retirement

Planned 2026-08-17 against standards main @ `8fba432`. Manifest facts at this SHA: component def `sync-manifest.yml:26-28`; `managed` in 4 targets — claude-code-plugins (:367), dotfiles (:418), github-iac (:445), provisioning (:537); `locally-owned` in medley (:480). All 4 managed targets carry the current 1552-byte copy (verified live 2026-08-17) — byte-in-sync, so no sync wave is in flight against AGENTS.md. The Brief's locked shape (per the decision ledger Q11): flip to `locally-owned` everywhere FIRST, then blank downstream, then retire the def — the flip closes the overwrite window so a blanked file cannot be resurrected by an in-flight sync.

Non-work discharged by evidence: the "PR body remains the just-in-time warning" criterion is already satisfied — the sync reusable's PR body carries "Do not hand-edit these managed files downstream; change their standards source instead." (ci-workflows `standards-sync.yml:463`); nothing to build. The 12-line "Cloud sessions and plugins" section added to `orientation.md` post-audit duplicates guidance that lives durably in `components/cloud-bootstrap/README.md` (settings.json as plugin source of truth; `cloud-bootstrap.local.sh` pattern) — blanking downstream copies loses nothing not already homed upstream.

### Phase 2.1: standards flip PR — managed → locally-owned [DONE]

Merged as standards PR 421 (squash 306ae05, 2026-08-17). Sanity verified: managed-holder count 0, locally-owned-holder count 5; Bash validator + mjs validator green; staging assertions pass (Windows-only symlink-test failures are environmental — `ln -s` degrades to copy — Linux CI green); post-merge push sync run 32065299476 succeeded with ZERO open sync PRs fleet-wide (also discharges the 2.2 pre-flight).

Branch `chore/sync-audit-phase2-flip` off main. One standards PR; no downstream effect (the synchronizer never reads, changes, or deletes `locally-owned` files, and no canonical component content changes — no sync PRs fan, canary untouched).

1. **Manifest flip** — move `- agent-orientation` from `managed:` to `locally-owned:` in the 4 targets (claude-code-plugins, dotfiles, github-iac, provisioning). Keep lists alphabetical (validator enforces sorted-unique). One shared comment shape per entry: retirement staging per the audit topic (docs/topics/standards-sync-audit/) — blanking PRs follow, then the def retires. No issue-reference shapes in comment prose (comment-hygiene gate).
2. **Test tracking** — `distribution/sync-manifest.test.sh`: the expected-managed-targets assertion (~:683) goes to `[]`-equivalent or is replaced by a locally-owned-in-5 staging assertion; the ci-workflows exclusion assertion (~:692) still passes unmodified (asserts 0). The medley loop (~:697) is unaffected. Keep assertions describing the STAGED state; Phase 2.3 deletes them.

**Sanity Check:**

- `yq '[.targets | to_entries[] | select(.value.managed[]? == "agent-orientation")] | length' distribution/sync-manifest.yml` → 0.
- `yq '[.targets | to_entries[] | select(.value["locally-owned"][]? == "agent-orientation")] | length' distribution/sync-manifest.yml` → 5.
- `distribution/sync-manifest.sh validate` green; full `sync-manifest.test.sh` green; standards CI green.
- Sync dry-run PLAN output lists no `AGENTS.md` destination for any target (dry-run skips the attest/sync jobs entirely — `standards-sync.yml:149,:374` — so it logs mappings, never diffs); then the post-merge push-triggered REAL sync run completes with zero new PRs opened.

### Phase 2.2: downstream blanking PRs — 4 repos [DONE]

All four merged, AGENTS.md 0 bytes verified on each main: claude-code-plugins PR 2991 (CLOUD-SESSIONS pointer now a manifest hyperlink after a review-nit fix), dotfiles PR 525 (whats-tracked bullet reworded), provisioning PR 311, github-iac PR 334 (merge human-approved 2026-08-19 after the session permission classifier denied the agent merge on that repo). Learned en route: the fleet linkage check now has per-repo variants (ccp/github-iac/dotfiles accept a "No linked issue" escape; provisioning enforces Summary/Fix/Verification/Related) — PR bodies conformed per repo.

After 2.1 merges. One PR per target: claude-code-plugins, dotfiles, github-iac, provisioning. Medley is NOT touched (bespoke locally-owned AGENTS.md — the content the split exists to protect). Pre-flight per repo: confirm no open sync PR still carries an AGENTS.md hunk (an in-flight pre-2.1 wave would reintroduce it; merge or close those first).

1. **Blank AGENTS.md** — truncate to 0 bytes (precedent: the org's blank-not-delete convention and standards' own root AGENTS.md placeholder). Never delete: preserves the Cursor surface and the file's slot for future bespoke content.
2. **Downstream CLAUDE.md imports left intact** — claude-code-plugins, github-iac, and provisioning each have an 11-byte `CLAUDE.md` containing only `@AGENTS.md` (verified live 2026-08-17; dotfiles' is already 0-byte). These imports stay untouched: an import of a blank file resolves to nothing (harmless), and leaving the slot mirrors the blank-not-delete rationale — a future bespoke AGENTS.md re-lights the import with zero plumbing.
3. **Reference sweep — pre-resolved main-session, executed by workers** — the main session composes each repo's exact edit list BEFORE dispatching workers (stress-test found the sweeps are not trivially empty: claude-code-plugins has ~15 doc hits needing content-bearing-or-not judgment). Known edits: claude-code-plugins `docs/CLOUD-SESSIONS.md:293` cites `[AGENTS.md](../AGENTS.md)` for bootstrap pin-source provenance — rewrite that maintenance-caveat sentence to cite the standards sync manifest (`melodic-software/standards` `distribution/sync-manifest.yml`) directly; dotfiles `docs/whats-tracked.md:308-310` describes root AGENTS.md as content-bearing — reword to reflect the blank placeholder.
4. **Expected CI lanes** — `.github/claude-security-paths` lists `AGENTS.md` in claude-code-plugins (:19) and provisioning (:21), so the blanking PRs there fire the Claude security-review lane on a trivial truncation — expected, not a failure; leave `claude-security-paths` untouched (blank-not-delete keeps the listed path valid). Worker briefs state this so nobody improvises.
5. **PR bodies** — each carries a non-empty `## Related` section citing the audit topic; per-repo linkage conventions honored (fleet repos enforce the `## Related`-only variant).

**Sanity Check (per repo):**

- `wc -c AGENTS.md` → 0 on the merged main.
- `grep -rn "AGENTS.md" --exclude-dir=.git .` → no remaining reference that presents AGENTS.md as content-bearing (bare mentions in changelogs/history acceptable).
- Repo CI green on each PR.
- claude-code-plugins only: `grep -n "AGENTS.md" docs/CLOUD-SESSIONS.md` → no `../AGENTS.md` link remains.

### Phase 2.3: standards retirement PR — def, source, docs, escape-hatch home [DOING]

Branch `chore/sync-audit-phase2-retire` off main, after all four 2.2 PRs merge. Def deletion and entry removal are the SAME PR (validator rejects `locally-owned`/`managed` refs to unknown components — sync-manifest.sh:739,745).

1. **Manifest** — delete the `agent-orientation` component def (:26-28) and all 5 target entries (4 staged in 2.1 + medley's) including their comments.
2. **Source deletion** — delete `components/agent-orientation/` entirely (git history preserves the content).
3. **standards CLAUDE.md** — the file is a single import line `@components/agent-orientation/orientation.md`; resolve per the approval-gate decision (recommended: blank to 0 bytes — the imported content is self-referentially false for standards itself, and the unhobble posture re-adds instructions only on evidence).
4. **distribution/README rewrite** — `:53-62`: drop the agent-orientation source-location clause (review-instructions' REVIEW.md contrast stays; the root-AGENTS.md-placeholder note simplifies or goes). `:325-350` "Review-instructions reconciliation (medley)": drop agent-orientation from the section (title, list, and the canonical-source parenthetical) — medley's reconciliation obligation continues for review-instructions only.
5. **Test retirement** — `sync-manifest.test.sh`: remove the agent-orientation staging assertion (from 2.1), the ci-workflows exclusion assertion, and drop `agent-orientation` from the medley locally-owned loop (review-instructions remains).
6. **Escape-hatch doc skeleton** — create `distribution/ESCAPE-HATCHES.md` (location per approval-gate decision) holding the re-homed opt-out procedure: how a consuming repo moves a component `managed` → `locally-owned` (or omits it) via a standards manifest PR, rewritten from the retired orientation.md prose. Link it from `distribution/README.md`. Phase 3 expands this file into the consolidated exception-surface index (`--target`/`--target-root`, `LEFTHOOK=0` incl. PowerShell shape, agent deny-rule reconciliation) — the skeleton just gives the opt-out a durable home with no gap.

**Sanity Check:**

- `grep -rnI "agent-orientation" --exclude-dir=.git --exclude-dir=.work --exclude-dir=node_modules .` → hits only under `docs/topics/standards-sync-audit/` plus exactly two deliberate retirement-record sites: the distribution/README medley-section sentence explaining the former component's retirement, and the sync-manifest.test.sh regression assertion that needs the literal to assert the component stays absent (`-I` skips untracked binary caches).
- `test -d components/agent-orientation` → absent; `wc -c CLAUDE.md` matches the approved disposition.
- `test -f distribution/ESCAPE-HATCHES.md` → present; contains the opt-out procedure (grep `locally-owned`).
- `distribution/sync-manifest.sh validate` green; full `sync-manifest.test.sh` green; standards CI green incl. offline lychee (README link edits + new doc anchors resolve) and comment-hygiene.
- Sync dry-run PLAN output lists no `AGENTS.md` destination; post-merge real sync run opens zero new PRs (retirement produces no downstream changes — the engine never deletes).

## Blast radius

**Phase 2: MEDIUM.** Six PRs across five repos; permanently removes a sync surface (the intended outcome) and blanks four downstream files. Mitigations: flip-first ordering closes the overwrite window; blank-not-delete is reversible (git history holds every copy; re-adding the component is a manifest PR); no engine/schema/automerge changes; no canonical content change touches the `.github` canary's components; each PR independently revertable; guidance content verified re-homed (cloud-bootstrap README; escape-hatch skeleton) before the source dies. Not LOW: cross-repo coordination with ordering constraints and a live canary watch running concurrently.

**Phase 1: MEDIUM-HIGH.** Re-arms fleet automerge (the audit's biggest live behavior change) and modifies the watchdog that guards it. Mitigations: proof-gated sequencing (test mode proves create/update/close/fail before any re-arm), canary-first, marker/title isolation for test issues, frozen job/step names (classifier string coupling), policy.json same-PR lockstep, per-target opt-out retained. Verified safe-canary evidence recorded in 1.4.

**Phase 0: MEDIUM** (complete). Behavior-changing surfaces: fleet node pin bump (5 targets + ci-workflows), two CI workflow caller re-pins (sync + watchdog — the sync cascade itself), actionlint managed flip (prose-only overwrite, verified), repin-automation code change. Mitigations: pre-flight contract diffs before re-pins; policy.json same-PR constraint honored; sync-wave PRs all human-merged (fleet disarmed); S1 is pure comments/docs; every phase independently revertable. Not HIGH: no schema changes, no engine changes, no App grant, no automerge arming (that is Phase 1).

## Stress-test summary

Fresh-context adversarial review (2026-08-16, execution-scoped — the 16 locked decisions were fenced off, already 3×-validated): 2 CRITICAL, 9 IMPORTANT, 4 SUGGESTION findings; all 15 verified against the repos and folded into the plan above. Headlines: (1) `.node-version` bump would have broken standards CI — `components/cloud-environment/setup.sh` carries 4 coupled literals hard-asserted by `setup.test.sh` (now in 0.2); (2) the briefed `LANE_PATHS` append is itself the breaking change — the lockstep script assumes one shared pin across all paths (0.4 rewritten to per-path refactor-or-defer, no partial edit); (3) two cross-repo ADR-0003 refs in ci-workflows the sweep would have missed (now in 0.7); (4) pr-issue-linkage is a REQUIRED check on standards + ci-workflows PRs — every PR needs a closing keyword + `## Related` body (now in Mechanical work). This review doubles as the Step-4 formal stress-test for the MEDIUM blast radius: it ran fresh-context with an adversarial failure-scenario brief; re-running `/planning:devils-advocate` on the same execution surface would relitigate the fenced decisions.

**Phase 2 stress-test (2026-08-17, fresh-context, execution-scoped — the locked decisions fenced off):** 0 CRITICAL, 2 IMPORTANT, 2 SUGGESTION; all four verified against live origin/main state (local clones were stale) and folded in. Headlines: (1) three of the four blanking targets have an `@AGENTS.md`-only CLAUDE.md — disposition decided (left intact), and the 2.2 sweeps are NOT trivially empty (ccp ~15 doc hits; dotfiles whats-tracked.md) — edit lists now composed main-session pre-dispatch; (2) the planned "dry-run shows empty diff set" evidence was non-producible — dry-run skips the attest/sync jobs (`standards-sync.yml:149,:374`) — replaced with mapping-output + real-run-zero-PRs checks; (3) claude-security-paths fires the security-review lane on the ccp/provisioning truncation PRs — expected, briefed; (4) residual grep hardened with `-I`. Reviewer also confirmed: all four downstream AGENTS.md blobs hash-identical to canonical, 0-byte lint safety (standards' own root AGENTS.md passes the same canonical lint set), no `AGENTS.md#fragment` inbound links (lychee-safe), dotfiles root AGENTS.md in `.chezmoiignore`, and no schema/mjs/baseline hardcoding of the component. This review doubles as the Step-4 formal stress-test for the MEDIUM blast radius, same pattern as Phases 0-1.

## Execution shape

Waves (file-overlap + dependency analysis):

- **Wave A (parallel-safe, zero file overlap):** 0.1 (standards), 0.5 (5 downstream repos), 0.6 (songwriting).
- **Wave B (sequential chain):** 0.2 after 0.1 merges (both edit sync-manifest.yml) → merge ci-workflows sync PR → 0.3 (needs `.node-version` in ci-workflows) → 0.4 (pins capture post-0.3 HEAD). 0.7 after 0.1 (cites S1 PR#).

| Phase | Surface | Basis |
|---|---|---|
| 0.1 | main session | judgment-heavy comment/prose rewrites against locked rationale |
| 0.2 | main session | small, gated on 0.1, manifest edits need care |
| 0.3 | main session (or worker) | small ci-workflows change + guard extension |
| 0.4 | main session | contract-diff judgment + policy.json lockstep |
| 0.5 | sub-agent workers (up to 5 parallel) | mechanical, per-repo templates fully specified, disjoint repos |
| 0.6 | sub-agent worker | mechanical, fully specified |
| 0.7 | main session | 5-minute doc append |

Cost note: worker fan-out for 0.5/0.6 ≈ 6 agents vs sequential — material only in wall-clock; token cost modest (small diffs). Sequential fallback: execute 0.5 repos one at a time in main session if a worker misbehaves; scope fence per worker = exactly one repo's `.github/dependabot.yml` (+ header comment) or songwriting's 2 files; FORBIDDEN: PLAN.md, any other repo, any workflow file.

Phase 2 shape: strictly 2.1 → 2.2 → 2.3 across sub-phases (each gates the next); WITHIN 2.2 the four repo PRs are parallel-safe (disjoint repos, zero file overlap).

| Phase | Surface | Basis |
|---|---|---|
| 2.1 | main session | manifest + test edits need staged-state care |
| 2.2 | sub-agent workers (up to 4 parallel) or sequential main | blanking + pre-resolved edit lists, disjoint repos; main session composes each repo's reference-sweep edits BEFORE dispatch (sweeps are not trivially empty) |
| 2.3 | main session | judgment-heavy README rewrites + escape-hatch doc authoring |

Phase 2 scope fence per 2.2 worker: exactly one repo — `AGENTS.md` (truncate) + any files its reference sweep flags; FORBIDDEN: PLAN.md, sync-manifest.yml, any other repo, deleting AGENTS.md. Sequential fallback: run the four repos one at a time in main session.

## Open questions

- 0.4 pin form: newest ci-workflows release tag containing C1 + retry hardening, vs HEAD-SHA fallback — resolved at implementation time by tag availability (decision rule in 0.4 item 2).
- 0.4 repin-automation refactor size: per-path pin resolution deliverable in one focused commit, or deferred to a tracker item (decision rule + fallback in 0.4 item 4 — no partial edit either way).

## Handoff to implementation

### User-approval gates

- Phase 2 decision A — escape-hatch sequencing: APPROVED 2026-08-17 as recommended — 2.3 ships a SKELETON `distribution/ESCAPE-HATCHES.md` holding just the opt-out procedure; Phase 3 expands it (no homeless gap, no double move).
- Phase 2 decision B — standards CLAUDE.md fate: APPROVED 2026-08-17 as recommended — blank CLAUDE.md to 0 bytes (imported prose self-referentially false for standards; unhobble posture re-adds instructions only on evidence).
- Phase 0.3's Brief deviation (2-of-5 pins convert; composites keep defaults; drift-check extension added) — approve or override before C1.
- Phase 0.6's two local deltas (MD055 re-add, corrected pointer comment) — [FALLBACK — confirm or override].
- If 0.4's investigation finds the caller-rewrite half non-trivial: scoped-down deliverable + tracker follow-up needs a nod (gate embedded in 0.4 item 4).

### Execution shape ([EXEC-SHAPE] tagged)

- PR series structure S1/S2/C1/S3 + 5 dependabot + songwriting + C2, with Wave A/B ordering above [EXEC-SHAPE].
- 0.5/0.6 delegated to scope-fenced workers; all standards PRs main-session [EXEC-SHAPE].
- medley groups-block defect fix folded into medley's 0.5 PR [EXEC-SHAPE].
- pr-convention-policy README obligation paragraph skipped (Phase 3 deletes the entry) [EXEC-SHAPE].
- ADR carve-out cascades to medley via architecture-decisions sync — accepted [EXEC-SHAPE].
- 0.4 pin form: release tag preferred per pin-comment convention; HEAD-SHA fallback with recorded reason [EXEC-SHAPE].
- 0.4 repin-automation: per-path refactor in one focused commit, else defer whole item to tracker — never the partial LANE_PATHS append [EXEC-SHAPE].
- 0.7 widened to carry the 2 cross-repo ADR-0003 ref fixes (same repo, same PR) [EXEC-SHAPE].
- Phase 2 PR series 2.1 flip → 2.2 ×4 blanking → 2.3 retire, with 2.2 worker fan-out and the scope fence above [EXEC-SHAPE].
- 2.2 blanks to exactly 0 bytes, matching standards' own root AGENTS.md placeholder [EXEC-SHAPE].
- 2.3 deletes `components/agent-orientation/` outright (git history is the archive) [EXEC-SHAPE].
- ccp CLOUD-SESSIONS.md fix re-points the pin-source provenance sentence at the standards sync manifest rather than deleting the caveat [EXEC-SHAPE].
- Test assertions track the staged state in 2.1 and retire in 2.3 — never deleted early [EXEC-SHAPE].
- Downstream `@AGENTS.md` CLAUDE.md imports (ccp, github-iac, provisioning) left intact — import of a blank file is inert; slot preserved [EXEC-SHAPE].
- 2.2 reference-sweep edit lists composed main-session pre-dispatch; workers execute, never judge content-bearing status [EXEC-SHAPE].

### Mechanical work

- **PR-body gate (required check, easy to forget):** standards and ci-workflows both run `pr-issue-linkage` as a REQUIRED check (v0.10.2 shape: native closing keyword + non-empty `## Related` section; only `dependabot[bot]` exempt). BEFORE opening each PR, file (or reuse) a tracking issue in that repo and write the body with `Closes #N` + `## Related`. Downstream fleet repos enforce the weaker `## Related`-only variant (6/8 at v0.10.2) — still include the section everywhere. ~9 PRs total across the series.
- Commit per logical item within each PR; conventional-commit subjects; Co-authored-by trailer per repo convention.
- Verification checkpoint per phase = its Sanity Check block; standards CI + runner-policy lane are the hard gates for S1-S3.
- Sequential fallback for worker fan-out documented under Execution shape.
- PLAN.md status tags advance main-session only; workers report back.
