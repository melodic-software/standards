# Security review criteria

Diff-time checks for the security concerns automated tooling cannot fully catch — trust boundaries, injection, data exposure, and supply chain. Severity labels are defined in [README.md](README.md). Mechanical backstops include the [`gitleaks`](../../components/gitleaks/) policy and the OSV-Scanner workflow in `ci-workflows`; review owns the judgment they cannot make.

## Secrets and credentials

- **No secrets in source** — tokens, keys, and connection strings live in environment variables or a secret store, never in code or tracked config. Watch for local-only config content leaking into a tracked file. (The Gitleaks component backstops this mechanically.)
- **Credential-bearing inputs via environment only** — a tool that consumes credentials, cookie files, or session state reads their location from the environment or detects them at runtime; it never embeds login state in a tracked file.
- **No personal data in logs** — personally identifiable information logged without a data-classification control is a finding; flag it for redaction.

## Trust boundaries and injection

- **Validate external input at the boundary** — every external input (a request, a tool parameter, a user-supplied path) is validated or sanitized at the entry point.
- **Injection** — parameterized queries only, never string-concatenated. No process invocation built from unsanitized input.
- **CORS and auth-header exposure** — cross-origin policies do not over-expose, and auth tokens do not leak into error responses or logs.
- **Transport security** — external endpoints use encrypted transport with no plaintext fallback in production.
- **Error-detail leaking** — production error responses do not include stack traces, internal paths, or connection strings; surfaced error messages are safe to show a caller.
- **Idempotency-key hygiene** — an idempotency key contains no sensitive data and is not predictable.

## Object-level authorization

- **Object-level authorization on every object-scoped request** — an endpoint or handler that receives an object id (a path segment, body field, or query parameter) and returns or mutates that object checks that the requesting principal is authorized for that specific record, not just that a well-formed id was supplied or that the caller holds some role over the object's type. A lookup-by-id, update-by-id, or delete-by-id path added with no per-object ownership or ACL check is the classic gap — an interface may render only the caller's own records while the endpoint itself still accepts and serves any id ([CWE-639](https://cwe.mitre.org/data/definitions/639.html)). An unguessable id (a GUID) is defense in depth, never a substitute for the check ([OWASP API1:2023](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/), [OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)). The cross-tenant case — the same gap at the tenant boundary rather than the individual-record boundary — is `multi-tenancy.md`'s "Fetch-by-id without ownership."

## Third-party and supply chain

Every external integration — a package, a CI action, a plugin, a tool server, a browser extension, a reusable workflow — is vetted before adoption and monitored after:

- Pin third-party CI actions by full commit hash, not a tag a maintainer can move.
- Check maintainer identity and bus factor, a published security scorecard where available, recent release activity, the count of unaddressed advisories, and license compatibility.
- Treat abandonment signals (no commits in a year, an archived repo, unpatched critical issues) as a trigger to plan migration.
- Re-audit critical dependencies and direct dependencies on a recurring schedule.

## Sources

- OWASP — [API1:2023 Broken Object Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/), [Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)
- MITRE — [CWE-639: Authorization Bypass Through User-Controlled Key](https://cwe.mitre.org/data/definitions/639.html)
