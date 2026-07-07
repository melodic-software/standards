# @melodic-software/biome-config

The shared Biome ruleset, published from this repo's
`modules/typescript/biome.json` — the single source of truth. The config file is
staged into the package at publish time (never committed here), so the package
cannot drift from the module.

## Install

GitHub Packages requires authentication even for public packages, so consumers
need the scope routed and a token available:

```ini
# .npmrc (committed)
@melodic-software:registry=https://npm.pkg.github.com
```

```bash
npm install --save-dev @melodic-software/biome-config
```

In GitHub Actions, `GITHUB_TOKEN` works via `actions/setup-node`'s
`registry-url`; locally, use a token with `read:packages`.

## Use

```jsonc
// biome.jsonc
{
  // root: true is required, not optional — the base carries root: false (it is
  // authored for nested/extended use), and an extended value fills any key the
  // consumer leaves unset.
  "root": true,
  "extends": ["@melodic-software/biome-config/biome"]
}
```

The specifier must stay `@melodic-software/biome-config/biome` (the package
`exports` entry); a path ending in `.json` is treated as a relative path and
will not resolve from `node_modules`.

## Changing the rules

This package is read-only downstream. Change
`modules/typescript/biome.json` upstream in
[melodic-software/standards](https://github.com/melodic-software/standards) and
bump the version in `packages/biome-config/package.json`; the publish workflow
does the rest.
