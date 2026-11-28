# Messaging

## Design and operate

- Trigger work on events instead of polling (the Hollywood principle: don't call us, we'll call you). Run only when needed and batch where possible.
- Back event-driven automation with a cheap periodic sweep that catches items stuck where event coverage is incomplete.
