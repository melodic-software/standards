# @melodic-software/tsconfig

The shared strict TypeScript base config, published from this repo's
`modules/typescript/tsconfig.json` — the single source of truth. The config
file is staged into the package at publish time (never committed here), so the
package cannot drift from the module.

## Install

GitHub Packages requires authentication even for public packages, so consumers
need the scope routed and a token available:

```ini
# .npmrc (committed)
@melodic-software:registry=https://npm.pkg.github.com
```

```bash
npm install --save-dev @melodic-software/tsconfig
```

In GitHub Actions, `GITHUB_TOKEN` works via `actions/setup-node`'s
`registry-url`; locally, use a token with `read:packages`.

## Use

```jsonc
// tsconfig.json
{
  "extends": "@melodic-software/tsconfig/tsconfig.json",
  "include": ["src"]
}
```

The base deliberately carries no project scope (`include`/`outDir`/`target`
runtime specifics) — supply those per project.

## Changing the rules

This package is read-only downstream. Change
`modules/typescript/tsconfig.json` upstream in
[melodic-software/standards](https://github.com/melodic-software/standards) and
bump the version in `packages/tsconfig/package.json`; the publish workflow does
the rest.
