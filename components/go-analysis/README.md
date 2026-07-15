# Go analysis

Strict, low-noise Go verification built from the official Go toolchain and
golangci-lint v2.12.2. The exported payload is the root-canonical
[`.golangci.yml`](../../.golangci.yml); this source slice owns its contract
fixtures, tests, and [analyzer evaluation](analyzer-evaluation.md).

## Analyzer policy

The [official v2 config][4] opts out of golangci-lint's moving default sets with
`linters.default: none` and enables exactly these reviewed analyzers:

- `errcheck` detects discarded error returns;
- `govet` runs the Go toolchain's suspicious-construct analyzers;
- `ineffassign` detects assignments whose values are never observed;
- `nolintlint` enforces the suppression contract below;
- `staticcheck` supplies Staticcheck's correctness, simplification, and style
  suites through the maintained aggregator; and
- `unused` detects unreachable declarations and values.

Do not replace the allowlist with `standard` or `all`: those names change as
golangci-lint changes. Do not run a second direct Staticcheck lane over the same
packages. The [recorded A/B](analyzer-evaluation.md) selected the aggregator so
one versioned invocation can enforce the exact reviewed set on both supported
operating systems.

Every `//nolint` directive names one or more specific linters and includes a
non-empty reason, for example:

```go
legacyCall() //nolint:errcheck // Compatibility is required until API v1 is retired.
```

Keep the directive on the smallest affected line. `nolintlint` rejects blanket,
unexplained, and unused directives; configuration exclusions and broad
baselines are not an accepted substitute for fixing findings. These are the
analyzer's [documented suppression controls][5]. Repositories own their Go
version and build tags, which the shared configuration deliberately does not
override.

## Execution contract

The reusable workflow in `melodic-software/ci-workflows` owns installation
according to the project's [CI guidance][6],
exact tool pins, checksums, caches, and invocation. It validates the config with
`golangci-lint config verify` before running analysis. Analyzer coverage runs on
both Linux and Windows because the evaluation found real build-tag-dependent
diagnostic differences.

The surrounding Go quality contract also runs:

- [`gofmt -l`][1], [`go mod tidy -diff`][2], and [`go mod verify`][3];
- ordinary `go test ./...` on Windows and `go test -race ./...` on Linux, in
  accordance with the Go team's [race-detector guidance][7];
- committed fuzz seeds during pull-request tests, plus active fuzzing for 30
  seconds per target in the weekly and manually dispatched lane; and
- the checksum-verified `govulncheck` v1.6.0 binary against the official
  [Go vulnerability database][8].

A vulnerability finding is a product failure. A database, network, tool, or
result-parsing failure is an infrastructure failure that must be rerun; it must
never be reported as a clean scan. The reusable workflow owns that
classification because the component test is hermetic.

`go-analysis.test.sh` proves the exact config bytes, `config verify`, good and
bad analyzer fixtures, the suppression contract, formatting, module hygiene,
vetting, ordinary tests, and race tests when the host supports them. A missing
Go toolchain or analyzer produces an explicit suite skip locally; CI installs
both exact versions and therefore cannot satisfy the contract by skipping.

[1]: https://pkg.go.dev/cmd/gofmt
[2]: https://go.dev/ref/mod#go-mod-tidy
[3]: https://go.dev/ref/mod#go-mod-verify
[4]: https://golangci-lint.run/docs/configuration/file/
[5]: https://golangci-lint.run/docs/linters/configuration/#nolintlint
[6]: https://golangci-lint.run/docs/welcome/install/ci/
[7]: https://go.dev/doc/articles/race_detector
[8]: https://go.dev/doc/security/vuln/
