# Performance analysis

## Plan and operate

- Take baselines while the real working load is running, and let the measurements set the order of fixes.

## Build and review

- Claim a speedup only against a baseline: measure first, change in small steps, re-measure, and keep a change only when the measurement shows it helped.

## Review and operate

- Measure a dependency's actual latency before blaming it or filing upstream; a sub-second cost does not justify a report.
