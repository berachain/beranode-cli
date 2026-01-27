# =============================================================================
# Init Command
# =============================================================================
# This module contains the implementation of the 'init' command which handles
# the initialization of Berachain nodes including configuration file generation,
# binary verification, and genesis file setup.
# =============================================================================

# Main init command
cmd_init() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_init" >&2
    print_header "Checking Dependencies"
    check_cast_version
    if [[ $? -ne 0 ]]; then
        log_error "Cast version is not supported. Please upgrade to version $SUPPORTED_CAST_VERSION or higher."
        return 1
    fi
    log_success "Cast version is supported."

    print_header "Initializing Berachain Node"

    local moniker="$(generate_random_name)"
    local network=$CHAIN_NAME_DEVNET
    local force=false
    local skip_genesis=false
    local total_nodes=0
    local validators=0
    local full_nodes=0
    local pruned_nodes=0
    local docker_mode=false
    local mode="local"
    local wallet_private_key=""
    local wallet_address=""
    local wallet_balance=${DEFAULT_WALLET_BALANCE}

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --beranode-dir)
                if [[ -n "$2" ]]; then
                    BERANODES_PATH="$2"
                    shift 2
                else
                    log_warn "--beranode-dir is not set. defaulting to ${BERANODES_PATH:-$(pwd)/beranodes}"
                    shift
                fi
                ;;
            --docker-mode)
                docker_mode=true
                mode="docker"
                ;;
            --moniker)
                if [[ -n "$2" ]]; then
                    moniker="$2"
                    shift 2
                else
                    log_warn "--moniker is not set. defaulting to a random name"
                    moniker="$(generate_random_name)"
                    shift
                fi
                ;;
            --network)
                if [[ -n "$2" ]]; then
                    network="$2"
                    shift 2
                else
                    log_warn "--network is not set. defaulting to $CHAIN_NAME_DEVNET"
                    network=$CHAIN_NAME_DEVNET
                    shift
                fi
                ;;
            --validators)
                if [[ -n "$2" ]]; then
                    validators="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --full-nodes)
                if [[ -n "$2" ]]; then
                    full_nodes="$2"
                    shift 2
                else
                    log_warn "--full-nodes is not set. defaulting to 0"
                    full_nodes=0
                fi
                ;;
            --pruned-nodes)
                if [[ -n "$2" ]]; then
                    pruned_nodes="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --wallet-private-key)
                if [[ -n "$2" ]]; then
                    wallet_private_key="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --wallet-address)
                if [[ -n "$2" ]]; then
                    wallet_address="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --wallet-balance)
                if [[ -n "$2" ]]; then
                    wallet_balance="$2"
                    shift 2
                else
                    wallet_balance=${DEFAULT_WALLET_BALANCE}
                    shift 2
                fi
                ;;
            *)
                log_error "Unknown option: $1"
                show_init_help
                return 1
                ;;
        esac
    done

    total_nodes=$(( (${validators:-0} + ${full_nodes:-0} + ${pruned_nodes:-0}) ))
    # devnet defaults
    if [[ "${network}" == "${CHAIN_NAME_DEVNET}" ]]; then
        if [[ ${total_nodes} -eq 0 ]]; then
            total_nodes=$(( (${validators} + ${full_nodes} + ${pruned_nodes}) ))
            log_warn "total nodes is 0. defaulting to ${validators} validator, ${full_nodes} rpc full node, and ${pruned_nodes} rpc pruned node"
        fi
        # if [[ -z "${moniker}" ]]; then
        #     moniker="beranode-${network}"
        # fi
    fi
    # testnet defaults
    # mainnet defaults

    # Output configuration settings
    echo "========= Configuration Settings ========="
    echo "Moniker:         ${moniker:-<unset>}"
    echo "Network:         ${network:-<unset>}"
    echo "Validators:      ${validators}"
    echo "Full Nodes:      ${full_nodes}"
    echo "Pruned Nodes:    ${pruned_nodes}"

    echo "Total Nodes:     $total_nodes"
    echo "Beranode Dir:    ${BERANODES_PATH:-<unset>}"
    echo "Skip Genesis:    ${skip_genesis:-false}"
    echo "Force:           ${force:-false}"
    echo "Mode:            ${mode}"
    echo "=========================================="

    # Ensure all required directories exist
    ensure_dir_exists "${BERANODES_PATH}"                          "beranode directory"              || return 1
    ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_BIN}"     "beranode binary directory"       || return 1
    ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_TMP}"     "beranode temporary directory"    || return 1
    ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_LOG}"     "beranode log directory"          || return 1
    ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_NODES}"   "beranode nodes directory"        || return 1

    # Check if the required binaries exist in the bin directory
    missing_binaries=0
    # - beacond
    if [[ ! -x "${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BEACONKIT}" ]]; then
        log_error "Binary '${BIN_BEACONKIT}' not found or not executable: ${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BEACONKIT}"
        missing_binaries=1
    else
      # Check if 'beacond version' command executes successfully
      beacon_version="$("${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BEACONKIT}" version 2>/dev/null)"
      if [[ $? -eq 0 ]]; then
          log_success "'${BIN_BEACONKIT} version' works as expected."
          log_info "${BIN_BEACONKIT} version:\n${beacon_version}\n"
      else
          log_error "'${BIN_BEACONKIT} version' did not work as expected."
      fi
    fi

    # - berareth
    if [[ ! -x "${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BERARETH}" ]]; then
        log_error "Binary '${BIN_BERARETH}' not found or not executable: ${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BERARETH}"
        missing_binaries=1
    else
      # Check if 'berareth version' command executes successfully
      bera_reth_version="$("${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BERARETH}" --version 2>/dev/null)"
      if [[ $? -eq 0 ]]; then
          log_success "'${BIN_BERARETH} --version' works as expected."
          log_info "${BIN_BERARETH} version:\n${bera_reth_version}\n"
      else
          log_error "'${BIN_BERARETH} --version' did not work as expected."
      fi
    fi
    if [[ $missing_binaries -ge 1 ]]; then
        log_error "Some required binaries are missing.\nPlease install them manually and place them in the 'beranodes/bin' directory.\n(Auto-installing coming soon!)"
        return 1
    fi

    wallet_private_key=$(generate_evm_private_key)
    if [[ $? -eq 0 ]]; then
        log_success "Wallet private key generated:\n${wallet_private_key}"
      else
        log_error "Failed to generate wallet private key."
        return 1
    fi
    wallet_address=$(get_evm_address_from_private_key "${wallet_private_key}")
    if [[ $? -eq 0 ]]; then
        log_success "Wallet address generated:\n${wallet_address}"
    else
        log_error "Failed to generate wallet address."
        return 1
    fi

    print_header "Creating Beranode Configuration"

    # Create beranodes.config.json with settings as JSON
    config_json_path="${BERANODES_PATH}/beranodes.config.json"
    # Check if the configuration file already exists, and don't overwrite it
    local_config_exists=false
    if [[ -f "${config_json_path}" ]]; then
        log_warn "Configuration already exists at ${config_json_path}. Will not overwrite."
        jq . "${config_json_path}"
        local_config_exists=true
        # Prompt the user to overwrite or use the existing config
        while true; do
            echo -e "${YELLOW}A configuration file already exists at ${config_json_path}.${RESET}"
            read -p "Do you want to overwrite it? [y/n]: " yn
            case "$yn" in
                [Yy]* )
                    log_warn "Overwriting existing configuration file at ${config_json_path}."
                    rm -f "${config_json_path}"
                    log_info "Previous configuration file removed."
                    local_config_exists=false
                    break
                    ;;
                [Nn]* | "" )
                    log_success "Using existing configuration file at ${config_json_path}."
                    jq . "${config_json_path}"
                    break
                    ;;
                * )
                    echo "Please answer yes (y) or no (n)."
                    ;;
            esac
        done
    fi

    if [[ "${local_config_exists}" = false ]]; then
        log_info "Creating new configuration file: ${config_json_path}"

        nodes_validators=""
        node_ethrpc_port=${DEFAULT_CL_ETHRPC_PORT}
        node_ethp2p_port=${DEFAULT_CL_ETHP2P_PORT}
        node_ethproxy_port=${DEFAULT_CL_ETHPROXY_PORT}
        node_el_ethrpc_port=${DEFAULT_EL_ETHRPC_PORT}
        node_el_authrpc_port=${DEFAULT_EL_AUTHRPC_PORT}
        node_el_eth_port=${DEFAULT_DEFAULT_EL_ETH_PORT}
        node_el_prometheus_port=${DEFAULT_EL_PROMETHEUS_PORT}
        node_cl_prometheus_port=${DEFAULT_CL_PROMETHEUS_PORT}
        if [[ ${validators} -gt 0 ]]; then
          for i in $(seq 1 ${validators}); do
              if [[ $i -eq ${validators} ]]; then
                  nodes_validators="${nodes_validators}{\"role\": \"validator\", \"moniker\": \"${moniker}-val-$(($i-1))\", \"network\": \"${network}\", \"wallet_address\": \"${evm_address}\", \"ethrpc_port\": ${node_ethrpc_port}, \"ethp2p_port\": ${node_ethp2p_port}, \"ethproxy_port\": ${node_ethproxy_port}, \"el_ethrpc_port\": ${node_el_ethrpc_port}, \"el_authrpc_port\": ${node_el_authrpc_port}, \"el_eth_port\": ${node_el_eth_port}, \"el_prometheus_port\": ${node_el_prometheus_port}, \"cl_prometheus_port\": ${node_cl_prometheus_port}}"
              else
                  nodes_validators="${nodes_validators}{\"role\": \"validator\", \"moniker\": \"${moniker}-val-$(($i-1))\", \"network\": \"${network}\", \"wallet_address\": \"${evm_address}\", \"ethrpc_port\": ${node_ethrpc_port}, \"ethp2p_port\": ${node_ethp2p_port}, \"ethproxy_port\": ${node_ethproxy_port}, \"el_ethrpc_port\": ${node_el_ethrpc_port}, \"el_authrpc_port\": ${node_el_authrpc_port}, \"el_eth_port\": ${node_el_eth_port}, \"el_prometheus_port\": ${node_el_prometheus_port}, \"cl_prometheus_port\": ${node_cl_prometheus_port}},"
              fi
              node_ethrpc_port=$((node_ethrpc_port + 1))
              node_ethp2p_port=$((node_ethp2p_port + 1))
              node_ethproxy_port=$((node_ethproxy_port + 1))
              node_el_ethrpc_port=$((node_el_ethrpc_port + 1))
              node_el_authrpc_port=$((node_el_authrpc_port + 1))
              node_el_eth_port=$((node_el_eth_port + 1))
              node_el_prometheus_port=$((node_el_prometheus_port + 1))
              node_cl_prometheus_port=$((node_cl_prometheus_port + 1))
          done
        fi

        nodes_full_nodes=""
        if [[ ${full_nodes} -gt 0 ]]; then
          for i in $(seq 1 ${full_nodes}); do
              if [[ $i -eq ${full_nodes} ]]; then
                  nodes_full_nodes="${nodes_full_nodes}{\"role\": \"rpc_full\", \"moniker\": \"${moniker}-rpc-full-$(($i-1))\", \"network\": \"${network}\", \"wallet_address\": \"${evm_address}\", \"ethrpc_port\": ${node_ethrpc_port}, \"ethp2p_port\": ${node_ethp2p_port}, \"ethproxy_port\": ${node_ethproxy_port}, \"el_ethrpc_port\": ${node_el_ethrpc_port}, \"el_authrpc_port\": ${node_el_authrpc_port}, \"el_eth_port\": ${node_el_eth_port}, \"el_prometheus_port\": ${node_el_prometheus_port}, \"cl_prometheus_port\": ${node_cl_prometheus_port}}"
              else
                  nodes_full_nodes="${nodes_full_nodes}{\"role\": \"rpc_full\", \"moniker\": \"${moniker}-rpc-full-$(($i-1))\", \"network\": \"${network}\", \"wallet_address\": \"${evm_address}\", \"ethrpc_port\": ${node_ethrpc_port}, \"ethp2p_port\": ${node_ethp2p_port}, \"ethproxy_port\": ${node_ethproxy_port}, \"el_ethrpc_port\": ${node_el_ethrpc_port}, \"el_authrpc_port\": ${node_el_authrpc_port}, \"el_eth_port\": ${node_el_eth_port}, \"el_prometheus_port\": ${node_el_prometheus_port}, \"cl_prometheus_port\": ${node_cl_prometheus_port}},"
              fi
              node_ethrpc_port=$((node_ethrpc_port + 1))
              node_ethp2p_port=$((node_ethp2p_port + 1))
              node_ethproxy_port=$((node_ethproxy_port + 1))
              node_el_ethrpc_port=$((node_el_ethrpc_port + 1))
              node_el_authrpc_port=$((node_el_authrpc_port + 1))
              node_el_eth_port=$((node_el_eth_port + 1))
              node_el_prometheus_port=$((node_el_prometheus_port + 1))
              node_cl_prometheus_port=$((node_cl_prometheus_port + 1))
          done
        fi

        nodes_pruned_nodes=""
        if [[ ${pruned_nodes} -gt 0 ]]; then
          for i in $(seq 1 ${pruned_nodes}); do
              if [[ $i -eq ${pruned_nodes} ]]; then
                  nodes_pruned_nodes="${nodes_pruned_nodes}{\"role\": \"rpc-pruned\", \"moniker\": \"${moniker}-rpc-pruned-$(($i-1))\", \"network\": \"${network}\", \"wallet_address\": \"${evm_address}\", \"ethrpc_port\": ${node_ethrpc_port}, \"ethp2p_port\": ${node_ethp2p_port}, \"ethproxy_port\": ${node_ethproxy_port}, \"el_ethrpc_port\": ${node_el_ethrpc_port}, \"el_authrpc_port\": ${node_el_authrpc_port}, \"el_eth_port\": ${node_el_eth_port}, \"el_prometheus_port\": ${node_el_prometheus_port}, \"cl_prometheus_port\": ${node_cl_prometheus_port}}"
              else
                  nodes_pruned_nodes="${nodes_pruned_nodes}{\"role\": \"rpc-pruned\", \"moniker\": \"${moniker}-rpc-pruned-$(($i-1))\", \"network\": \"${network}\", \"wallet_address\": \"${evm_address}\", \"ethrpc_port\": ${node_ethrpc_port}, \"ethp2p_port\": ${node_ethp2p_port}, \"ethproxy_port\": ${node_ethproxy_port}, \"el_ethrpc_port\": ${node_el_ethrpc_port}, \"el_authrpc_port\": ${node_el_authrpc_port}, \"el_eth_port\": ${node_el_eth_port}, \"el_prometheus_port\": ${node_el_prometheus_port}, \"cl_prometheus_port\": ${node_cl_prometheus_port}},"
              fi
            node_ethrpc_port=$((node_ethrpc_port + 1))
              node_ethp2p_port=$((node_ethp2p_port + 1))
              node_ethproxy_port=$((node_ethproxy_port + 1))
              node_el_ethrpc_port=$((node_el_ethrpc_port + 1))
              node_el_authrpc_port=$((node_el_authrpc_port + 1))
              node_el_eth_port=$((node_el_eth_port + 1))
              node_el_prometheus_port=$((node_el_prometheus_port + 1))
              node_cl_prometheus_port=$((node_cl_prometheus_port + 1))
          done
        fi

        # Combine all defined node groups into a properly formatted JSON nodes array.
        nodes_combined=""

        # Prepare a list of all potential node groups. Add new ones here if needed.
        all_groups=( "$nodes_validators" "$nodes_full_nodes" "$nodes_pruned_nodes" )
        for group in "${all_groups[@]}"; do
            if [[ -n "$group" ]]; then
                if [[ -z "$nodes_combined" ]]; then
                    nodes_combined="$group"
                else
                    nodes_combined="${nodes_combined},${group}"
                fi
            fi
        done

        jq -n \
          --arg moniker "$moniker" \
          --arg network "$network" \
          --argjson validators "$validators" \
          --argjson full_nodes "$full_nodes" \
          --argjson pruned_nodes "$pruned_nodes" \
          --argjson total_nodes "$total_nodes" \
          --arg beranode_dir "$BERANODES_PATH" \
          --argjson skip_genesis "$skip_genesis" \
          --argjson force "$force" \
          --arg mode "$mode" \
          --arg wallet_private_key "$wallet_private_key" \
          --arg wallet_address "$wallet_address" \
          --arg wallet_balance "$wallet_balance" \
          --argjson nodes "$(echo "[${nodes_combined}]" | jq .)" \
          '{
            moniker: $moniker,
            network: $network,
            validators: $validators,
            full_nodes: $full_nodes,
            pruned_nodes: $pruned_nodes,
            total_nodes: $total_nodes,
            beranode_dir: $beranode_dir,
            skip_genesis: $skip_genesis,
            force: $force,
            mode: $mode,
            wallet_private_key: $wallet_private_key,
            wallet_address: $wallet_address,
            wallet_balance: $wallet_balance,
            nodes: $nodes
          }' > "${config_json_path}"

        if [[ $? -eq 0 ]]; then
            log_success "Beranode configuration written to ${config_json_path}"
        else
            log_error "Could not write configuration to ${config_json_path}"
            return 1
        fi
    fi

    # Check if kzg-trusted-setup.json exists, otherwise download it
    if [[ ! -f "${BERANODES_PATH}/tmp/kzg-trusted-setup.json" ]]; then
        log_info "Downloading kzg-trusted-setup.json to ${BERANODES_PATH}/tmp"
        echo "$REPO_BEACONKIT/kzg-trusted-setup.json"
        curl -s -o "${BERANODES_PATH}/tmp/kzg-trusted-setup.json" "$REPO_BEACONKIT/kzg-trusted-setup.json"
        if [[ $? -eq 0 ]]; then
            log_success "Downloaded kzg-trusted-setup.json successfully."
        else
            log_error "Failed to download kzg-trusted-setup.json."
            return 1
        fi
    else
        log_info "kzg-trusted-setup.json already exists in ${BERANODES_PATH}/tmp"
    fi

    # Generate eth-genesis.json file
    if [[ -f "${BERANODES_PATH}/tmp/eth-genesis.json" ]]; then
        log_success "Found eth-genesis.json at ${BERANODES_PATH}/tmp/eth-genesis.json"
    else
        log_warn "eth-genesis.json not found at ${BERANODES_PATH}/tmp/eth-genesis.json creating it..."

        # Generates a eth-genesis.json file that is shared with all nodes
        generate_eth_genesis_file \
          --genesis-file-path "${BERANODES_PATH}/tmp/eth-genesis.json" \
          --chain-id "${CHAIN_ID_DEVNET}" \
          --prague1-time ${ETH_GENESIS_PRAGUE1_TIME} \
          --prague1-base-fee-change-denominator ${ETH_GENESIS_PRAGUE1_BASE_FEE_CHANGE_DENOMINATOR} \
          --prague1-min-base-fee ${ETH_GENESIS_PRAGUE1_MIN_BASE_FEE} \
          --prague1-pol-distributor ${ETH_GENESIS_PRAGUE1_POL_DISTRIBUTOR} \
          --prague2-time ${ETH_GENESIS_PRAGUE2_TIME} \
          --prague2-min-base-fee ${ETH_GENESIS_PRAGUE2_MIN_BASE_FEE} \
          --prague3-time ${ETH_GENESIS_PRAGUE3_TIME} \
          --prague3-bex-vault ${ETH_GENESIS_PRAGUE3_BEX_VAULT} \
          --prague3-rescue-address ${ETH_GENESIS_PRAGUE3_RESCUE_ADDRESS} \
          --prague3-blocked-addresses ${ETH_GENESIS_PRAGUE3_BLOCKED_ADDRESSES} \
          --prague4-time ${ETH_GENESIS_PRAGUE4_TIME} \
          --eth-genesis-custom0-contract-address ${wallet_address} \
          --eth-genesis-custom0-contract-balance ${wallet_balance}
    fi

    # Genate private and public keys for nodes
    generate_beacond_keys \
      --config-dir "${BERANODES_PATH}" \
      --chain-spec "${network}"
    
    # Generate beacon-kit genesis.json file
    generate_beacond_genesis \
      --config-dir "${BERANODES_PATH}" \
      --chain-spec "${network}"

    # # Generate beacon-kit genesis.json file
    # if [[ -f "${BERANODES_PATH}/tmp/genesis.json" ]]; then
    #     log_success "Found genesis.json at ${BERANODES_PATH}/tmp/genesis.json"
    # else
    #     log_warn "genesis.json not found at ${BERANODES_PATH}/tmp/genesis.json creating it..."

    #     # $BEACOND_BIN genesis add-premined-deposit $GENESIS_DEPOSIT_AMOUNT $WITHDRAW_ADDRESS --beacon-kit.chain-spec $CHAIN_SPEC --home $BEACOND_DATA

    #     # # Generates a genesis.json file that is shared with all nodes
    #     # generate_genesis_file \
    #     #   --config-dir "${BERANODES_PATH}" \
    #     #   --chain-spec "${network}" \

    #       # --prague1-time ${ETH_GENESIS_PRAGUE1_TIME} \
    #       # --prague1-base-fee-change-denominator ${ETH_GENESIS_PRAGUE1_BASE_FEE_CHANGE_DENOMINATOR} \
    #       # --prague1-min-base-fee ${ETH_GENESIS_PRAGUE1_MIN_BASE_FEE} \
    #       # --bin-bera_reth "${bin_bera_reth}" \
    #       # --kzg_file "${kzg_file}"
    #       # --prague1-pol-distributor ${ETH_GENESIS_PRAGUE1_POL_DISTRIBUTOR} \
    #       # --prague2-time ${ETH_GENESIS_PRAGUE2_TIME} \
    #       # --prague2-min-base-fee ${ETH_GENESIS_PRAGUE2_MIN_BASE_FEE} \
    #       # --prague3-time ${ETH_GENESIS_PRAGUE3_TIME} \
    #       # --prague3-bex-vault ${ETH_GENESIS_PRAGUE3_BEX_VAULT} \
    #       # --prague3-rescue-address ${ETH_GENESIS_PRAGUE3_RESCUE_ADDRESS} \
    #       # --prague3-blocked-addresses ${ETH_GENESIS_PRAGUE3_BLOCKED_ADDRESSES} \
    #       # --prague4-time ${ETH_GENESIS_PRAGUE4_TIME} \
    #       # --eth-genesis-custom0-contract-address ${wallet_address} \
    #       # --eth-genesis-custom0-contract-balance ${wallet_balance}
    # fi
}
