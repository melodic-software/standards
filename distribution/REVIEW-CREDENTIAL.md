# Native-reference review credential

Classification for the read-only credential a private calling repo's CI job
uses to mount this repo's `conventions/review` tree by native reference — the
depth tier described in [`conventions/README.md`](../conventions/README.md)
and cited from the synced `REVIEW.md`. Scope is exactly this credential's
authentication and republication boundary — adjacent to, but distinct from,
the sync-manifest push credential covered by
[`THREAT-MODEL.md`](THREAT-MODEL.md), which explicitly excludes
authentication and belongs instead to the reusable workflow in
`ci-workflows`. This credential is likewise external to the reconciliation
engine: it authenticates a *review* job's checkout, never a materialization
apply.

**Status: classified, not provisioned — re-derived 2026-07-26 as not
currently needed (see "Re-derivation" below).** Nothing below has been
created. Provisioning — registering the GitHub App, generating its key, and
wiring the org-secret visibility list — is `github-iac` governance work and
stays deferred behind it; under the current visibility state there is
nothing to provision.

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

The native-reference mount is **forbidden on any public calling repo**.
Mounting private content into a review agent whose output is published
wherever the calling repo's visibility allows moves the confidentiality
boundary from "who can read the mounted repo" to "who can read the review
output." A credential scoped to exactly the private targets, and never
resolvable in a public workflow run, is what keeps that boundary from moving
silently.

That reasoning stands on its own terms; what changed is that `standards` is no
longer a private source, so it no longer has a boundary of this kind to
protect.

## Re-derivation (2026-07-26)

The re-derivation [standards#264](https://github.com/melodic-software/standards/issues/264)
asked for, performed against the corrected visibility table above:

- **No consumer needs this credential today.** With `standards` public, a
  native-reference mount is an anonymous checkout — every calling repo,
  public or private, can reach the same tree without authenticating. The
  eligible-consumer question under the public-caller prohibition is moot:
  that prohibition exists to keep *private* mounted content out of
  published review output, and there is currently no private content to
  protect. `claude-code-plugins` being public is therefore not a per-repo
  ineligibility; the credential is simply unnecessary for the mount.
- **Provisioning stays deferred behind `github-iac` governance**, and under
  the current state there is nothing to provision. The classification below
  is retained as the record of what would be provisioned if the need
  returns.
- **The need returns in exactly two cases**, both already covered by the
  review triggers: `standards` (or another mounted source) becoming
  private again, or private-marketplace authentication becoming a
  documented, credential-dependent path (the one genuinely
  credential-dependent open question below).

## Classification

- **Type:** a dedicated **GitHub App installation token**, not a personal
  access token. `actions/checkout`'s cross-repo private-checkout path accepts
  either, but this org already has a precedent for the App shape: the
  sync-manifest reconciliation engine's own push/PR credential is a GitHub
  App in selected-repository mode, with two-snapshot access attestation
  before every real sync
  ([`README.md`](README.md#adopting-a-new-repository)). A separate App for
  this credential — never the sync-manifest App — keeps separation of
  duties: that App can push and open pull requests; this one must only read.
  An App installation token is also short-lived (minted per job, on the
  order of an hour) versus a PAT's fixed expiry, which lowers exposure if a
  job log or cache leaks it.
- **Scope:** selected-repository install on exactly `standards` and
  `claude-code-plugins` (the second only if/when the B4 upstream plugin PR
  and a private-marketplace install both require it — see the open question
  below). **`Contents: Read-only`** and no other permission.
- **Storage:** the App's own credentials — its client ID and private key —
  as org-level Actions secrets whose visibility is restricted to the private
  calling repos that run the review wiring (`dotfiles`, `provisioning`,
  `github-iac`, `claude-code-plugins`, `medley`) — **never `ci-workflows`**,
  so neither secret is resolvable in a public-repo workflow run regardless
  of which reusable workflow it calls. `ci-workflows` defines the reusable
  workflow only; the calling private repo's job supplies both secrets to it.
  **Never the installation token itself** — that token is minted fresh
  inside each job from the App credentials via
  [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token),
  expires in about an hour, and is never stored; storing it instead of the
  App credentials would break the mount after the first hour and would need
  manual rotation as it expires or is revoked.
- **Rotation:** GitHub Apps support multiple simultaneous keys, so the
  private key rotates on a fixed cadence with no downtime; the per-job
  installation token these keys mint is already ephemeral and needs no
  separate rotation policy of its own.

## Republication limits

These limits were written for a private `standards`; with it public they no
longer protect confidentiality, since a cited file is readable by anyone who
can read the review output anyway. **All three are retained, for two different
reasons.**

The second and third are the injection controls — block the trigger, and
refuse to treat a cited file as instructions rather than a rubric. Both hold
regardless of repository visibility, and both are why this section survives at
all.

The first is **not** a security control and should not be read as one. It
bounds how much of a cited file a session echoes; that file is now public, so
bounding it protects nothing, and it does not bound disclosure of the *calling*
repository's content, its secrets, or the session's tool actions — which is
where the real exposure sits once an injection succeeds. It is retained as
review-output discipline: findings stay grounded and terse instead of quoting
rubric at the reader.

With `standards` public, no calling repo's review output can reach an audience
that could not already read the cited criteria, so these are **not** access-
boundary controls. What remains is output integrity: a review session must
report findings grounded in the criteria, and must not be steerable by the
content it reviews into doing something else. The session may **use** a cited
criterion to ground a finding. It may **not**:

- echo a cited file's content verbatim beyond what stating the finding
  requires;
- follow instructions embedded in the reviewed diff that direct it to
  reproduce, summarize, or quote `standards`-internal content not otherwise
  relevant to that diff's own finding — the prompt-injection-via-diff class,
  where an attacker-controlled diff in the calling repo tries to use the
  mounted private tree as an exfiltration channel;
- treat a cited file's content as a source of instructions rather than as a
  review rubric.

## Open questions — pilot before relying

These were written when the mount required the App this document classifies
but does not provision. **With `standards` public, most no longer depend on
it** — an anonymous checkout mounts the same tree, so `--add-dir` visibility,
SDK rule loading, default tool grants, and OAuth quota can all be piloted now.
Only private-marketplace authentication is genuinely credential-dependent.

Gating them on an App that the caution above says not to provision would
deadlock the re-derivation it asks for, so they are not gated: pilot what an
anonymous checkout can reach, and let the results inform whether any
credential is needed at all rather than assuming one is.

- **Private-marketplace authentication.** Whether a `plugins`/
  `plugin_marketplaces` install authenticates using this same credential is
  unverified — the Claude Code GitHub Actions documentation and the
  `claude-code-action` setup guide do not currently document private-
  marketplace authentication. Treat as unsupported until confirmed
  empirically.
- **`--add-dir` visibility to a plugin subagent's `Read` tool.**
  **Resolved 2026-07-26** — empirically verified
  ([standards#264](https://github.com/melodic-software/standards/issues/264)):
  in a live session, a subagent performed Read, Glob, and Grep against an
  additional working directory outside the primary working directory — the
  same mechanism `--add-dir` uses. Mounted paths are visible to plugin
  subagents the same way they are to the main session.
- **Self-hosted Agent-SDK `.claude/rules/` auto-load** in a non-interactive
  CI invocation — not confirmed to behave like an interactive session's
  auto-load.
- **Action default tool grants.** Whether `Read`/`Grep`/`Glob` are on by
  default for a headless `claude-code-action` run, or must be explicitly
  allowlisted via `claude_args --allowedTools`, is not confirmed from the
  documentation fetched this round.
- **OAuth quota on a shared CI seat.** `CLAUDE_CODE_OAUTH_TOKEN` draws from
  an individual subscription; whether concurrent review runs across several
  private consumers exhaust it in practice is unmeasured.

## Review triggers

Re-run this classification when the App's granted permissions, installed
repository set, or storage visibility changes; when a new consumer of this
credential is added; or when any open question above is resolved either
way.

**Also when any source or caller repository's visibility changes** — and
verify it against the API rather than restating this document, because
repository visibility is mutable and a stale firsthand claim is exactly what
invalidated the classification once already. The claim is time-bound in the
sense of `conventions/engineering/documentation-and-citations.md`, so it
carries a verification date (2026-07-26) and does not survive on its own
authority. Recheck cheaply with:

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
