#!/usr/bin/env bash
################################################################################
# test_serviceman.sh - Tests for launchd serviceman helpers
################################################################################

cd "$(dirname "$0")"
source test_framework.sh
source ../src/lib/logging.sh
source ../src/lib/constants.sh
source ../src/lib/serviceman.sh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

# Isolate LaunchAgents writes from the developer machine.
export HOME="${TEST_ROOT}/home"
mkdir -p "${HOME}/Library/LaunchAgents"

BERADIR="${TEST_ROOT}/beranodes"
mkdir -p "${BERADIR}/logs" "${BERADIR}/services" "${BERADIR}/nodes/0-rpc-pruned/beacond"

test_suite "XML escape"

assert_equals "a&amp;b" "$(serviceman_xml_escape 'a&b')" "escapes ampersand first"
assert_equals "&lt;tag&gt;" "$(serviceman_xml_escape '<tag>')" "escapes angle brackets"
assert_equals "&quot;quoted&quot;" "$(serviceman_xml_escape '"quoted"')" "escapes double quotes"

test_suite "Label sanitization and identity"

assert_equals "fancy-read-river" "$(serviceman_sanitize_label_part 'Fancy-Read-River')" "lowercases moniker"
assert_equals "my-node" "$(serviceman_sanitize_label_part 'my node')" "replaces spaces"
assert_equals "node" "$(serviceman_sanitize_label_part '@@@')" "fallback when empty after sanitize"

label=$(serviceman_label "${BERADIR}" "fancy-read-river" 0 "beacond")
assert_not_empty "$label" "label is non-empty"
assert_contains "$label" "com.berachain.beranode." "label uses reverse-DNS prefix"
assert_contains "$label" ".fancy-read-river.0.beacond" "label includes moniker, index, and component"

hash_a=$(serviceman_path_hash "$(serviceman_abspath "${BERADIR}")")
label2=$(serviceman_label "${BERADIR}" "fancy-read-river" 0 "beacond")
assert_equals "$label" "$label2" "label is stable for the same path"
assert_contains "$label" ".${hash_a}." "label includes path hash to avoid LaunchAgent collisions"

test_suite "Plist generation"

log_file="${BERADIR}/logs/fancy-read-river-0-rpc-pruned-beacond.log"
working="${BERADIR}/nodes/0-rpc-pruned/beacond"
plist_path=$(serviceman_write_plist \
	"${BERADIR}" \
	"${label}" \
	"${working}" \
	"${log_file}" \
	"/tmp/beacond" start --home "${working}")

assert_file_exists "${plist_path}" "writes user LaunchAgent plist"
repo_plist=$(serviceman_repo_plist_path "${BERADIR}" "${label}")
assert_file_exists "${repo_plist}" "writes a copy under beranodes/services"

plist_body=$(cat "${plist_path}")
assert_contains "$plist_body" "<string>${label}</string>" "plist Label matches job label"
assert_contains "$plist_body" "<key>KeepAlive</key>" "plist enables KeepAlive"
assert_contains "$plist_body" "<string>${log_file}</string>" "plist StandardOutPath uses beranodes/logs"
assert_contains "$plist_body" "<string>/tmp/beacond</string>" "plist ProgramArguments include the binary"
assert_contains "$plist_body" "<string>start</string>" "plist ProgramArguments include start"

test_suite "Platform gate"

if [[ "${IS_MACOS}" == "true" ]]; then
	assert_success 'serviceman_require_launchd' "launchd is available on this macOS host"
else
	assert_failure 'serviceman_require_launchd' "serviceman is refused off macOS"
fi

print_results
