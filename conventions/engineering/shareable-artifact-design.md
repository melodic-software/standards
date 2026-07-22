# Shareable artifact design

An artifact built to be shared — a plugin, a reusable configuration component, a template, a dotfiles module, a workflow, a script — is a product with consumers, not a private convenience with an audience. Design it for a consumer who is not its author: a different machine, user, organization, and repository. The author's environment is one deployment among many, never the assumed one. This is a reasoning-only discipline: whether a value is genuinely universal or consumer-varying is a judgment no tool decides.

It composes with `code-organization.md` (when sharing begins — the second consumer — and which surface is contract versus private), `reference-dont-duplicate.md` (a shared artifact is a single source of truth its consumers cite, not copy), and `engineering-philosophy.md` (the explicit, fail-fast, idempotent posture every artifact carries). Those decide *when* to share and *how* to speak about what is shared; this decides how a shared artifact treats the consumers it then has.

## Consumer-agnostic by default

- Behavior never depends on the author's machine paths, personal environment, organization names, or repository layout. Publisher metadata may identify the source; runtime behavior must not require it.
- An artifact genuinely and inherently narrower — one platform, one forge, one ecosystem — declares that boundary explicitly where the coupling lives, rather than shipping the assumption unstated under a neutral name.

## Modular and independently useful

- A shareable artifact is a cohesive vertical slice that works alone. Optional collaboration with another artifact is presence-gated with a documented fallback; a bare unguarded reference to an optional collaborator is a defect. A hard requirement is declared as an explicit dependency, never discovered by failure.

## Externalize what a consumer may decide

- A shipped default is legitimate only when it cannot conflict in any consumer's environment. Anything a consumer could reasonably do differently — conventions, paths, tool choices, policies — is an externalized configuration point the artifact discovers or is told, never a baked-in assumption. `architecture-and-design.md` states the same externalization rule for environment-varying values, with the YAGNI counterweight that bounds both: variance a consumer could not realistically have stays inline.
- Adoption never requires forking the artifact or hand-editing its internals; if consuming demands an edit, the artifact is missing a configuration seam. This is the same strict separation of code from deploy-varying values the twelve-factor config rule mandates, applied to consumer-varying values.

## Design the consumer tiers

- Serve three tiers explicitly: **consume-only** (works as shipped, zero-config or via the documented setup), **customize** (sanctioned extension and configuration points, no fork), and **contribute** (a documented path for changes to flow back). An artifact that only serves its author has zero tiers; one that demands source edits to adopt has collapsed the first two.

## Adoption is explicit and repeatable

- The setup path is documented, idempotent, transparent about what it inferred and changed, and automatable — a non-interactive route exists for headless use.
- Every prerequisite — runtime, tool, credential, service — is declared at the point of use. Absence is classified deliberately: required for correctness stops with a remediation message; required for an optional feature warns visibly and continues with the documented reduced result; not applicable exits quietly. A silently skipped feature is a defect.

## Sources

- Wiggins, ["The Twelve-Factor App — III. Config"](https://12factor.net/config) — strict separation of config from code because config varies across deployments and code does not; the analogue here is consumer-varying versus universal values.
- [InnerSource Commons](https://innersourcecommons.org/) — applying open-source collaboration practices to internal shared projects; the inspiration for treating internal consumers and contributors as first-class.
