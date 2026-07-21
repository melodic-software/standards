# Package lifecycle harness

`package-lifecycle.mjs` compares the actual `npm pack` payload for each
publishable component with the same component at a Git base reference. A packed
payload change must carry a strictly greater stable semantic version. Package
identity changes, version regressions, and prerelease versions fail. A new
package may begin on a stable `0.x` version.

With no package directories on the command line, the harness discovers every
non-private `components/*/package.json` that declares the approved GitHub
Packages registry. The publish workflow matrix and component path triggers are
tested against that same manifest-derived inventory. Explicit package
directories remain available for focused local checks.

The comparison is local and deterministic: it exports the base tree with Git,
packs both trees with npm, and never reads a package registry. The version value
itself is normalized during payload comparison so a valid version-only release
is distinguishable from unversioned payload drift.

Run the unit and real-pack contract tests with:

```console
npm run test:packages
```

Run the PR gate against the pull request base commit with:

```console
PACKAGE_BASE_REF=<full-base-commit-sha> node harness/packages/package-lifecycle.mjs
```

The baseline must be a nonzero full commit SHA and must exist in the checkout;
CI fetches complete history and fails closed when that evidence is unavailable.

The behavior follows npm's definitions of [package identity][1], [`npm
pack`][2], and [semantic versioning][3]. Version comparison uses npm's maintained
[`semver` implementation][4], pinned exactly in the root lockfile.

[1]: https://docs.npmjs.com/cli/v11/configuring-npm/package-json/#name
[2]: https://docs.npmjs.com/cli/v11/commands/npm-pack/
[3]: https://docs.npmjs.com/about-semantic-versioning/
[4]: https://github.com/npm/node-semver
