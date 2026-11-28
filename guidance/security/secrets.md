# Secrets

## Design

- Keep each secret in exactly one store: a central vault that many machines and processes read, or the CI platform's store for secrets only CI uses. Split stores by isolation and access scope, not by which consumer reads them.
- Prefer SSH signing keys as the one commit-signing mechanism across every environment, over maintaining separate GPG keys.

## Design and build

- Have tools and setup fetch keys from the stores where they already live, through one consistent integration path per tool. Do not make a person load them by hand.

## Design and operate

- Give each distinct workload its own least-privilege identity and budget, preferring short-lived federated credentials; resources that need identical access may share one. In production name one specific credential, never a chain that silently tries another identity. A second credential with the same scope exists for rotation overlap, and an automated lane may declare one fallback with the same scope, used only when the primary is throttled, exhausted or failing, with every switch logged. Keep the count small for people through federation and by deleting unused credentials; name each credential by purpose and make its usage visible.

## Build and operate

- Enter secret values through scripts, wizards or tool logins that keep them out of terminals and chat. Agents never invent, print or commit a secret unless an explicit decision allows it. Decide with the person where each new secret lives; a throwaway prototype credential may stay local.

## Review and operate

- Scan diffs, pushes and published artifacts for secrets and machine-specific data.
  - Limit a pull request's scan to that pull request's own commits.
  - Set artifact scan depth by visibility, organization policy and who has access. Agents pick the setting, a human can tune it, and regulated contexts such as HIPAA can tighten it.
  - After work that handled secrets, confirm nothing leaked and delete downloaded files that held them.

## Operate

- Prefer automatic rotation. Before rotating, establish what uses the credential and whether rotation is needed, and schedule it as a separate follow-up at the end of an effort so it blocks no other work. Delete old and temporary keys once nothing uses them, and warn before credentials expire.
