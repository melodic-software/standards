# `@melodic-software/biome-config`

Shared Biome linting, formatting, and import-organization policy. This component
directory is both the source slice and the npm package: `biome.json` is authored,
tested, and published here with no staging copy.

The ruleset is strict and marked `root: false` so a consumer can extend it from
its own root config while retaining repository-specific scope:

```json
{
  "root": true,
  "extends": ["@melodic-software/biome-config/biome"],
  "files": { "includes": ["src/**", "tests/**"] }
}
```

Install from GitHub Packages with `npm install --save-dev
@melodic-software/biome-config`. The npm scope must resolve to
`https://npm.pkg.github.com`.

Biome owns lint, format, and import sorting; TypeScript owns type correctness.
Project scope belongs in the consumer adapter and is intentionally absent from
the shared payload. `fixtures/` and `biome.test.sh` prove named non-default rules
fire and are not part of the published package.

The publish workflow packs this directory directly. Any change to the complete
packed payload requires a version bump; an already-published version is compared
against a fresh local pack byte-for-byte at the extracted-file level.
