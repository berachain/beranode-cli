#!/usr/bin/env bash
set -euo pipefail
################################################################################
# validation.sh - Beranode Config Validation Functions
################################################################################

# Initialize DEBUG_MODE if not set
: "${DEBUG_MODE:=false}"
#
# This module provides validation functions for beranodes.config.json fields
# using regex patterns to ensure correct formatting and data integrity.
#
# LEGEND - Function Reference by Section:
# ──────────────────────────────────────────────────────────────────────────────
# 1. REGEX VALIDATORS
#    ├─ validate_string()               : Validate non-empty string
#    ├─ validate_boolean()              : Validate true/false boolean string
#    ├─ validate_integer()              : Validate integer number
#    ├─ validate_port()                 : Validate port number (1-65535)
#    ├─ validate_hex_address()          : Validate Ethereum address (0x + 40 hex)
#    ├─ validate_hex_private_key()      : Validate private key (0x + 64 hex)
#    ├─ validate_hex_string()           : Validate generic hex string with 0x
#    ├─ validate_jwt()                  : Validate JWT token (0x + 64 hex)
#    ├─ validate_path()                 : Validate file/directory path
#    ├─ validate_url()                  : Validate URL (http/tcp/ws)
#    ├─ validate_duration()             : Validate time duration (e.g., 5m0s, 10s)
#    ├─ validate_network()              : Validate network name (devnet, testnet, mainnet)
#    ├─ validate_moniker()              : Validate node moniker
#    └─ validate_pubkey()               : Validate BLS public key
#
# 2. FIELD-SPECIFIC VALIDATORS
#    ├─ validate_node_object()          : Validate individual node configuration
#    ├─ validate_deposit_object()       : Validate genesis deposit object
#    └─ validate_config_field()         : Validate a specific config field by name
#
# 3. MAIN VALIDATION
#    └─ validate_beranodes_config()     : Validate entire beranodes.config.json
#
################################################################################

################################################################################
# 1. REGEX VALIDATORS
################################################################################

# Validates a non-empty string
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_string() {
	local value="$1"
	[[ -n "$value" ]]
}

# Validates a boolean string (true or false)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_boolean() {
	local value="$1"
	[[ "$value" =~ ^(true|false)$ ]]
}

# Validates an integer number
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_integer() {
	local value="$1"
	[[ "$value" =~ ^[0-9]+$ ]]
}

# Validates a port number (1-65535)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_port() {
	local value="$1"
	if [[ "$value" =~ ^[0-9]+$ ]]; then
		((value > 0 && value <= 65535))
	else
		return 1
	fi
}

# Validates an Ethereum address (0x followed by 40 hex characters)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_hex_address() {
	local value="$1"
	[[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]]
}

# Validates a private key (0x followed by 64 hex characters)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_hex_private_key() {
	local value="$1"
	[[ "$value" =~ ^0x[0-9a-fA-F]{64}$ ]]
}

# Validates a generic hex string with 0x prefix
# Parameters: $1 - value to validate, $2 - expected length (optional)
# Returns: 0 if valid, 1 if invalid
validate_hex_string() {
	local value="$1"
	local expected_length="${2:-}"

	if [[ -n "$expected_length" ]]; then
		[[ "$value" =~ ^0x[0-9a-fA-F]{${expected_length}}$ ]]
	else
		[[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]
	fi
}

# Validates a JWT token (0x followed by 64 hex characters)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_jwt() {
	local value="$1"
	[[ "$value" =~ ^0x[0-9a-fA-F]{64}$ ]]
}

# Validates a file or directory path (absolute or relative)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_path() {
	local value="$1"
	# Path must be non-empty and not contain null bytes
	[[ -n "$value" && ! "$value" =~ $'\0' ]]
}

# Validates a URL (http, https, tcp, ws, wss)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_url() {
	local value="$1"
	[[ "$value" =~ ^(http|https|tcp|ws|wss)://.*$ ]]
}

# Validates a time duration (e.g., 5m0s, 10s, 1h30m, 0s)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_duration() {
	local value="$1"
	[[ "$value" =~ ^[0-9]+(h|m|s|ms|us|ns)([0-9]+(h|m|s|ms|us|ns))*$ || "$value" == "0s" || "$value" == "0" ]]
}

# Validates network name (devnet, testnet, mainnet, or custom)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_network() {
	local value="$1"
	[[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]
}

# Validates a node moniker (alphanumeric with hyphens, underscores)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_moniker() {
	local value="$1"
	[[ "$value" =~ ^[a-zA-Z0-9_-]+$ && ${#value} -ge 3 && ${#value} -le 64 ]]
}

# Validates a BLS public key (0x followed by 96 hex characters)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_pubkey() {
	local value="$1"
	[[ "$value" =~ ^0x[0-9a-fA-F]{96}$ ]]
}

# Validates a base64 string
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_base64() {
	local value="$1"
	[[ "$value" =~ ^[A-Za-z0-9+/]+=*$ ]]
}

# Validates a CometBFT address (uppercase hex, 40 chars)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_comet_address() {
	local value="$1"
	[[ "$value" =~ ^[0-9A-F]{40}$ ]]
}

# Validates mode (local, dev, testnet, mainnet)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_mode() {
	local value="$1"
	[[ "$value" =~ ^(local|docker)$ ]]
}

# Validates role (validator, full_node, pruned_node)
# Parameters: $1 - value to validate
# Returns: 0 if valid, 1 if invalid
validate_role() {
	local value="$1"
	[[ "$value" =~ ^(validator|rpc-full|rpc-pruned)$ ]]
}

################################################################################
# 2. FIELD-SPECIFIC VALIDATORS
################################################################################

# Validates an individual node object
# Parameters: $1 - JSON node object string
# Returns: 0 if valid, 1 if invalid (sets $VALIDATION_ERROR on failure)
validate_node_object() {
	local node_json="$1"
	local errors=()

	# Extract and validate fields
	local role=$(echo "$node_json" | jq -r '.role')
	local moniker=$(echo "$node_json" | jq -r '.moniker')
	local network=$(echo "$node_json" | jq -r '.network')
	local wallet_address=$(echo "$node_json" | jq -r '.wallet_address')
	local ethrpc_port=$(echo "$node_json" | jq -r '.ethrpc_port')
	local jwt=$(echo "$node_json" | jq -r '.beacond_config.jwt')
	local comet_address=$(echo "$node_json" | jq -r '.beacond_config.comet_address')
	local comet_pubkey=$(echo "$node_json" | jq -r '.beacond_config.comet_pubkey')
	local eth_beacon_pubkey=$(echo "$node_json" | jq -r '.beacond_config.eth_beacon_pubkey')

	validate_role "$role" || errors+=("Invalid role: $role")
	validate_moniker "$moniker" || errors+=("Invalid moniker: $moniker")
	validate_network "$network" || errors+=("Invalid network: $network")
	[[ -z "$wallet_address" ]] || validate_hex_address "$wallet_address" || errors+=("Invalid wallet_address: $wallet_address")
	validate_port "$ethrpc_port" || errors+=("Invalid ethrpc_port: $ethrpc_port")
	validate_jwt "$jwt" || errors+=("Invalid jwt: $jwt")
	validate_comet_address "$comet_address" || errors+=("Invalid comet_address: $comet_address")
	validate_pubkey "$eth_beacon_pubkey" || errors+=("Invalid eth_beacon_pubkey: $eth_beacon_pubkey")

	if [[ ${#errors[@]} -gt 0 ]]; then
		VALIDATION_ERROR="${errors[*]}"
		return 1
	fi
	return 0
}

# Validates a genesis deposit object
# Parameters: $1 - JSON deposit object string
# Returns: 0 if valid, 1 if invalid (sets $VALIDATION_ERROR on failure)
validate_deposit_object() {
	local deposit_json="$1"
	local errors=()

	local pubkey=$(echo "$deposit_json" | jq -r '.pubkey')
	local credentials=$(echo "$deposit_json" | jq -r '.credentials')
	local amount=$(echo "$deposit_json" | jq -r '.amount')
	local signature=$(echo "$deposit_json" | jq -r '.signature')
	local index=$(echo "$deposit_json" | jq -r '.index')

	validate_pubkey "$pubkey" || errors+=("Invalid pubkey: $pubkey")
	validate_hex_string "$credentials" || errors+=("Invalid credentials: $credentials")
	validate_hex_string "$amount" || errors+=("Invalid amount: $amount")
	validate_hex_string "$signature" || errors+=("Invalid signature: $signature")
	validate_integer "$index" || errors+=("Invalid index: $index")

	if [[ ${#errors[@]} -gt 0 ]]; then
		VALIDATION_ERROR="${errors[*]}"
		return 1
	fi
	return 0
}

# Validates a specific config field by name and value
# Parameters: $1 - field name, $2 - field value
# Returns: 0 if valid, 1 if invalid
validate_config_field() {
	local field="$1"
	local value="$2"

	case "$field" in
	# Empty strings or simple strings allowed for optional fields (check first!)
	*_keyring_default_keyname | *_graffiti | *_cors_* | *_wal_dir | *_external_address | *_seeds | *_persistent_peers | *_global_labels | *_metrics_sink | *_statsd_addr | *_chain_spec_file | *_priv_validator_laddr | *_tls_*_file | *_pprof_laddr | *_grpc_*_laddr | *_unconditional_peer_ids | *_private_peer_ids | *_rpc_servers | *_trust_hash | *_temp_dir | *_psql_conn | *_grpc_address)
		return 0
		;;

	# Boolean fields (must be specific!)
	skip_genesis | force | *_enabled | *_strict | *_unsafe | *_close_on_slow_client | *_keep_invalid_txs_in_cache | *_inter_block_cache | *_cache | *_broadcast | *_recheck | *_pex | *_seed_mode | *_disable_fastnode | *_addr_book_strict | *_allow_duplicate_ip | *_logging | apptoml_telemetry_enabled | apptoml_telemetry_enable_hostname | apptoml_telemetry_enable_hostname_label | apptoml_telemetry_enable_service_label | *_skip_timeout_commit | *_create_empty_blocks | *_discard_abci_responses | *_compact | configtoml_instrumentation_prometheus | configtoml_statesync_enable | configtoml_rpc_unsafe | configtoml_filter_peers | *_pruning_*_enabled | *_service_enabled)
		validate_boolean "$value"
		;;

	# Top-level fields
	moniker | configtoml_moniker) validate_moniker "$value" ;;
	network | apptoml_beacon_kit_chain_spec) validate_network "$value" ;;
	validators | full_nodes | pruned_nodes | total_nodes) validate_integer "$value" ;;
	beranode_dir | genesis_file | genesis_eth_file | *_path | *_file | *_dir) validate_path "$value" ;;
	mode) validate_mode "$value" ;;
	wallet_private_key) validate_hex_private_key "$value" ;;
	wallet_address)
		[[ -z "$value" ]] || validate_hex_address "$value"
		;;
	wallet_balance | deposit_amount) validate_hex_string "$value" || validate_integer "$value" ;;
	validator_root) validate_hex_string "$value" ;;
	*_suggested_fee_recipient) validate_hex_address "$value" ;;

	# Port fields (more specific than _address patterns)
	*_port | *ethrpc_port | *ethp2p_port | *ethproxy_port | *authrpc_port | *eth_port | *prometheus_port)
		validate_port "$value"
		;;

	# URL/Address fields (allow PORT_DEFINED_BY_NODE placeholder)
	*_dial_url | *_laddr | *_address)
		[[ "$value" =~ \<PORT_DEFINED_BY_NODE\> ]] || [[ -z "$value" ]] || validate_url "$value" || [[ "$value" =~ ^[0-9.:] ]] || return 0
		;;

	# Duration fields (specific timeout/interval/period patterns)
	*_timeout | *_period | apptoml_beacon_kit_shutdown_timeout | apptoml_beacon_kit_engine_rpc_* | apptoml_beacon_kit_payload_builder_payload_timeout | configtoml_p2p_persistent_peers_max_dial_period | configtoml_p2p_flush_throttle_timeout | configtoml_p2p_handshake_timeout | configtoml_p2p_dial_timeout | configtoml_mempool_recheck_timeout | configtoml_statesync_trust_period | configtoml_statesync_discovery_time | configtoml_statesync_chunk_request_timeout | configtoml_consensus_timeout_* | configtoml_consensus_peer_*_duration | configtoml_storage_pruning_interval)
		validate_duration "$value"
		;;

	# Integer interval/window fields (after duration patterns)
	configtoml_storage_compaction_interval | apptoml_pruning_interval | *_pruning_keep_recent | *_availability_window)
		validate_integer "$value"
		;;

	# Chain ID
	*chain_id) validate_string "$value" ;;

	# Integer configuration values
	*_height | *_retain_* | *_max_* | *_keep_* | apptoml_halt_* | apptoml_min_* | apptoml_iavl_cache_size | apptoml_telemetry_prometheus_retention_time | configtoml_*_buffer_size | configtoml_*_batch_size | configtoml_*_body_bytes | configtoml_*_header_bytes | configtoml_mempool_size | configtoml_mempool_max_tx_bytes | configtoml_mempool_max_txs_bytes | configtoml_mempool_cache_size | configtoml_mempool_experimental_* | configtoml_storage_compaction_interval | configtoml_*_send_rate | configtoml_*_recv_rate | configtoml_*_num_*_peers | configtoml_*_packet_* | configtoml_instrumentation_max_open_connections | configtoml_statesync_trust_height | configtoml_statesync_chunk_fetchers | configtoml_consensus_double_sign_check_height | configtoml_*_pruning_*_retain_height)
		validate_integer "$value"
		;;

	# Backend/type/implementation strings
	*_backend | *_db_backend | *_type | *_implementation | *_indexer | *_abci) validate_string "$value" ;;

	# Versions
	*_version) validate_string "$value" ;;

	# Log levels, formats, styles, names, hostnames
	*_log_level | *_log_format | *_style | *_output | *_time_format | *_service_name | apptoml_telemetry_datadog_hostname | *_namespace | *_experimental_db_key_layout) validate_string "$value" ;;

	# Default: non-empty string
	*) validate_string "$value" ;;
	esac
}

################################################################################
# 3. MAIN VALIDATION
################################################################################

# Validates the entire beranodes.config.json file
# Parameters: $1 - path to beranodes.config.json
# Returns: 0 if all validations pass, 1 if any fail
# Output: Prints validation errors to stderr
validate_beranodes_config() {
	local config_file="$1"
	local validation_errors=0

	# Check if file exists
	if [[ ! -f "$config_file" ]]; then
		echo "ERROR: Config file not found: $config_file" >&2
		return 1
	fi

	# Check if file is valid JSON
	if ! jq empty "$config_file" 2>/dev/null; then
		echo "ERROR: Invalid JSON in config file: $config_file" >&2
		return 1
	fi

	echo "Validating beranodes configuration: $config_file"

	# Read all top-level fields
	local fields=$(jq -r 'to_entries | .[] | select(.value | type != "array" and type != "object") | "\(.key)=\(.value)"' "$config_file")

	# Validate each field
	while IFS='=' read -r field value; do
		if ! validate_config_field "$field" "$value"; then
			echo "  ✗ Field '$field' failed validation: '$value'" >&2
			((validation_errors++))
		fi
	done <<<"$fields"

	# Validate nodes array
	local nodes_count=$(jq '.nodes | length' "$config_file")
	for ((i = 0; i < nodes_count; i++)); do
		local node=$(jq ".nodes[$i]" "$config_file")
		if ! validate_node_object "$node"; then
			echo "  ✗ Node $i validation failed: $VALIDATION_ERROR" >&2
			((validation_errors++))
		fi
	done

	# Validate genesis_deposits array
	local deposits_count=$(jq '.genesis_deposits | length' "$config_file")
	for ((i = 0; i < deposits_count; i++)); do
		local deposit=$(jq ".genesis_deposits[$i]" "$config_file")
		if ! validate_deposit_object "$deposit"; then
			echo "  ✗ Genesis deposit $i validation failed: $VALIDATION_ERROR" >&2
			((validation_errors++))
		fi
	done

	# Summary
	if [[ $validation_errors -eq 0 ]]; then
		echo "✓ All validations passed successfully"
		return 0
	else
		echo "✗ Validation failed with $validation_errors error(s)" >&2
		return 1
	fi
}

################################################################################
# EXPORT FUNCTIONS
################################################################################

# Export all validation functions for use in other scripts
export -f validate_string
export -f validate_boolean
export -f validate_integer
export -f validate_port
export -f validate_hex_address
export -f validate_hex_private_key
export -f validate_hex_string
export -f validate_jwt
export -f validate_path
export -f validate_url
export -f validate_duration
export -f validate_network
export -f validate_moniker
export -f validate_pubkey
export -f validate_base64
export -f validate_comet_address
export -f validate_mode
export -f validate_role
export -f validate_node_object
export -f validate_deposit_object
export -f validate_config_field
export -f validate_beranodes_config
