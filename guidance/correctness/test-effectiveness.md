# Test effectiveness

## Build

- In shared tooling, discover which mutation-testing tool the project uses rather than coupling to one.

## Build and review

- Reject tautological tests, tests of code shape, and coverage targets (100% included); ship no coverage threshold as a default.

## Review

- Judge test value with mutation testing scoped to the changed code and to the tests written or modified, rather than trusting coverage or passing tests.
