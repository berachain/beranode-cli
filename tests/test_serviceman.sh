#!/usr/bin/env bash
################################################################################
# test_serviceman.sh - Tests for launchd / systemd serviceman helpers
################################################################################

cd "$(dirname "$0")"
source test_framework.sh
source ../src/lib/logging.sh
source ../src/lib/constants.sh
source ../src/lib/serviceman.sh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

# Isolate LaunchAgents / systemd user unit writes from the developer machine.
export HOME="${TEST_ROOT}/home"
export XDG_CONFIG_HOME="${HOME}/.config"
mkdir -p "${HOME}/Library/LaunchAgents"
mkdir -p "${XDG_CONFIG_HOME}/systemd/user"

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
assert_contains "$label" ".${hash_a}." "label includes path hash to avoid service collisions"

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

test_suite "systemd ExecStart quoting"

assert_equals '"/usr/bin/beacond"' "$(serviceman_systemd_quote '/usr/bin/beacond')" "quotes a plain path"
assert_equals '"a\"b"' "$(serviceman_systemd_quote 'a"b')" "escapes double quotes"
assert_equals '"$$HOME"' "$(serviceman_systemd_quote '$HOME')" "doubles dollar signs for systemd"
assert_equals '"%%h"' "$(serviceman_systemd_quote '%h')" "doubles percent signs for systemd specifiers"
assert_equals '"/tmp/with space"' "$(serviceman_systemd_quote '/tmp/with space')" "quotes paths with spaces"

test_suite "systemd unit generation"

unit_path=$(serviceman_write_unit \
	"${BERADIR}" \
	"${label}" \
	"${working}" \
	"${log_file}" \
	"/tmp/beacond" start --home "${working}")

assert_file_exists "${unit_path}" "writes systemd user unit"
repo_unit=$(serviceman_repo_unit_path "${BERADIR}" "${label}")
assert_file_exists "${repo_unit}" "writes a unit copy under beranodes/services"
runner=$(serviceman_systemd_runner_path "${BERADIR}")
assert_file_exists "${runner}" "writes the journald tee runner"
assert_success "test -x '${runner}'" "tee runner is executable"
runner_body=$(cat "${runner}")
assert_contains "$runner_body" 'exec > >(tee -a "${log_file}")' "runner tees stdout into the log file"
assert_contains "$runner_body" 'exec "$@"' "runner execs the node binary so systemd MainPID is beacond/reth"

unit_body=$(cat "${unit_path}")
assert_contains "$unit_body" "SyslogIdentifier=${label}" "unit tags journald with the job label"
assert_contains "$unit_body" "StandardOutput=journal" "unit sends stdout to journald"
assert_contains "$unit_body" "StandardError=journal" "unit sends stderr to journald"
assert_contains "$unit_body" "Restart=always" "unit restarts on crash (KeepAlive equivalent)"
assert_contains "$unit_body" "RestartSec=${SERVICEMAN_SYSTEMD_RESTART_SEC}" "unit throttle matches restart sec"
assert_contains "$unit_body" "WantedBy=default.target" "unit is enabled for the user default target"
assert_contains "$unit_body" "$(serviceman_systemd_quote "${runner}")" "ExecStart runs the tee runner"
assert_contains "$unit_body" "$(serviceman_systemd_quote "${log_file}")" "ExecStart passes the beranodes log file"
assert_contains "$unit_body" "$(serviceman_systemd_quote "/tmp/beacond")" "ExecStart includes the binary"
assert_contains "$unit_body" "$(serviceman_systemd_quote "start")" "ExecStart includes start"
assert_equals "${XDG_CONFIG_HOME}/systemd/user/${label}.service" "${unit_path}" "user unit path uses XDG systemd dir"

test_suite "Backend and platform gate"

if [[ "${IS_MACOS}" == "true" ]]; then
	assert_equals "launchd" "$(serviceman_backend)" "macOS backend is launchd"
	assert_equals "launchd (user LaunchAgents)" "$(serviceman_backend_description)" "macOS description names launchd"
	assert_success 'serviceman_require' "launchd is available on this macOS host"
	assert_failure 'serviceman_require_systemd' "systemd require is refused on macOS"
	assert_equals "${BERADIR}/services/launchd.json" "$(serviceman_manifest_path "${BERADIR}")" "macOS manifest is launchd.json"
elif [[ "${IS_LINUX}" == "true" ]]; then
	assert_equals "systemd" "$(serviceman_backend)" "Linux backend is systemd"
	assert_equals "systemd (user units) + journald" "$(serviceman_backend_description)" "Linux description names systemd and journald"
	assert_equals "${BERADIR}/services/systemd.json" "$(serviceman_manifest_path "${BERADIR}")" "Linux manifest is systemd.json"
	if serviceman_systemd_binaries_present && serviceman_systemd_is_init && serviceman_journald_is_running && serviceman_systemd_user_available; then
		assert_success 'serviceman_require' "systemd and journald are available on this Linux host"
		assert_success 'serviceman_require_systemd' "systemd require succeeds when tools are present"
	else
		assert_failure 'serviceman_require' "serviceman is refused without systemd/journald"
		assert_failure 'serviceman_require_systemd' "systemd require fails when systemd/journald are missing"
	fi
else
	assert_equals "" "$(serviceman_backend)" "unknown OS has no serviceman backend"
	assert_failure 'serviceman_require' "serviceman is refused on unsupported OS"
fi

print_results
