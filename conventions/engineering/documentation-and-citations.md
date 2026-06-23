# Documentation and external citations

A source of truth that lives outside the repo — a vendor's product docs, a framework reference, a cloud dashboard, an API reference, a registry page — is owned by that upstream, not by you. Copying its content into tracked files creates a snapshot that decays the moment the upstream changes. Cite it; fetch it at read time. This complements the in-repo discipline (see `reference-dont-duplicate.md`): one governs facts you own, this governs facts someone else owns.

## Upstream bodies are read-on-demand

Catalogs, defaults, schemas, flag inventories, pricing, lifecycle mechanics, and install matrices are upstream-owned. Do not recap them in tracked markdown — link to the authority and let the reader (human or agent) fetch the current version. What the repo records instead is **policy and wiring**: the paths it commits, the decisions it made, the empirical findings it observed, and operator recipes that have no stable upstream source.

For one fact, cite either your own policy hub or the upstream URL — not both with recap prose between them. The hub owns repo policy; the upstream owns product behavior. The narrow exception is a minimal install or verify command for which no stable upstream source exists for your exact wiring; keep that inline and point at the upstream for everything around it.

## Place the citation where it is read

Documentation is rarely read top to bottom. Place an upstream link at the sentence that actually defers to it, so it survives a partial read or a search hit — not only in a footer. Pages that are read whole (reference hubs, overviews) additionally aggregate their external links in a footer section so a whole-file reader sees every authority at once. Both placements together beat footer-only, because readers attend to the start and end of a document more than its middle ([Liu et al., "Lost in the Middle", TACL 2024](https://aclanthology.org/2024.tacl-1.9/)).

## Two distinct footer kinds

Keep research provenance separate from product documentation:

- A **sources** footer holds research provenance — books, talks, studies, papers — the durable reasoning behind a convention.
- An **external-authority** footer holds vendor, framework, and cloud *product* documentation URLs — the living references a reader fetches for current behavior.

## Time-bound external claims need a recheck trigger

A recorded upstream default, version gate, or price belongs in durable content only with an explicit recheck trigger — a date, an automation, or a tracked task. Prefer linking and fetching at read time over storing a snapshot at all. A snapshot with no recheck trigger is drift waiting to happen.
