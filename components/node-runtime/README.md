# Node runtime

The organization-wide Node.js runtime pin. The exported payload is the
root-canonical [`.node-version`](../../.node-version), discovered by fnm,
setup-node, and other version managers.

This component owns only the runtime floor. It does not share `package.json`,
package-manager choices, dependencies, scripts, or repository-specific Node
behavior. Managed consumers do not edit the pin; upgrade it here, validate the
fleet, and let synchronization propagate the exact file.

The root location is the canonical source, so this source slice needs no
duplicate config, fixture, or test.
