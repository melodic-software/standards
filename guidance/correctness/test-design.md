# Test design

## Build

- Keep unit tests off real resources such as the file system; a test that touches one is an integration test and needs isolation.
