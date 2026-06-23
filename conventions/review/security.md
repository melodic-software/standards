# Security review criteria

Diff-time checks for the security concerns automated tooling cannot fully catch — trust boundaries, injection, data exposure, and supply chain. Severity labels are defined in [README.md](README.md). Two mechanical backstops already exist in the catalog: secret scanning (`modules/gitleaks/`) and dependency-vulnerability scanning (`modules/osv-scanner/`); review owns the judgment they cannot make.

## Secrets and credentials

- **No secrets in source** — tokens, keys, and connection strings live in environment variables or a secret store, never in code or tracked config. Watch for local-only config content leaking into a tracked file. (The gitleaks module backstops this mechanically.)
- **Credential-bearing inputs via environment only** — a tool that consumes credentials, cookie files, or session state reads their location from the environment or detects them at runtime; it never embeds login state in a tracked file.
- **No personal data in logs** — personally identifiable information logged without a data-classification control is a finding; flag it for redaction.

## Trust boundaries and injection

- **Validate external input at the boundary** — every external input (a request, a tool parameter, a user-supplied path) is validated or sanitized at the entry point.
- **Injection** — parameterized queries only, never string-concatenated. No process invocation built from unsanitized input.
- **CORS and auth-header exposure** — cross-origin policies do not over-expose, and auth tokens do not leak into error responses or logs.
- **Transport security** — external endpoints use encrypted transport with no plaintext fallback in production.
- **Error-detail leaking** — production error responses do not include stack traces, internal paths, or connection strings; surfaced error messages are safe to show a caller.
- **Idempotency-key hygiene** — an idempotency key contains no sensitive data and is not predictable.

## Third-party and supply chain

Every external integration — a package, a CI action, a plugin, a tool server, a browser extension, a reusable workflow — is vetted before adoption and monitored after:

- Pin third-party CI actions by full commit hash, not a tag a maintainer can move.
- Check maintainer identity and bus factor, a published security scorecard where available, recent release activity, the count of unaddressed advisories, and license compatibility.
- Treat abandonment signals (no commits in a year, an archived repo, unpatched critical issues) as a trigger to plan migration.
- Re-audit critical dependencies and direct dependencies on a recurring schedule.
