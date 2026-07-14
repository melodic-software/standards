# Go analyzer evaluation

Use golangci-lint v2.12.2 with the reviewed six-linter allowlist on native
Windows and Linux. Direct Staticcheck remains the simpler focused analyzer, but
the required contract also includes `errcheck`, `govet`, `ineffassign`,
`nolintlint`, and a separately integrated `unused` analyzer. The aggregator is
therefore the better fit despite its larger upgrade surface and modest runtime
overhead.

## Reproduction identity and protocol

- Source: `melodic-software/ci-runner` commit
  `97325c9f7aaa88db08d4166a21fc72d2ada38f00`, clean detached checkout with
  `core.autocrlf=false`.
- Go: 1.26.5 with command-local `GOTOOLCHAIN=local`.
- golangci-lint: 2.12.2; embedded Staticcheck and direct
  `honnef.co/go/tools`: v0.7.0, authenticated module sum
  `h1:w6WUp1VbkqPEgLz4rkBzH/CSU6HkoqNLp6GstyTx3lU=`.
- Linux: official `golang:1.26.5` image at
  `sha256:d52df9c279840adf958d017ebb275651ed8338b953d39817bc3633a2e6b1bbcc`.
- Windows: native X64 on Microsoft Windows 10.0.26200.

The exact timed invocations were:

```text
golangci-lint run --config configs/golangci-full.yml --timeout=10m --issues-exit-code=42 --max-issues-per-linter=0 --max-same-issues=0 ./...
golangci-lint run --config configs/golangci-staticcheck-only.yml --timeout=10m --issues-exit-code=42 --max-issues-per-linter=0 --max-same-issues=0 ./...
staticcheck ./...
staticcheck -checks=all ./...
```

Tools and modules were downloaded before timing. The module cache was warm;
each of three trials used an empty `GOCACHE`, and each golangci trial also used
an empty `GOLANGCI_LINT_CACHE`. Findings were byte-identical across all three
trials for every OS/tool combination. The retained external evidence bundle
contains configs, scripts, raw output, timings, tool identities, and downloads;
its core archive SHA-256 is
`d77b3f9f09c2e0f27fc35738228f4a68476028d600d3a16ccfa6ea57f20d1707`
and its evidence manifest SHA-256 is
`1ce05b833a1176a5cfc1e77a6a62b60f6a8a22d94748b5e4ff51e200330332b3`.

## Findings and platform coverage

| Host | Full total | errcheck | staticcheck | ineffassign | unused | govet | nolintlint |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Linux amd64 | 199 | 173 | 23 | 2 | 1 | 0 | 0 |
| Windows amd64 | 207 | 178 | 26 | 2 | 1 | 0 | 0 |

Direct Staticcheck default reported 21 findings on Linux (SA1019 9, ST1005 11,
U1000 1) and 24 on Windows (SA1019 9, ST1005 14, U1000 1). The integrated
Staticcheck results add four QF1008 findings. The full contract delegates U1000
to `unused`, and golangci coalesces two identical same-line SA1019 calls without
losing the source line or diagnostic category. Direct `-checks=all` is broader
than Staticcheck's default and was retained only as supplemental scope evidence.

Normalized full-contract output contained 196 common findings, 11 Windows-only
findings, and 3 Linux-only findings. The difference is real build-tag/platform
coverage, supporting native analyzer execution on both operating systems.

## Runtime and maintenance tradeoff

| OS/tool | Cold-cache trials (ms) | Median (ms) |
| --- | --- | ---: |
| Linux full golangci | 20,939; 19,297; 19,226 | 19,297 |
| Linux direct default | 23,886; 17,234; 10,432 | 17,234 |
| Windows full golangci | 25,851; 22,041; 26,105 | 25,851 |
| Windows direct default | 18,096; 16,940; 16,720 | 16,940 |

The full contract costs about 2.1 seconds at the Linux median and 8.9 seconds at
the Windows median on this repository. Direct Staticcheck has a smaller
dependency/configuration surface when only its diagnostics are required.
golangci-lint integrates independently versioned analyzers and can add findings
in minor releases, so upgrades carry more risk. Exact release pins, official
checksums, `linters.default: none`, six explicit names, config verification, and
a fresh cross-platform consumer baseline bound that risk while keeping one
invocation and one suppression policy.

## Supply-chain record

| Artifact | Verified SHA-256 |
| --- | --- |
| `go1.26.5.windows-amd64.zip` | `97e6b2a833b6d89f9ff17d25419ac0a7e3b482a044e9ab18cdef834bd834fd38` |
| `golangci-lint-2.12.2-linux-amd64.tar.gz` | `8df580d2670fed8fa984aac0507099af8df275e665215f5c7a2ae3943893a553` |
| `golangci-lint-2.12.2-windows-amd64.zip` | `bd42e3ebc8cb4ececb86941983baaf1dc221bbb04d838e94ce63b49cc91e02bb` |

The vulnerability lane separately pins `golang.org/x/vuln` v1.6.0, module sum
`h1:FeMO9Rm/HwyduOztbvKcOw+zvDEPr4I4aQNSfevFcKY=`, at commit
`19b0bb6a272792b9afa8a6983c3e9b9a1816947f`.

## Primary sources

- [Go downloads metadata](https://go.dev/dl/?mode=json&include=all)
- [golangci-lint v2.12.2 release](https://github.com/golangci/golangci-lint/releases/tag/v2.12.2)
- [golangci-lint CI installation guidance](https://golangci-lint.run/docs/welcome/install/ci/)
- [golangci-lint versioning policy](https://golangci-lint.run/docs/product/roadmap/)
- [golangci-lint linter configuration](https://golangci-lint.run/docs/linters/configuration/)
- [Staticcheck configuration](https://staticcheck.dev/docs/configuration/)
- [Staticcheck 2026.1 release notes](https://staticcheck.dev/changes/2026.1/)
- [Go module checksum record](https://sum.golang.org/lookup/honnef.co/go/tools@v0.7.0)
- [Go vulnerability management](https://go.dev/doc/security/vuln/)
