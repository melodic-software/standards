# Typos

Source-aware spell checking with [Typos](https://github.com/crate-ci/typos).
The exported payload is the root-canonical [`_typos.toml`](../../_typos.toml).

Because Typos has no native config layering, the managed config carries the
small organization-wide vocabulary union. One-off false positives use the
documented inline ignore directives. A broadly valid word goes upstream; a
repository with incompatible vocabulary policy owns the complete component.

`fixtures/` and `typos.test.sh` prove clean and failing input plus every blessed
inline directive. Typos exits `2` for spelling findings; the contract test
distinguishes that from engine errors.
