# TypeScript base

Strict, runtime-neutral TypeScript compiler defaults. The sync delivers
`tsconfig.json` to each target at `.github/standards/tsconfig/tsconfig.json`
(the `tsconfig` component in `distribution/sync-manifest.yml`).

Extend it by relative path from a project config:

```json
{
  "extends": "./.github/standards/tsconfig/tsconfig.json",
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

The base supports TypeScript 5.0 through 7.x. TypeScript 5.0 is the floor
because it introduced `verbatimModuleSyntax`. The range is a compiler-config
compatibility claim only; it makes none for frameworks or tools that consume
TypeScript compiler APIs. CI runs the contract test against exact
representative maintained stable patches for every supported major: 5.9.3,
6.0.3, and 7.0.2. See the official [TypeScript 5.0 release notes][1].

`fixtures/` and `tsconfig.test.sh` extend the base by relative path from an
isolated consumer, then prove strict and `noUncheckedIndexedAccess`
diagnostics.

[1]: https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-0.html#--verbatimmodulesyntax
