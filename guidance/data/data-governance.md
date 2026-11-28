# Data governance

## Design and operate

- Store only what is needed. Give every artifact, log, cache and store an enforced retention policy so nothing grows without bound, above all where storage costs money.
- Tie an artifact's lifetime to the event that ends its purpose (such as its issue closing), not to an imposed expiry date, and enforce it the simplest way that works.
- Do not keep redundant copies of data an upstream system already retains. Align your retention default with the upstream policy and state how the two reconcile. Keep distilled content and transcripts linked to their upstream source; raw bulky media need not be kept.
