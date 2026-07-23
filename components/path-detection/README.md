# Path detection

Shared regex bodies for detecting machine-specific absolute paths — Windows,
macOS, and Linux user-home directories and repo-checkout roots — in tracked
files and generated content. Each body matches a root and at least one child
segment: `C:\Users\Alice\project`, and equally the bare value form
`root = C:/Dev/GitHub` or `/home/alice` at end of line — the right boundary is
the segment class itself (it excludes whitespace and the double quote), not a
trailing separator. A root with no child segment (`C:\Users`, a lone
`D:/repos/`) never matches. Portable placeholders such as `C:\Users\<user>\`
and `<repo-root>/` stay clean by construction (the negative character classes
exclude `<`, `$`, `{`, and bare `~`); every body excludes `%`, so percent-env
interpolations like `C:\Users\%USERNAME%\` are not flagged.

`machine-path-patterns.sh` is a define-only Bash library: the five `HPP_*`
pattern bodies and nothing else. Scan drivers own everything around them —
boundary prefixes, exclusion stages, exemptions, and exit-code mapping. The
known drivers are the `machine-specific-paths` composite action in
`ci-workflows`, the `guardrails` plugin's session-time hook lib in
`claude-code-plugins`, and `medley`'s commit/verification tooling (examples,
not a fixed list — the manifest's target assignments are the authoritative
consumer record).

Before this component existed, each of those drivers carried its own
hand-synced copy of the bodies; the 8.3 short-name widening (`ALICE~1`) had to
be propagated by hand to every copy. The bodies now land here once and reach
every driver through the sync pipeline.

`machine-path-patterns.test.sh` pins the contract: each body matches the path
shapes it exists to catch (plain, forward-slash, JSON-escaped, 8.3 short-name,
and the bare value form at a natural boundary), and stays clean on the
placeholder forms, on roots with no child segment, and on prose — the old
trailing-separator right boundary is pinned OUT, since it both missed bare
config values and let the then space-permitting class match prose greedily.
