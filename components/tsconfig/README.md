# `@melodic-software/tsconfig`

Strict, runtime-neutral TypeScript compiler defaults. This component directory
is both the source slice and npm package: `tsconfig.json` is authored, tested,
and published here with no staging copy.

Install from GitHub Packages and extend the package from a project config:

```json
{
  "extends": "@melodic-software/tsconfig/tsconfig.json",
  "compilerOptions": {
    "target": "ES2024",
    "module": "NodeNext",
    "moduleResolution": "NodeNext"
  },
  "include": ["src", "tests"]
}
```

The base owns strict type-safety switches but deliberately omits runtime floor,
module environment, source scope, output, and `noEmit`. It also omits unused
symbol checks because Biome owns those findings.

`fixtures/` and `tsconfig.test.sh` prove strict and
`noUncheckedIndexedAccess` diagnostics. The publish workflow packs this
directory directly and requires a version bump whenever the complete packed
payload differs from an already-published version.
