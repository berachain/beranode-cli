#!/usr/bin/env bash
################################################################################
# test_download.sh - Tests for download.sh asset URL matching and extraction
################################################################################

cd "$(dirname "$0")"
source test_framework.sh

DEBUG_MODE="${DEBUG_MODE:-false}"
source ../src/lib/logging.sh
source ../src/lib/constants.sh
source ../src/lib/download.sh

BEACOND_RELEASE_JSON='{
  "tag_name": "v1.4.1",
  "assets": [
    {"name": "beacond-v1.4.1-darwin-arm64.tar.gz", "browser_download_url": "https://example.com/beacond-darwin.tar.gz"},
    {"name": "beacond-v1.4.1-darwin-arm64.tar.gz.sig", "browser_download_url": "https://example.com/beacond-darwin.tar.gz.sig"},
    {"name": "beacond-v1.4.1-linux-amd64.tar.gz", "browser_download_url": "https://example.com/beacond-linux-amd64.tar.gz"},
    {"name": "beacond-v1.4.1-linux-arm64.tar.gz", "browser_download_url": "https://example.com/beacond-linux-arm64.tar.gz"}
  ]
}'

BERARETH_RELEASE_JSON='{
  "tag_name": "v1.4.4",
  "assets": [
    {"name": "bera-reth-v1.4.4-aarch64-apple-darwin.tar.gz", "browser_download_url": "https://example.com/bera-reth-darwin.tar.gz"},
    {"name": "bera-reth-v1.4.4-aarch64-apple-darwin.tar.gz.asc", "browser_download_url": "https://example.com/bera-reth-darwin.tar.gz.asc"},
    {"name": "bera-reth-v1.4.4-aarch64-unknown-linux-gnu.tar.gz", "browser_download_url": "https://example.com/bera-reth-linux-arm64.tar.gz"},
    {"name": "bera-reth-v1.4.4-x86_64-unknown-linux-gnu.tar.gz", "browser_download_url": "https://example.com/bera-reth-linux-amd64.tar.gz"}
  ]
}'

test_suite "Release asset name patterns"

assert_contains "$(release_asset_name_patterns darwin-arm64)" "darwin-arm64" "darwin-arm64 includes Go asset name"
assert_contains "$(release_asset_name_patterns darwin-arm64)" "aarch64-apple-darwin" "darwin-arm64 includes Rust target triple"
assert_contains "$(release_asset_name_patterns linux-amd64)" "linux-amd64" "linux-amd64 includes Go asset name"
assert_contains "$(release_asset_name_patterns linux-amd64)" "x86_64-unknown-linux-gnu" "linux-amd64 includes Rust target triple"
assert_contains "$(release_asset_name_patterns linux-arm64)" "linux-arm64" "linux-arm64 includes Go asset name"
assert_contains "$(release_asset_name_patterns linux-arm64)" "aarch64-unknown-linux-gnu" "linux-arm64 includes Rust target triple"

test_suite "extract_download_url beacond (GOOS-GOARCH)"

assert_equals "https://example.com/beacond-darwin.tar.gz" \
	"$(extract_download_url "$BEACOND_RELEASE_JSON" "darwin-arm64")" \
	"beacond darwin-arm64 URL"
assert_equals "https://example.com/beacond-linux-amd64.tar.gz" \
	"$(extract_download_url "$BEACOND_RELEASE_JSON" "linux-amd64")" \
	"beacond linux-amd64 URL"
assert_equals "https://example.com/beacond-linux-arm64.tar.gz" \
	"$(extract_download_url "$BEACOND_RELEASE_JSON" "linux-arm64")" \
	"beacond linux-arm64 URL"

test_suite "extract_download_url bera-reth (cargo target triples)"

assert_equals "https://example.com/bera-reth-darwin.tar.gz" \
	"$(extract_download_url "$BERARETH_RELEASE_JSON" "darwin-arm64")" \
	"bera-reth aarch64-apple-darwin matches darwin-arm64"
assert_equals "https://example.com/bera-reth-linux-amd64.tar.gz" \
	"$(extract_download_url "$BERARETH_RELEASE_JSON" "linux-amd64")" \
	"bera-reth x86_64-unknown-linux-gnu matches linux-amd64"
assert_equals "https://example.com/bera-reth-linux-arm64.tar.gz" \
	"$(extract_download_url "$BERARETH_RELEASE_JSON" "linux-arm64")" \
	"bera-reth aarch64-unknown-linux-gnu matches linux-arm64"

test_suite "extract_download_url ignores captured [INFO] logs"

# fetch_github_release used to log to stdout, so command substitution captured:
#   [INFO] Checking binary from: ...
#   [INFO] Using version: v1.4.1
#   { ...release json... }
# jq then parsed "[INFO]" as an array and failed with
# "Invalid numeric literal at line 1, column 2".
PREFIXED_BEACOND=$'[INFO] Checking binary from: https://api.github.com/repos/berachain/beacon-kit/releases/latest\n[INFO] Using version: v1.4.1\n'"$BEACOND_RELEASE_JSON"
PREFIXED_BERARETH=$'[INFO] Checking binary from: https://api.github.com/repos/berachain/bera-reth/releases/latest\n[INFO] Using version: v1.4.4\n'"$BERARETH_RELEASE_JSON"

assert_equals "https://example.com/beacond-darwin.tar.gz" \
	"$(extract_download_url "$PREFIXED_BEACOND" "darwin-arm64")" \
	"beacond URL still found when payload is prefixed with [INFO] logs"
assert_equals "https://example.com/bera-reth-darwin.tar.gz" \
	"$(extract_download_url "$PREFIXED_BERARETH" "darwin-arm64")" \
	"bera-reth URL still found when payload is prefixed with [INFO] logs"

test_suite "extract_download_url misses"

assert_failure 'extract_download_url "{\"tag_name\":\"v1.0.0\",\"assets\":[]}" "darwin-arm64"' \
	"empty assets list fails"
assert_failure 'extract_download_url "$BEACOND_RELEASE_JSON" "linux-ppc64"' \
	"unsupported arch fails"

test_suite "install_extracted_binary naming conventions"

TMP_BIN=$(mktemp -d)

# beacond: archive stem is the extracted filename
echo "beacond-bin" > "${TMP_BIN}/beacond-v1.4.1-darwin-arm64"
chmod +x "${TMP_BIN}/beacond-v1.4.1-darwin-arm64"
assert_success 'install_extracted_binary "'"$TMP_BIN"'" beacond beacond-v1.4.1-darwin-arm64.tar.gz' \
	"renames beacond archive-stem binary"
assert_file_exists "${TMP_BIN}/beacond" "beacond binary installed"
assert_failure 'test -f "'"${TMP_BIN}"'/beacond-v1.4.1-darwin-arm64"' \
	"archive-stem file is moved away"

# bera-reth: tarball contains a file named bera-reth
echo "reth-bin" > "${TMP_BIN}/bera-reth"
chmod +x "${TMP_BIN}/bera-reth"
assert_success 'install_extracted_binary "'"$TMP_BIN"'" bera-reth bera-reth-v1.4.4-aarch64-apple-darwin.tar.gz' \
	"keeps bera-reth cargo binary name"
assert_file_exists "${TMP_BIN}/bera-reth" "bera-reth binary still present"
assert_success 'test -x "'"${TMP_BIN}"'/bera-reth"' "bera-reth is executable"

# missing extracted file
EMPTY_BIN=$(mktemp -d)
assert_failure 'install_extracted_binary "'"$EMPTY_BIN"'" bera-reth bera-reth-v1.4.4-aarch64-apple-darwin.tar.gz' \
	"fails when extracted binary is missing"

rm -rf "$TMP_BIN" "$EMPTY_BIN"

print_results
