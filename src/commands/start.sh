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

	# TODO: Implement JSON schema validation for beranodes.config.json
	# This will ensure all required fields are present and properly formatted

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

	# -------------------------------------------------------------------------
	# [DEBUG] Node Configuration Inspection (Currently Disabled)
	# -------------------------------------------------------------------------
	# Uncomment this section to debug individual node configurations.
	# Useful for troubleshooting port conflicts or misconfigurations.
	# -------------------------------------------------------------------------

	# # echo "nodes: ${nodes}"
	# for node in $(echo "${nodes}" | jq -c '.[]'); do
	#     echo "node: ${node}"
	#     echo "node role: $(echo "${node}" | jq -r '.role')"
	#     echo "node moniker: $(echo "${node}" | jq -r '.moniker')"
	#     echo "node network: $(echo "${node}" | jq -r '.network')"
	#     echo "node wallet_address: $(echo "${node}" | jq -r '.wallet_address')"
	#     echo "node ethrpc_port: $(echo "${node}" | jq -r '.ethrpc_port')"
	#     echo "node ethp2p_port: $(echo "${node}" | jq -r '.ethp2p_port')"
	#     echo "node ethproxy_port: $(echo "${node}" | jq -r '.ethproxy_port')"
	#     echo "node el_ethrpc_port: $(echo "${node}" | jq -r '.el_ethrpc_port')"
	#     echo "node el_authrpc_port: $(echo "${node}" | jq -r '.el_authrpc_port')"
	#     echo "node el_eth_port: $(echo "${node}" | jq -r '.el_eth_port')"
	#     echo "node el_prometheus_port: $(echo "${node}" | jq -r '.el_prometheus_port')"
	#     echo "node cl_prometheus_port: $(echo "${node}" | jq -r '.cl_prometheus_port')"
	# done

	# -------------------------------------------------------------------------
	# [STEP 4] KZG Trusted Setup Artifact Download (Currently Disabled)
	# -------------------------------------------------------------------------
	# The KZG trusted setup is required for EIP-4844 blob transactions.
	# This section downloads the setup file if not already present.
	# TODO: Re-enable when blob transaction support is implemented.
	# -------------------------------------------------------------------------

	# # Check if kzg-trusted-setup.json exists, otherwise download it
	# if [[ ! -f "${beranodes_dir}/tmp/kzg-trusted-setup.json" ]]; then
	#     log_info "Downloading kzg-trusted-setup.json to ${beranodes_dir}/tmp"
	#     echo "$REPO_BEACONKIT/kzg-trusted-setup.json"
	#     curl -s -o "${beranodes_dir}/tmp/kzg-trusted-setup.json" "$REPO_BEACONKIT/kzg-trusted-setup.json"
	#     if [[ $? -eq 0 ]]; then
	#         log_success "Downloaded kzg-trusted-setup.json successfully."
	#     else
	#         log_error "Failed to download kzg-trusted-setup.json."
	#         return 1
	#     fi
	# else
	#     log_info "kzg-trusted-setup.json already exists in ${beranodes_dir}/tmp"
	# fi

	# -------------------------------------------------------------------------
	# [STEP 5] Network-Specific Initialization
	# -------------------------------------------------------------------------
	# Route to the appropriate network handler based on the configuration.
	# Currently supports: devnet (local development)
	# Planned: bepolia (testnet), mainnet (production)
	# -------------------------------------------------------------------------

	if [[ "${network}" == "${CHAIN_NAME_DEVNET}" ]]; then
		log_info "Starting Beranode in ${CHAIN_NAME_DEVNET} mode"

		# ---------------------------------------------------------------------
		# [STEP 5.1] Mode Selection: Local Development
		# ---------------------------------------------------------------------
		# Local mode: Single-machine deployment for development/testing
		# - Runs all nodes on localhost with incremental ports
		# - Suitable for rapid iteration and testing
		# ---------------------------------------------------------------------

		if [[ "${mode}" == "local" ]]; then
			log_info "Starting Beranode in local mode"

			# TODO: Implement node creation loop
			# This will iterate through the requested node count and create:
			# - Validator nodes (participate in consensus)
			# - Full nodes (store complete blockchain history)
			# - Pruned nodes (store recent state only)
			#
			# for i in $(seq 1 ${validators}); do
			#   local validator_dir="${beranodes_dir}${BERANODES_PATH_NODES}/val-${i}"
			#   mkdir -p "${validator_dir}"
			#   create_validator_node "${beranodes_dir}" "${validator_dir}" \
			#       "${moniker}-val-${i}" "${network}" "${wallet_address}" \
			#       "${bin_beacond}" "${bin_bera_reth}" \
			#       "${beranodes_dir}/tmp/kzg-trusted-setup.json" \
			#       "${ethrpc_port}" "${ethp2p_port}" "${ethproxy_port}" \
			#       "${el_ethrpc_port}" "${el_authrpc_port}" "${el_eth_port}" \
			#       "${el_prometheus_port}" "${cl_prometheus_port}"
			# done

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
