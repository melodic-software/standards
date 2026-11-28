# Third-party dependencies

## Design

- Depend on upstream rather than keep a copy that is not kept in sync, and point to an upstream you would only copy one for one. Absorb an outside skill or tool only by recomposing it into your own extensible one, and drop yours once upstream meets your standards.
- Do not ship copies of fast-changing third-party integrations that drift from the vendor's API; keep the maintained copy where its consumer updates it.

## Design and operate

- Track which components derive from upstream. Vendor the ones you need to improve, cite the source, and keep them current through an automated drift check. Always read the upstream's latest version, never a stale copy.

## Plan and operate

- Know how old each dependency is, prefer the maintained one among duplicates, and research modern replacements for stale ones. When it is safe and the dependency will update on its own, move forward now rather than wait for an upstream release.

## Build

- Package your own extensions the way the upstream platform packages its own.

## Build and operate

- When an interim workaround waits on an upstream gap, record the conditions for removing it and check upstream for them, so the cutover happens as soon as they are met.

## Operate

- Keep pinned dependencies current through a standard update bot such as Dependabot rather than custom tooling.
