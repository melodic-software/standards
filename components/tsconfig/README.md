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

The package declares TypeScript `>=5 <8`. TypeScript 5.0 is the compatibility
floor because it introduced `verbatimModuleSyntax`. The peer range is the
intended compiler-config compatibility range; it makes no compatibility claim
for frameworks or tools that consume TypeScript compiler APIs. CI runs the
packed consumer contract against exact representative maintained stable patches
for every declared major: 5.9.3, 6.0.3, and 7.0.2. See the official
[TypeScript 5.0 release notes][1].

`fixtures/` and `tsconfig.test.sh` pack and install the package in an isolated
consumer, then prove strict and `noUncheckedIndexedAccess` diagnostics. The
publish workflow packs this directory directly and requires a version bump
whenever the complete packed payload differs from an already-published version.

[1]: https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-0.html#--verbatimmodulesyntax
