# Caching

## Design

- Consider caching fetched content together with a summary for the specific question, keyed by resource and question, so other agents reuse the answer until the source goes stale.

## Design and operate

- Send repeated web and upstream lookups through one shared per-machine cache with an expiry per resource, revalidated by expiry, ETag or content hash, so sessions and consumers do not refetch the same thing.
