# =============================================================================
# Start Command
# =============================================================================
# This module contains the implementation of the 'start' command which handles
# starting Berachain nodes based on the configuration file.
# =============================================================================

# Display help for start command
show_start_help() {
    cat << EOF
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

# Start command
cmd_start() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_start" >&2

    # Parse command line arguments
    local custom_beranodes_dir=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --beranodes-dir)
                if [[ -z "$2" ]] || [[ "$2" == --* ]]; then
                    log_error "Error: --beranodes-dir requires a path argument"
                    return 1
                fi
                custom_beranodes_dir="$2"
                shift 2
                ;;
            --help|-h)
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

    # Use custom beranodes directory if provided, otherwise use default
    local beranodes_path="${custom_beranodes_dir:-$BERANODES_PATH}"

    print_header "Starting Beranode"
    local beranodes_config_path="${beranodes_path}/beranodes.config.json"

    if ! [[ -f "${beranodes_config_path}" ]]; then
        log_error "Beranode configuration file does not exist: ${beranodes_path}/beranodes.config.json"
        return 1
    fi

    # TODO add check for beradenodes.config.json

    print_header "Beranode Configuration"
    log_info "Configuration file: ${beranodes_config_path}"
    jq . "${beranodes_config_path}"

    local config_json_path="${beranodes_path}/beranodes.config.json"
    local beranodes_dir=$(jq -r '.beranode_dir' "${config_json_path}")
    local bin_beacond="$beranodes_dir${BERANODES_PATH_BIN}/${BIN_BEACONKIT}"
    local bin_bera_reth="$beranodes_dir${BERANODES_PATH_BIN}/${BIN_BERARETH}"
    local moniker=$(jq -r '.moniker' "${config_json_path}")
    local network=$(jq -r '.network' "${config_json_path}")
    local validators=$(jq -r '.validators' "${config_json_path}")
    local full_nodes=$(jq -r '.full_nodes' "${config_json_path}")
    local pruned_nodes=$(jq -r '.pruned_nodes' "${config_json_path}")
    local total_nodes=$(jq -r '.total_nodes' "${config_json_path}")
    local beranode_dir=$(jq -r '.beranode_dir' "${config_json_path}")
    local skip_genesis=$(jq -r '.skip_genesis' "${config_json_path}")
    local force=$(jq -r '.force' "${config_json_path}")
    local mode=$(jq -r '.mode' "${config_json_path}")
    local wallet_private_key=$(jq -r '.wallet_private_key' "${config_json_path}")
    local wallet_address=$(jq -r '.wallet_address' "${config_json_path}")
    local nodes=$(jq -r '.nodes' "${config_json_path}")

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

    # devnet logic
    if [[ "${network}" == "${CHAIN_NAME_DEVNET}" ]]; then
        log_info "Starting Beranode in ${CHAIN_NAME_DEVNET} mode"

        if [[ "${mode}" == "local" ]]; then
            log_info "Starting Beranode in local mode"

            for i in $(seq 1 ${validators}); do
              local validator_dir="${beranodes_dir}${BERANODES_PATH_NODES}/val-${i}"
              mkdir -p "${validator_dir}"
                create_validator_node "${beranodes_dir}" "${validator_dir}" "${moniker}-val-${i}" "${network}" "${wallet_address}" "${bin_beacond}" "${bin_bera_reth}" "${beranodes_dir}/tmp/kzg-trusted-setup.json" "${ethrpc_port}" "${ethp2p_port}" "${ethproxy_port}" "${el_ethrpc_port}" "${el_authrpc_port}" "${el_eth_port}" "${el_prometheus_port}" "${cl_prometheus_port}"
            done

        else
            log_error "Unsupported mode: ${mode}"
            return 1
        fi
    fi
}
