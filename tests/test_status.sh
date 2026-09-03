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
#   Test 16: LIVE EL BLOCK column (bepolia/mainnet only; omitted on devnet)
#   Test 17: format_block_age treats CometBFT timestamps as UTC
#   Test 18: Storage footer (total / device used / nodes directory)
#   Test 19: --json output (valid JSON with storage + nodes)
#   Test 20: --json is incompatible with --watch
#   Test 21: --help mentions --json and Storage
#   Test 22: status_comma / status_percent / status_diskutil_field helpers
#   Test 23: Memory footer (per-binary RSS / total RAM)
#   Test 24: Memory footer shows RSS for a live PID file
#   Test 25: memory helper unit tests (parse size, format gb, total RAM, RSS)
#   Test 26: SNAPSHOT column (pruned / archive, including --json)
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
    "rpcs": ${full_nodes},
    "full_nodes": ${full_nodes},
    "pruned_nodes": 0,
    "total_nodes": ${total},
    "beranode_dir": "${output_dir}",
    "mode": "${mode}",
    "snapshot_type": "pruned",
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

if echo "$output" | grep -q "LIVE EL BLOCK"; then
    pass_test "--help mentions LIVE EL BLOCK"
else
    fail_test "--help missing LIVE EL BLOCK"
fi

if echo "$output" | grep -q "\-\-json"; then
    pass_test "--help mentions --json option"
else
    fail_test "--help missing --json option"
fi

if echo "$output" | grep -qi "storage"; then
    pass_test "--help mentions Storage"
else
    fail_test "--help missing Storage"
fi

if echo "$output" | grep -qi "memory"; then
    pass_test "--help mentions Memory"
else
    fail_test "--help missing Memory"
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

# Should have 4 service rows: 2 nodes x 2 services (ignore Memory footer names)
table_out=$(echo "$output" | awk '/^  Storage:/{exit} {print}')
bera_reth_count=$(echo "$table_out" | grep -c "bera-reth" || true)
beacond_count=$(echo "$table_out" | grep -c "beacond" || true)

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

# Compact columns: NODE ROLE SNAPSHOT EL_STATUS EL_BLOCK ...
el_block_val=$(echo "$output" | grep "val-0" | awk '{print $5}')
if [[ "${el_block_val}" =~ ^[0-9]+$ ]]; then
    pass_test "EL block is decimal: ${el_block_val}"
else
    fail_test "EL block is not decimal: '${el_block_val}'"
fi

# Also check verbose mode (NODE ROLE SNAPSHOT SERVICE STATUS BLOCK)
output=$(cd "${PROJECT_DIR}" && ./beranode status -v 2>&1) || true
el_block_val=$(echo "$output" | grep "bera-reth" | head -1 | awk '{print $6}')
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

# ─── Test 16: LIVE EL BLOCK column ──────────────────────────────────────────
log_header "Test 16: LIVE EL BLOCK column"

# Devnet omits LIVE EL BLOCK entirely (no public RPC)
TEST16_DIR=$(mktemp -d)
create_test_config "${TEST16_DIR}" "local" 1 0
output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST16_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "LIVE EL BLOCK"; then
    fail_test "Devnet status should omit LIVE EL BLOCK column"
else
    pass_test "Devnet omits LIVE EL BLOCK column"
fi

if echo "$output" | grep -q "EL BLOCK.*EL PEERS"; then
    pass_test "Devnet compact header is EL BLOCK | EL PEERS (no live column)"
else
    fail_test "Devnet compact header missing EL BLOCK | EL PEERS"
fi

output=$(cd "${PROJECT_DIR}" && ./beranode status --verbose --beranodes-dir "${TEST16_DIR}" 2>&1) || true
if echo "$output" | grep -q "LIVE EL BLOCK"; then
    fail_test "Devnet verbose status should omit LIVE EL BLOCK column"
else
    pass_test "Devnet verbose omits LIVE EL BLOCK column"
fi

rm -rf "${TEST16_DIR}"

# Bepolia: LIVE EL BLOCK column is present; value comes from public RPC
TEST16B_DIR=$(mktemp -d)
create_test_config "${TEST16B_DIR}" "local" 1 0
jq '.network = "bepolia"' "${TEST16B_DIR}/beranodes.config.json" > "${TEST16B_DIR}/beranodes.config.json.tmp"
mv "${TEST16B_DIR}/beranodes.config.json.tmp" "${TEST16B_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST16B_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "LIVE EL BLOCK"; then
    pass_test "Bepolia compact header has LIVE EL BLOCK column"
else
    fail_test "Bepolia compact header missing LIVE EL BLOCK column"
fi

if echo "$output" | grep -q "EL BLOCK.*LIVE EL BLOCK.*EL PEERS"; then
    pass_test "Bepolia column order is EL BLOCK | LIVE EL BLOCK | EL PEERS"
else
    fail_test "Bepolia column order is not EL BLOCK | LIVE EL BLOCK | EL PEERS"
fi

output=$(cd "${PROJECT_DIR}" && ./beranode status --verbose --beranodes-dir "${TEST16B_DIR}" 2>&1) || true
if echo "$output" | grep -q "LIVE EL BLOCK"; then
    pass_test "Bepolia verbose header has LIVE EL BLOCK column"
else
    fail_test "Bepolia verbose header missing LIVE EL BLOCK column"
fi

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST16B_DIR}" 2>&1) || true
if echo "$output" | grep "test-node-val-0" | grep -qE '[0-9]{4,}'; then
    pass_test "Bepolia LIVE EL BLOCK is a public-RPC decimal"
elif curl -sf --connect-timeout 2 --max-time 3 \
    -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "https://bepolia.rpc.berachain.com" >/dev/null 2>&1; then
    fail_test "Bepolia LIVE EL BLOCK should be a decimal from the public RPC"
else
    pass_test "Skipped bepolia public-RPC assertion (endpoint unreachable)"
fi

rm -rf "${TEST16B_DIR}"

# ─── Test 17: format_block_age treats CometBFT timestamps as UTC ─────────────
log_header "Test 17: format_block_age UTC parsing"

age_now=$(
    if [[ "$(uname)" == "Darwin" ]]; then IS_MACOS=true; else IS_MACOS=false; fi
    eval "$(sed -n '/^format_block_age()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    now_utc=$(date -u +"%Y-%m-%dT%H:%M:%S.123456789Z")
    format_block_age "${now_utc}"
)

if [[ "${age_now}" =~ ^[0-9]+s\ ago$ ]]; then
    pass_test "Current UTC timestamp is seconds old, not timezone-offset hours (${age_now})"
else
    fail_test "Current UTC timestamp should be 'Ns ago', got '${age_now}'"
fi

age_empty=$(
    if [[ "$(uname)" == "Darwin" ]]; then IS_MACOS=true; else IS_MACOS=false; fi
    eval "$(sed -n '/^format_block_age()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    format_block_age "--"
)

if [[ "${age_empty}" == "--" ]]; then
    pass_test "Missing block time formats as --"
else
    fail_test "Missing block time should be '--', got '${age_empty}'"
fi

# ─── Test 18: Storage footer ────────────────────────────────────────────────
log_header "Test 18: Storage footer"

TEST18_DIR=$(mktemp -d)
create_test_config "${TEST18_DIR}" "local" 1 0
mkdir -p "${TEST18_DIR}/nodes"
# ~20 MiB so du reports a non-zero nodes directory size in 0.01 GB units
dd if=/dev/zero of="${TEST18_DIR}/nodes/blob" bs=1024 count=20480 2>/dev/null

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST18_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "Storage:"; then
    pass_test "Storage section present"
else
    fail_test "Storage section missing"
fi

if echo "$output" | grep -q "Total space:"; then
    pass_test "Total space line present"
else
    fail_test "Total space line missing"
fi

if echo "$output" | grep -q "Device used:"; then
    pass_test "Device used line present"
else
    fail_test "Device used line missing"
fi

if echo "$output" | grep -q "Nodes directory:"; then
    pass_test "Nodes directory line present"
else
    fail_test "Nodes directory line missing"
fi

if echo "$output" | grep "Total space:" | grep -qE "[0-9]+(,[0-9]{3})* GB"; then
    pass_test "Total space shows GB"
else
    fail_test "Total space missing GB value"
fi

if echo "$output" | grep "Device used:" | grep -qE "GB \([0-9]+\.[0-9]+%\)"; then
    pass_test "Device used shows GB and percent"
else
    fail_test "Device used missing GB (percent) value"
fi

if echo "$output" | grep "Nodes directory:" | grep -qE "[0-9]+\.[0-9]+ GB \([0-9]+\.[0-9]+%\)"; then
    pass_test "Nodes directory shows GB and percent"
else
    fail_test "Nodes directory missing GB (percent) value"
fi

if echo "$output" | grep "Nodes directory:" | grep -q "0.00 GB"; then
    fail_test "Nodes directory should be non-zero GB when nodes/ has data: $(echo "$output" | grep "Nodes directory:")"
elif echo "$output" | grep "Nodes directory:" | grep -qE "[0-9]+\.[0-9]+ GB \([0-9]+\.[0-9]+%\)"; then
    pass_test "Nodes directory shows a non-zero GB size"
else
    fail_test "Nodes directory missing GB (percent) value"
fi

rm -rf "${TEST18_DIR}"

# ─── Test 19: --json output ─────────────────────────────────────────────────
log_header "Test 19: --json output"

TEST19_DIR=$(mktemp -d)
create_test_config "${TEST19_DIR}" "local" 1 0
mkdir -p "${TEST19_DIR}/nodes"
dd if=/dev/zero of="${TEST19_DIR}/nodes/blob" bs=1024 count=20480 2>/dev/null

json_output=$(cd "${PROJECT_DIR}" && ./beranode status --json --beranodes-dir "${TEST19_DIR}" 2>&1) || true
echo "$json_output"

if echo "$json_output" | jq empty 2>/dev/null && echo "$json_output" | jq -e 'type == "object"' >/dev/null 2>&1; then
    pass_test "--json emits valid JSON"
else
    fail_test "--json did not emit valid JSON"
fi

if echo "$json_output" | jq -e '.network == "devnet"' >/dev/null 2>&1; then
    pass_test "--json includes network"
else
    fail_test "--json missing network"
fi

if echo "$json_output" | jq -e '.nodes | length == 1' >/dev/null 2>&1; then
    pass_test "--json has one node"
else
    fail_test "--json node count mismatch"
fi

if echo "$json_output" | jq -e '.nodes[0].moniker == "test-node-val-0"' >/dev/null 2>&1; then
    pass_test "--json node moniker matches"
else
    fail_test "--json node moniker mismatch"
fi

if echo "$json_output" | jq -e '.nodes[0].snapshot_type == "pruned"' >/dev/null 2>&1; then
    pass_test "--json snapshot_type is pruned"
else
    fail_test "--json snapshot_type mismatch"
fi

if echo "$json_output" | jq -e '.nodes[0].el.status == "offline"' >/dev/null 2>&1; then
    pass_test "--json EL status is offline for synthetic config"
else
    fail_test "--json EL status mismatch"
fi

if echo "$json_output" | jq -e '.nodes[0].el.block == null' >/dev/null 2>&1; then
    pass_test "--json missing EL block is null (not \"--\")"
else
    fail_test "--json missing EL block should be null"
fi

if echo "$json_output" | jq -e '.live_el_block == null' >/dev/null 2>&1; then
    pass_test "--json omits live EL block on devnet (null)"
else
    fail_test "--json live_el_block should be null on devnet"
fi

if echo "$json_output" | jq -e '.storage.total_bytes > 0' >/dev/null 2>&1; then
    pass_test "--json storage.total_bytes > 0"
else
    fail_test "--json storage.total_bytes missing or zero"
fi

if echo "$json_output" | jq -e '.storage.nodes_bytes > 0' >/dev/null 2>&1; then
    pass_test "--json storage.nodes_bytes > 0"
else
    fail_test "--json storage.nodes_bytes missing or zero"
fi

if echo "$json_output" | jq -e '.storage.path | endswith("/nodes")' >/dev/null 2>&1; then
    pass_test "--json storage.path ends with /nodes"
else
    fail_test "--json storage.path should end with /nodes"
fi

if echo "$json_output" | jq -e '.memory.total_bytes > 0' >/dev/null 2>&1; then
    pass_test "--json memory.total_bytes > 0"
else
    fail_test "--json memory.total_bytes missing or zero"
fi

if echo "$json_output" | jq -e '.memory.processes | length == 2' >/dev/null 2>&1; then
    pass_test "--json memory.processes has two binaries"
else
    fail_test "--json memory.processes count mismatch"
fi

if echo "$json_output" | jq -e '.memory.processes[0].name == "val-0-bera-reth"' >/dev/null 2>&1; then
    pass_test "--json memory process name is val-0-bera-reth"
else
    fail_test "--json memory process name mismatch"
fi

if echo "$json_output" | jq -e '.memory.processes[0].rss_bytes == null' >/dev/null 2>&1; then
    pass_test "--json memory rss_bytes is null when process is not running"
else
    fail_test "--json memory rss_bytes should be null for synthetic offline node"
fi

# Table chrome must not leak into JSON mode
if echo "$json_output" | grep -q "Beranode Status"; then
    fail_test "--json should not include table header"
else
    pass_test "--json has no table header"
fi

rm -rf "${TEST19_DIR}"

# ─── Test 20: --json incompatible with --watch ──────────────────────────────
log_header "Test 20: --json cannot be used with --watch"

output=$(cd "${PROJECT_DIR}" && ./beranode status --json --watch 2>&1) || true
if echo "$output" | grep -qi "json.*watch\|watch.*json"; then
    pass_test "--json --watch shows incompatibility error"
else
    fail_test "--json --watch did not show incompatibility error"
fi

# ─── Test 21: --help mentions --json (also covered in Test 5) ───────────────
# (assertions live in Test 5)

# ─── Test 22: storage helper unit tests ─────────────────────────────────────
log_header "Test 22: status_comma / status_percent / status_diskutil_field"

helper_out=$(
    eval "$(sed -n '/^status_comma()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_percent()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_diskutil_field()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    echo "comma:$(status_comma 7999)"
    echo "pct1:$(status_percent 1970260938752 7998551654400 1)"
    echo "pct2:$(status_percent 12540000000 7998551654400 2)"
    echo "pct0:$(status_percent 1 0 1)"
    fixture=$'   Container Total Space:     8.0 TB (7998551654400 Bytes) (exactly 15622171200 512-Byte-Units)\n   Container Free Space:      6.0 TB (6028290715648 Bytes) (exactly 11774005304 512-Byte-Units)'
    echo "total:$(status_diskutil_field "$fixture" "Container Total Space")"
    echo "free:$(status_diskutil_field "$fixture" "Container Free Space")"
)

if echo "$helper_out" | grep -q "comma:7,999"; then
    pass_test "status_comma 7999 → 7,999"
else
    fail_test "status_comma failed: $(echo "$helper_out" | grep comma)"
fi

if echo "$helper_out" | grep -q "pct1:24.6"; then
    pass_test "status_percent 1 decimal is 24.6"
else
    fail_test "status_percent 1 decimal failed: $(echo "$helper_out" | grep pct1)"
fi

if echo "$helper_out" | grep -q "pct2:0.16"; then
    pass_test "status_percent 2 decimals is 0.16"
else
    fail_test "status_percent 2 decimals failed: $(echo "$helper_out" | grep pct2)"
fi

if echo "$helper_out" | grep -q "pct0:--"; then
    pass_test "status_percent whole=0 is --"
else
    fail_test "status_percent zero-whole failed: $(echo "$helper_out" | grep pct0)"
fi

if echo "$helper_out" | grep -q "total:7998551654400"; then
    pass_test "status_diskutil_field parses Container Total Space"
else
    fail_test "status_diskutil_field total failed: $(echo "$helper_out" | grep total)"
fi

if echo "$helper_out" | grep -q "free:6028290715648"; then
    pass_test "status_diskutil_field parses Container Free Space"
else
    fail_test "status_diskutil_field free failed: $(echo "$helper_out" | grep free)"
fi

# ─── Test 23: Memory footer ─────────────────────────────────────────────────
log_header "Test 23: Memory footer"

TEST23_DIR=$(mktemp -d)
create_test_config "${TEST23_DIR}" "local" 1 0
mkdir -p "${TEST23_DIR}/nodes"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST23_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "Memory:"; then
    pass_test "Memory section present"
else
    fail_test "Memory section missing"
fi

if echo "$output" | grep -q "val-0-bera-reth"; then
    pass_test "Memory lists val-0-bera-reth"
else
    fail_test "Memory missing val-0-bera-reth"
fi

if echo "$output" | grep -q "val-0-beacond"; then
    pass_test "Memory lists val-0-beacond"
else
    fail_test "Memory missing val-0-beacond"
fi

if echo "$output" | grep "val-0-bera-reth" | grep -q ": --"; then
    pass_test "Offline binary shows --"
else
    fail_test "Offline binary should show --: $(echo "$output" | grep "val-0-bera-reth")"
fi

rm -rf "${TEST23_DIR}"

# ─── Test 24: Memory footer with a live PID ─────────────────────────────────
log_header "Test 24: Memory footer shows RSS for a live PID file"

TEST24_DIR=$(mktemp -d)
create_test_config "${TEST24_DIR}" "local" 1 0
mkdir -p "${TEST24_DIR}/nodes" "${TEST24_DIR}/runs"
sleep 120 &
TEST24_PID=$!
echo "${TEST24_PID}" > "${TEST24_DIR}/runs/test-node-0-val-bera-reth.pid"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST24_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep "val-0-bera-reth" | grep -qE "[0-9]+\.[0-9]gb/[0-9]+gb \([0-9]+\.[0-9]{2}%\)"; then
    pass_test "Live PID shows used/total RAM and percent"
else
    fail_test "Live PID missing used/total format: $(echo "$output" | grep "val-0-bera-reth")"
fi

if echo "$output" | grep "val-0-beacond" | grep -q ": --"; then
    pass_test "Missing beacond PID still shows --"
else
    fail_test "Missing beacond PID should show --"
fi

kill "${TEST24_PID}" 2>/dev/null || true
wait "${TEST24_PID}" 2>/dev/null || true
rm -rf "${TEST24_DIR}"

# ─── Test 25: memory helper unit tests ──────────────────────────────────────
log_header "Test 25: memory helpers (parse size, format, total RAM, RSS)"

helper_out=$(
    eval "$(sed -n '/^status_role_short()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_binary_label()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_query_total_ram_bytes()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_parse_mem_size()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_parse_docker_mem_used()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_format_mem_used()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_format_mem_total()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    eval "$(sed -n '/^status_pid_rss_bytes()/,/^}/p' "${PROJECT_DIR}/src/commands/status.sh")"
    echo "role:$(status_role_short validator)"
    echo "label:$(status_binary_label 0 validator bera-reth)"
    echo "gib:$(status_parse_mem_size 4.40GiB)"
    echo "mib:$(status_parse_mem_size 500MiB)"
    echo "docker:$(status_parse_docker_mem_used '4.40GiB / 7.654GiB')"
    echo "used:$(status_format_mem_used 4724464026)"
    echo "total:$(status_format_mem_total 68719476736)"
    echo "ram:$(status_query_total_ram_bytes)"
    echo "rss:$(status_pid_rss_bytes $$)"
    echo "dead:$(status_pid_rss_bytes 99999999 || true)"
)

if echo "$helper_out" | grep -q "role:val"; then
    pass_test "status_role_short validator → val"
else
    fail_test "status_role_short failed: $(echo "$helper_out" | grep role)"
fi

if echo "$helper_out" | grep -q "label:val-0-bera-reth"; then
    pass_test "status_binary_label → val-0-bera-reth"
else
    fail_test "status_binary_label failed: $(echo "$helper_out" | grep label)"
fi

# 4.40 * 1073741824 = 4724464025.6 → 4724464026
if echo "$helper_out" | grep -qE "gib:472446402[0-9]"; then
    pass_test "status_parse_mem_size 4.40GiB"
else
    fail_test "status_parse_mem_size GiB failed: $(echo "$helper_out" | grep gib)"
fi

if echo "$helper_out" | grep -q "mib:524288000"; then
    pass_test "status_parse_mem_size 500MiB"
else
    fail_test "status_parse_mem_size MiB failed: $(echo "$helper_out" | grep mib)"
fi

if echo "$helper_out" | grep -qE "docker:472446402[0-9]"; then
    pass_test "status_parse_docker_mem_used takes the used side"
else
    fail_test "status_parse_docker_mem_used failed: $(echo "$helper_out" | grep docker)"
fi

if echo "$helper_out" | grep -q "used:4.4gb"; then
    pass_test "status_format_mem_used 4.40GiB → 4.4gb"
else
    fail_test "status_format_mem_used failed: $(echo "$helper_out" | grep used)"
fi

if echo "$helper_out" | grep -q "total:64gb"; then
    pass_test "status_format_mem_total 64GiB → 64gb"
else
    fail_test "status_format_mem_total failed: $(echo "$helper_out" | grep total)"
fi

ram_bytes=$(echo "$helper_out" | awk -F: '/^ram:/ {print $2}')
if [[ "${ram_bytes}" =~ ^[0-9]+$ && "${ram_bytes}" -gt 0 ]]; then
    pass_test "status_query_total_ram_bytes returns host RAM"
else
    fail_test "status_query_total_ram_bytes failed: $(echo "$helper_out" | grep ram)"
fi

rss_bytes=$(echo "$helper_out" | awk -F: '/^rss:/ {print $2}')
if [[ "${rss_bytes}" =~ ^[0-9]+$ && "${rss_bytes}" -gt 0 ]]; then
    pass_test "status_pid_rss_bytes reads current shell RSS"
else
    fail_test "status_pid_rss_bytes failed: $(echo "$helper_out" | grep rss)"
fi

if echo "$helper_out" | grep -q "dead:0"; then
    pass_test "status_pid_rss_bytes missing PID is 0"
else
    fail_test "status_pid_rss_bytes dead PID failed: $(echo "$helper_out" | grep dead)"
fi

# ─── Test 26: SNAPSHOT column (pruned / archive) ────────────────────────────
log_header "Test 26: SNAPSHOT column"

TEST26_DIR=$(mktemp -d)
create_test_config "${TEST26_DIR}" "local" 1 0

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST26_DIR}" 2>&1) || true
echo "$output"

if echo "$output" | grep -q "SNAPSHOT"; then
    pass_test "Compact header has SNAPSHOT column"
else
    fail_test "Compact header missing SNAPSHOT column"
fi

if echo "$output" | grep -q "ROLE.*SNAPSHOT.*EL STATUS"; then
    pass_test "Column order is ROLE | SNAPSHOT | EL STATUS"
else
    fail_test "Column order is not ROLE | SNAPSHOT | EL STATUS"
fi

if echo "$output" | grep "test-node-val-0" | grep -q "pruned"; then
    pass_test "Default snapshot_type shows pruned"
else
    fail_test "Default snapshot_type should show pruned"
fi

jq '.snapshot_type = "archive"' "${TEST26_DIR}/beranodes.config.json" > "${TEST26_DIR}/beranodes.config.json.tmp"
mv "${TEST26_DIR}/beranodes.config.json.tmp" "${TEST26_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST26_DIR}" 2>&1) || true
if echo "$output" | grep "test-node-val-0" | grep -q "archive"; then
    pass_test "snapshot_type=archive shows archive"
else
    fail_test "snapshot_type=archive should show archive"
fi

output=$(cd "${PROJECT_DIR}" && ./beranode status --verbose --beranodes-dir "${TEST26_DIR}" 2>&1) || true
if echo "$output" | grep "bera-reth" | head -1 | grep -q "archive"; then
    pass_test "Verbose bera-reth row shows archive"
else
    fail_test "Verbose bera-reth row missing archive"
fi

json_output=$(cd "${PROJECT_DIR}" && ./beranode status --json --beranodes-dir "${TEST26_DIR}" 2>&1) || true
if echo "$json_output" | jq -e '.nodes[0].snapshot_type == "archive"' >/dev/null 2>&1; then
    pass_test "--json snapshot_type is archive when configured"
else
    fail_test "--json snapshot_type should be archive"
fi

# Older configs without snapshot_type: rpc-full still maps to archive
jq 'del(.snapshot_type) | .nodes[0].role = "rpc-full"' "${TEST26_DIR}/beranodes.config.json" > "${TEST26_DIR}/beranodes.config.json.tmp"
mv "${TEST26_DIR}/beranodes.config.json.tmp" "${TEST26_DIR}/beranodes.config.json"

output=$(cd "${PROJECT_DIR}" && ./beranode status --beranodes-dir "${TEST26_DIR}" 2>&1) || true
if echo "$output" | grep "test-node-val-0" | grep -q "archive"; then
    pass_test "Legacy rpc-full role without override shows archive"
else
    fail_test "Legacy rpc-full role should map to archive"
fi

rm -rf "${TEST26_DIR}"

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
