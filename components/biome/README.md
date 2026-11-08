# Biome policy

Shared Biome linting, formatting, and import-organization policy. The sync
delivers `biome.json` to each target at `.github/standards/biome/biome.json`
(the `biome` component in `distribution/sync-manifest.yml`).

The ruleset is strict and marked `root: false` so a target can extend it from
its own root config by relative path while retaining repository-specific scope:

```json
{
  "root": true,
  "extends": ["./.github/standards/biome/biome.json"],
  "files": { "includes": ["src/**", "tests/**"] }
}
```

Biome owns lint, format, and import sorting; TypeScript owns type correctness.
Project scope belongs in the target's root config and is intentionally absent
from the shared file. The ruleset needs Biome 2.5.1 or later within major
version 2. `fixtures/` and `biome.test.sh` prove named non-default rules fire
through a relative-path extends.
