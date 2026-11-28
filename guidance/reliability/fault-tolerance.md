# Fault tolerance

## Design and build

- When an optional dependency is missing, degrade and say so; when a required tool or runtime is missing, stop (fail closed). Never proceed without a required piece, and never fail hard or get stuck needing a person over an optional one.

## Design and operate

- Make automated jobs idempotent and resumable: check state before acting, skip finished work, and let a rerun continue where the last one stopped.
- Gate risky work and writes behind a self-resetting circuit breaker and headroom check. It trips only when needed, releases as soon as it can, and never leaves anything permanently disabled.
- Give automation a fallback capacity source used only when the primary is throttled, exhausted or failing, declared and logged as security.secrets says. Report the failed credential and cache that result so later runs skip it.

## Operate

- When a step is skipped because of resource pressure or an unreachable host, record the gap visibly so it can be retried later. It must not go silently missing.
- On an outage or limit: detect it, gate dependent work, back off with scripted exponential retry rather than retries that burn model tokens, and resume automatically when the signal recovers. Retry transient server errors, but never retry silently forever, and stop retrying a path or credential known to fail.
