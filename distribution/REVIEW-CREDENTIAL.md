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

**Status: classified, not provisioned.** Nothing below has been created.
Provisioning — registering the GitHub App, generating its key, and wiring the
org-secret visibility list — is `github-iac` governance work and is recorded
as an open item, not attempted here.

## Why a dedicated credential

The native-reference mount is **forbidden on any public calling repo**
(`ci-workflows` is public; `standards`, `dotfiles`, `provisioning`,
`github-iac`, `claude-code-plugins`, and `medley` are private — confirmed
firsthand). Mounting this repo's private content into a review agent whose
output is published wherever the calling repo's visibility allows moves the
confidentiality boundary from "who can read `standards`" to "who can read the
review output." A credential scoped to exactly the private targets, and never
resolvable in a public workflow run, is what keeps that boundary from moving
silently.

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
- **Storage:** an org-level Actions secret whose visibility is restricted to
  the private calling repos that run the review wiring
  (`dotfiles`, `provisioning`, `github-iac`, `claude-code-plugins`,
  `medley`) — **never `ci-workflows`**, so the secret is not resolvable in a
  public-repo workflow run regardless of which reusable workflow it calls.
  `ci-workflows` defines the reusable workflow only; the calling private
  repo's job supplies the token.
- **Rotation:** GitHub Apps support multiple simultaneous keys, so the
  private key rotates on a fixed cadence with no downtime; the per-job
  installation token these keys mint is already ephemeral and needs no
  separate rotation policy of its own.

## Republication limits

The review session reads private `standards` content — criteria files
reached via the native-reference cite — into an agent whose output (PR
comments, check-run text, workflow logs) may be visible beyond `standards`'
own access boundary on some calling repos. The session may **use** a cited
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

## Open question

Whether a private-marketplace install via the `plugins`/`plugin_marketplaces`
action inputs authenticates using this same credential is unverified — the
Claude Code GitHub Actions documentation and the `claude-code-action` setup
guide do not currently document private-marketplace authentication. Treat as
unsupported until confirmed empirically (tracked as an empirical test, not a
provisioning assumption).

## Review triggers

Re-run this classification when the App's granted permissions, installed
repository set, or storage visibility changes; when a new consumer of this
credential is added; or when the private-marketplace open question above is
resolved either way.

## Sources

- [GitHub Apps — installation permissions and access](https://docs.github.com/en/apps/creating-github-apps/setting-up-a-github-app/choosing-permissions-for-github-apps)
- [`actions/checkout` — checking out a different repository](https://github.com/actions/checkout#checkout-a-different-repository)
- [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token)
- [Encrypted secrets — restricting a secret to selected repositories](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
