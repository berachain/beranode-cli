#!/bin/bash
# =============================================================================
# Test Suite for beranode status command
# =============================================================================
# Tests the status command against different configurations:
#   Test 1: Docker mode, 2 validators (live - uses current running containers)
#   Test 2: Docker mode, 1 validator (synthetic config)
#   Test 3: Local mode, 1 validator (synthetic config)
#   Test 4: Docker mode, 1 validator + 1 full node (synthetic config)
#   Test 5: --help flag
#   Test 6: Missing config file
#   Test 7: --beranodes-dir option
#   Test 8: Verbose mode, live
#   Test 9: Verbose mode, synthetic
#   Test 10: Verbose short flag -v
#   Test 11: Chain ID in header
#   Test 12: Block age column
#   Test 13: EL block shown as decimal
#   Test 14: --watch/--interval flag parsing
#   Test 15: --help mentions watch/interval
#
# Usage: ./tests/test_status.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
log_header()  { echo ""; echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${YELLOW}$1${NC}"; echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"; }

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_success "$1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_error "$1"
}

# Create a synthetic beranodes.config.json for testing
# Arguments: $1=output_dir, $2=mode, $3=validators, $4=full_nodes
create_test_config() {
    local output_dir="$1"
    local mode="$2"
    local validators="$3"
    local full_nodes="${4:-0}"
    local total=$((validators + full_nodes))

    mkdir -p "${output_dir}"

    # Build node array
    local nodes_json="["
    local node_index=0

    # Add validators
    # Use high ports (19xxx / 49xxx) to avoid conflicts with real running containers
    for ((v = 0; v < validators; v++)); do
        local el_port=$((19545 + v * 100))
        local cl_port=$((49657 + v * 1000))
        local beacond_port=$((13500 + v * 100))
        [[ $node_index -gt 0 ]] && nodes_json+=","
        nodes_json+=$(cat <<NODEEOF
{
    "role": "validator",
    "moniker": "test-node-val-${v}",
    "network": "devnet",
    "wallet_address": "0x0000000000000000000000000000000000000001",
    "ethrpc_port": ${cl_port},
    "ethp2p_port": $((cl_port - 1)),
    "ethproxy_port": $((cl_port + 1)),
    "el_ethrpc_port": ${el_port},
    "el_ws_port": $((el_port + 1)),
    "el_authrpc_port": $((el_port + 6)),
    "el_eth_port": $((30303 + v * 100)),
    "el_prometheus_port": $((9101 + v * 100)),
    "cl_prometheus_port": $((cl_port + 3)),
    "beacond_node_port": ${beacond_port},
    "configtoml_grpc_laddr": $((9090 + v * 100)),
    "configtoml_grpc_privileged_laddr": $((9091 + v * 100)),
    "berareth_config": { "private_key": "aabb", "public_key": "ccdd" },
    "beacond_config": { "node_id": "abc${v}", "jwt": "0xdead" }
}
NODEEOF
        )
        node_index=$((node_index + 1))
    done

    # Add full nodes
    for ((f = 0; f < full_nodes; f++)); do
        local idx=$((validators + f))
        local el_port=$((19545 + idx * 100))
        local cl_port=$((49657 + idx * 1000))
        local beacond_port=$((13500 + idx * 100))
        [[ $node_index -gt 0 ]] && nodes_json+=","
        nodes_json+=$(cat <<NODEEOF
{
    "role": "full",
    "moniker": "test-node-full-${f}",
    "network": "devnet",
    "wallet_address": "0x0000000000000000000000000000000000000001",
    "ethrpc_port": ${cl_port},
    "ethp2p_port": $((cl_port - 1)),
    "ethproxy_port": $((cl_port + 1)),
    "el_ethrpc_port": ${el_port},
    "el_ws_port": $((el_port + 1)),
    "el_authrpc_port": $((el_port + 6)),
    "el_eth_port": $((30303 + idx * 100)),
    "el_prometheus_port": $((9101 + idx * 100)),
    "cl_prometheus_port": $((cl_port + 3)),
    "beacond_node_port": ${beacond_port},
    "configtoml_grpc_laddr": $((9090 + idx * 100)),
    "configtoml_grpc_privileged_laddr": $((9091 + idx * 100)),
    "berareth_config": { "private_key": "eeff", "public_key": "0011" },
    "beacond_config": { "node_id": "def${f}", "jwt": "0xbeef" }
}
NODEEOF
        )
        node_index=$((node_index + 1))
    done

    nodes_json+="]"

    cat > "${output_dir}/beranodes.config.json" <<CFGEOF
{
    "chain_id": "80087",
    "moniker": "test-node",
    "network": "devnet",
    "validators": ${validators},
    "full_nodes": ${full_nodes},
    "pruned_nodes": 0,
    "total_nodes": ${total},
    "beranode_dir": "${output_dir}",
    "mode": "${mode}",
    "wallet_address": "0x0000000000000000000000000000000000000001",
    "nodes": ${nodes_json}
}
CFGEOF
}

# =============================================================================
# Tests
# =============================================================================

log_header "BERANODE STATUS - TEST SUITE"
echo ""

# ─── Test 1: Docker mode, 2 validators (live) ────────────────────────────────
log_header "Test 1: Docker mode, 2 validators (live running containers)"

output=$(cd "${PROJECT_DIR}" && ./beranode status 2>&1) || true
echo "$output"

# Verify output contains expected elements
if echo "$output" | grep -q "Beranode Status"; then
    pass_test "Header 'Beranode Status' present"
else
    fail_test "Header 'Beranode Status' missing"
fi

if echo "$output" | grep -q "Network:.*devnet"; then
    pass_test "Network shows 'devnet'"
else
    fail_test "Network not showing 'devnet'"
fi

if echo "$output" | grep -q "Mode:.*docker"; then
    pass_test "Mode shows 'docker'"
else
    fail_test "Mode not showing 'docker'"
fi

if echo "$output" | grep -q "Nodes:.*2"; then
    pass_test "Node count shows 2"
else
    fail_test "Node count not showing 2"
fi

# Check both nodes appear
if echo "$output" | grep -q "val-0"; then
    pass_test "Node val-0 present in output"
else
    fail_test "Node val-0 missing from output"
fi

if echo "$output" | grep -q "val-1"; then
    pass_test "Node val-1 present in output"
else
    fail_test "Node val-1 missing from output"
fi

# Check that EL and CL columns have data (not all --)
if echo "$output" | grep "val-0" | grep -q "running"; then
    pass_test "Node val-0 shows 'running' status"
else
    fail_test "Node val-0 not showing 'running' status"
fi

# EL block should now show as a decimal number (not hex)
if echo "$output" | grep "val-0" | grep -qE "[0-9]{2,}"; then
    pass_test "Node val-0 shows EL block height (decimal)"
else
    fail_test "Node val-0 not showing EL block height"
fi

# Check CATCHING UP column
if echo "$output" | grep "val-0" | grep -q "false"; then
    pass_test "Node val-0 shows catching_up=false"
else
    fail_test "Node val-0 not showing catching_up value"
fi

# Check chain ID in header
if echo "$output" | grep -q "Chain ID:.*80087"; then
    pass_test "Chain ID shown in header"
else
    fail_test "Chain ID missing from header"
fi

# Check block age column header
if echo "$output" | grep -q "BLOCK AGE"; then
    pass_test "BLOCK AGE column present in header"
else
    fail_test "BLOCK AGE column missing from header"
fi

# Check block age value (should contain 'ago' or '--')
if echo "$output" | grep "val-0" | grep -qE "ago|--"; then
    pass_test "Block age value present for val-0"
else
    fail_test "Block age value missing for val-0"
fi

# ─── Test 2: Docker mode, 1 validator (synthetic config, nodes offline) ──────
log_header "Test 2: Docker mode, 1 validator (synthetic config, offline)"

TEST2_DIR=$(mktemp -d)
create_test_config "${TEST2_DIR}" "docker" 1 0
log_info "Config created at ${TEST2_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST2_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "Nodes:.*1"; then
    pass_test "Shows 1 node"
else
    fail_test "Not showing 1 node"
fi

if echo "$output" | grep -q "test-node-val-0"; then
    pass_test "Shows validator node name"
else
    fail_test "Validator node name missing"
fi

if echo "$output" | grep -q "validator"; then
    pass_test "Shows 'validator' role"
else
    fail_test "'validator' role missing"
fi

# No full nodes should appear
if echo "$output" | grep -q "full"; then
    # 'full' might appear in the role column only — check if it's a node row
    if echo "$output" | grep "test-node-full" > /dev/null 2>&1; then
        fail_test "Full node row should not appear for 1 validator config"
    else
        pass_test "No full node row present (correct)"
    fi
else
    pass_test "No full node present (correct)"
fi

rm -rf "${TEST2_DIR}"

# ─── Test 3: Local mode, 1 validator (synthetic config, nodes offline) ───────
log_header "Test 3: Local mode, 1 validator (synthetic config, offline)"

TEST3_DIR=$(mktemp -d)
create_test_config "${TEST3_DIR}" "local" 1 0
log_info "Config created at ${TEST3_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST3_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "Mode:.*local"; then
    pass_test "Mode shows 'local'"
else
    fail_test "Mode not showing 'local'"
fi

if echo "$output" | grep -q "Nodes:.*1"; then
    pass_test "Shows 1 node"
else
    fail_test "Not showing 1 node"
fi

if echo "$output" | grep -q "test-node-val-0"; then
    pass_test "Shows validator node name"
else
    fail_test "Validator node name missing"
fi

# In local mode with no processes running, status should show offline
if echo "$output" | grep "test-node-val-0" | grep -q "offline"; then
    pass_test "Node shows 'offline' status when not running"
else
    fail_test "Node not showing 'offline' (might be picking up unrelated docker containers)"
fi

rm -rf "${TEST3_DIR}"

# ─── Test 4: Docker mode, 1 validator + 1 full node (synthetic, offline) ─────
log_header "Test 4: Docker mode, 1 validator + 1 full node (synthetic config, offline)"

TEST4_DIR=$(mktemp -d)
create_test_config "${TEST4_DIR}" "docker" 1 1
log_info "Config created at ${TEST4_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST4_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "Nodes:.*2"; then
    pass_test "Shows 2 nodes total"
else
    fail_test "Not showing 2 nodes"
fi

if echo "$output" | grep -q "test-node-val-0"; then
    pass_test "Shows validator node"
else
    fail_test "Validator node missing"
fi

if echo "$output" | grep -q "test-node-full-0"; then
    pass_test "Shows full node"
else
    fail_test "Full node missing"
fi

# Verify roles are correct
if echo "$output" | grep "test-node-val-0" | grep -q "validator"; then
    pass_test "Validator has 'validator' role"
else
    fail_test "Validator role mismatch"
fi

if echo "$output" | grep "test-node-full-0" | grep -q "full"; then
    pass_test "Full node has 'full' role"
else
    fail_test "Full node role mismatch"
fi

rm -rf "${TEST4_DIR}"

# ─── Test 5: --help flag ─────────────────────────────────────────────────────
log_header "Test 5: --help flag"

output=$(cd "${PROJECT_DIR}" && ./beranode status --help 2>&1) || true

if echo "$output" | grep -q "Usage: beranode status"; then
    pass_test "--help displays usage"
else
    fail_test "--help not showing usage"
fi

if echo "$output" | grep -q "beranodes-dir"; then
    pass_test "--help mentions --beranodes-dir option"
else
    fail_test "--help missing --beranodes-dir option"
fi

if echo "$output" | grep -q "\-\-verbose"; then
    pass_test "--help mentions --verbose option"
else
    fail_test "--help missing --verbose option"
fi

if echo "$output" | grep -q "\-\-watch"; then
    pass_test "--help mentions --watch option"
else
    fail_test "--help missing --watch option"
fi

if echo "$output" | grep -q "\-\-interval"; then
    pass_test "--help mentions --interval option"
else
    fail_test "--help missing --interval option"
fi

# ─── Test 6: Missing config file ────────────────────────────────────────────
log_header "Test 6: Missing config file error handling"

TEST6_DIR=$(mktemp -d)
# Intentionally don't create a config file

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST6_DIR}" 2>&1) || true

if echo "$output" | grep -qi "error.*not found\|error.*configuration"; then
    pass_test "Shows error for missing config file"
else
    fail_test "No error message for missing config file"
fi

rm -rf "${TEST6_DIR}"

# ─── Test 7: Local mode, 2 validators (synthetic config, offline) ───────────
log_header "Test 7: Local mode, 2 validators (synthetic config, offline)"

TEST7_DIR=$(mktemp -d)
create_test_config "${TEST7_DIR}" "local" 2 0
log_info "Config created at ${TEST7_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST7_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "Mode:.*local"; then
    pass_test "Mode shows 'local'"
else
    fail_test "Mode not showing 'local'"
fi

if echo "$output" | grep -q "Nodes:.*2"; then
    pass_test "Shows 2 nodes"
else
    fail_test "Not showing 2 nodes"
fi

if echo "$output" | grep -q "test-node-val-0"; then
    pass_test "Shows first validator"
else
    fail_test "First validator missing"
fi

if echo "$output" | grep -q "test-node-val-1"; then
    pass_test "Shows second validator"
else
    fail_test "Second validator missing"
fi

# Both should be offline in local mode with no processes running
if echo "$output" | grep "test-node-val-0" | grep -q "offline"; then
    pass_test "First validator shows 'offline'"
else
    fail_test "First validator not showing 'offline'"
fi

if echo "$output" | grep "test-node-val-1" | grep -q "offline"; then
    pass_test "Second validator shows 'offline'"
else
    fail_test "Second validator not showing 'offline'"
fi

rm -rf "${TEST7_DIR}"

# ─── Test 8: Verbose mode, 2 validators (live docker) ───────────────────────
log_header "Test 8: Verbose mode, 2 validators (live docker)"

output=$(cd "${PROJECT_DIR}" && ./beranode status --verbose 2>&1) || true
echo "$output"

# Verbose header should have SERVICE column instead of separate EL/CL columns
if echo "$output" | grep -q "SERVICE"; then
    pass_test "Verbose header has SERVICE column"
else
    fail_test "Verbose header missing SERVICE column"
fi

# Should show bera-reth and beacond as separate rows
if echo "$output" | grep -q "bera-reth"; then
    pass_test "Verbose output shows bera-reth service row"
else
    fail_test "Verbose output missing bera-reth row"
fi

if echo "$output" | grep -q "beacond"; then
    pass_test "Verbose output shows beacond service row"
else
    fail_test "Verbose output missing beacond row"
fi

# Node name should appear on the bera-reth row (first service)
if echo "$output" | grep "val-0" | grep -q "bera-reth"; then
    pass_test "Node val-0 appears with bera-reth row"
else
    fail_test "Node val-0 not paired with bera-reth row"
fi

# beacond row should be a continuation (no node name repeated)
# Count how many lines have the moniker — should be 2 (one per node), not 4
moniker_lines=$(echo "$output" | grep -c "tiny-swim-cloud-val-" || true)
if [[ $moniker_lines -eq 2 ]]; then
    pass_test "Node name appears once per node (not repeated on beacond row)"
else
    fail_test "Node name should appear 2 times (once per node), got ${moniker_lines}"
fi

# Both services should show running status
if echo "$output" | grep "bera-reth" | head -1 | grep -q "running"; then
    pass_test "bera-reth shows running"
else
    fail_test "bera-reth not showing running"
fi

if echo "$output" | grep "beacond" | head -1 | grep -q "running"; then
    pass_test "beacond shows running"
else
    fail_test "beacond not showing running"
fi

# ─── Test 9: Verbose mode, 1 val + 1 full (synthetic, offline) ──────────────
log_header "Test 9: Verbose mode, 1 validator + 1 full node (synthetic, offline)"

TEST9_DIR=$(mktemp -d)
create_test_config "${TEST9_DIR}" "local" 1 1
log_info "Config created at ${TEST9_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --verbose --beranodes-dir "${TEST9_DIR}" 2>&1) || true
echo "$output"

# Should have 4 service rows: 2 nodes x 2 services
bera_reth_count=$(echo "$output" | grep -c "bera-reth" || true)
beacond_count=$(echo "$output" | grep -c "beacond" || true)

if [[ $bera_reth_count -eq 2 ]]; then
    pass_test "Shows 2 bera-reth rows (one per node)"
else
    fail_test "Expected 2 bera-reth rows, got ${bera_reth_count}"
fi

if [[ $beacond_count -eq 2 ]]; then
    pass_test "Shows 2 beacond rows (one per node)"
else
    fail_test "Expected 2 beacond rows, got ${beacond_count}"
fi

# Verify both roles appear
if echo "$output" | grep -q "validator"; then
    pass_test "Validator role present in verbose output"
else
    fail_test "Validator role missing in verbose output"
fi

if echo "$output" | grep -q "full"; then
    pass_test "Full node role present in verbose output"
else
    fail_test "Full node role missing in verbose output"
fi

# Both should be offline
if echo "$output" | grep "bera-reth" | head -1 | grep -q "offline"; then
    pass_test "bera-reth shows offline when not running"
else
    fail_test "bera-reth not showing offline"
fi

rm -rf "${TEST9_DIR}"

# ─── Test 10: Verbose short flag -v ─────────────────────────────────────────
log_header "Test 10: Verbose short flag -v"

output=$(cd "${PROJECT_DIR}" && ./beranode status -v 2>&1) || true

if echo "$output" | grep -q "SERVICE"; then
    pass_test "-v flag enables verbose mode"
else
    fail_test "-v flag not enabling verbose mode"
fi

if echo "$output" | grep -q "bera-reth"; then
    pass_test "-v shows bera-reth service row"
else
    fail_test "-v not showing bera-reth row"
fi

# ─── Test 11: Chain ID appears in header (live) ─────────────────────────────
log_header "Test 11: Chain ID in header"

output=$(cd "${PROJECT_DIR}" && ./beranode status 2>&1) || true

if echo "$output" | grep -q "Chain ID:"; then
    pass_test "Chain ID label present in header"
else
    fail_test "Chain ID label missing from header"
fi

# Synthetic config also has chain_id
TEST11_DIR=$(mktemp -d)
create_test_config "${TEST11_DIR}" "local" 1 0

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST11_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "Chain ID:.*80087"; then
    pass_test "Synthetic config chain ID 80087 shown"
else
    fail_test "Synthetic config chain ID missing"
fi

rm -rf "${TEST11_DIR}"

# ─── Test 12: Block age column in verbose mode ──────────────────────────────
log_header "Test 12: Block age in verbose mode"

output=$(cd "${PROJECT_DIR}" && ./beranode status --verbose 2>&1) || true

if echo "$output" | grep -q "BLOCK AGE"; then
    pass_test "Verbose header has BLOCK AGE column"
else
    fail_test "Verbose header missing BLOCK AGE column"
fi

# beacond row should show a block age (contains 'ago')
if echo "$output" | grep "beacond" | head -1 | grep -qE "ago"; then
    pass_test "beacond row shows block age"
else
    fail_test "beacond row missing block age"
fi

# bera-reth row should show '--' for block age (EL has no block time)
if echo "$output" | grep "bera-reth" | head -1 | grep -q "\-\-"; then
    pass_test "bera-reth row shows '--' for block age"
else
    fail_test "bera-reth row missing '--' for block age"
fi

# ─── Test 13: EL block shown as decimal (not hex) ───────────────────────────
log_header "Test 13: EL block shown as decimal"

output=$(cd "${PROJECT_DIR}" && ./beranode status 2>&1) || true

# In compact mode the EL BLOCK column should be a plain decimal (no 0x prefix)
el_block_val=$(echo "$output" | grep "val-0" | awk '{print $4}')
if [[ "${el_block_val}" =~ ^[0-9]+$ ]]; then
    pass_test "EL block is decimal: ${el_block_val}"
else
    fail_test "EL block is not decimal: '${el_block_val}'"
fi

# Also check verbose mode
output=$(cd "${PROJECT_DIR}" && ./beranode status -v 2>&1) || true
el_block_val=$(echo "$output" | grep "bera-reth" | head -1 | awk '{print $5}')
if [[ "${el_block_val}" =~ ^[0-9]+$ ]]; then
    pass_test "Verbose EL block is decimal: ${el_block_val}"
else
    fail_test "Verbose EL block is not decimal: '${el_block_val}'"
fi

# ─── Test 14: --watch flag parsing & --interval validation ──────────────────
log_header "Test 14: --watch and --interval flag parsing"

# --interval with invalid value should error
output=$(cd "${PROJECT_DIR}" && ./beranode status --interval abc 2>&1) || true
if echo "$output" | grep -qi "invalid\|error"; then
    pass_test "--interval with non-numeric value shows error"
else
    fail_test "--interval with non-numeric value did not show error"
fi

# --interval with no value should error
output=$(cd "${PROJECT_DIR}" && ./beranode status --interval 2>&1) || true
if echo "$output" | grep -qi "invalid\|error"; then
    pass_test "--interval with missing value shows error"
else
    fail_test "--interval with missing value did not show error"
fi

# --watch without tty should show an error (we pipe to capture, so no tty)
output=$(cd "${PROJECT_DIR}" && ./beranode status --watch 2>&1) || true
if echo "$output" | grep -qi "interactive\|tty\|terminal"; then
    pass_test "--watch without tty shows terminal requirement error"
else
    fail_test "--watch without tty did not show terminal requirement error"
fi

# Short flag -w should also trigger watch mode (and fail without tty)
output=$(cd "${PROJECT_DIR}" && ./beranode status -w 2>&1) || true
if echo "$output" | grep -qi "interactive\|tty\|terminal"; then
    pass_test "-w flag recognized (watch mode, fails gracefully without tty)"
else
    fail_test "-w flag not recognized"
fi

# =============================================================================
# Summary
# =============================================================================

log_header "TEST SUMMARY"
echo ""
echo -e "  Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "  Tests Failed: ${RED}${TESTS_FAILED}${NC}"
echo -e "  Tests Total:  ${TESTS_TOTAL}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    log_success "ALL ${TESTS_TOTAL} TESTS PASSED!"
    exit 0
else
    log_error "${TESTS_FAILED} TEST(S) FAILED"
    exit 1
fi
