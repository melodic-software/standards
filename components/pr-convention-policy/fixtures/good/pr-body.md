Closes #173

## Summary

Adds the pr-convention-policy component so PR conventions live as data.

## Fix

Records the canonical policy file, schema, and validator in `components/`.

## Verification

`npm run lint:pr-convention-policy` and `npm run test:pr-convention-policy` pass.

## Related

- melodic-software/ci-workflows thin-runner follow-on
