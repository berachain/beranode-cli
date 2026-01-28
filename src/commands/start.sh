# =============================================================================
# Start Command - Beranode CLI v0.2.1
# =============================================================================
# This module implements the 'start' command for the Beranode CLI tool.
# It orchestrates the startup of Berachain nodes (validators, full nodes, or
# pruned nodes) based on the configuration specified in beranodes.config.json.
#
# EXECUTION FLOW LEGEND:
# ----------------------
# [1] Parse command-line arguments and validate beranodes directory
# [2] Locate and validate beranodes.config.json configuration file
# [3] Parse configuration and extract node parameters
# [4] Validate network type (devnet, testnet, mainnet)
# [5] Download required artifacts (KZG trusted setup, genesis files)
# [6] Initialize node directories and configuration files
# [7] Start nodes based on role (validator, full node, or pruned node)
# [8] Monitor node health and report status
#
# VERSION HISTORY:
# ----------------
# v0.2.1 - Current version
#        - Added --help command support
#        - Enhanced version management with semantic versioning
#        - Improved error handling and validation
#        - Standardized logging output
#
# DEPENDENCIES:
# -------------
# - jq (JSON parsing)
# - beacond binary (consensus layer)
# - bera-reth binary (execution layer)
# - beranodes.config.json (configuration file)
#
# =============================================================================

# =============================================================================
# [SECTION 1] Help Documentation
# =============================================================================
# Displays comprehensive usage information for the start command.
# Invoked via: beranode start --help
# =============================================================================

show_start_help() {
	cat <<EOF
Usage: beranode start [OPTIONS]

Start Berachain nodes based on the configuration file.

Options:
  --beranodes-dir <path>    Specify the beranodes directory path
                            (default: \$PWD/beranodes)
  --help|-h                 Display this help message

Examples:
  beranode start
  beranode start --beranodes-dir /custom/path
  beranode start --help

EOF
}

# =============================================================================
# [SECTION 2] Main Start Command Function
# =============================================================================
# Primary entry point for the start command. Orchestrates the entire node
# startup process from configuration parsing to node initialization.
# =============================================================================

cmd_start() {
	# Enable debug output if DEBUG_MODE is set
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_start" >&2

	# -------------------------------------------------------------------------
	# [STEP 1] Command-Line Argument Parsing
	# -------------------------------------------------------------------------
	# Parse and validate command-line options. Supports:
	# - --beranodes-dir: Custom directory for node data
	# - --help/-h: Display help information
	# -------------------------------------------------------------------------

	local beranodes_dir="${BERANODES_PATH_DEFAULT}"

	while [[ $# -gt 0 ]]; do
		case $1 in
		--beranodes-dir)
			if [[ -z "$2" ]] || [[ "$2" == --* ]]; then
				log_warn "--beranodes-dir not provided or missing argument. Defaulting to: $beranodes_dir"
				shift
			else
				beranodes_dir="$2"
				shift 2
			fi
			;;
		--help | -h)
			show_start_help
			return 0
			;;
		*)
			log_error "Unknown option: $1"
			show_start_help
			return 1
			;;
		esac
	done

	# -------------------------------------------------------------------------
	# [STEP 2] Configuration File Validation
	# -------------------------------------------------------------------------
	# Verify the existence of beranodes.config.json in the specified directory.
	# This file contains all node configuration parameters including:
	# - Network type (devnet/testnet/mainnet)
	# - Node counts (validators, full nodes, pruned nodes)
	# - Port configurations
	# - Wallet addresses and keys
	# -------------------------------------------------------------------------

	log_info "Starting Beranode in ${beranodes_dir} directory"

	print_header "Starting Beranode"
	local beranodes_config_path="${beranodes_dir}/beranodes.config.json"

	if ! [[ -f "${beranodes_config_path}" ]]; then
		log_error "Beranode configuration file does not exist: ${beranodes_dir}/beranodes.config.json"
		return 1
	else
		log_success "Beranode configuration file exists: ${beranodes_config_path}"
	fi

	# This will ensure all required fields are present and properly formatted
	# Validate the beranodes configuration JSON file before proceeding
	if ! validate_beranodes_config "${beranodes_config_path}"; then
		log_error "Configuration validation failed. Please review errors above and fix your beranodes.config.json file."
		return 1
	else
		log_success "beranodes.config.json passed validation."
	fi

	# -------------------------------------------------------------------------
	# [STEP 3] Configuration Parsing
	# -------------------------------------------------------------------------
	# Extract all configuration values from beranodes.config.json using jq.
	# These values control node behavior, network settings, and resource
	# allocation throughout the startup process.
	# -------------------------------------------------------------------------

	print_header "Beranode Configuration"
	log_info "Configuration file: ${beranodes_config_path}"

	local config_json_path="${beranodes_dir}/beranodes.config.json"

	# Binary paths
	local beranodes_dir=$(jq -r '.beranode_dir' "${config_json_path}")
	local bin_beacond="$beranodes_dir${BERANODES_PATH_BIN}/${BIN_BEACONKIT}"
	local bin_bera_reth="$beranodes_dir${BERANODES_PATH_BIN}/${BIN_BERARETH}"

	# Node identity and network configuration
	local moniker=$(jq -r '.moniker' "${config_json_path}")
	local network=$(jq -r '.network' "${config_json_path}")

	# Node count configuration
	local validators=$(jq -r '.validators' "${config_json_path}")
	local full_nodes=$(jq -r '.full_nodes' "${config_json_path}")
	local pruned_nodes=$(jq -r '.pruned_nodes' "${config_json_path}")
	local total_nodes=$(jq -r '.total_nodes' "${config_json_path}")

	# Directory and operational settings
	local beranode_dir=$(jq -r '.beranode_dir' "${config_json_path}")
	local skip_genesis=$(jq -r '.skip_genesis' "${config_json_path}")
	local force=$(jq -r '.force' "${config_json_path}")
	local mode=$(jq -r '.mode' "${config_json_path}")

	# Wallet configuration
	local wallet_private_key=$(jq -r '.wallet_private_key' "${config_json_path}")
	local wallet_address=$(jq -r '.wallet_address' "${config_json_path}")

	# Node-specific configurations (array of node objects)
	local nodes=$(jq -r '.nodes' "${config_json_path}")
	local nodes_count=$(echo "${nodes}" | jq -r '. | length')

	# -------------------------------------------------------------------------
	# [DEBUG] Node Configuration Inspection (Currently Disabled)
	# -------------------------------------------------------------------------
	# Uncomment this section to debug individual node configurations.
	# Useful for troubleshooting port conflicts or misconfigurations.
	# -------------------------------------------------------------------------

	# -------------------------------------------------------------------------
	# [STEP 5] Network-Specific Initialization
	# -------------------------------------------------------------------------
	# Route to the appropriate network handler based on the configuration.
	# Currently supports: devnet (local development)
	# Planned: bepolia (testnet), mainnet (production)
	# -------------------------------------------------------------------------

	if [[ "${network}" == "${CHAIN_NAME_DEVNET}" ]]; then
		log_info "Starting Beranode in ${CHAIN_NAME_DEVNET} network"

		# ---------------------------------------------------------------------
		# [STEP 5.1] Mode Selection: Local Development
		# ---------------------------------------------------------------------
		# Local mode: Single-machine deployment for development/testing
		# - Runs all nodes on localhost with incremental ports
		# - Suitable for rapid iteration and testing
		# ---------------------------------------------------------------------

		if [[ "${mode}" == "local" ]]; then
			log_info "Starting Beranode in local mode"

			# Do a a check if `beranode_dir/nodes` has any directories, if so, ask if the user wants to delete them
			if [ -d "${beranode_dir}/nodes" ] && [ "$(ls -A "${beranode_dir}/nodes")" ]; then
				log_warn "Node directories already exist in ${beranode_dir}/nodes"
				read -p "Do you want to delete them? (y/n) " delete_nodes
				if [ "${delete_nodes}" == "y" ]; then
					rm -rf "${beranode_dir}/nodes"
					log_info "Node directories deleted"
				else
					log_error "Node directories not deleted. stopping..."
					return 1
				fi
			fi
			mkdir -p "${beranode_dir}/nodes"
			log_info "Node directories created in ${beranode_dir}/nodes"

			local network=$(jq -r '.network' "${config_json_path}")
			local chain_id="${CHAIN_ID_DEVNET}"
			local chain_spec="${CHAIN_NAME_DEVNET}"
			local chain_id_beacond=$(jq -r '.clienttoml.chain_id' "${config_json_path}")

			local wallet_address=$(jq -r '.wallet_address' "${config_json_path}")
			local wallet_private_key=$(jq -r '.wallet_private_key' "${config_json_path}")
			local wallet_balance=$(jq -r '.wallet_balance' "${config_json_path}")

			# get all seeds and peers
			local seeds=()
			local peers=()
			for ((node_index = 0; node_index < ${nodes_count}; node_index++)); do
				local json=$(echo "${nodes}" | jq -r ".[$node_index]")
				local id=$(echo "${json}" | jq -r '.node_id')
				seeds[${node_index}]="${id}"
				peers[${node_index}]="${id}"
			done

			for ((node_index = 0; node_index < ${nodes_count}; node_index++)); do
				echo "--------------------------------"
				echo "Configuring node $node_index"
				echo "--------------------------------"

				local node_json=$(echo "${nodes}" | jq -r ".[$node_index]")
				local role=$(echo "${node_json}" | jq -r '.role')
				local moniker=$(echo "${node_json}" | jq -r '.moniker')
				local node_key_type=$(echo "${node_json}" | jq -r '.node_key.priv_key.type')
				local node_key_value=$(echo "${node_json}" | jq -r '.node_key.priv_key.value')
				local node_id=$(echo "${node_json}" | jq -r '.node_id')
				local priv_validator_key_address=$(echo "${node_json}" | jq -r '.priv_validator_key.address')
				local priv_validator_key_pubkey_type=$(echo "${node_json}" | jq -r '.priv_validator_key.pub_key.type')
				local priv_validator_key_pubkey_value=$(echo "${node_json}" | jq -r '.priv_validator_key.pub_key.value')
				local priv_validator_key_privkey_type=$(echo "${node_json}" | jq -r '.priv_validator_key.priv_key.type')
				local priv_validator_key_privkey_value=$(echo "${node_json}" | jq -r '.priv_validator_key.priv_key.value')
				local premined_deposit=$(echo "${node_json}" | jq -r '.premined_deposit')
				local deposit_amount=$(echo "${node_json}" | jq -r '.deposit_amount')
				local jwt=$(echo "${node_json}" | jq -r '.jwt')
				local comet_address=$(echo "${node_json}" | jq -r '.comet_address')
				local comet_pubkey=$(echo "${node_json}" | jq -r '.comet_pubkey')
				local eth_beacon_pubkey=$(echo "${node_json}" | jq -r '.eth_beacon_pubkey')

				# ports
				local ethrpc_port=$(echo "${node_json}" | jq -r '.ethrpc_port')
				local ethp2p_port=$(echo "${node_json}" | jq -r '.ethp2p_port')
				local ethproxy_port=$(echo "${node_json}" | jq -r '.ethproxy_port')
				local el_ethrpc_port=$(echo "${node_json}" | jq -r '.el_ethrpc_port')
				local el_authrpc_port=$(echo "${node_json}" | jq -r '.el_authrpc_port')
				local el_eth_port=$(echo "${node_json}" | jq -r '.el_eth_port')
				local el_prometheus_port=$(echo "${node_json}" | jq -r '.el_prometheus_port')
				local cl_prometheus_port=$(echo "${node_json}" | jq -r '.cl_prometheus_port')
				local beacond_node_port=$(echo "${node_json}" | jq -r '.beacond_node_port')

				# client.toml variables
				local clienttoml_chain_id=$(jq -r '.clienttoml.chain_id' "${config_json_path}")
				local clienttoml_keyring_backend=$(jq -r '.clienttoml.keyring_backend' "${config_json_path}")
				local clienttoml_keyring_default_keyname=$(jq -r '.clienttoml.keyring_default_keyname' "${config_json_path}")
				local clienttoml_output=$(jq -r '.clienttoml.output' "${config_json_path}")
				local clienttoml_node=$(jq -r '.clienttoml.node' "${config_json_path}")
				local clienttoml_broadcast_mode=$(jq -r '.clienttoml.broadcast_mode' "${config_json_path}")
				local clienttoml_grpc_address=$(jq -r '.clienttoml.grpc_address' "${config_json_path}")
				local clienttoml_grpc_insecure=$(jq -r '.clienttoml.grpc_insecure' "${config_json_path}")

				# app.toml variables
				local apptoml_pruning=$(jq -r '.apptoml.pruning' "${config_json_path}")
				local apptoml_pruning_keep_recent=$(jq -r '.apptoml.pruning_keep_recent' "${config_json_path}")
				local apptoml_pruning_interval=$(jq -r '.apptoml.pruning_interval' "${config_json_path}")
				local apptoml_halt_height=$(jq -r '.apptoml.halt_height' "${config_json_path}")
				local apptoml_halt_time=$(jq -r '.apptoml.halt_time' "${config_json_path}")
				local apptoml_min_retain_blocks=$(jq -r '.apptoml.min_retain_blocks' "${config_json_path}")
				local apptoml_inter_block_cache=$(jq -r '.apptoml.inter_block_cache' "${config_json_path}")
				local apptoml_iavl_cache_size=$(jq -r '.apptoml.iavl_cache_size' "${config_json_path}")
				local apptoml_iavl_disable_fastnode=$(jq -r '.apptoml.iavl_disable_fastnode' "${config_json_path}")
				local apptoml_telemetry_service_name=$(jq -r '.apptoml.telemetry_service_name' "${config_json_path}")
				local apptoml_telemetry_enabled=$(jq -r '.apptoml.telemetry_enabled' "${config_json_path}")
				local apptoml_telemetry_enable_hostname=$(jq -r '.apptoml.telemetry_enable_hostname' "${config_json_path}")
				local apptoml_telemetry_enable_hostname_label=$(jq -r '.apptoml.telemetry_enable_hostname_label' "${config_json_path}")
				local apptoml_telemetry_enable_service_label=$(jq -r '.apptoml.telemetry_enable_service_label' "${config_json_path}")
				local apptoml_telemetry_prometheus_retention_time=$(jq -r '.apptoml.telemetry_prometheus_retention_time' "${config_json_path}")
				local apptoml_telemetry_global_labels=$(jq -r '.apptoml.telemetry_global_labels' "${config_json_path}")
				local apptoml_telemetry_metrics_sink=$(jq -r '.apptoml.telemetry_metrics_sink' "${config_json_path}")
				local apptoml_telemetry_statsd_addr=$(jq -r '.apptoml.telemetry_statsd_addr' "${config_json_path}")
				local apptoml_telemetry_datadog_hostname=$(jq -r '.apptoml.telemetry_datadog_hostname' "${config_json_path}")
				local apptoml_beacon_kit_chain_spec=$(jq -r '.apptoml.beacon_kit_chain_spec' "${config_json_path}")
				local apptoml_beacon_kit_chain_spec_file=$(jq -r '.apptoml.beacon_kit_chain_spec_file' "${config_json_path}")
				local apptoml_beacon_kit_shutdown_timeout=$(jq -r '.apptoml.beacon_kit_shutdown_timeout' "${config_json_path}")
				local apptoml_beacon_kit_engine_rpc_dial_url=$(jq -r '.apptoml.beacon_kit_engine_rpc_dial_url' "${config_json_path}")
				local apptoml_beacon_kit_engine_rpc_timeout=$(jq -r '.apptoml.beacon_kit_engine_rpc_timeout' "${config_json_path}")
				local apptoml_beacon_kit_engine_rpc_startup_check_interval=$(jq -r '.apptoml.beacon_kit_engine_rpc_startup_check_interval' "${config_json_path}")
				local apptoml_beacon_kit_engine_rpc_jwt_refresh_interval=$(jq -r '.apptoml.beacon_kit_engine_rpc_jwt_refresh_interval' "${config_json_path}")
				local apptoml_beacon_kit_engine_jwt_secret_path=$(jq -r '.apptoml.beacon_kit_engine_jwt_secret_path' "${config_json_path}")
				local apptoml_beacon_kit_logger_time_format=$(jq -r '.apptoml.beacon_kit_logger_time_format' "${config_json_path}")
				local apptoml_beacon_kit_logger_log_level=$(jq -r '.apptoml.beacon_kit_logger_log_level' "${config_json_path}")
				local apptoml_beacon_kit_logger_style=$(jq -r '.apptoml.beacon_kit_logger_style' "${config_json_path}")
				local apptoml_beacon_kit_kzg_trusted_setup_path=$(jq -r '.apptoml.beacon_kit_kzg_trusted_setup_path' "${config_json_path}")
				local apptoml_beacon_kit_kzg_implementation=$(jq -r '.apptoml.beacon_kit_kzg_implementation' "${config_json_path}")
				local apptoml_beacon_kit_payload_builder_enabled=$(jq -r '.apptoml.beacon_kit_payload_builder_enabled' "${config_json_path}")
				local apptoml_beacon_kit_payload_builder_suggested_fee_recipient=$(jq -r '.apptoml.beacon_kit_payload_builder_suggested_fee_recipient' "${config_json_path}")
				local apptoml_beacon_kit_payload_builder_payload_timeout=$(jq -r '.apptoml.beacon_kit_payload_builder_payload_timeout' "${config_json_path}")
				local apptoml_beacon_kit_validator_graffiti=$(jq -r '.apptoml.beacon_kit_validator_graffiti' "${config_json_path}")
				local apptoml_beacon_kit_validator_availability_window=$(jq -r '.apptoml.beacon_kit_validator_availability_window' "${config_json_path}")
				local apptoml_beacon_kit_node_api_enabled=$(jq -r '.apptoml.beacon_kit_node_api_enabled' "${config_json_path}")
				local apptoml_beacon_kit_node_api_address=$(jq -r '.apptoml.beacon_kit_node_api_address' "${config_json_path}")
				local apptoml_beacon_kit_node_api_logging=$(jq -r '.apptoml.beacon_kit_node_api_logging' "${config_json_path}")

				# config.toml variables
				local configtoml_version=$(jq -r '.configtoml.version' "${config_json_path}")
				local configtoml_proxy_app=$(jq -r '.configtoml.proxy_app' "${config_json_path}")
				local configtoml_moniker=$(jq -r '.configtoml.moniker' "${config_json_path}")
				local configtoml_db_backend=$(jq -r '.configtoml.db_backend' "${config_json_path}")
				local configtoml_db_dir=$(jq -r '.configtoml.db_dir' "${config_json_path}")
				local configtoml_log_level=$(jq -r '.configtoml.log_level' "${config_json_path}")
				local configtoml_log_format=$(jq -r '.configtoml.log_format' "${config_json_path}")
				local configtoml_genesis_file=$(jq -r '.configtoml.genesis_file' "${config_json_path}")
				local configtoml_priv_validator_key_file=$(jq -r '.configtoml.priv_validator_key_file' "${config_json_path}")
				local configtoml_priv_validator_state_file=$(jq -r '.configtoml.priv_validator_state_file' "${config_json_path}")
				local configtoml_priv_validator_laddr=$(jq -r '.configtoml.priv_validator_laddr' "${config_json_path}")
				local configtoml_node_key_file=$(jq -r '.configtoml.node_key_file' "${config_json_path}")
				local configtoml_abci=$(jq -r '.configtoml.abci' "${config_json_path}")
				local configtoml_filter_peers=$(jq -r '.configtoml.filter_peers' "${config_json_path}")
				local configtoml_rpc_laddr=$(jq -r '.configtoml.rpc_laddr' "${config_json_path}")
				local configtoml_rpc_cors_allowed_origins=$(jq -r '.configtoml.rpc_cors_allowed_origins' "${config_json_path}")
				local configtoml_rpc_cors_allowed_methods=$(jq -r '.configtoml.rpc_cors_allowed_methods' "${config_json_path}")
				local configtoml_rpc_cors_allowed_headers=$(jq -r '.configtoml.rpc_cors_allowed_headers' "${config_json_path}")
				local configtoml_rpc_unsafe=$(jq -r '.configtoml.rpc_unsafe' "${config_json_path}")
				local configtoml_rpc_max_open_connections=$(jq -r '.configtoml.rpc_max_open_connections' "${config_json_path}")
				local configtoml_rpc_max_subscription_clients=$(jq -r '.configtoml.rpc_max_subscription_clients' "${config_json_path}")
				local configtoml_rpc_max_subscriptions_per_client=$(jq -r '.configtoml.rpc_max_subscriptions_per_client' "${config_json_path}")
				local configtoml_rpc_experimental_subscription_buffer_size=$(jq -r '.configtoml.rpc_experimental_subscription_buffer_size' "${config_json_path}")
				local configtoml_rpc_experimental_websocket_write_buffer_size=$(jq -r '.configtoml.rpc_experimental_websocket_write_buffer_size' "${config_json_path}")
				local configtoml_rpc_experimental_close_on_slow_client=$(jq -r '.configtoml.rpc_experimental_close_on_slow_client' "${config_json_path}")
				local configtoml_rpc_timeout_broadcast_tx_commit=$(jq -r '.configtoml.rpc_timeout_broadcast_tx_commit' "${config_json_path}")
				local configtoml_rpc_max_request_batch_size=$(jq -r '.configtoml.rpc_max_request_batch_size' "${config_json_path}")
				local configtoml_rpc_max_body_bytes=$(jq -r '.configtoml.rpc_max_body_bytes' "${config_json_path}")
				local configtoml_rpc_max_header_bytes=$(jq -r '.configtoml.rpc_max_header_bytes' "${config_json_path}")
				local configtoml_rpc_tls_cert_file=$(jq -r '.configtoml.rpc_tls_cert_file' "${config_json_path}")
				local configtoml_rpc_tls_key_file=$(jq -r '.configtoml.rpc_tls_key_file' "${config_json_path}")
				local configtoml_rpc_pprof_laddr=$(jq -r '.configtoml.rpc_pprof_laddr' "${config_json_path}")
				local configtoml_grpc_laddr=$(jq -r '.configtoml.grpc_laddr' "${config_json_path}")
				local configtoml_grpc_version_service_enabled=$(jq -r '.configtoml.grpc_version_service_enabled' "${config_json_path}")
				local configtoml_grpc_block_service_enabled=$(jq -r '.configtoml.grpc_block_service_enabled' "${config_json_path}")
				local configtoml_grpc_block_results_service_enabled=$(jq -r '.configtoml.grpc_block_results_service_enabled' "${config_json_path}")
				local configtoml_grpc_privileged_laddr=$(jq -r '.configtoml.grpc_privileged_laddr' "${config_json_path}")
				local configtoml_grpc_privileged_pruning_service_enabled=$(jq -r '.configtoml.grpc_privileged_pruning_service_enabled' "${config_json_path}")
				local configtoml_p2p_laddr=$(jq -r '.configtoml.p2p_laddr' "${config_json_path}")
				local configtoml_p2p_external_address=$(jq -r '.configtoml.p2p_external_address' "${config_json_path}")
				local configtoml_p2p_seeds=$(jq -r '.configtoml.p2p_seeds' "${config_json_path}")
				local configtoml_p2p_persistent_peers=$(jq -r '.configtoml.p2p_persistent_peers' "${config_json_path}")
				local configtoml_p2p_addr_book_file=$(jq -r '.configtoml.p2p_addr_book_file' "${config_json_path}")
				local configtoml_p2p_addr_book_strict=$(jq -r '.configtoml.p2p_addr_book_strict' "${config_json_path}")
				local configtoml_p2p_max_num_inbound_peers=$(jq -r '.configtoml.p2p_max_num_inbound_peers' "${config_json_path}")
				local configtoml_p2p_max_num_outbound_peers=$(jq -r '.configtoml.p2p_max_num_outbound_peers' "${config_json_path}")
				local configtoml_p2p_unconditional_peer_ids=$(jq -r '.configtoml.p2p_unconditional_peer_ids' "${config_json_path}")
				local configtoml_p2p_persistent_peers_max_dial_period=$(jq -r '.configtoml.p2p_persistent_peers_max_dial_period' "${config_json_path}")
				local configtoml_p2p_flush_throttle_timeout=$(jq -r '.configtoml.p2p_flush_throttle_timeout' "${config_json_path}")
				local configtoml_p2p_max_packet_msg_payload_size=$(jq -r '.configtoml.p2p_max_packet_msg_payload_size' "${config_json_path}")
				local configtoml_p2p_send_rate=$(jq -r '.configtoml.p2p_send_rate' "${config_json_path}")
				local configtoml_p2p_recv_rate=$(jq -r '.configtoml.p2p_recv_rate' "${config_json_path}")
				local configtoml_p2p_pex=$(jq -r '.configtoml.p2p_pex' "${config_json_path}")
				local configtoml_p2p_seed_mode=$(jq -r '.configtoml.p2p_seed_mode' "${config_json_path}")
				local configtoml_p2p_private_peer_ids=$(jq -r '.configtoml.p2p_private_peer_ids' "${config_json_path}")
				local configtoml_p2p_allow_duplicate_ip=$(jq -r '.configtoml.p2p_allow_duplicate_ip' "${config_json_path}")
				local configtoml_p2p_handshake_timeout=$(jq -r '.configtoml.p2p_handshake_timeout' "${config_json_path}")
				local configtoml_p2p_dial_timeout=$(jq -r '.configtoml.p2p_dial_timeout' "${config_json_path}")
				local configtoml_mempool_type=$(jq -r '.configtoml.mempool_type' "${config_json_path}")
				local configtoml_mempool_recheck=$(jq -r '.configtoml.mempool_recheck' "${config_json_path}")
				local configtoml_mempool_recheck_timeout=$(jq -r '.configtoml.mempool_recheck_timeout' "${config_json_path}")
				local configtoml_mempool_broadcast=$(jq -r '.configtoml.mempool_broadcast' "${config_json_path}")
				local configtoml_mempool_wal_dir=$(jq -r '.configtoml.mempool_wal_dir' "${config_json_path}")
				local configtoml_mempool_size=$(jq -r '.configtoml.mempool_size' "${config_json_path}")
				local configtoml_mempool_max_tx_bytes=$(jq -r '.configtoml.mempool_max_tx_bytes' "${config_json_path}")
				local configtoml_mempool_max_txs_bytes=$(jq -r '.configtoml.mempool_max_txs_bytes' "${config_json_path}")
				local configtoml_mempool_cache_size=$(jq -r '.configtoml.mempool_cache_size' "${config_json_path}")
				local configtoml_mempool_keep_invalid_txs_in_cache=$(jq -r '.configtoml.mempool_keep_invalid_txs_in_cache' "${config_json_path}")
				local configtoml_statesync_enable=$(jq -r '.configtoml.statesync_enable' "${config_json_path}")
				local configtoml_statesync_rpc_servers=$(jq -r '.configtoml.statesync_rpc_servers' "${config_json_path}")
				local configtoml_statesync_trust_height=$(jq -r '.configtoml.statesync_trust_height' "${config_json_path}")
				local configtoml_statesync_trust_hash=$(jq -r '.configtoml.statesync_trust_hash' "${config_json_path}")
				local configtoml_statesync_trust_period=$(jq -r '.configtoml.statesync_trust_period' "${config_json_path}")
				local configtoml_statesync_discovery_time=$(jq -r '.configtoml.statesync_discovery_time' "${config_json_path}")
				local configtoml_statesync_temp_dir=$(jq -r '.configtoml.statesync_temp_dir' "${config_json_path}")
				local configtoml_statesync_chunk_request_timeout=$(jq -r '.configtoml.statesync_chunk_request_timeout' "${config_json_path}")
				local configtoml_statesync_chunk_fetchers=$(jq -r '.configtoml.statesync_chunk_fetchers' "${config_json_path}")
				local configtoml_blocksync_version=$(jq -r '.configtoml.blocksync_version' "${config_json_path}")
				local configtoml_consensus_wal_file=$(jq -r '.configtoml.consensus_wal_file' "${config_json_path}")
				local configtoml_consensus_timeout_propose=$(jq -r '.configtoml.consensus_timeout_propose' "${config_json_path}")
				local configtoml_consensus_timeout_propose_delta=$(jq -r '.configtoml.consensus_timeout_propose_delta' "${config_json_path}")
				local configtoml_consensus_timeout_prevote=$(jq -r '.configtoml.consensus_timeout_prevote' "${config_json_path}")
				local configtoml_consensus_timeout_prevote_delta=$(jq -r '.configtoml.consensus_timeout_prevote_delta' "${config_json_path}")
				local configtoml_consensus_timeout_precommit=$(jq -r '.configtoml.consensus_timeout_precommit' "${config_json_path}")
				local configtoml_consensus_timeout_precommit_delta=$(jq -r '.configtoml.consensus_timeout_precommit_delta' "${config_json_path}")
				local configtoml_consensus_timeout_commit=$(jq -r '.configtoml.consensus_timeout_commit' "${config_json_path}")
				local configtoml_consensus_skip_timeout_commit=$(jq -r '.configtoml.consensus_skip_timeout_commit' "${config_json_path}")
				local configtoml_consensus_double_sign_check_height=$(jq -r '.configtoml.consensus_double_sign_check_height' "${config_json_path}")
				local configtoml_consensus_create_empty_blocks=$(jq -r '.configtoml.consensus_create_empty_blocks' "${config_json_path}")
				local configtoml_consensus_create_empty_blocks_interval=$(jq -r '.configtoml.consensus_create_empty_blocks_interval' "${config_json_path}")
				local configtoml_consensus_peer_gossip_sleep_duration=$(jq -r '.configtoml.consensus_peer_gossip_sleep_duration' "${config_json_path}")
				local configtoml_consensus_peer_gossip_intraloop_sleep_duration=$(jq -r '.configtoml.consensus_peer_gossip_intraloop_sleep_duration' "${config_json_path}")
				local configtoml_consensus_peer_query_maj23_sleep_duration=$(jq -r '.configtoml.consensus_peer_query_maj23_sleep_duration' "${config_json_path}")
				local configtoml_storage_discard_abci_responses=$(jq -r '.configtoml.storage_discard_abci_responses' "${config_json_path}")
				local configtoml_storage_experimental_db_key_layout=$(jq -r '.configtoml.storage_experimental_db_key_layout' "${config_json_path}")
				local configtoml_storage_compact=$(jq -r '.configtoml.storage_compact' "${config_json_path}")
				local configtoml_storage_compaction_interval=$(jq -r '.configtoml.storage_compaction_interval' "${config_json_path}")
				local configtoml_storage_pruning_interval=$(jq -r '.configtoml.storage_pruning_interval' "${config_json_path}")
				local configtoml_storage_pruning_data_companion_enabled=$(jq -r '.configtoml.storage_pruning_data_companion_enabled' "${config_json_path}")
				local configtoml_storage_pruning_data_companion_initial_block_retain_height=$(jq -r '.configtoml.storage_pruning_data_companion_initial_block_retain_height' "${config_json_path}")
				local configtoml_storage_pruning_data_companion_initial_block_results_retain_height=$(jq -r '.configtoml.storage_pruning_data_companion_initial_block_results_retain_height' "${config_json_path}")
				local configtoml_tx_index_indexer=$(jq -r '.configtoml.tx_index_indexer' "${config_json_path}")
				local configtoml_tx_index_psql_conn=$(jq -r '.configtoml.tx_index_psql_conn' "${config_json_path}")
				local configtoml_instrumentation_prometheus=$(jq -r '.configtoml.instrumentation_prometheus' "${config_json_path}")
				local configtoml_instrumentation_prometheus_listen_addr=$(jq -r '.configtoml.instrumentation_prometheus_listen_addr' "${config_json_path}")
				local configtoml_instrumentation_max_open_connections=$(jq -r '.configtoml.instrumentation_max_open_connections' "${config_json_path}")
				local configtoml_instrumentation_namespace=$(jq -r '.configtoml.instrumentation_namespace' "${config_json_path}")

				# Make node directories
				local node_dir="${beranodes_dir}${BERANODES_PATH_NODES}/${role}-${node_index}"
				local beacond_dir="${node_dir}/beacond"
				local bera_reth_dir="${node_dir}/bera-reth"
				mkdir -p "${node_dir}"
				mkdir -p "${beacond_dir}"
				mkdir -p "${bera_reth_dir}"

				# Init beacond node
				${bin_beacond} init "${moniker}" --chain-id "${chain_id_beacond}" --beacon-kit.chain-spec "${chain_spec}" --home "${beacond_dir}" 2>/dev/null

				# - replace priv_validator_key.json
				cat >"${beacond_dir}/config/priv_validator_key.json" <<EOF
{
  "address": "${priv_validator_key_address}",
  "pub_key": {
    "type": "${priv_validator_key_pubkey_type}",
    "value": "${priv_validator_key_pubkey_value}"
  },
  "priv_key": {
    "type": "${priv_validator_key_privkey_type}",
    "value": "${priv_validator_key_privkey_value}"
  }
}
EOF
				# - replace node_key.json
				cat >"${beacond_dir}/config/node_key.json" <<EOF
{
  "priv_key": {
    "type": "${node_key_type}",
    "value": "${node_key_value}"
  }
}
EOF

				# - update genesis.json
				cp -f "${beranodes_dir}/tmp/genesis.json" "${node_dir}/beacond/config/genesis.json"

				# - add jwt.hex
				cat >"${node_dir}/beacond/config/jwt.hex" <<EOF
${jwt}
EOF

				# - update client.toml
				# chain-id
				sed "${SED_OPT[@]}" "s|^chain_id = \".*\"|chain_id = \"${chain_id_beacond}\"|" "${node_dir}/beacond/config/client.toml"
				# keyring-backend
				sed "${SED_OPT[@]}" "s|^keyring_backend = \".*\"|keyring_backend = \"${clienttoml_keyring_backend}\"|" "${node_dir}/beacond/config/client.toml"
				# keyring-default-keyname
				sed "${SED_OPT[@]}" "s|^keyring_default_keyname = \".*\"|keyring_default_keyname = \"${clienttoml_keyring_default_keyname}\"|" "${node_dir}/beacond/config/client.toml"
				# output
				sed "${SED_OPT[@]}" "s|^output = \".*\"|output = \"${clienttoml_output}\"|" "${node_dir}/beacond/config/client.toml"
				# node
				sed "${SED_OPT[@]}" "s|^node = \".*\"|node = \"tcp://localhost:${ethrpc_port}\"|" "${node_dir}/beacond/config/client.toml"
				# broadcast-mode
				sed "${SED_OPT[@]}" "s|^broadcast_mode = \".*\"|broadcast_mode = \"${clienttoml_broadcast_mode}\"|" "${node_dir}/beacond/config/client.toml"
				# grpc-address
				sed "${SED_OPT[@]}" "s|^grpc_address = \".*\"|grpc_address = \"${clienttoml_grpc_address}\"|" "${node_dir}/beacond/config/client.toml"
				# grpc-insecure
				sed "${SED_OPT[@]}" "s|^grpc_insecure = \".*\"|grpc_insecure = \"${clienttoml_grpc_insecure}\"|" "${node_dir}/beacond/config/client.toml"

				# - update app.toml
				echo "--------------------------------"
				echo "app.toml"
				echo "--------------------------------"
				# [base]
				# pruning - TODO - revamp if pruned node
				sed "${SED_OPT[@]}" "s|^pruning = \".*\"|pruning = \"${apptoml_pruning}\"|" "${node_dir}/beacond/config/app.toml"
				# pruning-keep-recent
				sed "${SED_OPT[@]}" "s|^pruning-keep-recent = \".*\"|pruning-keep-recent = \"${apptoml_pruning_keep_recent}\"|" "${node_dir}/beacond/config/app.toml"
				# pruning-interval
				sed "${SED_OPT[@]}" "s|^pruning-interval = \".*\"|pruning-interval = \"${apptoml_pruning_interval}\"|" "${node_dir}/beacond/config/app.toml"
				# halt-height
				sed "${SED_OPT[@]}" "s|^halt-height = \".*\"|halt-height = \"${apptoml_halt_height}\"|" "${node_dir}/beacond/config/app.toml"
				# halt-time
				sed "${SED_OPT[@]}" "s|^halt-time = \".*\"|halt-time = \"${apptoml_halt_time}\"|" "${node_dir}/beacond/config/app.toml"
				# min-retain-blocks
				sed "${SED_OPT[@]}" "s|^min-retain-blocks = \".*\"|min-retain-blocks = \"${apptoml_min_retain_blocks}\"|" "${node_dir}/beacond/config/app.toml"
				# inter-block-cache
				sed "${SED_OPT[@]}" "s|^inter-block-cache = \".*\"|inter-block-cache = \"${apptoml_inter_block_cache}\"|" "${node_dir}/beacond/config/app.toml"
				# iavl-cache-size
				sed "${SED_OPT[@]}" "s|^iavl-cache-size = \".*\"|iavl-cache-size = \"${apptoml_iavl_cache_size}\"|" "${node_dir}/beacond/config/app.toml"
				# iavl-disable-fastnode
				sed "${SED_OPT[@]}" "s|^iiavl-disable-fastnode = \".*\"|iiavl-disable-fastnode = \"${apptoml_iavl_disable_fastnode}\"|" "${node_dir}/beacond/config/app.toml"
				# [telemetry]
				# service-name
				sed "${SED_OPT[@]}" "s|^service-name = \".*\"|service-name = \"${apptoml_telemetry_service_name}\"|" "${node_dir}/beacond/config/app.toml"
				# enabled
				sed "${SED_OPT[@]}" "70s|^enabled = .*|enabled = ${apptoml_telemetry_enabled}|" "${node_dir}/beacond/config/app.toml"
				# enable-hostname
				sed "${SED_OPT[@]}" "s|^enable-hostname = \".*\"|enable-hostname = \"${apptoml_telemetry_enable_hostname}\"|" "${node_dir}/beacond/config/app.toml"
				# enable-hostname-label
				sed "${SED_OPT[@]}" "s|^enable-hostname-label = \".*\"|enable-hostname-label = \"${apptoml_telemetry_enable_hostname_label}\"|" "${node_dir}/beacond/config/app.toml"
				# enable-service-label
				sed "${SED_OPT[@]}" "s|^enable-service-label = \".*\"|enable-service-label = \"${apptoml_telemetry_enable_service_label}\"|" "${node_dir}/beacond/config/app.toml"
				# prometheus-retention-time
				sed "${SED_OPT[@]}" "s|^prometheus-retention-time = \".*\"|prometheus-retention-time = \"${apptoml_telemetry_prometheus_retention_time}\"|" "${node_dir}/beacond/config/app.toml"
				# global-labels
				sed "${SED_OPT[@]}" "s|^global-labels = \[.*\]|global-labels = [\n${apptoml_telemetry_global_labels}\n]|" "${node_dir}/beacond/config/app.toml"
				# metrics-sink
				sed "${SED_OPT[@]}" "s|^metrics-sink = \".*\"|metrics-sink = \"${apptoml_telemetry_metrics_sink}\"|" "${node_dir}/beacond/config/app.toml"
				# statsd-addr
				sed "${SED_OPT[@]}" "s|^statsd-addr = \".*\"|statsd-addr = \"${apptoml_telemetry_statsd_addr}\"|" "${node_dir}/beacond/config/app.toml"
				# datadog-hostname
				sed "${SED_OPT[@]}" "s|^datadog-hostname = \".*\"|datadog-hostname = \"${moniker}\"|" "${node_dir}/beacond/config/app.toml"
				# [beacon-kit]
				# chain-spec
				sed "${SED_OPT[@]}" "s|^chain-spec = \".*\"|chain-spec = \"${apptoml_beacon_kit_chain_spec}\"|" "${node_dir}/beacond/config/app.toml"
				# chain-spec-file
				sed "${SED_OPT[@]}" "s|^chain-spec-file = \".*\"|chain-spec-file = \"${apptoml_beacon_kit_chain_spec_file}\"|" "${node_dir}/beacond/config/app.toml"
				# shutdown-timeout
				sed "${SED_OPT[@]}" "s|^shutdown-timeout = \".*\"|shutdown-timeout = \"${apptoml_beacon_kit_shutdown_timeout}\"|" "${node_dir}/beacond/config/app.toml"
				# rpc-dial-url
				sed "${SED_OPT[@]}" "s|^rpc-dial-url = \".*\"|rpc-dial-url = \"http://localhost:${el_authrpc_port}\"|" "${node_dir}/beacond/config/app.toml"
				# rpc-timeout
				sed "${SED_OPT[@]}" "s|^rpc-timeout = \".*\"|rpc-timeout = \"${apptoml_beacon_kit_engine_rpc_timeout}\"|" "${node_dir}/beacond/config/app.toml"
				# rpc-startup-check-interval
				sed "${SED_OPT[@]}" "s|^rpc-startup-check-interval = \".*\"|rpc-startup-check-interval = \"${apptoml_beacon_kit_engine_rpc_startup_check_interval}\"|" "${node_dir}/beacond/config/app.toml"
				# rpc-jwt-refresh-interval
				sed "${SED_OPT[@]}" "s|^rpc-jwt-refresh-interval = \".*\"|rpc-jwt-refresh-interval = \"${apptoml_beacon_kit_engine_rpc_jwt_refresh_interval}\"|" "${node_dir}/beacond/config/app.toml"
				# jwt-secret-path
				sed "${SED_OPT[@]}" "s|^jwt-secret-path = \".*\"|jwt-secret-path = \"${node_dir}/beacond/config/jwt.hex\"|" "${node_dir}/beacond/config/app.toml"
				# [beacon-kit-logger]
				# time-format
				sed "${SED_OPT[@]}" "s|^time-format = \".*\"|time-format = \"${apptoml_beacon_kit_logger_time_format}\"|" "${node_dir}/beacond/config/app.toml"
				# log-level
				sed "${SED_OPT[@]}" "s|^log-level = \".*\"|log-level = \"${apptoml_beacon_kit_logger_log_level}\"|" "${node_dir}/beacond/config/app.toml"
				# log-style
				sed "${SED_OPT[@]}" "s|^log-style = \".*\"|log-style = \"${apptoml_beacon_kit_logger_style}\"|" "${node_dir}/beacond/config/app.toml"
				# [beacon-kit-kzg]
				# trusted-setup-path
				sed "${SED_OPT[@]}" "s|^trusted-setup-path = \".*\"|trusted-setup-path = \"${beranodes_dir}/tmp/kzg-trusted-setup.json\"|" "${node_dir}/beacond/config/app.toml"
				# kzg-implementation
				sed "${SED_OPT[@]}" "s|^implementation = \".*\"|implementation = \"${apptoml_beacon_kit_kzg_implementation}\"|" "${node_dir}/beacond/config/app.toml"
				# [beacon-kit-payload-builder]
				# enabled
				sed "${SED_OPT[@]}" "157s|^enabled = .*|enabled = ${apptoml_beacon_kit_payload_builder_enabled}|" "${node_dir}/beacond/config/app.toml"
				# suggested-fee-recipient
				sed "${SED_OPT[@]}" "s|^suggested-fee-recipient = \".*\"|suggested-fee-recipient = \"${wallet_address}\"|" "${node_dir}/beacond/config/app.toml"
				# payload-timeout
				sed "${SED_OPT[@]}" "s|^payload-timeout = \".*\"|payload-timeout = \"${apptoml_beacon_kit_payload_builder_payload_timeout}\"|" "${node_dir}/beacond/config/app.toml"
				# [beacon-kit.validator]
				# graffiti
				sed "${SED_OPT[@]}" "s|^graffiti = \".*\"|graffiti = \"${moniker}\"|" "${node_dir}/beacond/config/app.toml"
				# availability-window
				sed "${SED_OPT[@]}" "s|^availability-window = \".*\"|availability-window = \"${apptoml_beacon_kit_validator_availability_window}\"|" "${node_dir}/beacond/config/app.toml"
				# [beacon-kit.node-api]
				# enabled
				sed "${SED_OPT[@]}" "176s|^enabled = .*|enabled = ${apptoml_beacon_kit_node_api_enabled}|" "${node_dir}/beacond/config/app.toml"
				# address
				sed "${SED_OPT[@]}" "183s|^address = \".*\"|address = \"127.0.0.1:${beacond_node_port}\"|" "${node_dir}/beacond/config/app.toml"
				# logging
				sed "${SED_OPT[@]}" "s|^logging = \".*\"|logging = \"${apptoml_beacon_kit_node_api_logging}\"|" "${node_dir}/beacond/config/app.toml"

				# - update config.toml
				echo "--------------------------------"
				echo "config.toml"
				echo "--------------------------------"
				# version
				sed "${SED_OPT[@]}" "11s|^version = \".*\"|version = \"${configtoml_version}\"|" "${node_dir}/beacond/config/config.toml"
				# [base]
				# proxy_app
				sed "${SED_OPT[@]}" "s|^proxy_app = \".*\"|proxy_app = \"tcp://127.0.0.1:${ethproxy_port}\"|" "${node_dir}/beacond/config/config.toml"
				# moniker
				sed "${SED_OPT[@]}" "s|^moniker = \".*\"|moniker = \"${moniker}\"|" "${node_dir}/beacond/config/config.toml"
				# db_backend
				sed "${SED_OPT[@]}" "s|^db_backend = \".*\"|db_backend = \"${configtoml_db_backend}\"|" "${node_dir}/beacond/config/config.toml"
				# db_dir
				sed "${SED_OPT[@]}" "s|^db_dir = \".*\"|db_dir = \"${node_dir}/beacond/data\"|" "${node_dir}/beacond/config/config.toml"
				# log_level
				sed "${SED_OPT[@]}" "s|^log_level = \".*\"|log_level = \"${configtoml_log_level}\"|" "${node_dir}/beacond/config/config.toml"
				# log_format
				sed "${SED_OPT[@]}" "s|^log_format = \".*\"|log_format = \"${configtoml_log_format}\"|" "${node_dir}/beacond/config/config.toml"
				# genesis_file
				sed "${SED_OPT[@]}" "s|^genesis_file = \".*\"|genesis_file = \"${node_dir}/beacond/config/genesis.json\"|" "${node_dir}/beacond/config/config.toml"
				# priv_validator_key_file
				sed "${SED_OPT[@]}" "s|^priv_validator_key_file = \".*\"|priv_validator_key_file = \"${node_dir}/beacond/config/priv_validator_key.json\"|" "${node_dir}/beacond/config/config.toml"
				# priv_validator_state_file
				sed "${SED_OPT[@]}" "s|^priv_validator_state_file = \".*\"|priv_validator_state_file = \"${node_dir}/beacond/data/priv_validator_state.json\"|" "${node_dir}/beacond/config/config.toml"
				# priv_validator_laddr
				sed "${SED_OPT[@]}" "s|^priv_validator_laddr = \".*\"|priv_validator_laddr = \"${configtoml_priv_validator_laddr}\"|" "${node_dir}/beacond/config/config.toml"
				# node_key_file
				sed "${SED_OPT[@]}" "s|^node_key_file = \".*\"|node_key_file = \"${node_dir}/beacond/config/node_key.json\"|" "${node_dir}/beacond/config/config.toml"
				# abci
				sed "${SED_OPT[@]}" "s|^abci = \".*\"|abci = \"${configtoml_abci}\"|" "${node_dir}/beacond/config/config.toml"
				# filter_peers
				sed "${SED_OPT[@]}" "s|^filter_peers = \".*\"|filter_peers = \"${configtoml_filter_peers}\"|" "${node_dir}/beacond/config/config.toml"
				# [rpc]
				echo "--------------------------------"
				echo "config.toml - [rpc]"
				echo "--------------------------------"
				# laddr
				sed "${SED_OPT[@]}" "94s|^laddr = \".*\"|laddr = \"tcp://127.0.0.1:${ethrpc_port}\"|" "${node_dir}/beacond/config/config.toml"
				# cors_allowed_origins
				if [ -z "${configtoml_rpc_cors_allowed_origins}" ]; then
					sed "${SED_OPT[@]}" "s|^cors_allowed_origins = \[.*\]|cors_allowed-origins = []|" "${node_dir}/beacond/config/config.toml"
				else
					formatted_cors_allowed_origins="$(format_csv_as_string "${configtoml_rpc_cors_allowed_origins}")"
					sed "${SED_OPT[@]}" "s|^cors_allowed_origins = \[.*\]|cors_allowed-origins = [${formatted_cors_allowed_origins}]|" "${node_dir}/beacond/config/config.toml"
				fi
				# cors_allowed_methods
				if [ -z "${configtoml_rpc_cors_allowed_methods}" ]; then
					sed "${SED_OPT[@]}" "s|^cors_allowed_methods = \[.*\]|cors_allowed_methods = []|" "${node_dir}/beacond/config/config.toml"
				else
					formatted_cors_allowed_methods="$(format_csv_as_string "${configtoml_rpc_cors_allowed_methods}")"
					sed "${SED_OPT[@]}" "s|^cors_allowed_methods = \[.*\]|cors_allowed_methods = [${formatted_cors_allowed_methods}]|" "${node_dir}/beacond/config/config.toml"
				fi
				# cors_allowed_headers
				if [ -z "${configtoml_rpc_cors_allowed_headers}" ]; then
					sed "${SED_OPT[@]}" "s|^cors_allowed_headers = \[.*\]|cors_allowed_headers = []|" "${node_dir}/beacond/config/config.toml"
				else
					formatted_cors_allowed_headers="$(format_csv_as_string "${configtoml_rpc_cors_allowed_headers}")"
					sed "${SED_OPT[@]}" "s|^cors_allowed_headers = \[.*\]|cors_allowed_headers = [${formatted_cors_allowed_headers}]|" "${node_dir}/beacond/config/config.toml"
				fi
				# unsafe
				sed "${SED_OPT[@]}" "s|^unsafe = \".*\"|unsafe = \"${configtoml_rpc_unsafe}\"|" "${node_dir}/beacond/config/config.toml"
				# max_open_connections
				sed "${SED_OPT[@]}" "s|^max_open_connections = \".*\"|max_open_connections = \"${configtoml_rpc_max_open_connections}\"|" "${node_dir}/beacond/config/config.toml"
				# max_subscription_clients
				sed "${SED_OPT[@]}" "s|^max_subscription_clients = \".*\"|max_subscription_clients = \"${configtoml_rpc_max_subscription_clients}\"|" "${node_dir}/beacond/config/config.toml"
				# max_subscriptions_per_client
				sed "${SED_OPT[@]}" "s|^max_subscriptions_per_client = \".*\"|max_subscriptions_per_client = \"${configtoml_rpc_max_subscriptions_per_client}\"|" "${node_dir}/beacond/config/config.toml"
				# experimental-subscription-buffer-size
				sed "${SED_OPT[@]}" "s|^experimental_subscription_buffer_size = \".*\"|experimental_subscription_buffer_size = \"${configtoml_rpc_experimental_subscription_buffer_size}\"|" "${node_dir}/beacond/config/config.toml"
				# experimental_websocket_write_buffer_size
				sed "${SED_OPT[@]}" "s|^experimental_websocket_write_buffer_size = \".*\"|experimental_websocket_write_buffer_size = \"${configtoml_rpc_experimental_websocket_write_buffer_size}\"|" "${node_dir}/beacond/config/config.toml"
				# experimental_close_on_slow_client
				sed "${SED_OPT[@]}" "s|^experimental_close_on_slow_client = \".*\"|experimental_close_on_slow_client = \"${configtoml_rpc_experimental_close_on_slow_client}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_broadcast_tx_commit
				sed "${SED_OPT[@]}" "s|^timeout_broadcast_tx_commit = \".*\"|timeout_broadcast_tx_commit = \"${configtoml_rpc_timeout_broadcast_tx_commit}\"|" "${node_dir}/beacond/config/config.toml"
				# max_request_batch_size
				sed "${SED_OPT[@]}" "s|^max_request_batch_size = \".*\"|max_request_batch_size = \"${configtoml_rpc_max_request_batch_size}\"|" "${node_dir}/beacond/config/config.toml"
				# max_body_bytes
				sed "${SED_OPT[@]}" "s|^max_body_bytes = \".*\"|max_body_bytes = \"${configtoml_rpc_max_body_bytes}\"|" "${node_dir}/beacond/config/config.toml"
				# max_header_bytes
				sed "${SED_OPT[@]}" "s|^max_header_bytes = \".*\"|max_header_bytes = \"${configtoml_rpc_max_header_bytes}\"|" "${node_dir}/beacond/config/config.toml"
				# tls_cert_file
				sed "${SED_OPT[@]}" "s|^tls_cert_file = \".*\"|tls_cert_file = \"${configtoml_rpc_tls_cert_file}\"|" "${node_dir}/beacond/config/config.toml"
				# tls_key_file
				sed "${SED_OPT[@]}" "s|^tls_key_file = \".*\"|tls_key_file = \"${configtoml_rpc_tls_key_file}\"|" "${node_dir}/beacond/config/config.toml"
				# pprof_laddr
				sed "${SED_OPT[@]}" "s|^pprof_laddr = \".*\"|pprof_laddr = \"${configtoml_rpc_pprof_laddr}\"|" "${node_dir}/beacond/config/config.toml"
				# [grpc]
				echo "--------------------------------"
				echo "config.toml - [grpc]"
				echo "--------------------------------"
				# laddr
				sed "${SED_OPT[@]}" "137s|^laddr = \".*\"|laddr = \"${configtoml_grpc_laddr}\"|" "${node_dir}/beacond/config/config.toml"
				# [grpc.version_service]
				# enabled
				sed "${SED_OPT[@]}" "218s|^enabled = \".*\"|enabled = \"${configtoml_grpc_version_service_enabled}\"|" "${node_dir}/beacond/config/config.toml"
				# [grpc.block_service]
				# enabled
				sed "${SED_OPT[@]}" "222s|^enabled = \".*\"|enabled = \"${configtoml_grpc_block_service_enabled}\"|" "${node_dir}/beacond/config/config.toml"
				# [grpc.block_results_service]
				# enabled
				sed "${SED_OPT[@]}" "227s|^enabled = \".*\"|enabled = \"${configtoml_grpc_block_results_service_enabled}\"|" "${node_dir}/beacond/config/config.toml"
				# [grpc.privileged]
				# laddr
				sed "${SED_OPT[@]}" "235s|^laddr = \".*\"|laddr = \"${configtoml_grpc_privileged_laddr}\"|" "${node_dir}/beacond/config/config.toml"
				# [grpc.privileged.pruning_service]
				# enabled
				sed "${SED_OPT[@]}" "248s|^enabled = \".*\"|enabled = \"${configtoml_grpc_privileged_pruning_service_enabled}\"|" "${node_dir}/beacond/config/config.toml"
				# [p2p]
				# laddr
				sed "${SED_OPT[@]}" "256s|^laddr = \".*\"|laddr = \"tcp://0.0.0.0:${ethp2p_port}\"|" "${node_dir}/beacond/config/config.toml"
				# external_address
				sed "${SED_OPT[@]}" "s|^external_address = \".*\"|external_address = \"${configtoml_p2p_external_address}\"|" "${node_dir}/beacond/config/config.toml"

				# Adjust seeds and peers to exclude the current node for connections
				read -a node_seeds < <(array_exclude_element seeds[@] "${seeds[0]}")
				configtoml_p2p_seeds="$(
					IFS=,
					echo "${node_seeds[*]/%/@localhost:${ethp2p_port}}"
				)"

				read -a node_peers < <(array_exclude_element peers[@] "${peers[0]}")
				configtoml_p2p_persistent_peers="$(
					IFS=,
					echo "${node_peers[*]/%/@localhost:${ethp2p_port}}"
				)"

				# seeds
				sed "${SED_OPT[@]}" "s|^seeds = \".*\"|seeds = \"${configtoml_p2p_seeds}\"|" "${node_dir}/beacond/config/config.toml"
				# persistent_peers
				sed "${SED_OPT[@]}" "s|^persistent_peers = \".*\"|persistent_peers = \"${configtoml_p2p_persistent_peers}\"|" "${node_dir}/beacond/config/config.toml"
				# addr_book_file
				sed "${SED_OPT[@]}" "s|^addr_book_file = \".*\"|addr_book_file = \"${node_dir}/beacond/config/addrbook.json\"|" "${node_dir}/beacond/config/config.toml"
				# addr_book_strict
				sed "${SED_OPT[@]}" "s|^addr_book_strict = \".*\"|addr_book_strict = \"${configtoml_p2p_addr_book_strict}\"|" "${node_dir}/beacond/config/config.toml"
				# max_num_inbound_peers
				sed "${SED_OPT[@]}" "s|^max_num_inbound_peers = \".*\"|max_num_inbound_peers = \"${configtoml_p2p_max_num_inbound_peers}\"|" "${node_dir}/beacond/config/config.toml"
				# max_num_outbound_peers
				sed "${SED_OPT[@]}" "s|^max_num_outbound_peers = \".*\"|max_num_outbound_peers = \"${configtoml_p2p_max_num_outbound_peers}\"|" "${node_dir}/beacond/config/config.toml"
				# unconditional_peer_ids
				sed "${SED_OPT[@]}" "s|^unconditional_peer_ids = \".*\"|unconditional_peer_ids = \"${configtoml_p2p_unconditional_peer_ids}\"|" "${node_dir}/beacond/config/config.toml"
				# persistent_peers_max_dial_period
				sed "${SED_OPT[@]}" "s|^persistent_peers_max_dial_period = \".*\"|persistent_peers_max_dial_period = \"${configtoml_p2p_persistent_peers_max_dial_period}\"|" "${node_dir}/beacond/config/config.toml"
				# flush_throttle_timeout
				sed "${SED_OPT[@]}" "s|^flush_throttle_timeout = \".*\"|flush_throttle_timeout = \"${configtoml_p2p_flush_throttle_timeout}\"|" "${node_dir}/beacond/config/config.toml"
				# max_packet_msg_payload_size
				sed "${SED_OPT[@]}" "s|^max_packet_msg_payload_size = \".*\"|max_packet_msg_payload_size = \"${configtoml_p2p_max_packet_msg_payload_size}\"|" "${node_dir}/beacond/config/config.toml"
				# send_rate
				sed "${SED_OPT[@]}" "s|^send_rate = \".*\"|send_rate = \"${configtoml_p2p_send_rate}\"|" "${node_dir}/beacond/config/config.toml"
				# recv_rate
				sed "${SED_OPT[@]}" "s|^recv_rate = \".*\"|recv_rate = \"${configtoml_p2p_recv_rate}\"|" "${node_dir}/beacond/config/config.toml"
				# pex
				sed "${SED_OPT[@]}" "s|^pex = \".*\"|pex = \"${configtoml_p2p_pex}\"|" "${node_dir}/beacond/config/config.toml"
				# seed_mode
				sed "${SED_OPT[@]}" "s|^seed_mode = \".*\"|seed_mode = \"${configtoml_p2p_seed_mode}\"|" "${node_dir}/beacond/config/config.toml"
				# private_peer_ids
				sed "${SED_OPT[@]}" "s|^private_peer_ids = \".*\"|private_peer_ids = \"${configtoml_p2p_private_peer_ids}\"|" "${node_dir}/beacond/config/config.toml"
				# allow_duplicate_ip
				sed "${SED_OPT[@]}" "s|^allow_duplicate_ip = \".*\"|allow_duplicate_ip = \"${configtoml_p2p_allow_duplicate_ip}\"|" "${node_dir}/beacond/config/config.toml"
				# handshake_timeout
				sed "${SED_OPT[@]}" "s|^handshake_timeout = \".*\"|handshake_timeout = \"${configtoml_p2p_handshake_timeout}\"|" "${node_dir}/beacond/config/config.toml"
				# dial_timeout
				sed "${SED_OPT[@]}" "s|^dial_timeout = \".*\"|dial_timeout = \"${configtoml_p2p_dial_timeout}\"|" "${node_dir}/beacond/config/config.toml"
				# [mempool]
				echo "--------------------------------"
				echo "config.toml - [mempool]"
				echo "--------------------------------"
				# type
				sed "${SED_OPT[@]}" "s|^type = \".*\"|type = \"${configtoml_mempool_type}\"|" "${node_dir}/beacond/config/config.toml"
				# recheck
				sed "${SED_OPT[@]}" "s|^recheck = \".*\"|recheck = \"${configtoml_mempool_recheck}\"|" "${node_dir}/beacond/config/config.toml"
				# recheck_timeout
				sed "${SED_OPT[@]}" "s|^recheck_timeout = \".*\"|recheck_timeout = \"${configtoml_mempool_recheck_timeout}\"|" "${node_dir}/beacond/config/config.toml"
				# broadcast
				sed "${SED_OPT[@]}" "s|^broadcast = \".*\"|broadcast = \"${configtoml_mempool_broadcast}\"|" "${node_dir}/beacond/config/config.toml"
				# wal_dir
				sed "${SED_OPT[@]}" "s|^wal_dir = \".*\"|wal_dir = \"${configtoml_mempool_wal_dir}\"|" "${node_dir}/beacond/config/config.toml"
				# size
				sed "${SED_OPT[@]}" "s|^size = \".*\"|size = \"${configtoml_mempool_size}\"|" "${node_dir}/beacond/config/config.toml"
				# max_tx_bytes
				sed "${SED_OPT[@]}" "s|^max_tx_bytes = \".*\"|max_tx_bytes = \"${configtoml_mempool_max_tx_bytes}\"|" "${node_dir}/beacond/config/config.toml"
				# max_txs_bytes
				sed "${SED_OPT[@]}" "s|^max_txs_bytes = \".*\"|max_txs_bytes = \"${configtoml_mempool_max_txs_bytes}\"|" "${node_dir}/beacond/config/config.toml"
				# cache_size
				sed "${SED_OPT[@]}" "s|^cache_size = \".*\"|cache_size = \"${configtoml_mempool_cache_size}\"|" "${node_dir}/beacond/config/config.toml"
				# keep-invalid-txs-in-cache
				sed "${SED_OPT[@]}" "s|^keep_invalid_txs_in_cache = \".*\"|keep_invalid_txs_in_cache = \"${configtoml_mempool_keep_invalid_txs_in_cache}\"|" "${node_dir}/beacond/config/config.toml"
				# [statesync]
				echo "--------------------------------"
				echo "config.toml - [statesync]"
				echo "--------------------------------"
				# enable
				sed "${SED_OPT[@]}" "404s|^enable = .*|enable = ${configtoml_statesync_enable}|" "${node_dir}/beacond/config/config.toml"
				# rpc_servers
				sed "${SED_OPT[@]}" "s|^rpc_servers = \".*\"|rpc_servers = \"${configtoml_statesync_rpc_servers}\"|" "${node_dir}/beacond/config/config.toml"
				# trust_height
				sed "${SED_OPT[@]}" "s|^trust_height = \".*\"|trust_height = \"${configtoml_statesync_trust_height}\"|" "${node_dir}/beacond/config/config.toml"
				# trust_hash
				sed "${SED_OPT[@]}" "s|^trust_hash = \".*\"|trust_hash = \"${configtoml_statesync_trust_hash}\"|" "${node_dir}/beacond/config/config.toml"
				# trust_period
				sed "${SED_OPT[@]}" "s|^trust_period = \".*\"|trust_period = \"${configtoml_statesync_trust_period}\"|" "${node_dir}/beacond/config/config.toml"
				# discovery_time
				sed "${SED_OPT[@]}" "s|^discovery_time = \".*\"|discovery_time = \"${configtoml_statesync_discovery_time}\"|" "${node_dir}/beacond/config/config.toml"
				# temp_dir
				sed "${SED_OPT[@]}" "s|^temp_dir = \".*\"|temp_dir = \"${configtoml_statesync_temp_dir}\"|" "${node_dir}/beacond/config/config.toml"
				# chunk_request_timeout
				sed "${SED_OPT[@]}" "s|^chunk_request_timeout = \".*\"|chunk_request_timeout = \"${configtoml_statesync_chunk_request_timeout}\"|" "${node_dir}/beacond/config/config.toml"
				# chunk_fetchers
				sed "${SED_OPT[@]}" "s|^chunk_fetchers = \".*\"|chunk_fetchers = \"${configtoml_statesync_chunk_fetchers}\"|" "${node_dir}/beacond/config/config.toml"
				# [blocksync]
				echo "--------------------------------"
				echo "config.toml - [blocksync]"
				echo "--------------------------------"
				# version
				sed "${SED_OPT[@]}" "442s|^version = .*|version = \"${configtoml_blocksync_version}\"|" "${node_dir}/beacond/config/config.toml"
				# [consensus]
				echo "--------------------------------"
				echo "config.toml - [consensus]"
				echo "--------------------------------"
				# wal_file
				sed "${SED_OPT[@]}" "s|^wal_file = \".*\"|wal_file = \"${configtoml_consensus_wal_file}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_propose
				sed "${SED_OPT[@]}" "s|^timeout_propose = \".*\"|timeout_propose = \"${configtoml_consensus_timeout_propose}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_propose_delta
				sed "${SED_OPT[@]}" "s|^timeout_propose_delta = \".*\"|timeout_propose_delta = \"${configtoml_consensus_timeout_propose_delta}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_prevote
				sed "${SED_OPT[@]}" "s|^timeout_prevote = \".*\"|timeout_prevote = \"${configtoml_consensus_timeout_prevote}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_prevote_delta
				sed "${SED_OPT[@]}" "s|^timeout_prevote_delta = \".*\"|timeout_prevote_delta = \"${configtoml_consensus_timeout_prevote_delta}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_precommit
				sed "${SED_OPT[@]}" "s|^timeout_precommit = \".*\"|timeout_precommit = \"${configtoml_consensus_timeout_precommit}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_precommit_delta
				sed "${SED_OPT[@]}" "s|^timeout_precommit_delta = \".*\"|timeout_precommit_delta = \"${configtoml_consensus_timeout_precommit_delta}\"|" "${node_dir}/beacond/config/config.toml"
				# timeout_commit
				sed "${SED_OPT[@]}" "s|^timeout_commit = \".*\"|timeout_commit = \"${configtoml_consensus_timeout_commit}\"|" "${node_dir}/beacond/config/config.toml"
				# skip_timeout_commit
				sed "${SED_OPT[@]}" "s|^skip_timeout_commit = \".*\"|skip_timeout_commit = \"${configtoml_consensus_skip_timeout_commit}\"|" "${node_dir}/beacond/config/config.toml"
				# double_sign_check_height
				sed "${SED_OPT[@]}" "s|^double_sign_check_height = \".*\"|double_sign_check_height = \"${configtoml_consensus_double_sign_check_height}\"|" "${node_dir}/beacond/config/config.toml"
				# create_empty_blocks
				sed "${SED_OPT[@]}" "s|^create_empty_blocks = \".*\"|create_empty_blocks = \"${configtoml_consensus_create_empty_blocks}\"|" "${node_dir}/beacond/config/config.toml"
				# create_empty_blocks_interval
				sed "${SED_OPT[@]}" "s|^create_empty_blocks_interval = \".*\"|create_empty_blocks_interval = \"${configtoml_consensus_create_empty_blocks_interval}\"|" "${node_dir}/beacond/config/config.toml"
				# peer_gossip_sleep_duration
				sed "${SED_OPT[@]}" "s|^peer_gossip_sleep_duration = \".*\"|peer_gossip_sleep_duration = \"${configtoml_consensus_peer_gossip_sleep_duration}\"|" "${node_dir}/beacond/config/config.toml"
				# peer_gossip_intraloop_sleep_duration
				sed "${SED_OPT[@]}" "s|^peer_gossip_intraloop_sleep_duration = \".*\"|peer_gossip_intraloop_sleep_duration = \"${configtoml_consensus_peer_gossip_intraloop_sleep_duration}\"|" "${node_dir}/beacond/config/config.toml"
				# peer_query_maj23_sleep_duration
				sed "${SED_OPT[@]}" "s|^peer_query_maj23_sleep_duration = \".*\"|peer_query_maj23_sleep_duration = \"${configtoml_consensus_peer_query_maj23_sleep_duration}\"|" "${node_dir}/beacond/config/config.toml"
				# [storage]
				# discard_abci_responses
				sed "${SED_OPT[@]}" "s|^discard_abci_responses = \".*\"|discard_abci_responses = \"${configtoml_storage_discard_abci_responses}\"|" "${node_dir}/beacond/config/config.toml"
				# experimental_db_key_layout
				sed "${SED_OPT[@]}" "s|^experimental_db_key_layout = \".*\"|experimental_db_key_layout = \"${configtoml_storage_experimental_db_key_layout}\"|" "${node_dir}/beacond/config/config.toml"
				# compact
				sed "${SED_OPT[@]}" "s|^compact = \".*\"|compact = \"${configtoml_storage_compact}\"|" "${node_dir}/beacond/config/config.toml"
				# compaction_interval
				sed "${SED_OPT[@]}" "s|^compaction_interval = \".*\"|compaction_interval = \"${configtoml_storage_compaction_interval}\"|" "${node_dir}/beacond/config/config.toml"
				# [storage.pruning]
				echo "--------------------------------"
				echo "config.toml - [storage.pruning]"
				echo "--------------------------------"
				# interval
				sed "${SED_OPT[@]}" "s|^interval = \".*\"|interval = \"${configtoml_storage_pruning_interval}\"|" "${node_dir}/beacond/config/config.toml"
				# [storage.pruning.data_companion]
				# enabled
				sed "${SED_OPT[@]}" '537s|^enabled = .*$|enabled = '"${configtoml_storage_pruning_data_companion_enabled}"'|' "${node_dir}/beacond/config/config.toml"
				# initial_block_retain_height
				sed "${SED_OPT[@]}" "s|^initial_block_retain_height = \".*\"|initial_block_retain_height = \"${configtoml_storage_pruning_data_companion_initial_block_retain_height}\"|" "${node_dir}/beacond/config/config.toml"
				# initial_block_results_retain_height
				sed "${SED_OPT[@]}" "s|^initial_block_results_retain_height = \".*\"|initial_block_results_retain_height = \"${configtoml_storage_pruning_data_companion_initial_block_results_retain_height}\"|" "${node_dir}/beacond/config/config.toml"
				# [tx_index]
				# indexer
				sed "${SED_OPT[@]}" "s|^indexer = \".*\"|indexer = \"${configtoml_tx_index_indexer}\"|" "${node_dir}/beacond/config/config.toml"
				# psql_conn
				sed "${SED_OPT[@]}" "s|^psql_conn = \".*\"|psql_conn = \"${configtoml_tx_index_psql_conn}\"|" "${node_dir}/beacond/config/config.toml"
				# [instrumentation]
				# prometheus
				sed "${SED_OPT[@]}" "s|^prometheus = \".*\"|prometheus = \"${cl_prometheus_port}\"|" "${node_dir}/beacond/config/config.toml"
				# prometheus_listen_addr
				sed "${SED_OPT[@]}" "s|^prometheus_listen_addr = \".*\"|prometheus_listen_addr = \":${cl_prometheus_port}\"|" "${node_dir}/beacond/config/config.toml"
				# max_open_connections
				sed "${SED_OPT[@]}" '588s|^max_open_connections = .*$|max_open_connections = '"${configtoml_instrumentation_max_open_connections}"'|' "${node_dir}/beacond/config/config.toml"
				# namespace
				sed "${SED_OPT[@]}" "s|^namespace = \".*\"|namespace = \"${configtoml_instrumentation_namespace}\"|" "${node_dir}/beacond/config/config.toml"

				# Init bera-reth node
				cp "${beranodes_dir}/tmp/eth-genesis.json" "${bera_reth_dir}/eth-genesis.json"
				${bin_bera_reth} init \
					--chain="${bera_reth_dir}/eth-genesis.json" \
					--datadir="${bera_reth_dir}" \
					2>/dev/null

				# --full - full archiving
				# --bootnodes
				# --trusted-peers
				# --authrpc.port
				# --authrpc.jwtsecret
				# --port
				# --metrics
				# --http
				# --http.addr
				# --http.port
				# --ipcpath
				# --discovery.port
				# --http.corsdomain
				# --log.file.directory
				# --engine.persistence-threshold
				# --engine.memory-block-buffer-target
				#
				# --authrpc.addr 127.0.0.1		\
				# --authrpc.port $EL_AUTHRPC_PORT		\
				# --authrpc.jwtsecret $JWT_PATH		\
				# --port $EL_ETH_PORT			\
				# --metrics $EL_PROMETHEUS_PORT		\
				# --http					\
				# --http.addr 0.0.0.0			\
				# --http.port $EL_ETHRPC_PORT		\
				# --ipcpath /tmp/reth.ipc.$EL_ETHRPC_PORT \
				# --discovery.port $EL_ETH_PORT		\
				# --http.corsdomain '*'			\
				# --log.file.directory $LOG_DIR		\
				# --engine.persistence-threshold 0	\
				# --engine.memory-block-buffer-target 0
			done

			# Start the nodes and record their pids
			for ((node_index = 0; node_index < ${nodes_count}; node_index++)); do
				# beacond
				local node_json=$(echo "${nodes}" | jq -r ".[$node_index]")
				local moniker=$(echo "${node_json}" | jq -r '.moniker')
				local node_dir="${beranode_dir}${BERANODES_PATH_NODES}/${role}-${node_index}"
				local beacond_dir="${node_dir}/beacond"
				${bin_beacond} start --home "${beacond_dir}" &>"${beranode_dir}${BERANODES_PATH_LOGS}/${moniker}-beacond.log" &
				echo "$!" >"${beranode_dir}${BERANODES_PATH_RUNS}/${moniker}-beacond.pid"

				# bera-reth
				local el_authrpc_port=$(echo "${node_json}" | jq -r '.el_authrpc_port')
				local el_ws_port=$(echo "${node_json}" | jq -r '.el_ws_port')
				${bin_bera_reth} node \
					--chain="${bera_reth_dir}/eth-genesis.json" \
					--datadir="${bera_reth_dir}" \
					--authrpc.addr="127.0.0.1" \
					--authrpc.port="${el_authrpc_port}" \
					--authrpc.jwtsecret="${beacond_dir}/config/jwt.hex" \
					--port="${el_eth_port}" \
					--engine.persistence-threshold=0 \
					--engine.memory-block-buffer-target=0 \
					--http \
					--http.api="admin,debug,eth,net,trace,txpool,web3,rpc,reth,ots,flashbots,miner,mev" \
					--http.addr=0.0.0.0 \
					--http.port="${el_ethrpc_port}" \
					--http.corsdomain=\"*\" \
					--ws \
					--ws.addr=0.0.0.0 \
					--ws.port="${el_ws_port}" \
					--ws.origins=\"*\" \
					&>"${beranode_dir}${BERANODES_PATH_LOGS}/${moniker}-bera-reth.log" &
				echo "$!" >"${beranode_dir}${BERANODES_PATH_RUNS}/${moniker}-bera-reth.pid"
			done
		else
			# Unsupported mode (e.g., "distributed", "cloud")
			log_error "Unsupported mode: ${mode}"
			return 1
		fi
	fi

	# -------------------------------------------------------------------------
	# [STEP 6] Future Network Support
	# -------------------------------------------------------------------------
	# TODO: Implement testnet (bepolia) and mainnet support
	# This will require:
	# - Network-specific genesis files
	# - Bootnodes for peer discovery
	# - Chain-specific configuration parameters
	# -------------------------------------------------------------------------
}
