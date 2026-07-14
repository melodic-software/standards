#!/usr/bin/env bash
# Tests the Go analysis component: official Go checks plus the exact root
# golangci-lint v2 contract accept good code and reject focused violations.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

command -v go >/dev/null 2>&1 || skip_suite 'Go toolchain not installed'
command -v gofmt >/dev/null 2>&1 || skip_suite 'gofmt not installed'
command -v golangci-lint >/dev/null 2>&1 || skip_suite 'golangci-lint not installed'

go_version="$(go env GOVERSION)"
require_min_version Go "${go_version#go}" 1.23

config="$root/.golangci.yml"
expected_config='version: "2"

linters:
  default: none
  enable:
    - errcheck
    - govet
    - ineffassign
    - nolintlint
    - staticcheck
    - unused
  settings:
    nolintlint:
      allow-unused: false
      require-explanation: true
      require-specific: true'
assert_eq 'golangci-lint config is the exact reviewed allowlist' \
  "$expected_config" "$(cat "$config")"

version_out="$(golangci-lint version 2>&1)"
rc=$?
assert_exit 'golangci-lint reports its version' 0 "$rc"
assert_contains 'golangci-lint uses the approved release' "$version_out" '2.12.2'

out="$(golangci-lint config verify --config "$config" 2>&1)"
rc=$?
assert_exit 'golangci-lint accepts the v2 config' 0 "$rc"
assert_silent 'config verification has no diagnostics' "$out"

good="$root/components/go-analysis/fixtures/good"
bad_format="$root/components/go-analysis/fixtures/bad/format/violations.go"
bad_tidy="$root/components/go-analysis/fixtures/bad/tidy"
bad_vet="$root/components/go-analysis/fixtures/bad/vet"
bad_analyzer="$root/components/go-analysis/fixtures/bad/analyzer"
bad_suppression_blanket="$root/components/go-analysis/fixtures/bad/suppression-blanket"
bad_suppression_reason="$root/components/go-analysis/fixtures/bad/suppression-reason"
bad_suppression_unused="$root/components/go-analysis/fixtures/bad/suppression-unused"

out="$(gofmt -l "$good")"
assert_silent 'gofmt: good fixture is formatted' "$out"

out="$(gofmt -l "$bad_format")"
assert_contains 'gofmt: bad fixture is reported' "$out" 'violations.go'

out="$(cd "$good" && go mod tidy -diff 2>&1)"
rc=$?
assert_exit 'go mod tidy -diff: good module is tidy' 0 "$rc"
assert_silent 'go mod tidy -diff: good module has no diff' "$out"

out="$(cd "$bad_tidy" && GOPROXY=off go mod tidy -diff 2>&1)"
rc=$?
assert_nonzero 'go mod tidy -diff: stale module metadata fails' "$rc"
assert_contains 'go mod tidy -diff: stale requirement is removed' "$out" 'example.com/unused'

(cd "$good" && go mod verify >/dev/null 2>&1)
rc=$?
assert_exit 'go mod verify: good module verifies' 0 "$rc"

(cd "$good" && go vet ./... >/dev/null 2>&1)
rc=$?
assert_exit 'go vet: good fixture passes' 0 "$rc"

out="$(cd "$bad_vet" && go vet ./... 2>&1)"
rc=$?
assert_nonzero 'go vet: suspicious Printf call fails' "$rc"
assert_contains 'go vet: Printf diagnostic is visible' "$out" 'format %d'

(cd "$good" && go test ./... >/dev/null 2>&1)
rc=$?
assert_exit 'go test: good fixture passes' 0 "$rc"

cc="$(go env CC)"
if [[ "$(go env CGO_ENABLED)" == 1 ]] && command -v "$cc" >/dev/null 2>&1; then
  (cd "$good" && go test -race ./... >/dev/null 2>&1)
  rc=$?
  assert_exit 'go test -race: good fixture passes on a supported host' 0 "$rc"
else
  skip_case 'go test -race requires cgo and the configured C compiler'
fi

out="$(cd "$good" && golangci-lint run --config "$config" ./... 2>&1)"
rc=$?
assert_exit 'golangci-lint: good fixture and explained suppression pass' 0 "$rc"

out="$(cd "$bad_analyzer" && golangci-lint run --config "$config" ./... 2>&1)"
rc=$?
assert_nonzero 'golangci-lint: analyzer violations fail' "$rc"
for linter in errcheck ineffassign staticcheck unused; do
  assert_contains "golangci-lint: $linter diagnostic is visible" "$out" "($linter)"
done

out="$(cd "$bad_vet" && golangci-lint run --config "$config" ./... 2>&1)"
rc=$?
assert_nonzero 'golangci-lint: govet violation fails' "$rc"
assert_contains 'golangci-lint: govet diagnostic is visible' "$out" '(govet)'

out="$(cd "$bad_suppression_blanket" && golangci-lint run --config "$config" ./... 2>&1)"
rc=$?
assert_nonzero 'nolintlint: blanket suppression fails' "$rc"
assert_contains 'nolintlint: blanket diagnostic is visible' "$out" '(nolintlint)'

out="$(cd "$bad_suppression_reason" && golangci-lint run --config "$config" ./... 2>&1)"
rc=$?
assert_nonzero 'nolintlint: unexplained suppression fails' "$rc"
assert_contains 'nolintlint: explanation diagnostic is visible' "$out" '(nolintlint)'

out="$(cd "$bad_suppression_unused" && golangci-lint run --config "$config" ./... 2>&1)"
rc=$?
assert_nonzero 'nolintlint: unused suppression fails' "$rc"
assert_contains 'nolintlint: unused diagnostic is visible' "$out" '(nolintlint)'

[[ $FAILED -eq 0 ]] || exit 1
