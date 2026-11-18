# Security review criteria

Diff-time checks for the security concerns automated tooling cannot fully catch: trust boundaries, injection, data exposure, and supply chain. Severity labels are defined in [README.md](README.md). Mechanical backstops include the [`gitleaks`](../../components/gitleaks/) policy and the OSV-Scanner workflow in `ci-workflows`; review owns the judgment they cannot make.

## Secrets and credentials

- **No secrets in source**: tokens, keys, and connection strings live in environment variables or a secret store, never in code or tracked config. Watch for local-only config content leaking into a tracked file. (The Gitleaks component backstops this mechanically.) Rotation, expiry, revocation, and store placement follow [secrets-lifecycle.md](../engineering/secrets-lifecycle.md).
- **Credential-bearing inputs via environment only**: a tool that consumes credentials, cookie files, or session state reads their location from the environment or detects them at runtime; it never embeds login state in a tracked file.
- **No personal data in logs**: personally identifiable information logged without a data-classification control is a finding; flag it for redaction.

## Trust boundaries and injection

- **Validate external input at the boundary**: every external input (a request, a tool parameter, a user-supplied path) is validated or sanitized at the entry point.
- **Injection**: parameterized queries only, never string-concatenated. No process invocation built from unsanitized input.
- **CORS and auth-header exposure**: cross-origin policies do not over-expose, and auth tokens do not leak into error responses or logs.
- **Transport security**: external endpoints use encrypted transport with no plaintext fallback in production.
- **Error-detail leaking**: production error responses do not include stack traces, internal paths, or connection strings; surfaced error messages are safe to show a caller.
- **Idempotency-key hygiene**: an idempotency key contains no sensitive data and is not predictable.
- **Comment-claimed mitigations**: a comment asserting a security property of a deployed environment ("does not emit in production", "gated in prod") is a claim, not a control. Verify it against every configuration layer that environment loads: the base configuration plus the environment's own file, where an empty environment file means the base value applies. Important when the claim is false.
- **Rate limiter ordered after authorization**: a limiter that runs after authorization never sees the requests authorization rejects, so the unauthenticated-failure path on a protected endpoint is unthrottled, and an anonymous or per-address partition covers only anonymous-allowed endpoints. Flag it unless a limiter ahead of authorization, or a recorded deferral, covers that path.
- **Required-secret guard that accepts an empty value**: a startup check for a required secret rejects a missing, empty, or whitespace-only value, not only null. An empty secret is a value every caller already knows (an empty HMAC key, the hash of an empty client secret, an empty API-key comparison), so it authenticates anyone ([CWE-287](https://cwe.mitre.org/data/definitions/287.html)).
- **Command guard matching a flattened string**: a guard that substring- or pattern-matches a flattened command line is bypassable, because the shell rewrites quoting, global options, and wrappers before the program sees its arguments. Test the guard against a quoted executable, a displaced global option (`git -C . commit`), bundled short flags, wrappers (`command`, `env`, `sh -c`), and case or path variants on Windows. A guard that cannot see variable or command-substitution expansion is a friction layer, not a boundary, and its documentation claims no more.
- **Agent permissions broader than the task**: a change to what an AI agent may do (a tool or command allowlist, a permission rule, a hook, an instruction file that grants a capability) that grants more than the task needs or removes a guardrail. [mcp.md](mcp.md) owns scope at the tool-definition surface; this covers the agent's configuration.

## Object-level authorization

- **Object-level authorization on every object-scoped request**: an endpoint or handler that receives an object id (a path segment, body field, or query parameter) and returns or mutates that object checks that the requesting principal is authorized for that specific record, not just that a well-formed id was supplied or that the caller holds some role over the object's type. A lookup-by-id, update-by-id, or delete-by-id path added with no per-object ownership or ACL check is the classic gap: an interface may render only the caller's own records while the endpoint itself still accepts and serves any id ([CWE-639](https://cwe.mitre.org/data/definitions/639.html)). An unguessable id (a GUID) is defense in depth, never a substitute for the check ([OWASP API1:2023](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/), [OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)).

## Third-party and supply chain

Every external integration, whether a package, a CI action, a plugin, a tool server, a browser extension, or a reusable workflow, is vetted before adoption and monitored after:

- Pin third-party CI actions by full commit hash, not a tag a maintainer can move.
- Check maintainer identity and bus factor, a published security scorecard where available, recent release activity, the count of unaddressed advisories, and license compatibility.
- Treat abandonment signals (no commits in a year, an archived repo, unpatched critical issues) as a trigger to plan migration.
- Re-audit critical dependencies and direct dependencies on a recurring schedule.

## Sources

- OWASP: [API1:2023 Broken Object Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/), [Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)
- MITRE: [CWE-639: Authorization Bypass Through User-Controlled Key](https://cwe.mitre.org/data/definitions/639.html), [CWE-287: Improper Authentication](https://cwe.mitre.org/data/definitions/287.html)
