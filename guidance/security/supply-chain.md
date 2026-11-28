# Supply chain

## Design

- Allow generated pages to load widely used libraries from a CDN when a local fallback exists; forbidding it adds friction that is not worth its cost.

## Design and build

- Adopt only official, trusted, actively maintained and secure dependencies and tools, vetted before they go into provisioning. Prefer official or self-built tooling over third-party extensions, and leave official vendor integrations unchanged unless there is a concrete need.

## Review

- Hold any diff that changes a workflow trigger, permissions, trusted-actor logic or token requests for a security review pass before merge.

## Review and operate

- Check that a package carries registry provenance before accepting an update, and find out why when it is missing.
- In a public repository, make sure no credential can be obtained from CI runs, logs, artifacts or caches; check variable, secret and fork exposure.

## Operate

- Let owned code and official vendors float to latest; updates from the official vendor of a core tool merge as soon as they land, with no cooldown or manual review. Pin only untrusted third-party code, and keep those pins moving through automated updates with cooldowns.
- Fix dependency vulnerabilities right away in every repository, auto-applying safe patch and minor updates.
