# standards-sync-audit

## Brief

### TLDR

Six-lane deep audit of the standards distribution/sync system found the engine byte-perfect but the governance around it stale: fleet automerge disarmed past its recorded restore trigger (~65 human merges/week), an AGENTS.md component that reaches Claude Code in zero repos and clobbered bespoke content four times in six weeks, five fully-built components with zero adopters, a sync caller pinned 123 commits behind, and genuine overengineering rooted in a hollow Bash+yq purity constraint. Sixteen decisions were interviewed, adversarially validated by three fresh-context agents (two same-vendor, one cross-vendor Codex), and locked. Remediation is phased below.

### Goal

Execute the locked decision set: restore automerge safely (canary + proven watchdog), retire the agent-orientation component, clean up zero-adopter components, bring pins current, run the hygiene wave, cut consumer friction, expand the sync fleet by one batched App grant (claude-code-proxy, codex-plugins, cursor-plugins), and later port the engine to Node.

### Constraints

- Exact-set App attestation: any roster change is an atomic two-sided operation (manifest edit + org-owner grant); grant-first per github-iac's documented procedure; a skew window reds out the whole fleet — schedule nothing sync-dependent inside it.
- [DISCHARGED at Phase 1.5] Every new target entered with explicit `automerge: false` while the canary was in flight (omitted defaults to TRUE and would have bypassed it). Post-1.5 the fleet default is armed; a new target takes an explicit opt-out only for a live per-target blocker — today, its default branch sitting outside the org `ci-gate` ruleset — recorded at its own key with a removal trigger.
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

### Phase 1.4: canary — re-arm melodic-software/.github [DONE]

Standards manifest PR after 1.3 proof passes.

1. Remove `automerge: false` from the `.github` target (restores the opt-out default = armed). Verified safe 2026-08-17: all four required contexts fire on every PR (bare `pull_request`, no paths filters), `strict_required_status_checks_policy: false`, squash triple-aligned, arming mutation + Workflows grant proven live under v0.14.2. Thread-resolution rule is ACTIVE but no automated lane opens threads there — a human comment-as-review would block an armed PR, which is precisely the armed-BLOCKED condition the now-proven watchdog reports.
2. Re-cut the fleet-automerge header comment (manifest:313-319): canary armed; fleet pending the recorded proof (cite 1.3 evidence).
3. **Trigger (decision D-P1-1):** `.github` is byte-in-sync — the flip alone opens no PR, and 1.2's policy.json wave does NOT reach it (runner-policy is not in its component set). Default: wait for the next organic canonical change to any of its 7 components (recent cadence: 5 sync PRs/week there), TIME-BOXED at 7 days — if no organic trigger lands, proceed to 1.5 on the 1.3 proof alone (the Brief's gate is the proof, not the canary merge). Do NOT manufacture a canonical change (it would fan PRs fleet-wide).
4. Observe the first armed PR end-to-end: arms on open, merges itself when the four contexts pass. Known flake mode (watchdog-owned): a concurrency-cancelled `do-not-merge` landing last leaves the PR armed-BLOCKED — reported within the hour.

**Sanity Check:** `yq '.targets."melodic-software/.github" | has("automerge")'` → false; next `.github` sync PR shows `autoMergeRequest.enabledAt` set within its run; PR merges without human action OR a watchdog issue appears (both = canary working).

**Evidence (2026-08-23):** the canary fired organically inside the time box. `.github` PR 62 opened 02:28:08Z; the App armed auto-merge on it at 02:28:10Z (`enabledBy` = the sync App itself, SQUASH); it self-merged at 02:28:39Z, `mergedBy` the same App, no human action. All four required contexts ran and passed (`pr-title`, `pr-issue-linkage`, `do-not-merge`, `ci-status`). The watchdog stayed green throughout.

### Phase 1.5: fleet re-arm [DONE]

Standards manifest PR, gated on the 1.3 proof (canary-armed observation desirable; 1.4's 7-day box governs). Executed 2026-08-23 on the observed canary, inside the box.

1. Remove `automerge: false` from 8 targets — the 7 originals (ci-runner, ci-workflows, claude-code-plugins, dotfiles, github-iac, medley, provisioning) plus codex-plugins. Three Phase 4 targets (agent-plugins, claude-code-proxy, cursor-plugins) keep the key: their default branches are not covered by the org `ci-gate` ruleset, so they carry no required status checks and an armed sync PR would merge ungated. Proven live — claude-code-proxy PR 182 merged 2026-08-23 with `ci-status`, Ruff, Pester and pytest all FAILURE, because none of them are required. codex-plugins entered in the same Phase 4 window and IS armed, because it alone among the four carries `ci-gate` (verified on its PR 22: all four contexts SUCCESS). Removal trigger for the three is tracked as Phase 1.6.
2. Final header re-cut: fleet armed; watchdog proven (cite proof); the surviving opt-outs each name a live per-target blocker and its removal trigger, rather than reading as roster vintage.

**Sanity Check:** `yq '[.targets[] | select(has("automerge"))] | length' distribution/sync-manifest.yml` → 3, and `yq '[.targets | to_entries[] | select(.value.automerge == false) | .key]'` → exactly agent-plugins, claude-code-proxy, cursor-plugins, each carrying a comment naming the `ci-gate` gap and its removal trigger (tests the data, not prose — the re-cut comment may legitimately mention the literal); manifest validator green (absent key = true is schema-optional, verified: schema:64, engine :666-684, engine tests cover both forms); next sync wave's PRs arm (spot-check one private + one public target for `autoMergeRequest.enabledAt`); human sync-merge load trends to zero over the following week.

### Phase 1.6: extend the org ci-gate ruleset to the three disarmed targets [PENDING]

Surfaced by Phase 1.5's adversarial review: three sync targets sit permanently disarmed with no tracked path back to armed, and nothing in the repo recorded the reason before this phase. `agent-plugins`, `claude-code-proxy` and `cursor-plugins` resolve to `base` + `signing` only, while every armed target also resolves `ci-gate` (org ruleset id 17989001) — the rule that supplies `pr-title`, `pr-issue-linkage`, `do-not-merge` and `ci-status` as required contexts.

1. github-iac PR: extend `ci-gate` to the three repositories. Pulumi-managed per repo convention — never the GitHub UI or ad-hoc `gh`.
2. claude-code-proxy additionally needs its checks green before arming: PR 182's rollup shows Ruff, Pester, pytest and `ci-status` failing.
3. Standards PR: drop the three `automerge: false` keys once each repository has one real sync PR showing all four required contexts firing.

**Sanity Check:** `gh api repos/melodic-software/<repo>/rules/branches/main` reports `required_status_checks` carrying all four contexts for all three repositories; then `yq '[.targets[] | select(has("automerge"))] | length'` → 0.

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

### Phase 2.3: standards retirement PR — def, source, docs, escape-hatch home [DONE]

Merged as standards PR 424 (squash 7798d92, 2026-08-19). Sanity verified: manifest at 37 components with zero agent-orientation refs (Bash + mjs validators green); component dir gone; CLAUDE.md 0 bytes; ESCAPE-HATCHES.md present with the opt-out procedure; residual grep hits only the audit topic plus the two deliberate retirement-record sites; full test suite green on CI (local Windows symlink cases environmental); post-merge push sync run 32256390285 succeeded with zero open sync PRs fleet-wide. Phase 2 COMPLETE.

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

### Phase 3 — component cleanup

Planned 2026-08-19 against standards main @ `ae35486` (ci-workflows @ `01c3295` = v0.15.0). Facts verified by two fresh-context explorers reading live origin/main fleet-wide, plus main-session probes. Key facts the sub-phases build on:

- concurrency-policy, dependabot-policy, pin-comment-convention are already zero-target (defs at manifest :161, :169, :264; no target references, no downstream payloads anywhere in the fleet, no rationale comments adjacent). Their standards-internal enforcement (ci.yml jobs :204-225, :227-248, :839-873, npm scripts, dependabot entries, repin-caller test fixtures) all STAYS — Q3's "keep dirs as producer-internal lint".
- pr-convention-policy (def :268-276, `requires: node-runtime`) is `managed` in 5 targets (ccp :370, dotfiles :427, github-iac :450, medley :470, provisioning :541 at `ae35486` — all managed, none locally-owned; deletions are name-based, numbers informational). Payloads exist in all 5 at `.github/standards/pr-convention-policy/` (5 files each) but are INVOKED nowhere — the only live coupling is a Dependabot npm root entry per repo's `.github/dependabot.yml`. Retirement follows the README Retire lifecycle row: upstream first, then one-time downstream deletion PRs.
- ADR ledger: next number 0005; README convention = new superseding ADR + old ADR's Status line becomes `superseded by [ADR-0005](...)` (exactly-one-lifecycle-status vocabulary; body untouched). No supersede precedent exists yet — 0003's status edit is the first.
- pr-issue-linkage pins: 6 of 8 callers at v0.10.2 (`e9443874`) — standards, ci-workflows self-caller, ccp, dotfiles, github-iac, medley; ci-runner + provisioning already at v0.14.2 (`7107b348`). The reusable is byte-identical v0.14.2 → v0.15.0 → main. Strictness is version-inherent (no inputs control it): v0.10.2 = closing keyword + `## Related`; v0.14.2 = that plus non-empty `## Summary`/`## Fix`/`## Verification`. runner-policy `policy.json` ALREADY carries the v0.14.2 SHA entry (line ~872) incl. `minimumCallerPermissions: pull-requests: read, actions: read`; the v0.15.0 SHA is NOT listed for this reusable.
- Org-default PR template (`melodic-software/.github` `.github/PULL_REQUEST_TEMPLATE.md`, 870 bytes): fails BOTH gate versions as shipped — `## Summary` holds a bare `-` (passes vacuously = the bare-dash hole), `## Related` is comment-only (stripped → empty → fails), no `## Fix`/`## Verification`, `Closes #` digit-less. ccp's repo-local template already has the 4 headers; provisioning's local template has its own stray bare dash under `## Related`.
- Escape-hatch sources: engine per-command filter matrix (parsed/enforced sync-manifest.sh :1020-1085) — `validate` accepts NO filter flags; `matrix`/`plan` accept `--targets` (exact CSV allowlist) only; `mappings`/`dest-paths` require `--target OWNER/REPO` and reject the others; `apply` requires `--target` AND `--target-root DIR` and rejects `--targets`. None of `--target`/`--target-root` documented in distribution/README (Commands section documents only validate/plan). Lefthook skip surfaces: native `skip: true` (lefthook-base README:11); `LEFTHOOK=0` appears nowhere in docs but is DENIED to agents by claude-permissions (Bash globs :88-90) with NO PowerShell twins — while the `--no-verify` denies DO have PowerShell twins (:280, :309-310). claude-permissions syncs to exactly one target (dotfiles).
- Zero-target validator rule: engine-only (schema cannot express cross-object reachability; validate-sync-manifest.mjs is a fixture-agreement subset by design). Landing zone: after the target loop in `validate_manifest` (sync-manifest.sh :761-762); closure expansion must be written (REQUIRES_BY_COMPONENT holds direct deps only). Fixture precedent for engine-only FAIL cases: sync-manifest.test.sh :374-382. CRITICAL interaction: after this phase's deletions, `local-lane-guards` (refs=0, requires=2) remains legitimately zero-target until Phase 5's staged migration — the rule needs a named temporary exemption (decision C below).

Approval-gate decisions (resolved at plan approval):

- **Decision 3-A — re-pin version: v0.14.2, not v0.15.0.** The reusable is byte-identical across the two tags; the v0.14.2 SHA already has the policy.json contract entry, so pinning v0.14.2 needs ZERO policy.json change and ZERO fleet sync wave, and converges all 8 repos on one SHA (ci-runner + provisioning are already there). Pinning v0.15.0 would force a policy.json append + 7 hand-merged sync PRs (fleet still disarmed) for no content difference.
- **Decision 3-B — zero-target rule ships WITH a named temporary exemption** for `local-lane-guards` (and its dependency closure), carrying a rationale comment pointing at the Phase 5 staged migration; Phase 5 removes the exemption. Alternative (deferring the whole rule to Phase 5) abandons the Brief's "lands LAST in the component-cleanup series" sequencing.
- **Decision 3-C — provisioning's local-template stray-dash fix rides Phase 3** as a one-line PR beside the org-default fix (same defect class, found during fact-gathering) [EXEC-SHAPE].
- Medley's `select-runner` sibling pin at v0.8.0 is OUT of scope (not pr-issue-linkage) — recorded as a follow-up tracker item in 3.6.

### Phase 3.1: standards PR — delete the zero-target trio defs [DONE]

Merged as standards PR 430 (squash 68e4a96, 2026-08-19). Validator 34 components, 11 targets; both validators green; review threads (stale target count, filter-flag matrix) fixed and resolved. Post-merge zero-new-PRs evidence DEFERRED — sync runs red at attest (App installation 14 vs manifest 11) pending the org-owner installation trim.

Branch `chore/sync-audit-phase3-zero-target-defs` off main. Delete the manifest component defs for concurrency-policy (:161-168), dependabot-policy (:169-178), pin-comment-convention (:264-267). Nothing else changes: no target rows exist, no downstream payloads exist, no adjacent comments are lost, and every standards-internal consumer (CI jobs, npm scripts, dependabot entries, `repin-callers.test.sh` fixture corpus, runner-policy README citation, claude-lanes comments) references the component DIRECTORIES, which stay.

**Sanity Check:**

- `distribution/sync-manifest.sh validate` → "Manifest valid: 34 components, 11 targets" (11 since the Phase 4 fleet-expansion PR landed out of band); mjs validator green.
- `grep -c "concurrency-policy\|dependabot-policy\|pin-comment-convention" distribution/sync-manifest.yml` → 0.
- Full `sync-manifest.test.sh` green (Linux CI; local Windows symlink cases environmental); standards CI green — the four component jobs still run and pass (producer-internal lint untouched).
- Post-merge push sync run completes with zero new PRs.

### Phase 3.2: standards PR — pr-convention-policy retirement + ADR-0005 [DONE]

Merged as standards PR 434 (2026-08-19). Validator 33 components, 11 targets; ADR-0005 accepted, ADR-0003 status superseded-by; review folded a retained-README rewrite (component described post-retirement, thin-runner follow-on retired).

Branch `chore/sync-audit-phase3-pr-convention-retire` off main, after 3.1 merges (same file).

1. Delete the pr-convention-policy def (:268-276) and its 5 managed rows (ccp, dotfiles, github-iac, medley, provisioning).
2. **ADR-0005** `docs/adr/0005-retire-pr-convention-policy-distribution.md`: supersedes ADR-0003's distribution claim — the analyzer stays standards-internal (policy.json remains the machine-readable convention record per `conventions/process/issue-tracker.md:66`); enforcement lives in the ci-workflows pr-issue-linkage reusable, which consumers pin directly; distributing a second vendored analyzer to consumers added payloads nobody invoked (verified fleet-wide: zero invocations, Dependabot-root coupling only). ADR-0003's Status line becomes `superseded by [ADR-0005](0005-retire-pr-convention-policy-distribution.md)`; its body is not rewritten.
3. Grep-check `sync-manifest.test.sh` for pr-convention-policy assertions and retire any found (explorers surfaced none; verify at implementation).

**Sanity Check:**

- Validator → 33 components; `grep -c "pr-convention-policy" distribution/sync-manifest.yml` → 0.
- `grep -n "Status" docs/adr/0003-pr-convention-policy-as-data.md` → the superseded-by line; `ls docs/adr/ | grep -c 0005` → 1; lychee + markdownlint green.
- Post-merge sync run: zero new PRs (deselection never deletes downstream).

### Phase 3.3: five downstream payload-deletion PRs [DONE]

All five merged 2026-08-19 (ccp 3025, dotfiles 528, github-iac 338, medley 1864, provisioning 313): payload dirs deleted, Dependabot roots removed, header comments reworded (one review nit — provisioning's stale three-roots count — fixed in-flight). Zero pr-convention-policy references remain in any consumer.

After 3.2 merges. One PR per repo (ccp, dotfiles, github-iac, medley, provisioning), Retire-lifecycle one-time deletions, main session pre-resolving exact edits before dispatching workers:

0. Pre-flight per repo (Phase 2.2 pattern): no open sync PR carries `.github/standards/pr-convention-policy/` hunks (a pre-3.2 wave merged after this PR would resurrect the payload), and any open Dependabot PRs against that npm root are closed first (they would conflict against the deletion).
1. Delete `.github/standards/pr-convention-policy/` (5 files).
2. Remove the repo's `.github/dependabot.yml` pr-convention-policy entry/group (fact-sheet locations: ccp :90-95 + header mention :3-4; dotfiles :84-99; github-iac :92-104 + header :6-7; medley :92-110 + comment :92-96; provisioning :73-85 + header :9-10) — rewording headers that name it alongside runner-policy.
3. PR bodies conform to each repo's live linkage contract (provisioning: Summary/Fix/Verification/Related; others: `## Related` + "No linked issue" escape).

**Sanity Check (per repo):** `test -d .github/standards/pr-convention-policy` → absent on merged main; `git grep -c "pr-convention-policy"` → 0; repo CI green (dependabot.yml schema lint included).

### Phase 3.4: standards PR — escape-hatch expansion + deny-rule reconciliation [DONE]

Merged as standards PR 432 (squash 5a93a99, 2026-08-19). Review hardened the deny shape further: PowerShell's Env: drive is case-insensitive, so the single `*env:LEFTHOOK*` anchor became two — `PowerShell(*LEFTHOOK*)` (any uppercase-name reference, any drive casing) + `PowerShell(*:lefthook*)` (drive-qualified lowercase, bare `lefthook run` untouched), mixed-case residual recorded in the test; the doc example now unsets the session-scoped variable. Dotfiles sync-wave evidence DEFERRED on the attest outage.

Branch `chore/sync-audit-phase3-escape-hatches` off main (no dependency on 3.1-3.3).

1. **ESCAPE-HATCHES.md expansion** — add sections: (a) *Engine target filters* per the exact per-command matrix above (`--targets` matrix/plan only; `--target` for mappings/dest-paths/apply; `--target-root` apply only, incl. the origin-identity check), sourced from sync-manifest.sh :1020-1085; (b) *Skipping Lefthook lanes* — native per-repo `skip: true` (the lefthook-base documented opt-out), and the `LEFTHOOK=0` environment variable for a one-off human bypass, with the PowerShell shape (`$env:LEFTHOOK = '0'`) spelled out; states plainly that AGENT sessions are deny-floored from this bypass by claude-permissions and that the deny floor is not relaxable (README :149-151, :195).
2. **distribution/README Commands section** gains the `--target`/`--target-root` documentation (or a pointer to the new section).
3. **claude-permissions reconciliation** — the Bash LEFTHOOK denies (:88-90) anchor on the inline-env spelling `LEFTHOOK…=0 cmd`, which has no PowerShell equivalent — a literal twin would never match (stress-test CRITICAL finding). PowerShell's bypass shapes are `$env:LEFTHOOK = '0'`, `Set-Item env:LEFTHOOK …`, `${env:LEFTHOOK} = …`. Add an env-var-reference-anchored deny (`PowerShell(*env:LEFTHOOK*)` shape — deliberately broad: agents have no legitimate reason to touch that variable, and deny rules are whole-string globs with `*` as the only metacharacter, so precision costs coverage). Extend `claude-permissions.test.sh` to assert the exact new deny rows' membership. ESCAPE-HATCHES.md's deny-floor sentence is written AFTER this lands so the claim is true for both shells.

**Sanity Check:** lychee (`include_fragments = "full"`) green over new anchors; `grep -c "target-root" distribution/README.md distribution/ESCAPE-HATCHES.md` ≥ 1 each; `grep -n "env:LEFTHOOK" components/claude-permissions/claude-permissions.json` → the new PowerShell row(s) present alongside the 3 Bash rows; claude-permissions test green asserting the new rows; a manual glob walk confirms `PowerShell(*env:LEFTHOOK*)` matches each of the three PowerShell bypass shapes above (write the three sample strings into the test as membership-adjacent comments); the post-merge sync PR to dotfiles (sole claude-permissions target) shows a claude-permissions.json-only diff and is merged (hand-merge if the fleet is still disarmed).

### Phase 3.5: org-default PR template fix + provisioning rider [DONE]

Merged: melodic-software/.github PR 52 (four contract headers, all guidance in stripped HTML comments; review also caught the repo's `.claude/source-control.md` pr_body_required_sections still on the old Summary/Test plan/Related contract — aligned in the same PR) and provisioning PR 312 (stray dash dropped).

1. PR to `melodic-software/.github`: rewrite `.github/PULL_REQUEST_TEMPLATE.md` to carry the four contract headers (`## Summary`, `## Fix`, `## Verification`, `## Related`) plus the `Closes #` line, with ALL guidance inside HTML comments (the gate strips them — no bare-dash placeholder content under any header, closing the vacuous-pass hole; an unfilled template now fails cleanly on every section instead of passing Summary). Content-only change to a repo file — the github-iac Pulumi rule governs settings, not community-health files. No canary interaction (human PR; sync uninvolved).
2. Rider PR to provisioning: remove the stray bare `-` under `## Related` in its local template [EXEC-SHAPE, decision 3-C].

**Sanity Check:** template contains all four `##`-level contract headers and zero non-comment placeholder lines under them (`awk` over the merged file); a scratch PR against a template-inheriting repo (or the next real PR) passes the linkage gate with the template filled normally.

### Phase 3.6: pr-issue-linkage fleet re-pin to v0.14.2 [DONE]

All six callers converged on v0.14.2 and merged 2026-08-19: standards PR 436 (header contract prose also refreshed per review), ci-workflows PR 496 (pin-only), ccp PR 3026, dotfiles PR 529, github-iac PR 339, medley PR 1865 (its select-runner v0.8.0 lag filed as medley issue 1863). Permissions replaced per the pre-resolved edit lists; policy.json untouched (entry pre-existed). Open-PR sweep at close: dependabot PRs exempt everywhere; the one flagged non-conforming open body is standards PR 422 (repin-App claude-lanes re-pin — carries Summary + no-issue marker but not Fix/Verification/Related; will need a body edit before its next gate event). The strict gate's live proof is the next human PR per repo — the Phase 3 close-out PR itself in standards.

After 3.5 merges (the stricter gate must meet a compliant default template). Six caller PRs — standards, ci-workflows (self-caller `pr-issue-linkage-self.yml`), ccp, dotfiles, github-iac, medley:

1. Bump the `uses:` pin `e9443874… # v0.10.2` → `7107b348… # v0.14.2` (pin-comment shape per repo convention).
2. Permissions: **replace, not insert** — five callers (standards, ccp, dotfiles, github-iac, medley) declare job-level `permissions: {}` today; replace that with `pull-requests: read` + `actions: read` (workflow-level `{}` stays, matching ci-runner/provisioning's verified shape). The sixth (ci-workflows `pr-issue-linkage-self.yml`) already grants both — pin-only edit there. policy.json's `minimumCallerPermissions` for this SHA enforces the contract loudly if an edit is missed; NO policy.json change needed (entry exists).
3. Callers trigger on `pull_request_target` — each re-pin PR is gated by the OLD base-branch pin (a four-section body satisfies both contracts, so no breakage; but the strict gate cannot be observed on the re-pin PR itself). At each merge, sweep that repo's OPEN PRs: they re-validate under the strict contract on their next event — human-authored Related-only bodies need a body update (sync-bot bodies already emit all four sections by construction, standards-sync.yml :449-464; dependabot exempt everywhere).
4. File the out-of-scope observation as a tracker item: medley's select-runner caller pin lags at v0.8.0 (search-before-create in medley's tracker; pivot to comment on an existing item if one matches).

**Sanity Check (per repo):** `grep -c "7107b348" .github/workflows/<caller>.yml` → 1 and no `e9443874` remains; job-level permissions block reads `pull-requests: read` + `actions: read` (not `{}`); runner-policy lane green (SHA already allowlisted); post-merge, the strict gate is proven by the FIRST subsequent PR event in that repo (or a body-edit re-trigger on any open PR) passing/failing per the four-section contract; open-PR sweep recorded in the PR body.

### Phase 3.7: zero-target validator rule — lands LAST [DONE]

Merged as standards PR 438 (squash aed54b5, 2026-08-19). Engine-only reachability rule with closure credit and the conditional local-lane-guards exemption (review hardened the seed to be conditional so a stale exemption reads as dead code); three fixture cases green; live manifest validates at 33 components. Phase 3 COMPLETE — deferred evidence items (post-merge zero-new-PRs sync runs; the dotfiles claude-permissions sync wave) were parked on the App-attestation outage (installation 14 vs manifest 11) and discharged when the org owner trimmed the installation (4R.1: attest run 32278759065 at 2026-08-19T16:56Z; the parked dotfiles claude-permissions sync PR materialized as dotfiles PR 530).

Branch `chore/sync-audit-phase3-zero-target-rule` off main, after 3.1 and 3.2 merge (manifest stable at 33 components).

1. **Engine rule** in `validate_manifest` after the target loop (:761-762): every component must be referenced by ≥1 target (`managed` or `locally-owned`, accumulating across the loop) OR sit in the dependency closure of a referenced component. Closure expansion written over `REQUIRES_BY_COMPONENT` (direct-deps-only today; `visit_component` :454-475 is cycle-detection only — extend or add a helper).
2. **Named temporary exemption** for `local-lane-guards` and its dependency closure, with a rationale comment citing the Phase 5 staged migration (decision 3-B); Phase 5 removes it.
3. **Fixtures**: engine-only `invalid_case` per the :374-382 precedent (a def with no target reference and no closure path dies with a named diagnostic); a valid case proving the exemption; a valid case proving closure counting (a component referenced only via `requires` of a targeted component passes).
4. **Schema/mjs lockstep** = documented non-expressibility: one line in the schema's description noting the reachability rule is engine-only; mjs untouched (fixture-agreement cases for this rule run engine-only, per existing precedent).

**Sanity Check:** full `sync-manifest.test.sh` green incl. the three new cases; `distribution/sync-manifest.sh validate` green on the real manifest (exemption honored); a scratch manifest with an unreferenced component fails with the new diagnostic; grep confirms the exemption names exactly `local-lane-guards` + its closure and the rationale comment cites Phase 5.

### Phase 4R — fleet-expansion reconciliation (operator-executed Phase 4 vs the Brief)

Planned 2026-08-19. Phase 4 was executed out-of-band by the operator: standards PR 428 (three targets: claude-code-proxy, codex-plugins, cursor-plugins) and PR 440 (a fourth, agent-plugins, postdating the audit roster), plus github-iac PR 337 (roster mirror at 11). A fresh-context reconciliation audit verified every Brief item DONE except the follow-ups below. The manifest stands at 33 components, 12 targets.

### Phase 4R.1: operator — trim the App installation to the 12 targets [DONE]

Executed by the operator before this plan's approval round: sync run 32278759065 (2026-08-19T16:56Z) shows `sync / attest` SUCCESS with all 12 target jobs green — the installation's selected set equals the manifest roster. The attest outage is OVER: the deferred sync-run evidence from Phases 3.1-3.4 is discharged (the parked dotfiles claude-permissions sync PR materialized as dotfiles PR 530), and the Phase 1.4/1.5 canary observation path is unblocked (`.github` rides the matrix with automerge true).

### Phase 4R.2: github-iac PR — roster mirror 11 → 12 [DONE]

Executed by the operator as github-iac PR 341 (merged): README roster lists exactly the 12 manifest targets including agent-plugins.

### Phase 4R.3: standards PR — reconcile stale manifest comment prose [DONE]

Executed 2026-08-19: PR 446 merged (manifest comment re-cut; sanity grep empty on main; validator green at 33 components, 12 targets). PR 422's body gained the missing Fix and Verification sections (Test plan folded into Verification) and its linkage check re-ran green on the edited event.

The claude-review-caller comment block (:70-90) still claims cursor-plugins "is not a target at all … needs the App grant below, plus its own TARGET_VISIBILITY entry — exactly like claude-code-proxy on both counts" and claude-code-proxy is "BLOCKED on the org owner extending the sync App's selected access … Add it only with that grant recorded" — all false since PR 428 (targets exist, grant landed, TARGET_VISIBILITY entries shipped). Re-cut to present-tense truth, which requires SUPPLYING a new rationale for ccp-proxy/cursor-plugins' continued exclusion from the claude-review-caller component (verified honest answer: they are sync targets now but have not adopted the review lane — "not yet adopted", with the public-shape blocker still governing cursor-plugins). The ci-runner bullet remains accurate and survives. Keep both knowledge-corpus deferral rationales (lane adoption = prompt-injection surface at :83-90; sync-target roster = LFS blocker at :402-403) but make each name its own question so they read as complementary. New prose must avoid comment-hygiene trip shapes (`owner/repo#N`, `PR #N`, `issue N`, `GH-N` — bare "PR 428" is safe). Also fix standards PR 422's body (repin App PR: add the missing `## Fix` and `## Verification` sections — Summary and a content-bearing Related already exist; fold the legacy Test plan into Verification) so its next gate event passes under the v0.14.2 contract.

**Sanity Check:** `grep -n "not a target at all\|BLOCKED on the org owner\|needs the App grant\|alongside its .TARGET_VISIBILITY" distribution/sync-manifest.yml` → empty; comment-hygiene + validator green; PR 422's linkage check green on its next event.

### Phase 5 — local-lane-guards staged migration

Planned 2026-08-19 from a fresh-context guard-by-guard inventory (live origin/main fleet-wide). The audit's finding stands: ADR-0004 built the component, adoption never happened, and the drift it exists to prevent is live. But the inventory sharpened WHO diverged and HOW:

- **comment-hygiene policy library** — the real hazard. Medley's `tools/shared/comment-hygiene/comment-hygiene-patterns.sh` is a 212-line fork AT the canonical `comment-hygiene-tools` destination (canonical: 133). It adds 6 functions its lefthook hook, its scan-tree fork, AND its CI (which passes the fork as `patterns-file` to the ci-workflows action) all call — a managed sync would silently replace a tracked file and break every consumer (`preflight_destination` only protects UNTRACKED destinations). Asymmetry: the canonical driver runs fine against the fork; medley's consumers cannot run against canonical.
- **machine-specific-paths** — already at the target state in medley: ADR-0019's two-driver/one-SSOT pattern has the managed `path-detection-tools` body sourced by a medley-owned wrapper ("share bodies, NOT wrapping"). Nothing to migrate.
- **exec-bit** — three INDEPENDENT implementations, not forks: canonical 80L full-tree, medley 184L staged + 96L push-range, ccp 411L new-index-entry (a different rule for the commit skill). Legitimate diversity of scope.
- **heading-cites (reference-integrity)** — medley's 333L copy diverged ~106 lines at a NON-canonical path (`tools/markdown-coupling/`); ci-workflows' action copy is byte-identical to canonical. Working, diverged, unrecorded.
- **The dispatcher** (`run-local-lane-guards.sh`) and `coarse-prefilter.sh` — consumed by NOBODY: standards runs only the component's contract test in CI and gates itself via the ci-workflows actions; medley has its own lane wrappers; every other repo uses the CI actions with zero local lanes. ci-workflows' action copies of the patterns/exec-bit/heading-cites files are byte-identical (comment-hygiene-action is already a managed component there); its scan-tree.sh diverges ~20 lines (required PATTERNS_FILE, no default).

Approval-gate decisions (5-A/5-B/5-C below in User-approval gates).

### Phase 5.1: Guard A — medley comment-hygiene wrapper refactor [DONE]

Executed 2026-08-19, medley-first as specified. Medley PR 1868 merged: wrapper `comment-hygiene-local.sh` (all 7 medley functions + the `chp::scan_text` override), patterns file reduced to byte-canonical (git blob hash equals canonical `f0e37659`), every consumer re-pointed (lefthook hook, scan-tree, ci-status `patterns-file:`, scan-tree.test.sh fixture copy), positive AND negative fixtures green, medley ADR-0023 records the honesty caveat. Standards PR 448 merged: comment-hygiene-tools flipped to managed for medley with the comment re-cut. Final proof: post-merge sync run 32291418474 — attest plus all 12 target jobs green, NO medley PR opened (zero-delta apply). Follow-up filed in medley for the lowercase-XXX backport (a deliberate later policy change, kept out of the behavior-preserving refactor).

The one guard with a live break-hazard and a repo-local precedent to follow (ADR-0019: share bodies, not wrapping). Two-sided, medley-first:

CRITICAL respec from the stress-test: medley's fork is a POLICY REWRITE, not an additive extension. It carries 7 extra functions (`chp::should_skip_path`, `chp::is_scannable_extension`, `chp::scan_file`, plus 4 internal helpers `chp::_is_work_artifact_phase_token_line`, `chp::_is_internal_repo_issue_ref`, `chp::_match_warning_marker`, `chp::_emit_scan_matches`), it LACKS canonical's `chp::_record_violation`, and its `chp::scan_text` is a divergent rewrite: it permits external owner-slash-repo issue citations, phase-token grammar, and encapsulation-audit markers that canonical flags, and bans only medley-internal issue refs. Rebinding `scan_text` to canonical would red medley CI on currently-allowed tracked content (three named files carry external citations).

1. **Medley PR** — the wrapper (e.g. `tools/shared/comment-hygiene/comment-hygiene-local.sh`) carries ALL 7 medley functions AND explicitly overrides `chp::scan_text` with medley's policy after sourcing the canonical patterns file beside it; the patterns file reduces to canonical 133L bytes (sourced-but-shadowed — see decision 5-A's honesty note). ALL consumers re-point to the wrapper — `.lefthook/pre-commit/comment-hygiene-check.sh`, `tools/shared/comment-hygiene/scan-tree.sh`, `ci-status.yml` `patterns-file:` input (decided, not open: the ci-workflows action takes its scan entrypoint from `PATTERNS_FILE`, so it MUST point at the wrapper to keep medley policy), and `scan-tree.test.sh`'s fixture copy (it copies the patterns file — it must copy the wrapper too). `comment-hygiene-patterns.test.sh` re-targets the wrapper for medley functions and adds a canonical-parity assertion (`cmp`) on the base file. A short medley ADR (or ADR-0019 amendment) records the shape honestly: this contains the sync-clobber hazard (a managed overwrite of the base file breaks nothing) — it does NOT converge enforcement policy, which stays medley's own in the wrapper.
2. **Standards PR (after the medley PR merges and the destination is byte-canonical)** — flip `comment-hygiene-tools` from `locally-owned` to `managed` for medley; re-cut the :508-512 audit comment. Verified safe: the def has no `requires`, no test asserts the membership, and the sync reusable opens NO PR on a zero-delta apply (create-pull-request detects no diff).

**Sanity Check:** medley: `cmp tools/shared/comment-hygiene/comment-hygiene-patterns.sh <canonical>` → identical; `git grep -l "chp::scan_file\|chp::scan_text"` consumers resolve through the wrapper only; POSITIVE fixture (planted violation) fails both lanes; NEGATIVE fixture (an external owner-slash-repo citation line and a phase-token line, matching existing tracked content) passes both lanes post-refactor; medley CI comment-hygiene gate green on the unmodified tree. Standards: `yq` shows medley manages comment-hygiene-tools; the post-merge sync run opens NO medley PR.

### Phase 5.2: record dispositions — exec-bit, heading-cites, machine-paths [DONE]

Executed 2026-08-19 on PR 450: the three dispositions are recorded verbatim in ADR-0006 (the 5.3 ADR, per the stress-test re-homing). The manifest-side record landed as specified: the comment-hygiene-tools comment re-cut rode PR 448, and medley's remaining `locally-owned` audit comments were reviewed and remain present-tense accurate (still diverged, still locally owned) — no refresh needed.

No code migration; make the deliberate states legible where the audit found them unrecorded (the Phase 0 medley-counterpart pattern):

1. The dispositions live in the 5.3 ADR (stress-test finding: exec-bit and heading-cites have NO manifest entries — they are files inside the local-lane-guards def that 5.3 deletes, so manifest comments have no durable home and would collide with 5.3's zero-references sanity): machine-specific-paths = ADR-0019 wrapper state, migration complete by prior art; exec-bit = three independent scope-differentiated implementations (canonical full-tree, medley staged/push-range, ccp new-index-entry), deliberately not unified; heading-cites = medley's diverged copy at a non-canonical path, migration deferred with a named revisit trigger (the next behavioral change to the canonical checker).
2. The only manifest-side record: the re-cut `comment-hygiene-tools` comment from 5.1 and, where medley's `locally-owned` entries already carry audit comments, present-tense refreshes.

**Sanity Check:** the three dispositions appear verbatim in the 5.3 ADR; comment-hygiene gate green (no issue-ref shapes); validator green.

### Phase 5.3: component endgame — local-lane-guards def + exemption [DONE]

Executed 2026-08-19 on PR 450: def deleted (validator green at 32 components, rule unexempted), exemption block + conditional seed removed from the engine, exemption fixture case retired, ADR-0006 created (partial supersession + dispositions), ADR-0004 status line updated, and the retained component README + dispatcher header re-cut per the folded review finding (sanity grep on the README → 0).

After 5.1/5.2, the drivers (dispatcher, scan-comment-hygiene, coarse-prefilter, canonical exec-bit/heading-cites/machine-paths scripts) still have ZERO consumers of the materialized form — medley kept its own drivers by design and every other repo gates via the ci-workflows actions. Execute decision 5-B (default: retire), one standards PR:

1. Delete the `local-lane-guards` manifest def (:214-224).
2. Remove the reachability exemption block from `sync-manifest.sh` (visibly dead code by 3.7's conditional-seed design).
3. Retire the `valid_case 'zero-target exemption for local-lane-guards'` fixture case in `sync-manifest.test.sh` (it fails the moment the exemption goes — the planted fixture component becomes unreferenced); the unreferenced-component and closure fixtures survive untouched.
4. **ADR-0006** SUPERSEDES ADR-0004 (status-line edit on 0004 per the 0003→0005 precedent), scoped as a PARTIAL supersession: the drivers' distribution ends (adoption never happened; the enforcement surface consolidated in the ci-workflows actions and repo-local wrappers); `comment-hygiene-tools`/`path-detection-tools` distribution CONTINUES. The ADR carries the 5.2 dispositions.
5. Component DIRECTORY stays as producer-internal source + contract test, same treatment as the Phase 3.1 trio — with a same-PR re-cut of the retained files that still document the retired distribution path: `components/local-lane-guards/README.md` (drop the "distribution answer" framing and ADR-0004 pointer in favor of ADR-0006, delete the "Sync destinations" section naming `tools/shared/local-lane-guards/` and the manifest component/`requires` claims, reframe producer-internal) and the `run-local-lane-guards.sh` header comment (stop instructing consumers to invoke the distributed source; point at ADR-0006).

**Sanity Check:** `grep -c "local-lane-guards" distribution/sync-manifest.yml` → 0; the exemption block gone from `sync-manifest.sh` (grep → 0); validator green at 32 components with the rule unexempted; full test suite green with the retired fixture case removed; ADR-0004 status line reads superseded-by; `ls docs/adr/ | grep -c 0006` → 1; `grep -c "Sync destinations\|distribution answer" components/local-lane-guards/README.md` → 0.

### Phase 6 — engine Node port

Planned 2026-08-19 against origin/main @ `e6b9155`, grounded by a fresh-context exploration of the engine contract (all cites at that SHA). Executes ledger decision Q12 (Node port approved; yq-adapter-only alternative REJECTED — do not relitigate). The Brief's acceptance stands with one figure correction: the black-box contract suite is now 929 lines (the 921 figure predates the Phase 5.3 reachability edits).

**The contract being ported.** `distribution/sync-manifest.sh` (1151 lines) exposes six subcommands (`validate`, `matrix`, `plan`, `mappings`, `dest-paths`, `apply`) with a strict per-command flag-rejection matrix, byte-exact stdout shapes the suite asserts with `assert_eq` (single-line fixed-key-order matrix JSON; `synced <src> -> <dst> (<mode>)` apply lines; U+2192 mappings bullets; `LC_ALL=C`-sorted dest-paths), exit codes 0/1/2 (2 = no args; 0 + empty stdout = `dest-paths` unknown target — managed-files-guard depends on that no-op branch), stderr only via `error: %s`, and a hard spawn-batching contract (exactly one `git ls-files --stage -z` + one `git hash-object` per validate, proven by a counting git shim). The yq behaviors the port must reproduce with a real YAML AST: tag inspection (`!!str`/`!!int`/`!!map`/`!!seq`/`!!bool`/`!!merge`), duplicate-mapping-key rejection, merge-key rejection (never silent expansion), single-document assertion, control-char gating, and absent-key non-materialization. Collation is byte-order everywhere (port uses code-unit comparison, never `localeCompare`).

### Phase 6 decisions (approval gate — recommendations below)

- **6-A YAML dependency:** `yaml` (npm, Eemeli Aro), exact-pinned in `distribution/package.json`, WITH a dependency split: `yaml` is the only production dependency; `ajv` moves to `devDependencies` (it backs the authoring-only fixture-agreement validator) so production installs run `npm ci --omit=dev` and the production supply-chain delta is exactly one zero-transitive-dep package. Parser configuration is pinned, not defaulted (stress-test finding: the lib's defaults do NOT satisfy the contract): explicit YAML-1.2 core schema, merge OFF with an explicit check that maps BOTH a `!!merge`-tagged key and a literal `"<<"` string key to the contract's `merge keys are not supported` diagnostic, `uniqueKeys` errors re-mapped to the byte-exact `duplicate mapping key` diagnostic, and the control-char class pinned to POSIX `[[:cntrl:]]` = `[\x00-\x1F\x7F]` (never `\p{Cc}`, which also matches C1 and silently widens the contract). Alternatives: `js-yaml` (weaker tag/CST access for the merge-key and dup-key contracts), vendoring a parser (unreviewable), shelling to yq (the rejected adapter).
- **6-B entrypoint continuity:** `distribution/sync-manifest.sh` STAYS the stable CLI entrypoint and becomes a minimal exec wrapper (`exec node "$(dirname "$0")/sync-manifest.mjs" "$@"`) at cutover; the engine body lives in a new `distribution/sync-manifest.mjs`. Basis: every caller — standards ci.yml, the ci-workflows standards-sync + stuck-automerge reusables, managed-files-guard, check-plugin-baseline.sh, claude-lanes.test.sh, ESCAPE-HATCHES.md, README command blocks — invokes the `.sh` path; the wrapper keeps all invocation lines byte-stable and makes the cutover a single-file standards-side swap (revertable in one commit). Alternative (rename entry + sweep every caller across two repos) trades a permanent one-line indirection for a much wider, riskier cutover diff.
- **6-C cutover strategy:** staged dual-gate. 6.1 lands the Node engine BESIDE the untouched Bash engine with the suite parameterized to run against both in standards CI AND pre-provisions every standards-CI surface that executes the engine (stress-test finding: the actionlint job runs `claude-lanes.test.sh`, which invokes the engine, and has neither setup-node nor `npm ci --prefix distribution` — provisioned in 6.1 where it is inert under Bash, so the 6.4 cutover PR really is one file); 6.2's threat-model re-run gates production; 6.3 preps the ci-workflows reusables (engine-agnostic Node setup); 6.4 swaps the `.sh` body to the wrapper (the actual cutover) and retires the Bash body after a green organic sync run. Big-bang rejected: the sync reusable is SHA-pinned from standards `sync.yml`, so production stays on Bash until the standards-side swap — every step independently revertable.
- **6-D no-Node control disposition (Brief acceptance item):** the control (`sync-manifest.test.sh` yq-only runtime block: single-file engine copy + exit-99 `node` shim + "never invokes the Node shim" assert) is RETIRED at 6.4 and REPLACED by its inversion: an exit-99 `yq` shim proving the production Node path never invokes yq, plus a scratch-copy runtime proof re-shaped for the Node engine (copy `sync-manifest.sh` + `sync-manifest.mjs` + `node_modules` into the scratch runtime dir). During the 6.1-6.3 window the control's gate is CONTENT-BASED, not path-based (stress-test finding: a path-keyed gate still runs the control against the post-cutover wrapper and reds the cutover PR), and it detects the LEGACY BASH ENGINE POSITIVELY, not by wrapper-absence (review finding: a not-wrapper test would also run the control against the direct `.mjs` engine in the dual-gate run and fail it): the block runs only when the engine file is the real Bash engine — e.g. `grep -q 'require_command yq' "$engine"` — and otherwise `skip_case`s with the disposition comment, which covers the `.mjs` dual-gate run now and the wrapper after cutover. The sibling `control-char-equivalence.sh` proof (grep-vs-Bash-glob agreement) gets its own 6.4 disposition: retired with the Bash engine, replaced by a JS-side equivalence fixture asserting the port's `[\x00-\x1F\x7F]` class against the same TSV fixture. THREAT-MODEL row 9 (tool substitution) is rewritten in 6.2: Node (pinned by `.node-version` 24.19.0, installed via SHA-pinned setup-node) + git enter the production trust set; yq LEAVES it and remains authoring-CI tooling only (suite fixture conversion, pin-comment-convention, actionlint).

### Phase 6.1: port + dual-gate suite (standards PR) [DONE]

Executed 2026-08-20 as PR 454 (merged; 45/45 checks): `sync-manifest.mjs` landed beside the Bash engine, suite parameterized with the positively-gated yq-only control, full-output byte assertions and the automerge literal rule in both engines, ci.yml dual suite runs + cross-engine parity step green on Linux, actionlint job provisioned, deps split (`yaml` production / `ajv` dev). Review findings folded: explicit core YAML tags now win over value-shape classification (with an engine-only `!!float 2` fixture), and the CLI switches became if/else chains (the CI-pinned biome 2.5.1 misinfers argv-string switch cases as unreachable).

1. Add `yaml` (exact pin, latest stable) to `distribution/package.json` + lockfile (SRI, lockfile v3) with the 6-A dependency split (`ajv` → `devDependencies`). The distribution CI job already runs `npm ci --prefix distribution` (dev install — the suite's fixture-agreement half needs ajv).
2. Write `distribution/sync-manifest.mjs` (`#!/usr/bin/env node`, mode 100755, ESM, imports: `node:` builtins + `yaml` + nothing else): a behavior-complete port of the contract above — CLI matrix incl. `-h`/`--help` both positions and the git-toplevel-of-script-location default source root; `is_safe_repo_path` semantics; tracked-file shape + index-mode contract via the same batched `git ls-files --stage -z` / `git hash-object --no-filters` invocations; identity verification (three accepted GitHub origin forms, case-insensitive); full-collect-then-preflight apply atomicity; destination symlink/FIFO/shape rejection via `lstat`; dependency-cycle and reachability validation; byte-exact output emitters. The stderr DIAGNOSTIC TEXT and check PRECEDENCE are contract surface too (stress-test finding: ~60 suite needles assert exact `error:` substrings and report-ordering, e.g. non-string key before control-char) — port diagnostics verbatim and preserve validation order.
3. Parameterize the suite's engine path (`engine="${SYNC_ENGINE_PATH:-$root/distribution/sync-manifest.sh}"`, with a relative `SYNC_ENGINE_PATH` resolved against `$root` — the direct `"$engine"` call sites are cwd-sensitive); gate the yq-only runtime block per 6-D (content-based). Add full-output `assert_eq` fixtures for `mappings`, `plan`, and `apply` (today only matrix and dest-paths are byte-asserted; an `->`-for-`→` regression would stay green and churn every sync-PR body).
4. Harden the dual-gate against window drift (stress-test finding, empirically confirmed on the pinned versions: `automerge: False` is `!!bool` under both parsers yet yq's `@tsv` emits `False` verbatim — invalid matrix JSON — while the `yaml` lib normalizes to `false`): add a validation rule to BOTH engines restricting the automerge scalar to literal `true`/`false`, with a `False` rejection fixture; add a cross-engine byte-diff step to the ci.yml distribution job (`matrix`/`plan`/`mappings`/`dest-paths` output of both engines on the real manifest must be byte-identical).
5. Extend the standards ci.yml `distribution` job to run the suite twice (default Bash run, then the Node-engine run). Node setup + npm cache already present in that job. Same PR: provision the actionlint job (setup-node via `.node-version` + `npm ci --prefix distribution` before `claude-lanes.test.sh`) — inert under the Bash engine, load-bearing at cutover.

**Sanity Check:** both suite runs green in the ci.yml distribution job (job log shows two suite invocations) plus the cross-engine byte-diff step green — Linux CI is the authoritative gate; the local Windows Node-engine run is expected to fail the PATH-shim-based cases too (mock-git index failure, both spawn-count asserts, the node shim) in addition to the two known symlink cases — Node's win32 spawn bypasses extensionless shims; the spawn-count contract (1× ls-files, 1× hash-object) passes against the Node engine in CI; the `sync-manifest.sh` diff is limited to the item-4 automerge literal rule (corrected at implementation: the original "Bash engine untouched" clause contradicted item 4's both-engines rule); `grep -c '"ajv"' distribution/package.json` under `devDependencies` → 1; the actionlint job green with the new prep steps; production sync unaffected (reusable pinned at the pre-port SHA).

### Phase 6.2: threat-model re-run + npm supply-chain assessment (standards PR, gates cutover) [DONE]

Executed 2026-08-20 as PR 456 (merged): trust-set rewrite, tool-substitution row re-cut, guard interim gap recorded, npm supply-chain standing controls added, trigger discharged with the re-run date. One review follow-up rides the 6.4 retirement sweep: narrow the data-flow parity sentence to the four read-only emitters the CI step actually byte-compares.

1. Re-run `distribution/THREAT-MODEL.md` per its own review triggers (parser + yq rows fire): rewrite row 9's Control/Evidence (Node runtime pinned via `.node-version`, SHA-pinned setup-node, exact-locked production deps, `--ignore-scripts` on every production install, the inverted no-yq control as the new evidence), the trusted-tooling statements, and the authoring-vs-production boundary prose ("no Node dependency" leaves; the independent-second-validator framing is re-cut honestly — and post-port the fixture-agreement contract actually GAINS parse independence: yq/Go parses the schema-path input while the `yaml` lib parses the engine-path input). Cover the managed-files-guard path explicitly, including its interim reliance on the runner image's unpinned yq at the frozen standards-ref (a pre-existing gap row 9 currently overstates).
2. Add the npm supply-chain assessment to THREAT-MODEL (new subsection): production dep tree after the 6-A split (`yaml` alone, zero transitive deps; the ajv tree is authoring-only via `devDependencies` + `--omit=dev`), SRI integrity in the committed lockfile, `npm ci` provenance (lockfile ships in the reviewed standards checkout the reusable clones), `--ignore-scripts` as a STANDING control (never derived from the current tree's emptiness — a future dependency's postinstall would otherwise execute inside the job holding the App token), registry-substitution risk, engines gate `>=24`, and the update policy: the existing nested Dependabot root covers `distribution/`, but `yaml` bumps are a production-parser change requiring human review — excluded from any future automerge policy.
3. Discharge the review-trigger row with the re-run date.

**Sanity Check:** `grep -c "no Node" distribution/THREAT-MODEL.md` → 0 (wrap-safe needle); a dated re-run line exists (grep for `2026-` in the review-trigger section); the supply-chain subsection names the production package and the standing controls (`grep -c "ignore-scripts" distribution/THREAT-MODEL.md` ≥ 1); comment-hygiene + lychee green.

### Phase 6.3: reusable prep (ci-workflows PR + release) [DONE]

Executed 2026-08-20: ci-workflows PRs 500 (per-job prep) and 502 (engine-flavor gating, folding the four review findings) merged; release v0.16.0 cut at `a7742cb3`; standards re-pin PR 458 merged with the two policy.json entries in lockstep, plus PR 460 recording the runner-policy README review note the lockstep procedure requires. Inertness proven: sync run 32344517872 at the new pin green with the Bash engine live — Detect-the-engine-flavor, Set up Node, and Install engine dependencies all succeeded in the plan and sync jobs.

1. ci-workflows `standards-sync.yml`: add SHA-pinned setup-node + npm install prep before the engine steps, with PER-JOB paths (stress-test finding — the checkout layouts differ): the **plan** job and the alert reusable check standards out at the workspace ROOT (`node-version-file: .node-version`, `npm ci --prefix distribution`); only the **sync** job uses `.standards-src` (`node-version-file: .standards-src/.node-version`, `npm ci --prefix .standards-src/distribution`); the guard action resolves against `$STANDARDS_ROOT`. Every production install runs `npm ci --omit=dev --ignore-scripts --no-audit --no-fund` with npm fetch-retry configuration mirroring the yq step's outage-hardening rationale (the registry becomes a new external dependency of every sync run — behavior-inert under Bash, availability-NON-inert; partial-fleet recovery is the existing per-leg `fail-fast: false` bound plus the next cron tick reconciling). Keep the yq install (Bash engine still runs until 6.4; yq drops in the 6.4 follow-up). The guard's prep is engine-flavor-gated mechanically: run npm ci iff `sync-manifest.mjs` exists in the pinned checkout.
2. Release tag; standards `sync.yml` + alert-caller re-pin PR with the matching `path@SHA` policy.json append (same-PR lockstep per the standing constraint).

**Sanity Check:** next organic sync run green at the new pin with the Bash engine still active (prep behavior-inert); policy.json carries the new SHA entries (grep); managed-files-guard consumer job green in ci-workflows CI; the alert reusable's hourly cron green at the new pin.

### Phase 6.4: cutover + Bash retirement + control inversion (standards PR series) [DONE]

Executed 2026-08-20. Cutover PR 462 (one-file wrapper swap) merged; its organic sync run 32345715813 ran the full cascade — plan, attest, all 12 targets — green on the Node engine. Retirement PR 464 merged: single suite run, node-only control (6-D inversion) green, hard-fail node_modules gate, Node control-char equivalence proof over the 256-byte fixture, docs sweep. ci-workflows PR 504 + release v0.17.0 dropped the reusables' yq installs and advanced the managed-files-guard ref onto the Node engine; standards re-pin PR 466 (policy entries + README review note in lockstep) merged, and its organic sync run 32349013117 came back 14/14 green with ZERO yq steps anywhere on the production path.

1. Cutover PR: `sync-manifest.sh` body → exec wrapper (per 6-B). One file, one commit, instantly revertable — genuinely, because 6.1 already provisioned the actionlint job and made the yq-only control's gate content-based (the two surfaces that would otherwise red this PR's own CI). Watch the next organic sync run end-to-end (matrix byte-shape, attest, per-target apply, mappings in PR bodies).
2. Retirement PR (after that green run): suite drops the dual-run + `SYNC_ENGINE_PATH` default flips inert (wrapper IS the engine path now); no-Node control replaced by the 6-D inversion (no-yq shim + reshaped scratch-copy runtime proof incl. `node_modules`); `control-char-equivalence.sh` retired per 6-D with the JS-side equivalence fixture over the same TSV; the suite's absent-`node_modules` skip-gate flips to a HARD FAILURE (stress-test finding: `skip_suite` exits 0, so a forgotten install would turn the 929-line production gate into a false green — post-port the deps are the engine's own runtime, not an environment nicety); docs sweep — `distribution/README.md` engine-language claims, `sync-manifest.schema.json` description's "Bash engine" sentence, `components/pin-comment-convention/README.md` + `pin-comment-patterns.sh` yq-precedent anchor re-cut (yq stays that component's tool on its own merits), `claude-lanes.test.sh` comment, ESCAPE-HATCHES flag doc verified unchanged (CLI surface identical).
3. Post-cutover follow-up PR in ci-workflows: drop the yq install from the sync + alert reusables (yq no longer on the production path); bump the managed-files-guard caller's `standards-ref` pin to a post-cutover standards SHA (stress-test finding: nothing else ever advances it — the guard would otherwise run the retired Bash engine against a frozen manifest forever, and 6.3's guard prep would stay permanently inert); release + re-pin + policy.json lockstep.

**Sanity Check:** organic sync run green with the wrapper live BEFORE the retirement PR merges; `grep -c "no Node" distribution/README.md` → 0 (wrap-safe — the current phrase line-wraps and a naive needle passes vacuously); suite green with the inverted control (job log shows the yq-shim case passing); `grep -c "SYNC_ENGINE_PATH" .github/workflows/ci.yml` → 0 after retirement; guard consumer job green at the bumped standards-ref; one full sync cron tick green after the ci-workflows yq-drop re-pin.

### Phase 6.5: close-out [DONE]

Executed 2026-08-20 (this PR carries the tags and the threat-model tense sweep from the retirement PR's review thread). Brief acceptance, item by item:

1. **Black-box contract suite green against the Node engine** — PR 454's dual-gate `distribution` job (both suite runs + cross-engine parity) and every post-cutover CI run of the single-invocation suite; the two post-cutover organic sync runs (32345715813 at cutover, 32349013117 at v0.17.0, 14/14 jobs each) are the production proof.
2. **Threat-model re-run** — the dated 2026-08-20 discharge line in `distribution/THREAT-MODEL.md` (PR 456; tense sweep here).
3. **Explicit disposition of the no-Node control + its test** — decision 6-D executed: content-gated skip through the window (PR 454), inverted at retirement into the node-only yq-shim control plus the Node control-char equivalence proof (PR 464).
4. **npm supply-chain assessment** — the "npm supply chain (production engine)" standing-controls section in THREAT-MODEL (PR 456), enforced in the reusables by `--omit=dev --ignore-scripts` plus retry hardening (ci-workflows PRs 500/502/504) and the policy test's npm retry-budget contract.

**Sanity Check:** all four Brief acceptance items cite merged evidence in this file; no [PENDING] or [DOING] tags remain under Phase 6.

## Blast radius

**Phase 6: HIGH.** A full rewrite of the security engine on the fleet-wide apply path, plus a production trust-set change (Node + one npm package enter; yq leaves) and a cross-repo cutover through the SHA-pinned reusable. Mitigations: the 929-line black-box suite runs against BOTH engines through the whole window plus a real-manifest cross-engine byte-diff; the threat-model re-run gates cutover; the cutover itself is a one-file standards-side swap (revertable in one commit) with the reusable prep landed earlier and proven behavior-inert; `--omit=dev --ignore-scripts` fences the new npm surface; every stage independently revertable; per-target apply atomicity bounds a mid-fleet red to stale-but-consistent targets. Not CRITICAL: no schema change, no automerge change, no App-grant/roster change, and the Bash engine remains one revert away until the retirement PR.

**Phases 4R + 5: MEDIUM.** 4R is docs/comments plus one operator action, but that action (the installation trim) is the single switch un-redding every sync run — getting the removal list wrong extends the outage. 5.1 refactors a live medley pre-commit hook and CI gate input (mitigations: ADR-0019 precedent is the exact shape; the asymmetry means each intermediate state keeps the canonical driver runnable; planted-violation fixture proof before merge; medley-first ordering so the manifest flip only lands against a byte-canonical destination). 5.3 removes a validator exemption and a component def (mitigation: 3.7's conditional seed makes the leftover exemption visibly dead; the deletion follows the proven 3.1 treatment). Not LOW: a botched 5.1 breaks medley commits repo-wide until reverted.

**Phase 3: MEDIUM.** Thirteen-ish PRs across seven repos, a validator behavior change, and a fleet-wide gate strictness increase (v0.10.2 → v0.14.2 linkage in 6 repos — every future PR in those repos meets the four-section contract). Mitigations: the re-pin targets a SHA two repos already run in production with the policy entry pre-existing (zero sync waves); the org template lands BEFORE the stricter gate; upstream-before-downstream ordering per the Retire lifecycle row; the validator rule lands last against a stable manifest with fixture coverage; every PR independently revertable; no engine apply-path changes, no automerge changes, no App-grant/roster changes. Not LOW: the gate tightening changes day-to-day contributor experience fleet-wide and the validator rule can brick manifest CI if the exemption closure is wrong.

**Phase 2: MEDIUM.** Six PRs across five repos; permanently removes a sync surface (the intended outcome) and blanks four downstream files. Mitigations: flip-first ordering closes the overwrite window; blank-not-delete is reversible (git history holds every copy; re-adding the component is a manifest PR); no engine/schema/automerge changes; no canonical content change touches the `.github` canary's components; each PR independently revertable; guidance content verified re-homed (cloud-bootstrap README; escape-hatch skeleton) before the source dies. Not LOW: cross-repo coordination with ordering constraints and a live canary watch running concurrently.

**Phase 1: MEDIUM-HIGH.** Re-arms fleet automerge (the audit's biggest live behavior change) and modifies the watchdog that guards it. Mitigations: proof-gated sequencing (test mode proves create/update/close/fail before any re-arm), canary-first, marker/title isolation for test issues, frozen job/step names (classifier string coupling), policy.json same-PR lockstep, per-target opt-out retained. Verified safe-canary evidence recorded in 1.4.

**Phase 0: MEDIUM** (complete). Behavior-changing surfaces: fleet node pin bump (5 targets + ci-workflows), two CI workflow caller re-pins (sync + watchdog — the sync cascade itself), actionlint managed flip (prose-only overwrite, verified), repin-automation code change. Mitigations: pre-flight contract diffs before re-pins; policy.json same-PR constraint honored; sync-wave PRs all human-merged (fleet disarmed); S1 is pure comments/docs; every phase independently revertable. Not HIGH: no schema changes, no engine changes, no App grant, no automerge arming (that is Phase 1).

## Stress-test summary

**Phase 6 stress-test (2026-08-19, two independent fresh-context reviews — a plan reviewer and an adversarial devils-advocate, execution-scoped with Q12 fenced):** combined 2 CRITICAL, 8 IMPORTANT (deduplicated), all verified against the live repos and folded in. Headlines: (1) CRITICAL — the "one file, one commit" cutover PR would have redded its own CI two ways: the yq-only control copies the `.sh` alone into a scratch dir and a path-keyed gate still runs it against the wrapper, and the actionlint job executes the engine via `claude-lanes.test.sh` with no node/npm provisioning — both remediated in 6.1 (content-based gate; actionlint prep, inert under Bash). (2) CRITICAL — the reusable's plan job and the alert reusable check standards out at the workspace ROOT, not `.standards-src`; literal paths would have shipped a broken release redding the weekly sync and the hourly watchdog — 6.3 now specifies per-job paths. (3) Empirically confirmed dual-engine drift hazard: `automerge: False` validates under both parsers but yq's `@tsv` emits invalid matrix JSON while the `yaml` lib normalizes it — both engines gain a literal-`true`/`false` rule plus a cross-engine byte-diff step. (4) The `yaml` lib's DEFAULTS violate the contract (merge keys parse as a literal `"<<"` key; dup-keys are parse errors, not diagnostics) — 6-A now pins parser configuration and diagnostic re-mapping. (5) npm enters the production path: `--omit=dev` (ajv split to devDependencies), `--ignore-scripts` as a standing threat-model control (postinstall would run inside the App-token job), retry hardening mirroring the yq outage precedent, and human-review policy on `yaml` bumps. (6) The guard's `standards-ref` pin needed a scheduled post-cutover bump; `skip_suite`'s exit-0 needed a hard-fail flip; the local-Windows sanity line was over-promised (Node's win32 spawn bypasses the PATH shims); one grep needle was vacuously green (line-wrapped README phrase); stderr diagnostics + check precedence named as contract surface; mappings/plan/apply gain full-output byte asserts. This review pair doubles as the Step-4 formal stress-test for the HIGH blast radius.

Fresh-context adversarial review (2026-08-16, execution-scoped — the 16 locked decisions were fenced off, already 3×-validated): 2 CRITICAL, 9 IMPORTANT, 4 SUGGESTION findings; all 15 verified against the repos and folded into the plan above. Headlines: (1) `.node-version` bump would have broken standards CI — `components/cloud-environment/setup.sh` carries 4 coupled literals hard-asserted by `setup.test.sh` (now in 0.2); (2) the briefed `LANE_PATHS` append is itself the breaking change — the lockstep script assumes one shared pin across all paths (0.4 rewritten to per-path refactor-or-defer, no partial edit); (3) two cross-repo ADR-0003 refs in ci-workflows the sweep would have missed (now in 0.7); (4) pr-issue-linkage is a REQUIRED check on standards + ci-workflows PRs — every PR needs a closing keyword + `## Related` body (now in Mechanical work). This review doubles as the Step-4 formal stress-test for the MEDIUM blast radius: it ran fresh-context with an adversarial failure-scenario brief; re-running `/planning:devils-advocate` on the same execution surface would relitigate the fenced decisions.

**Phase 4R + 5 stress-test (2026-08-19, fresh-context, execution-scoped — Q3's locked mechanism fenced off):** 1 CRITICAL, 4 IMPORTANT, 4 SUGGESTION; all verified live and folded in. Headlines: (1) CRITICAL — the medley patterns fork is a POLICY REWRITE (divergent `chp::scan_text`, 7 extras, missing `_record_violation`), so the wrapper must override `scan_text` and every consumer must point at the wrapper — the original spec would have redded medley CI on currently-allowed external citations while all planned sanity checks stayed green; a negative fixture check was added. (2) The post-flip canonical file is sourced-but-shadowed — 5-A now states honestly that 5.1 buys clobber containment, not policy convergence. (3) 4R.1/4R.2 turned out ALREADY DONE on live state (operator trimmed the installation — attest green run 32278759065 — and merged the github-iac roster bump PR 341); tags corrected before execution, deferred Phase 3 evidence discharged. (4) The 5.2 dispositions re-homed into the 5.3 ADR (two guards have no manifest entries, and the comments would break 5.3's zero-references sanity). Also pinned: ADR-0006 partial supersession of 0004; the exemption fixture case retires explicitly; PR 422 needs exactly Fix + Verification; the 5.1 sync-wave proof sharpened to "opens NO PR" (create-pull-request skips zero-delta); scan-tree.test.sh's fixture copy joins the 5.1 edit list. This review doubles as the Step-4 formal stress-test for the MEDIUM blast radius, same pattern as Phases 0-3.

**Phase 3 stress-test (2026-08-19, fresh-context, execution-scoped — the locked decisions fenced off):** 1 CRITICAL, 3 IMPORTANT, 3 SUGGESTION; all verified against live origin/main fleet-wide and folded in. Headlines: (1) CRITICAL — the planned "PowerShell LEFTHOOK deny twins" could never match (the Bash rules anchor on an inline-env spelling PowerShell lacks; deny globs are whole-string with `*` only) while every planned sanity check stayed green — respecified as an env-var-reference-anchored `PowerShell(*env:LEFTHOOK*)` deny with shape-aware tests; (2) `--targets` is matrix/plan-only — `validate` hard-rejects all filter flags (doc claim corrected before authoring); (3) 3.6's "self-demonstrating" gate proof was impossible under `pull_request_target` (base-branch pin gates the PR) — replaced with post-merge proof + an open-PR sweep, since merged re-pins re-gate every open PR on its next event; (4) the permissions edit is replace-`{}`-not-insert in five callers, pin-only in ci-workflows. Reviewer also confirmed decision 3-A end-to-end (byte-identical reusable both hops; policy entry with minimumCallerPermissions present in all four checked fleet policy copies — zero sync wave), that local-lane-guards is the ONLY post-deletion zero-target component (its two requires are independently targeted via medley — the closure clause of the exemption is redundant-but-harmless), that no test/schema/mjs hardcodes component names or counts, and that the org-template rewrite is regression-free for the v0.10.2 window. This review doubles as the Step-4 formal stress-test for the MEDIUM blast radius, same pattern as Phases 0-2.

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

Phase 4R + 5 shape: 4R.1 (operator) is the global unblocker and runs first/anytime; 4R.2 and 4R.3 are independent small PRs (parallel-safe, different repos). 5.1's two PRs are strictly medley-then-standards; 5.2 follows 5.1's manifest edit (same file); 5.3 last (after both, removing the exemption against the final state).

| Phase | Surface | Basis |
|---|---|---|
| 4R.1 | operator | App-installation management is org-owner-only |
| 4R.2, 4R.3 | main session | small judgment edits (roster list; comment prose re-cut) |
| 5.1 medley PR | main session | live-hook refactor with parity proof — judgment-heavy |
| 5.1 standards PR, 5.2, 5.3 | main session | manifest/comment/ADR edits + validator/exemption removal |

No worker fan-out this phase — every step is either sequential-gated or judgment-heavy; the standards clone's checkout belongs to the user, so all standards work rides worktrees.

Phase 6 shape: strictly sequential — 6.1 gates 6.2 (threat model re-runs against the landed port), 6.2 gates 6.3 (cutover prep only after the security re-run), 6.3 gates 6.4 (cutover needs the prepped reusable pin live), 6.4's green organic run gates its own retirement PR and the ci-workflows follow-up, then 6.5. No parallelism opportunity: 6.1/6.2/6.4 edit overlapping distribution/ files and each later stage's Sanity Check consumes the prior stage's merged state.

| Phase | Surface | Basis |
|---|---|---|
| 6.1 port | main session (worktree) | security-engine rewrite — maximum-judgment work; the 929-line suite is the harness, not a worker task |
| 6.2 threat-model + supply-chain | main session | security judgment against the landed port |
| 6.3 reusable prep + re-pin | main session | cross-repo workflow edits with per-job path nuance + policy.json lockstep |
| 6.4 cutover + retirement | main session | one-file swap + gated retirement, each watched against a live sync run |
| 6.5 close-out | main session | tag advance + evidence citations |

Phase 3 shape: Wave A (parallel-safe, zero file overlap): 3.1→3.2 chain, 3.4, 3.5 — three independent standards/.github tracks. Wave B: 3.3 (×5 workers) after 3.2; 3.6 (×6 workers) after 3.5; 3.7 after 3.1+3.2, deliberately last.

| Phase | Surface | Basis |
|---|---|---|
| 3.1, 3.2 | main session | manifest + ADR judgment |
| 3.3 | sub-agent workers (up to 5) | mechanical deletions, pre-resolved dependabot.yml edits, disjoint repos |
| 3.4 | main session | doc authoring + deny-rule shape judgment |
| 3.5 | main session | two small template PRs |
| 3.6 | sub-agent workers (up to 6) or sequential main | mechanical pin+permissions edits, pre-resolved per repo; each PR body must self-satisfy the new gate |
| 3.7 | main session | validator logic + closure algorithm |

Phase 3 scope fence per 3.3 worker: one repo — `.github/standards/pr-convention-policy/` (delete) + `.github/dependabot.yml` (listed lines); FORBIDDEN: PLAN.md, any workflow file, any other repo. Per 3.6 worker: one repo — the linkage caller workflow file only. Sequential fallback both waves: main session, one repo at a time.

## Open questions

- 0.4 pin form: newest ci-workflows release tag containing C1 + retry hardening, vs HEAD-SHA fallback — resolved at implementation time by tag availability (decision rule in 0.4 item 2).
- 0.4 repin-automation refactor size: per-path pin resolution deliverable in one focused commit, or deferred to a tracker item (decision rule + fallback in 0.4 item 4 — no partial edit either way).

## Handoff to implementation

### User-approval gates

- Phase 6 decisions 6-A (yaml dependency + split + pinned parser config), 6-B (exec-wrapper entrypoint continuity), 6-C (staged dual-gate cutover), 6-D (no-Node control inversion + control-char-equivalence disposition): APPROVED 2026-08-20 as recommended (plan PR 452 merged on explicit user approval; all four executed through 6.1-6.5).
- Phase 6 sub-topic promotion considered and declined: the phase exceeds the promotion thresholds, but the audit's one-file phase contract (Phases 0-5 precedent) wins for continuity [EXEC-SHAPE — carried through unchallenged at approval].
- Phase 5 decision 5-A: APPROVED 2026-08-19 as recommended — shadow-wholesale wrapper, honestly documented (all 7 medley functions + a `chp::scan_text` override in a medley-owned wrapper sourcing the canonical file; every consumer re-points to the wrapper; the outcome is clobber containment, not policy convergence, and the medley ADR note says so).
- Phase 5 decision 5-B: APPROVED 2026-08-19 as recommended — retire the local-lane-guards def + the reachability exemption in 5.3; ADR-0006 partially supersedes ADR-0004; directory stays producer-internal.
- Phase 5 decision 5-C: APPROVED 2026-08-19 as recommended — exec-bit and heading-cites record-not-migrate, dispositions carried in ADR-0006.
- Phase 4R.1/4R.2 were executed by the operator before this approval round (attest green; roster at 12) — recorded DONE, nothing to approve there.
- Phase 3 decision 3-A: APPROVED 2026-08-19 as recommended — linkage re-pin to v0.14.2 (byte-identical reusable; policy.json entry pre-exists; zero sync waves; fleet SHA convergence).
- Phase 3 decision 3-B: APPROVED 2026-08-19 as recommended — zero-target rule ships with a named temporary exemption for local-lane-guards, removed in Phase 5.
- Phase 3 gate-tightening: APPROVED 2026-08-19 — after 3.6, six more repos enforce Summary/Fix/Verification/Related on every PR body.
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
- Phase 3 PR series 3.1→3.2 / 3.4 / 3.5 parallel tracks, then 3.3 ×5, 3.6 ×6, 3.7 last, with the scope fences above [EXEC-SHAPE].
- 3.1 and 3.2 split into two PRs (zero-effect trio vs downstream-implicating retirement + ADR) [EXEC-SHAPE].
- 3.5 rider: provisioning local-template stray-dash fix as its own one-line PR (decision 3-C) [EXEC-SHAPE].
- 3.6 workers' edit lists (pin line + permissions block per repo) pre-resolved main-session [EXEC-SHAPE].
- Medley select-runner v0.8.0 pin drift filed as a tracker item, not fixed in Phase 3 [EXEC-SHAPE].

### Mechanical work

- **PR-body gate (required check, easy to forget):** `pr-issue-linkage` runs as a REQUIRED check in standards and ci-workflows, and since Phase 3.6 the v0.14.2 four-section contract is enforced across the fleet (standards, ci-workflows, ccp, dotfiles, github-iac, medley, ci-runner, provisioning): every PR body needs non-empty `## Summary`, `## Fix`, `## Verification`, and `## Related` sections plus a native closing keyword (or "No linked issue"); only `dependabot[bot]` exempt. BEFORE opening each PR, file (or reuse) a tracking issue in that repo and write the body to that contract — the older v0.10.2 keyword+Related shape no longer passes. Applies to every PR in the remaining series (1.5, and the Phase 6 series: 6.1, 6.2, the 6.3 ci-workflows PR + standards re-pin, the 6.4 cutover + retirement PRs and ci-workflows follow-up + re-pin).
- Commit per logical item within each PR; conventional-commit subjects; Co-authored-by trailer per repo convention.
- Verification checkpoint per phase = its Sanity Check block; standards CI + runner-policy lane are the hard gates for S1-S3.
- Sequential fallback for worker fan-out documented under Execution shape.
- PLAN.md status tags advance main-session only; workers report back.
