# Native-reference review credential

Classification for the read-only credential a private calling repo's CI job
uses to mount this repo's `conventions/review` tree by native reference — the
depth tier described in [`conventions/README.md`](../conventions/README.md)
and cited from the synced `REVIEW.md`. Scope is exactly this credential's
authentication and republication boundary. It is adjacent to, but distinct
from, the sync-manifest push credential covered by
[`THREAT-MODEL.md`](THREAT-MODEL.md), and external to the reconciliation
engine: it authenticates a *review* job's checkout, never a materialization
apply.

**Status: classified, not provisioned — re-derived 2026-07-26 as not
currently needed (see "Re-derivation" below).** Nothing below has been
created. Provisioning is `github-iac` governance work and stays deferred
behind it; under the current visibility state there is nothing to provision.

## Why a dedicated credential

> [!CAUTION]
> **This section's premise no longer holds. Do not provision from it.**
>
> It was written against a repository classification that has since changed.
> Re-verified 2026-07-26 by observing the fact through three authorization
> planes:
>
> 1. the authenticated REST API (`gh api repos/melodic-software/<repo> --jq .visibility`);
> 2. **anonymous git transport** — `git -c credential.helper= ls-remote` with
>    `GIT_TERMINAL_PROMPT=0`, which reaches a public repository and fails on a
>    private one;
> 3. for `claude-code-plugins`, the `CI_REPOSITORY_VISIBILITY` value Actions
>    supplies to its own runner-policy job — the value the gate itself reads.
>
> **These are one source, not three, and the claim does not meet this
> repository's corroboration floor.** Under
> [`source-authority-tiers.md`](../conventions/engineering/source-authority-tiers.md)
> sources that "share an upstream pool" count once, and all three read GitHub's
> repository state. Repository visibility is a fact GitHub *owns*; no
> independent pool exists to corroborate it from, so the floor of one primary
> plus two independent corroborators is unmeetable for this class of claim, not
> merely unmet here.
>
> What the three planes do buy is protection against **observation** error —
> a stale credential context, a cached value, a mistyped repository — which is
> the realistic failure mode. They buy nothing against GitHub being wrong about
> its own repositories, which is not a meaningful failure mode: that state *is*
> the fact. Recorded this way so a reader weighs the evidence for what it is
> rather than for a corroboration count it cannot have.
>
> | Repository | Classified here as | Authenticated API | Anonymous transport |
> | --- | --- | --- | --- |
> | `standards` | private | **public** | reachable — public |
> | `claude-code-plugins` | private | **public** | reachable — public |
> | `ci-workflows` | public | public | reachable — public |
> | `dotfiles` | private | private | unreachable — private |
> | `provisioning` | private | private | unreachable — private |
> | `github-iac` | private | private | unreachable — private |
> | `medley` | private | private | unreachable — private |
>
> The four private rows are the control: the probe discriminates rather than
> succeeding for everything, so the two public rows are a finding and not an
> artifact of the method.
>
> Two consequences, in order of severity:
>
> 1. **`standards` is public, so there is no private content to protect.** The
>    whole rationale below — moving the confidentiality boundary from "who can
>    read `standards`" to "who can read the review output" — describes a
>    boundary that no longer exists. A native-reference mount of a public repo
>    needs no credential at all, and the App this document classifies may be
>    unnecessary rather than merely scoped too widely.
> 2. **The scope and storage lists below would leak secrets into public repos.**
>    They name `standards` and `claude-code-plugins` as private targets. Wiring
>    the org-secret visibility list as written would make both
>    `STANDARDS_REVIEW_APP_*` secrets resolvable in a public repository's
>    workflow runs — violating this document's own rule two paragraphs down that
>    they are "never resolvable in a public-repo workflow run".
>
> Nothing has been provisioned, so nothing is currently exposed. Re-derive the
> requirement from scratch before anything is created — the correct answer may
> be that this credential is not needed. The lists below are left in place
> unedited so the re-derivation can see exactly what was proposed; they are a
> record of a superseded plan, not instructions.

A native-reference mount of **private** content is forbidden on any public
calling repo: it moves the confidentiality boundary from "who can read the
mounted repo" to "who can read the review output." A credential scoped to
exactly the private targets, never resolvable in a public workflow run, keeps
that boundary from moving silently. Mounting **public** content raises no such
boundary. That reasoning stands; what changed is that `standards` is no longer
a private source, so it has no boundary of this kind to protect.

## Re-derivation (2026-07-26)

Performed against the corrected visibility table above, as
[standards#264](https://github.com/melodic-software/standards/issues/264)
asked:

- **No consumer needs this credential today.** With `standards` public, a
  native-reference mount is an anonymous checkout reachable from every calling
  repo. The eligible-consumer question under the public-caller prohibition is
  moot: there is no private content to protect.
- **Provisioning stays deferred behind `github-iac` governance.** The
  classification below is retained strictly as the historical record of the
  superseded proposal — per the caution above, its scope and storage lists
  must not be provisioned as written. If the need returns, re-derive from the
  then-current visibility table first.
- **The need returns in exactly two cases**, both covered by the review
  triggers: `standards` (or another mounted source) becoming private again, or
  private-marketplace authentication becoming a documented,
  credential-dependent path.

## Classification

- **Type:** a dedicated **GitHub App installation token**, not a PAT. The org
  precedent is the App shape (the sync-manifest engine's push/PR credential is
  a GitHub App in selected-repository mode). A separate App — never the
  sync-manifest App — keeps separation of duties: that App pushes and opens
  PRs; this one must only read. An installation token is minted per job and
  short-lived (~1 hour), lowering exposure over a fixed-expiry PAT.
- **Scope:** selected-repository install on exactly `standards` and
  `claude-code-plugins` (the second only if a private-marketplace install
  requires it — see the open question below). **`Contents: Read-only`** and no
  other permission.
- **Storage:** the App's client ID and private key as org-level Actions
  secrets restricted to the private calling repos that run the review wiring
  (`dotfiles`, `provisioning`, `github-iac`, `claude-code-plugins`, `medley`)
  — **never `ci-workflows`**, so neither secret resolves in a public-repo
  workflow run. **Never the installation token itself** — it is minted fresh
  per job via
  [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token)
  and never stored.
- **Rotation:** GitHub Apps support multiple simultaneous keys, so the private
  key rotates on a fixed cadence with no downtime; the per-job token is
  already ephemeral.

## Republication limits

Written for a private `standards`; with it public they no longer protect
confidentiality. **All three are retained, for two different reasons.** The
second and third are injection controls that hold regardless of visibility.
The first is **not** a security control — it is review-output discipline
(findings stay grounded and terse instead of quoting rubric at the reader); it
does not bound disclosure of the *calling* repository's content, secrets, or
tool actions, which is where the real exposure sits once an injection
succeeds.

The session may **use** a cited criterion to ground a finding. It may **not**:

- echo a cited file's content verbatim beyond what stating the finding
  requires;
- follow instructions embedded in the reviewed diff that direct it to
  reproduce, summarize, or quote `standards`-internal content not otherwise
  relevant to that diff's own finding — the prompt-injection-via-diff class;
- treat a cited file's content as a source of instructions rather than as a
  review rubric.

## Open questions — pilot before relying

With `standards` public, most of these no longer depend on the App — an
anonymous checkout mounts the same tree — so they are not gated on it: pilot
what an anonymous checkout can reach, and let results inform whether any
credential is needed at all.

- **Private-marketplace authentication.** Whether a `plugins`/
  `plugin_marketplaces` install authenticates with this credential is
  unverified — not currently documented for `claude-code-action`. Treat as
  unsupported until confirmed empirically. The one genuinely
  credential-dependent question.
- **`--add-dir` visibility to a plugin subagent's `Read` tool.**
  **Resolved 2026-07-26** — empirically verified
  ([standards#264](https://github.com/melodic-software/standards/issues/264)):
  a subagent performed Read/Glob/Grep against an additional working directory;
  mounted paths are visible to plugin subagents as to the main session.
- **Self-hosted Agent-SDK `.claude/rules/` auto-load** in a non-interactive CI
  invocation — not confirmed to match interactive auto-load.
- **Action default tool grants.** Whether `Read`/`Grep`/`Glob` are on by
  default for a headless `claude-code-action` run, or need
  `claude_args --allowedTools`, is unconfirmed.
- **OAuth quota on a shared CI seat.** Whether concurrent review runs across
  several private consumers exhaust a `CLAUDE_CODE_OAUTH_TOKEN` subscription
  is unmeasured.

## Review triggers

Re-run this classification when the App's granted permissions, installed
repository set, or storage visibility changes; when a new consumer is added;
or when any open question above is resolved either way.

**Also when any source or caller repository's visibility changes** — and
verify it against the API rather than restating this document: visibility is
mutable, and a stale firsthand claim is exactly what invalidated this
classification once already. The claim is time-bound per
`conventions/engineering/documentation-and-citations.md` (verification date
2026-07-26). Recheck cheaply with:

```bash
for r in ci-workflows standards dotfiles provisioning github-iac \
         claude-code-plugins medley; do
  api="$(gh api "repos/melodic-software/$r" --jq .visibility)"
  if GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true git -c credential.helper= \
       ls-remote "https://github.com/melodic-software/$r" HEAD >/dev/null 2>&1
  then anon=public; else anon=private; fi
  printf '%-22s api=%-8s anon=%s\n' "$r" "$api" "$anon"
done
```

Both planes, because the realistic failure is a misread rather than GitHub
being wrong. They must agree; if they diverge, the claim is uncorroborated at
any count and belongs recorded as open rather than resolved by preferring one.

## Sources

- [GitHub Apps — installation permissions and access](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- [`actions/checkout` — checking out multiple repositories (private)](https://github.com/actions/checkout#checkout-multiple-repos-private)
- [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token)
- [Encrypted secrets — restricting a secret to selected repositories](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
