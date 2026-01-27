# =============================================================================
# Genesis Module
# =============================================================================
# This module contains functions related to genesis file generation and
# validator node creation for the Berachain network.
#
# Functions:
#   - generate_eth_genesis_file: Generates the Ethereum genesis JSON file
#   - generate_beacond_keys: Generates validator keys for beacond nodes
#   - generate_genesis_file: Generates the beacon chain genesis file
#   - create_validator_node: Creates and configures a validator node
# =============================================================================

generate_eth_genesis_file() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_eth_genesis_file" >&2
    # Parse flags for function arguments with defaults

    # CHAIN IDENTITY
    # =============================================================================
    # Chain ID uniquely identifies this blockchain network. It's used in transaction
    # signing (EIP-155) to prevent replay attacks across different networks.
    # Berachain devnet uses chain ID 80087.
    # Berachain bepolia testnet uses chain ID 80069.
    # Berachain mainnet uses chain ID 80094.
    local genesis_file_path=""
    local chain_id="80087"  # Default: Berachain devnet chain ID

    # ETHEREUM HARD FORK BLOCK NUMBERS
    # =============================================================================
    # These values specify at which block number each Ethereum hard fork activates.
    # Setting them all to 0 means all upgrades are active from the genesis block.
    # This is standard practice for new EVM chains that want full compatibility.

    # Homestead (March 2016): Early protocol improvements
    # - EIP-2: Homestead gas cost changes
    # - EIP-7: DELEGATECALL opcode
    # - EIP-8: devp2p forward compatibility
    local eth_genesis_homestead_block="0"

    # DAO Fork (July 2016): Response to the DAO hack
    # daoForkSupport=true means we follow the forked chain (like mainnet Ethereum)
    local eth_genesis_dao_fork_block="0"
    local eth_genesis_dao_fork_support="true"

    # Tangerine Whistle / EIP-150 (October 2016)
    # Gas cost increases for IO-heavy operations to prevent DoS attacks
    local eth_genesis_eip150_block="0"

    # Spurious Dragon (November 2016)
    # - EIP-155: Replay attack protection using chain ID in tx signatures
    # - EIP-158: State clearing, account nonce rules
    local eth_genesis_eip155_block="0"
    local eth_genesis_eip158_block="0"

    # Byzantium (October 2017): Major upgrade including
    # - REVERT opcode, STATICCALL, precompiled contracts for zkSNARKs
    local eth_genesis_byzantium_block="0"

    # Constantinople (February 2019): Gas optimizations
    # - Bitwise shifting, CREATE2, EXTCODEHASH
    local eth_genesis_constantinople_block="0"

    # Petersburg (February 2019): Removed EIP-1283 due to reentrancy concerns
    local eth_genesis_petersburg_block="0"

    # Istanbul (December 2019): Gas repricing, new precompiles
    local eth_genesis_istanbul_block="0"

    # Muir Glacier (January 2020): Difficulty bomb delay
    local eth_genesis_muir_glacier_block="0"

    # Berlin (April 2021): Gas cost changes, access lists (EIP-2929, EIP-2930)
    local eth_genesis_berlin_block="0"

    # London (August 2021): EIP-1559 fee market, BASEFEE opcode
    local eth_genesis_london_block="0"

    # Arrow Glacier (December 2021): Difficulty bomb delay
    local eth_genesis_arrow_glacier_block="0"

    # Gray Glacier (June 2022): Final difficulty bomb delay before The Merge
    local eth_genesis_gray_glacier_block="0"

    # Merge Netsplit Block: The Merge transition (PoW -> PoS)
    local eth_genesis_merge_netsplit_block="0"

    # TIME-BASED FORK TIMESTAMPS (Post-Merge upgrades use timestamps, not blocks)
    # =============================================================================
    # Shanghai (April 2023): Beacon chain withdrawals, warm COINBASE, PUSH0 opcode
    # Timestamp 0 = active from genesis
    local eth_genesis_shanghai_time="0"

    # Cancun (March 2024): Blob transactions (EIP-4844) for L2 data availability
    # Timestamp 0 = active from genesis
    local eth_genesis_cancun_time="0"

    # Prague: Future Ethereum upgrade - scheduled for Berachain
    # Unix timestamp: 1749056400 = Wednesday, June 4, 2025 1:00:00 PM UTC
    local eth_genesis_prague_time="0"

    # PROOF-OF-STAKE CONFIGURATION
    # =============================================================================
    # Terminal Total Difficulty (TTD) is the cumulative PoW difficulty at which
    # the chain transitions to PoS (The Merge). Setting TTD=0 means the chain
    # starts as PoS from genesis with no PoW phase.
    local eth_genesis_terminal_total_difficulty="0"
    local eth_genesis_terminal_total_difficulty_passed="true"

    # BLOB TRANSACTION CONFIGURATION (EIP-4844)
    # =============================================================================
    # Blobs are large data chunks used primarily by Layer 2 rollups.
    # These parameters control blob gas pricing and limits.

    # Target blobs per block (the "ideal" number for fee stability)
    local eth_genesis_blob_target="3"

    # Maximum blobs allowed per block
    local eth_genesis_blob_max="6"

    # Controls how quickly blob base fee adjusts to demand
    # Higher value = slower adjustment. Formula: new_fee = old_fee * e^((actual-target)/fraction)
    local eth_genesis_blob_base_fee_update_fraction="3338477"

    # BERACHAIN-SPECIFIC CONFIGURATION (Prague 1-N)
    # =============================================================================
    # Support for multiple Prague upgrades: prague_times*, prague_base_fee_change_denominator*, etc.
    # Example: for n=1,2,3...
    local -a prague_times=()
    local -a prague_base_fee_change_denominator=()
    local -a prague_min_base_fee=()
    local -a prague_pol_distributor=()
    local -a prague_bex_vault=()
    local -a prague_rescue_address=()
    local -a prague_blocked_addresses=()

    # GENESIS CONFIGURATION
    # =============================================================================
    local genesis_coinbase_address="0x0000000000000000000000000000000000000000"
    local genesis_difficulty="0x01"
    local genesis_extra_data="0x0000000000000000000000000000000000000000000000000000000000000000"
    local genesis_gas_limit="0x1c9c380"
    local genesis_nonce="0x1234"
    local genesis_mix_hash="0x0000000000000000000000000000000000000000000000000000000000000000"
    local genesis_parent_hash="0x0000000000000000000000000000000000000000000000000000000000000000"
    local genesis_timestamp="0"

    # PRE-DEPLOYED CONTRACT BYTECODE
    # =============================================================================
    local eth_genesis_beacon_roots_address="$ETH_GENESIS_BEACON_ROOTS_ADDRESS"
    local eth_genesis_beacon_roots_code="$ETH_GENESIS_BEACON_ROOTS_CODE"
    local eth_genesis_beacon_roots_balance="$ETH_GENESIS_BEACON_ROOTS_BALANCE"
    local eth_genesis_beacon_roots_nonce="$ETH_GENESIS_BEACON_ROOTS_NONCE"
    local eth_genesis_create2_deployer_address="$ETH_GENESIS_CREATE2_DEPLOYER_ADDRESS"
    local eth_genesis_create2_deployer_code="$ETH_GENESIS_CREATE2_DEPLOYER_CODE"
    local eth_genesis_create2_deployer_balance="$ETH_GENESIS_CREATE2_DEPLOYER_BALANCE"
    local eth_genesis_create2_deployer_nonce="$ETH_GENESIS_CREATE2_DEPLOYER_NONCE"
    local eth_genesis_multicall3_address="$ETH_GENESIS_MULTICALL3_ADDRESS"
    local eth_genesis_multicall3_balance="$ETH_GENESIS_MULTICALL3_BALANCE"
    local eth_genesis_multicall3_nonce="$ETH_GENESIS_MULTICALL3_NONCE"
    local eth_genesis_multicall3_code="$ETH_GENESIS_MULTICALL3_CODE"
    local eth_genesis_wbera_address="$ETH_GENESIS_WBERA_ADDRESS"
    local eth_genesis_wbera_code="$ETH_GENESIS_WBERA_CODE"
    local eth_genesis_wbera_balance="$ETH_GENESIS_WBERA_BALANCE"
    local eth_genesis_wbera_nonce="$ETH_GENESIS_WBERA_NONCE"
    local eth_genesis_permit2_address="$ETH_GENESIS_PERMIT2_ADDRESS"
    local eth_genesis_permit2_code="$ETH_GENESIS_PERMIT2_CODE"
    local eth_genesis_permit2_balance="$ETH_GENESIS_PERMIT2_BALANCE"
    local eth_genesis_permit2_nonce="$ETH_GENESIS_PERMIT2_NONCE"
    local eth_genesis_beacon_deposit_address="$ETH_GENESIS_BEACON_DEPOSIT_ADDRESS"
    local eth_genesis_beacon_deposit_code="$ETH_GENESIS_BEACON_DEPOSIT_CODE"
    local eth_genesis_beacon_deposit_balance="$ETH_GENESIS_BEACON_DEPOSIT_BALANCE"
    local eth_genesis_beacon_deposit_nonce="$ETH_GENESIS_BEACON_DEPOSIT_NONCE"
    local eth_genesis_beacon_deposit_storage_key="$ETH_GENESIS_BEACON_DEPOSIT_STORAGE_KEY"
    local eth_genesis_beacon_deposit_storage_value="$ETH_GENESIS_BEACON_DEPOSIT_STORAGE_VALUE"

    # Custom contracts
    # =============================================================================
    local -a eth_genesis_custom_contract_address=()
    local -a eth_genesis_custom_contract_nonce=()
    local -a eth_genesis_custom_contract_code=()
    local -a eth_genesis_custom_contract_balance=()
    local -a eth_genesis_custom_contract_storage=()

    # Genesis allocations
    # =============================================================================
    local eth_genesis_allocations=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            --genesis-file-path)
                genesis_file_path="$2"
                shift 2
                ;;
            --chain-id)
                chain_id="$2"
                shift 2
                ;;
            --homestead-block)
                eth_genesis_homestead_block="${2:-0}"
                shift 2
                ;;
            --dao-fork-block)
                eth_genesis_dao_fork_block="${2:-0}"
                shift 2
                ;;
            --dao-fork-support)
                eth_genesis_dao_fork_support="${2:-true}"
                shift 2
                ;;
            --eip150-block)
                eth_genesis_eip150_block="${2:-0}"
                shift 2
                ;;
            --eip155-block)
                eth_genesis_eip155_block="${2:-0}"
                shift 2
                ;;
            --eip158-block)
                eth_genesis_eip158_block="${2:-0}"
                shift 2
                ;;
            --byzantium-block)
                eth_genesis_byzantium_block="${2:-0}"
                shift 2
                ;;
            --constantinople-block)
                eth_genesis_constantinople_block="${2:-0}"
                shift 2
                ;;
            --petersburg-block)
                eth_genesis_petersburg_block="${2:-0}"
                shift 2
                ;;
            --istanbul-block)
                eth_genesis_istanbul_block="${2:-0}"
                shift 2
                ;;
            --muir-glacier-block)
                eth_genesis_muir_glacier_block="${2:-0}"
                shift 2
                ;;
            --berlin-block)
                eth_genesis_berlin_block="${2:-0}"
                shift 2
                ;;
            --london-block)
                eth_genesis_london_block="${2:-0}"
                shift 2
                ;;
            --arrow-glacier-block)
                eth_genesis_arrow_glacier_block="${2:-0}"
                shift 2
                ;;
            --gray-glacier-block)
                eth_genesis_gray_glacier_block="${2:-0}"
                shift 2
                ;;
            --merge-netsplit-block)
                eth_genesis_merge_netsplit_block="${2:-0}"
                shift 2
                ;;
            --shanghai-time)
                eth_genesis_shanghai_time="${2:-0}"
                shift 2
                ;;
            --cancun-time)
                eth_genesis_cancun_time="${2:-0}"
                shift 2
                ;;
            --prague-time)
                eth_genesis_prague_time="${2:-0}"
                shift 2
                ;;
            --terminal-total-difficulty)
                eth_genesis_terminal_total_difficulty="${2:-0}"
                shift 2
                ;;
            --terminal-total-difficulty-passed)
                eth_genesis_terminal_total_difficulty_passed="${2:-true}"
                shift 2
                ;;
            --blob-target)
                eth_genesis_blob_target="${2:-3}"
                shift 2
                ;;
            --blob-max)
                eth_genesis_blob_max="${2:-6}"
                shift 2
                ;;
            --blob-base-fee-update-fraction)
                eth_genesis_blob_base_fee_update_fraction="${2:-3338477}"
                shift 2
                ;;
            # Handle --pragueN-... flags generically for N in [1, 2, ...]
            --prague*-time)
                prague_epoch="${1#--prague}"
                prague_num="${prague_epoch%%-*}"
                prague_times[prague_num]="$2"
                shift 2
                ;;
            --prague*-base-fee-change-denominator)
                prague_epoch="${1#--prague}"
                prague_num="${prague_epoch%%-*}"
                prague_base_fee_change_denominator[prague_num]="$2"
                shift 2
                ;;
            --prague*-min-base-fee)
                prague_epoch="${1#--prague}"
                prague_num="${prague_epoch%%-*}"
                prague_min_base_fee[prague_num]="$2"
                shift 2
                ;;
            --prague*-pol-distributor)
                prague_epoch="${1#--prague}"
                prague_num="${prague_epoch%%-*}"
                prague_pol_distributor[prague_num]="$2"
                shift 2
                ;;
            --prague*-bex-vault)
                prague_epoch="${1#--prague}"
                prague_num="${prague_epoch%%-*}"
                prague_bex_vault[prague_num]="$2"
                shift 2
                ;;
            --prague*-rescue-address)
                prague_epoch="${1#--prague}"
                prague_num="${prague_epoch%%-*}"
                prague_rescue_address[prague_num]="$2"
                shift 2
                ;;
            --prague*-blocked-addresses)
                prague_epoch="${1#--prague}"
                prague_num="${prague_epoch%%-*}"
                IFS=',' read -ra addresses <<< "$2"

                valid_addresses=1
                formatted_addresses=()
                for addr in "${addresses[@]}"; do
                    if [[ "$addr" =~ ^0x[0-9a-fA-F]+$ ]]; then
                        formatted_addresses+=("$addr")
                    else
                        valid_addresses=0
                        break
                    fi
                done

                if [[ $valid_addresses -eq 1 ]]; then
                    # Store as comma-separated values (as in original)
                    prague_blocked_addresses[prague_num]=$(IFS=,; echo "${formatted_addresses[*]}")
                else
                    log_error "Invalid format for $1: expected comma-separated 0x addresses, got '$2'"
                    return 1
                fi
                shift 2
                ;;
            --genesis-coinbase-address)
                genesis_coinbase_address="${2:-0x0000000000000000000000000000000000000000}"
                shift 2
                ;;
            --genesis-difficulty)
                genesis_difficulty="${2:-0x01}"
                shift 2
                ;;
            --genesis-extra-data)
                genesis_extra_data="${2:-0x0000000000000000000000000000000000000000000000000000000000000000}"
                shift 2
                ;;
            --genesis-gas-limit)
                genesis_gas_limit="${2:-0x1c9c380}"
                shift 2
                ;;
            --genesis-nonce)
                genesis_nonce="${2:-0x1234}"
                shift 2
                ;;
            --genesis-mix-hash)
                genesis_mix_hash="${2:-0x0000000000000000000000000000000000000000000000000000000000000000}"
                shift 2
                ;;
            --genesis-parent-hash)
                genesis_parent_hash="${2:-0x0000000000000000000000000000000000000000000000000000000000000000}"
                shift 2
                ;;
            --genesis-timestamp)
                genesis_timestamp="${2:-0}"
                shift 2
                ;;
            --eth-genesis-beacon-roots-address)
                eth_genesis_beacon_roots_address="${2:-$ETH_GENESIS_BEACON_ROOTS_ADDRESS}"
                shift 2
                ;;
            --eth-genesis-beacon-roots-code)
                eth_genesis_beacon_roots_code="${2:-$ETH_GENESIS_BEACON_ROOTS_CODE}"
                shift 2
                ;;
            --eth-genesis-beacon-roots-balance)
                eth_genesis_beacon_roots_balance="${2:-$ETH_GENESIS_BEACON_ROOTS_BALANCE}"
                shift 2
                ;;
            --eth-genesis-beacon-roots-nonce)
                eth_genesis_beacon_roots_nonce="${2:-$ETH_GENESIS_BEACON_ROOTS_NONCE}"
                shift 2
                ;;
            --eth-genesis-create2-deployer-address)
                eth_genesis_create2_deployer_address="${2:-$ETH_GENESIS_CREATE2_DEPLOYER_ADDRESS}"
                shift 2
                ;;
            --eth-genesis-create2-deployer-code)
                eth_genesis_create2_deployer_code="${2:-$ETH_GENESIS_CREATE2_DEPLOYER_CODE}"
                shift 2
                ;;
            --eth-genesis-create2-deployer-balance)
                eth_genesis_create2_deployer_balance="${2:-$ETH_GENESIS_CREATE2_DEPLOYER_BALANCE}"
                shift 2
                ;;
            --eth-genesis-create2-deployer-nonce)
                eth_genesis_create2_deployer_nonce="${2:-$ETH_GENESIS_CREATE2_DEPLOYER_NONCE}"
                shift 2
                ;;
            --eth-genesis-multicall3-address)
                eth_genesis_multicall3_address="${2:-$ETH_GENESIS_MULTICALL3_ADDRESS}"
                shift 2
                ;;
            --eth-genesis-multicall3-code)
                eth_genesis_multicall3_code="${2:-$ETH_GENESIS_MULTICALL3_CODE}"
                shift 2
                ;;
            --eth-genesis-multicall3-balance)
                eth_genesis_multicall3_balance="${2:-$ETH_GENESIS_MULTICALL3_BALANCE}"
                shift 2
                ;;
            --eth-genesis-multicall3-nonce)
                eth_genesis_multicall3_nonce="${2:-$ETH_GENESIS_MULTICALL3_NONCE}"
                shift 2
                ;;
            --eth-genesis-wbera-address)
                eth_genesis_wbera_address="${2:-$ETH_GENESIS_WBERA_ADDRESS}"
                shift 2
                ;;
            --eth-genesis-wbera-code)
                eth_genesis_wbera_code="${2:-$ETH_GENESIS_WBERA_CODE}"
                shift 2
                ;;
            --eth-genesis-wbera-balance)
                eth_genesis_wbera_balance="${2:-$ETH_GENESIS_WBERA_BALANCE}"
                shift 2
                ;;
            --eth-genesis-wbera-nonce)
                eth_genesis_wbera_nonce="${2:-$ETH_GENESIS_WBERA_NONCE}"
                shift 2
                ;;
            --eth-genesis-permit2-address)
                eth_genesis_permit2_address="${2:-$ETH_GENESIS_PERMIT2_ADDRESS}"
                shift 2
                ;;
            --eth-genesis-permit2-code)
                eth_genesis_permit2_code="${2:-$ETH_GENESIS_PERMIT2_CODE}"
                shift 2
                ;;
            --eth-genesis-permit2-balance)
                eth_genesis_permit2_balance="${2:-$ETH_GENESIS_PERMIT2_BALANCE}"
                shift 2
                ;;
            --eth-genesis-permit2-nonce)
                eth_genesis_permit2_nonce="${2:-$ETH_GENESIS_PERMIT2_NONCE}"
                shift 2
                ;;
            --eth-genesis-beacon-deposit-address)
                eth_genesis_beacon_deposit_address="${2:-$ETH_GENESIS_BEACON_DEPOSIT_ADDRESS}"
                shift 2
                ;;
            --eth-genesis-beacon-deposit-code)
                eth_genesis_beacon_deposit_code="${2:-$ETH_GENESIS_BEACON_DEPOSIT_CODE}"
                shift 2
                ;;
            --eth-genesis-beacon-deposit-balance)
                eth_genesis_beacon_deposit_balance="${2:-$ETH_GENESIS_BEACON_DEPOSIT_BALANCE}"
                shift 2
                ;;
            --eth-genesis-beacon-deposit-nonce)
                eth_genesis_beacon_deposit_nonce="${2:-$ETH_GENESIS_BEACON_DEPOSIT_NONCE}"
                shift 2
                ;;
            --eth-genesis-beacon-deposit-storage-key)
                # Accept an array of storage keys as a comma-separated string, and split into a Bash array
                IFS=',' read -ra eth_genesis_beacon_deposit_storage_key <<< "${2:-$(IFS=,; echo "${ETH_GENESIS_BEACON_DEPOSIT_STORAGE_KEY[*]}")}"
                shift 2
                ;;
            --eth-genesis-beacon-deposit-storage-value)
                # Accept an array of storage values as a comma-separated string, and split into a Bash array
                IFS=',' read -ra eth_genesis_beacon_deposit_storage_value <<< "${2:-$(IFS=,; echo "${ETH_GENESIS_BEACON_DEPOSIT_STORAGE_VALUE[*]}")}"
                shift 2
                ;;
             --eth-genesis-custom*-contract-address)
                # Extract the custom contract index from the flag (e.g., --eth-genesis-custom1-contract-address)
                # Valid flag pattern is --eth-genesis-custom<index>-contract-address
                index="${1#--eth-genesis-custom}"
                index="${index%-contract-address}"

                # Only process if the provided address starts with 0x01 (as a hex string)
                if [[ "${2}" == 0x* ]]; then
                    eth_genesis_custom_contract_address[index]="${2}"
                fi
                shift 2
                ;;
            --eth-genesis-custom*-contract-code)
                # Extract the custom contract index from the flag (e.g., --eth-genesis-custom1-contract-code)
                # Valid flag pattern is --eth-genesis-custom<index>-contract-code
                index="${1#--eth-genesis-custom}"
                index="${index%-contract-code}"

                # Only process if the provided code starts with 0x01 (as a hex string)
                if [[ "${2}" == 0x* ]]; then
                    eth_genesis_custom_contract_code[index]="${2}"
                fi
                shift 2
                ;;
            --eth-genesis-custom*-contract-balance)
                # Extract the custom contract index from the flag (e.g., --eth-genesis-custom1-contract-balance)
                # Valid flag pattern is --eth-genesis-custom<index>-contract-balance
                index="${1#--eth-genesis-custom}"
                index="${index%-contract-balance}"

                # Only process if the provided balance starts with 0x01 (as a hex string)
                eth_genesis_custom_contract_balance[index]="${2}"
                shift 2
                ;;
            --eth-genesis-custom*-contract-nonce)
                # Extract the custom contract index from the flag (e.g., --eth-genesis-custom1-contract-nonce)
                # Valid flag pattern is --eth-genesis-custom<index>-contract-nonce
                index="${1#--eth-genesis-custom}"
                index="${index%-contract-nonce}"

                # Only process if the provided nonce starts with 0x01 (as a hex string)
                if [[ "${2}" == 0x* ]]; then
                    eth_genesis_custom_contract_nonce[index]="${2}"
                fi
                shift 2
                ;;
            --eth-genesis-custom*-contract-storage)
                # Extract the custom contract index from the flag (e.g., --eth-genesis-custom7-contract-storage)
                # Valid flag pattern is --eth-genesis-custom<index>-contract-storage
                index="${1#--eth-genesis-custom}"
                index="${index%-contract-storage}"

                # The value must be a comma-separated list of storage entries: 0xKEY=VALUE,...
                # We'll validate and transform this to a canonical format array
                storage_arg="$2"
                valid_format=1
                formatted_storage=""

                # Check the whole flag value for expected format: 0xKEY=VALUE,0xKEY2=VALUE2,...
                IFS=',' read -ra entries <<< "$storage_arg"
                for entry in "${entries[@]}"; do
                    # Each entry must be of the form 0xKEY=VALUE
                    if [[ "$entry" =~ ^0x[0-9a-fA-F]+=[0-9a-fA-Fx]+$ ]]; then
                        # Format each pair as JSON-style string for later use if needed.
                        [[ -n "$formatted_storage" ]] && formatted_storage+=","
                        formatted_storage+="$entry"
                    else
                        valid_format=0
                        break
                    fi
                done

                if [[ $valid_format -eq 1 ]]; then
                    eth_genesis_custom_contract_storage[index]="$formatted_storage"
                else
                    log_error "Invalid format for $1: expected '0xKEY=VALUE[,0xKEY2=VALUE2...]' got '$2'"
                    return 1
                fi
                shift 2
                ;;
            --eth-genesis-allocations)
                # Accept one or more allocations of the form 0xADDR=VALUE[,0xADDR2=VALUE2...]
                # Handle both multiple and single value scenarios
                if [[ -n "${2-}" ]]; then
                    IFS=',' read -ra eth_genesis_allocations <<< "$2"
                else
                    # Fallback to ETH_GENESIS_ALLOCATIONS env or default
                    IFS=',' read -ra eth_genesis_allocations <<< "${ETH_GENESIS_ALLOCATIONS[*]}"
                fi
                shift 2
                ;;
            *)
                echo "Unknown flag: $1"
                shift
                ;;
        esac
    done

    # Print first instance of eth_genesis_custom_contract_address if set
    if [[ ${#eth_genesis_custom_contract_address[@]} -gt 0 ]]; then
        echo "eth_genesis_custom_contract_address: ${eth_genesis_custom_contract_address[0]}"
    else
        echo "eth_genesis_custom_contract_address: (unset)"
    fi
    # TESTING
    # echo "eth_genesis_custom_contract_nonce: ${eth_genesis_custom_contract_nonce[0]}"
    # echo "eth_genesis_custom_contract_code: ${eth_genesis_custom_contract_code[0]}"
    # echo "eth_genesis_custom_contract_balance: ${eth_genesis_custom_contract_balance[0]}"
    # echo "eth_genesis_custom_contract_storage: ${eth_genesis_custom_contract_storage[0]}"
    # exit 1

    # Check for required arguments
    if [[ -z "$genesis_file_path" ]]; then
        log_error "Missing required flag: --genesis-file-path"
        return 1
    fi

    # Build the berachain section
    _eth_genesis_build_berachain_section() {
        local sections=()

        # Iterate over prague_times array (should be indexed by prague number)
        for i in "${!prague_times[@]}"; do
            # Only build for pragueN where time is set and non-empty
            if [[ -n "${prague_times[$i]}" ]]; then
                local section_lines=()
                local indent='            '

                # time
                if [[ -n "${prague_times[$i]}" ]]; then
                    section_lines+=("${indent}\"time\": ${prague_times[$i]}")
                fi

                # baseFeeChangeDenominator
                if [[ -n "${prague_base_fee_change_denominator[$i]:-}" ]]; then
                    section_lines+=("${indent}\"baseFeeChangeDenominator\": ${prague_base_fee_change_denominator[$i]}")
                fi

                # minimumBaseFeeWei
                if [[ -n "${prague_min_base_fee[$i]:-}" ]]; then
                    section_lines+=("${indent}\"minimumBaseFeeWei\": ${prague_min_base_fee[$i]}")
                fi

                # polDistributorAddress
                if [[ -n "${prague_pol_distributor[$i]:-}" ]]; then
                    section_lines+=("${indent}\"polDistributorAddress\": \"${prague_pol_distributor[$i]}\"")
                fi

                # bexVaultAddress
                if [[ -n "${prague_bex_vault[$i]:-}" ]]; then
                    section_lines+=("${indent}\"bexVaultAddress\": \"${prague_bex_vault[$i]}\"")
                fi

                # rescueAddress
                if [[ -n "${prague_rescue_address[$i]:-}" ]]; then
                    section_lines+=("${indent}\"rescueAddress\": \"${prague_rescue_address[$i]}\"")
                fi

                # blockedAddresses
                if [[ -n "${prague_blocked_addresses[$i]+set}" && -n "${prague_blocked_addresses[$i]}" ]]; then
                    IFS=',' read -ra addresses <<< "${prague_blocked_addresses[$i]}"
                    local formatted="[\n"
                    local num_addresses=0
                    for j in "${!addresses[@]}"; do
                        local addr_trimmed="$(echo -n "${addresses[j]}" | xargs)"
                        if [[ -n "$addr_trimmed" ]]; then
                            (( num_addresses > 0 )) && formatted+=",\n"
                            formatted+="                \"$addr_trimmed\""
                            ((num_addresses++))
                        fi
                    done
                    formatted+="\n            ]"
                    section_lines+=("${indent}\"blockedAddresses\": ${formatted}")
                fi

                # Build the section json with correct indentation (12 spaces for level 2, 8 for berachain line)
                local section="        \"prague${i}\": {\n"
                for j in "${!section_lines[@]}"; do
                    section+="${section_lines[$j]}"
                    [[ $j -lt $((${#section_lines[@]}-1)) ]] && section+=",\n" || section+="\n"
                done
                section+="        }"
                sections+=("$section")
            fi
        done

        # Output all sections, comma-separated (with no trailing comma), add appropriate tabs
        local output=""
        for idx in "${!sections[@]}"; do
            [[ $idx -gt 0 ]] && output+=",\n"
            output+="${sections[$idx]}"
        done
        echo -e "$output"
    }

    # Build the contracts alloc section
    _build_contracts_alloc() {
      local contract_alloc_lines=()
      local indent='    '

      # beacon roots
      if [[ -n "${eth_genesis_beacon_roots_address}" ]]; then
        contract_alloc_lines+=("${indent}\"${eth_genesis_beacon_roots_address}\": {")
        contract_alloc_lines+=("${indent}  \"balance\": \"${eth_genesis_beacon_roots_balance}\",")
        contract_alloc_lines+=("${indent}  \"nonce\": \"${eth_genesis_beacon_roots_nonce}\",")
        contract_alloc_lines+=("${indent}  \"code\": \"${eth_genesis_beacon_roots_code}\"")
        if [[ -n "${eth_genesis_create2_deployer_address}" ]]; then
          contract_alloc_lines+=("${indent}},")
        else
          contract_alloc_lines+=("${indent}}")
        fi
      fi

      # create2 deployer
      if [[ -n "${eth_genesis_create2_deployer_address}" ]]; then
        contract_alloc_lines+=("${indent}\"${eth_genesis_create2_deployer_address}\": {")
        contract_alloc_lines+=("${indent}  \"balance\": \"${eth_genesis_create2_deployer_balance}\",")
        contract_alloc_lines+=("${indent}  \"nonce\": \"${eth_genesis_create2_deployer_nonce}\",")
        contract_alloc_lines+=("${indent}  \"code\": \"${eth_genesis_create2_deployer_code}\"")
        if [[ -n "${eth_genesis_multicall3_address}" ]]; then
          contract_alloc_lines+=("${indent}},")
        else
          contract_alloc_lines+=("${indent}}")
        fi
      fi

      # multicall3
      if [[ -n "${eth_genesis_multicall3_address}" ]]; then
        contract_alloc_lines+=("${indent}\"${eth_genesis_multicall3_address}\": {")
        contract_alloc_lines+=("${indent}  \"balance\": \"${eth_genesis_multicall3_balance}\",")
        contract_alloc_lines+=("${indent}  \"nonce\": \"${eth_genesis_multicall3_nonce}\",")
        contract_alloc_lines+=("${indent}  \"code\": \"${eth_genesis_multicall3_code}\"")
        if [[ -n "${eth_genesis_wbera_address}" ]]; then
          contract_alloc_lines+=("${indent}},")
        else
          contract_alloc_lines+=("${indent}}")
        fi
      fi

      # wbera
      if [[ -n "${eth_genesis_wbera_address}" ]]; then
        contract_alloc_lines+=("${indent}\"${eth_genesis_wbera_address}\": {")
        contract_alloc_lines+=("${indent}  \"balance\": \"${eth_genesis_wbera_balance}\",")
        contract_alloc_lines+=("${indent}  \"nonce\": \"${eth_genesis_wbera_nonce}\",")
        contract_alloc_lines+=("${indent}  \"code\": \"${eth_genesis_wbera_code}\"")
        if [[ -n "${eth_genesis_permit2_address}" ]]; then
          contract_alloc_lines+=("${indent}},")
        else
          contract_alloc_lines+=("${indent}}")
        fi
      fi

      # permit2
      if [[ -n "${eth_genesis_permit2_address}" ]]; then
        contract_alloc_lines+=("${indent}\"${eth_genesis_permit2_address}\": {")
        contract_alloc_lines+=("${indent}  \"balance\": \"${eth_genesis_permit2_balance}\",")
        contract_alloc_lines+=("${indent}  \"nonce\": \"${eth_genesis_permit2_nonce}\",")
        contract_alloc_lines+=("${indent}  \"code\": \"${eth_genesis_permit2_code}\"")
        if [[ -n "${eth_genesis_beacon_deposit_address}" ]]; then
          contract_alloc_lines+=("${indent}},")
        else
          contract_alloc_lines+=("${indent}}")
        fi
      fi

      # beacon deposit
      if [[ -n "${eth_genesis_beacon_deposit_address}" ]]; then
        contract_alloc_lines+=("${indent}\"${eth_genesis_beacon_deposit_address}\": {")
        contract_alloc_lines+=("${indent}  \"balance\": \"${eth_genesis_beacon_deposit_balance}\",")
        contract_alloc_lines+=("${indent}  \"nonce\": \"${eth_genesis_beacon_deposit_nonce}\",")
        if [[ -n "${eth_genesis_beacon_deposit_storage_key}" ]]; then
          contract_alloc_lines+=("${indent}  \"code\": \"${eth_genesis_beacon_deposit_code}\",")
          contract_alloc_lines+=("${indent}  \"storage\": {")
          # Split storage keys/values on comma if string contains ',' (to support "0x1,0x2" format)
          storage_keys=()
          storage_values=()
          if [[ "${#eth_genesis_beacon_deposit_storage_key[@]}" -eq 1 && "${eth_genesis_beacon_deposit_storage_key[0]}" == *,* ]]; then
            IFS=',' read -ra storage_keys <<< "${eth_genesis_beacon_deposit_storage_key[0]}"
          else
            storage_keys=("${eth_genesis_beacon_deposit_storage_key[@]}")
          fi
          if [[ "${#eth_genesis_beacon_deposit_storage_value[@]}" -eq 1 && "${eth_genesis_beacon_deposit_storage_value[0]}" == *,* ]]; then
            IFS=',' read -ra storage_values <<< "${eth_genesis_beacon_deposit_storage_value[0]}"
          else
            storage_values=("${eth_genesis_beacon_deposit_storage_value[@]}")
          fi

          storage_len=${#storage_keys[@]}
          for i in "${!storage_keys[@]}"; do
            if [[ $i -lt $((storage_len-1)) ]]; then
              contract_alloc_lines+=("${indent}    \"${storage_keys[$i]}\": \"${storage_values[$i]}\",")
            else
              contract_alloc_lines+=("${indent}    \"${storage_keys[$i]}\": \"${storage_values[$i]}\"")
            fi
          done
          contract_alloc_lines+=("${indent}  }")
        else
          contract_alloc_lines+=("${indent}  \"code\": \"${eth_genesis_beacon_deposit_code}\"")
        fi
        contract_alloc_lines+=("${indent}}")
      fi

      # Output all contract allocations, comma-separated (with no trailing comma), add appropriate tabs
      local output=""
      for idx in "${!contract_alloc_lines[@]}"; do
          [[ $idx -gt 0 ]] && output+="\n"
          output+="${contract_alloc_lines[$idx]}"
      done
      echo -e "$output"
    }

    # Build the custom contracts alloc section
    _build_custom_alloc() {
      local contract_custom_alloc_lines=()
      local indent='    '
      local contract_custom_alloc_count=${#eth_genesis_custom_contract_address[@]}

      for index in "${!eth_genesis_custom_contract_address[@]}"; do
        # Only proceed if the contract address is set (required for a valid allocation)
        if [[ -n "${eth_genesis_custom_contract_address[$index]:-}" ]]; then
          contract_custom_alloc_lines+=("${indent}\"${eth_genesis_custom_contract_address[$index]}\": {")
          # Only include balance if set
          if [[ -n "${eth_genesis_custom_contract_balance[$index]:-}" ]]; then
            local line="${indent}  \"balance\": \"${eth_genesis_custom_contract_balance[$index]}\""
            if [[ -n "${eth_genesis_custom_contract_nonce[$index]:-}" || -n "${eth_genesis_custom_contract_code[$index]:-}" || -n "${eth_genesis_custom_contract_storage[$index]:-}" ]]; then
              line+=","
            fi
            contract_custom_alloc_lines+=("${line}")
          fi
          # Only include nonce if set
          if [[ -n "${eth_genesis_custom_contract_nonce[$index]:-}" ]]; then
            local line="${indent}  \"nonce\": \"${eth_genesis_custom_contract_nonce[$index]}\""
            if [[ -n "${eth_genesis_custom_contract_code[$index]:-}" || -n "${eth_genesis_custom_contract_storage[$index]:-}" ]]; then
              line+=","
            fi
            contract_custom_alloc_lines+=("${line}")
          fi
          # Only include code if set
          if [[ -n "${eth_genesis_custom_contract_code[$index]:-}" ]]; then
            local line="${indent}  \"code\": \"${eth_genesis_custom_contract_code[$index]}\""
            if [[ -n "${eth_genesis_custom_contract_storage[$index]:-}" ]]; then
              line+=","
            fi
            contract_custom_alloc_lines+=("${line}")
          fi
          # Only include storage if set
          if [[ -n "${eth_genesis_custom_contract_storage[$index]:-}" ]]; then
            local line="${indent}  \"storage\": {\n"

            # Process comma-separated storage entries for the current custom contract
            # eth_genesis_custom_contract_storage[$index] will look like: "0x01=0x01,0x02=0x02,0x03=0x05"
            if [[ -n "${eth_genesis_custom_contract_storage[$index]}" ]]; then
              IFS=',' read -ra storage_entries <<< "${eth_genesis_custom_contract_storage[$index]}"
              for entry_idx in "${!storage_entries[@]}"; do
                entry="${storage_entries[$entry_idx]}"
                storage_key="${entry%%=*}"
                storage_value="${entry#*=}"
                line+="${indent}    \"${storage_key}\": \"${storage_value}\""
                # If not the last entry, add a comma
                if [[ $entry_idx -lt $(( ${#storage_entries[@]} - 1 )) ]]; then
                  line+=",\n"
                else
                  line+="\n"
                fi
              done
            fi

            line+="${indent}  }"
            contract_custom_alloc_lines+=("${line}")
          fi

          # Remove trailing comma if present before closing } (optional for improved JSON validity)
          if [[ "${contract_custom_alloc_lines[-1]}" =~ ,$ ]]; then
            contract_custom_alloc_lines[-1]="${contract_custom_alloc_lines[-1]%,}"
          fi
          if [[ $index -lt $((contract_custom_alloc_count-1)) ]]; then
            contract_custom_alloc_lines+=("${indent}},")
          else
            contract_custom_alloc_lines+=("${indent}}")
          fi
        fi
      done

      # Output all custom contract allocations, comma-separated (with no trailing comma), add appropriate tabs
      local output=""
      if [[ ${#contract_custom_alloc_lines[@]} -gt 0 ]]; then
        output+=",\n"
      fi
      for idx in "${!contract_custom_alloc_lines[@]}"; do
          [[ $idx -gt 0 ]] && output+="\n"
          output+="${contract_custom_alloc_lines[$idx]}"
      done
      echo -e "$output"
    }

    cat > "$genesis_file_path" <<EOF
{
  "config": {
    "chainId": ${chain_id},
    "homesteadBlock": ${eth_genesis_homestead_block},
    "daoForkBlock": ${eth_genesis_dao_fork_block},
    "daoForkSupport": ${eth_genesis_dao_fork_support},
    "eip150Block": ${eth_genesis_eip150_block},
    "eip155Block": ${eth_genesis_eip155_block},
    "eip158Block": ${eth_genesis_eip158_block},
    "byzantiumBlock": ${eth_genesis_byzantium_block},
    "constantinopleBlock": ${eth_genesis_constantinople_block},
    "petersburgBlock": ${eth_genesis_petersburg_block},
    "istanbulBlock": ${eth_genesis_istanbul_block},
    "muirGlacierBlock": ${eth_genesis_muir_glacier_block},
    "berlinBlock": ${eth_genesis_berlin_block},
    "londonBlock": ${eth_genesis_london_block},
    "arrowGlacierBlock": ${eth_genesis_arrow_glacier_block},
    "grayGlacierBlock": ${eth_genesis_gray_glacier_block},
    "mergeNetsplitBlock": ${eth_genesis_merge_netsplit_block},
    "shanghaiTime": ${eth_genesis_shanghai_time},
    "cancunTime": ${eth_genesis_cancun_time},
    "pragueTime": ${eth_genesis_prague_time},
    "terminalTotalDifficulty": ${eth_genesis_terminal_total_difficulty},
    "terminalTotalDifficultyPassed": ${eth_genesis_terminal_total_difficulty_passed},
    "blobSchedule": {
      "cancun": {
        "target": ${eth_genesis_blob_target},
        "max": ${eth_genesis_blob_max},
        "baseFeeUpdateFraction": ${eth_genesis_blob_base_fee_update_fraction}
      },
      "prague": {
        "target": ${eth_genesis_blob_target},
        "max": ${eth_genesis_blob_max},
        "baseFeeUpdateFraction": ${eth_genesis_blob_base_fee_update_fraction}
      }
    },
    "berachain": {
$(_eth_genesis_build_berachain_section)
    },
    "ethash": {}
  },
  "coinbase": "${genesis_coinbase_address}",
  "difficulty": "${genesis_difficulty}",
  "extraData": "${genesis_extra_data}",
  "gasLimit": "${genesis_gas_limit}",
  "nonce": "${genesis_nonce}",
  "mixhash": "${genesis_mix_hash}",
  "parentHash": "${genesis_parent_hash}",
  "timestamp": "${genesis_timestamp}",
  "alloc": {
$(_build_contracts_alloc)$(_build_custom_alloc)
  }
}
EOF

  # Validate and pretty-print the eth-genesis.json file with jq to ensure correct and pretty formatting
  if [[ -f "${genesis_file_path}" ]]; then
    if jq . "${genesis_file_path}" > "${genesis_file_path}.formatted" 2>/dev/null; then
      mv "${genesis_file_path}.formatted" "${genesis_file_path}"
      log_success "eth-genesis.json at ${genesis_file_path} is valid JSON and has been formatted with jq."
    else
      log_error "eth-genesis.json at ${genesis_file_path} is not valid JSON or is corrupted."
      rm -f "${genesis_file_path}.formatted"
      return 1
    fi
  else
    log_error "eth-genesis.json does not exist at ${genesis_file_path}."
    return 1
  fi

}

# Helper function to generate beacond keys
generate_beacond_keys() {
  [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_beacond_keys" >&2
  local config_dir="$1"
  local chain_spec="$2"
  local chain_id="$3"

  # Parse flags
  while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
          --config-dir)
              config_dir="$2"
              shift 2
              ;;
          --chain-spec)
              chain_spec="$2"
              if [[ "$chain_spec" == "${CHAIN_NAME_DEVNET}" ]]; then
                  chain_id="${CHAIN_ID_DEVNET}"
              elif [[ "$chain_spec" == "${CHAIN_NAME_TESTNET}" ]]; then
                  chain_id="${CHAIN_ID_TESTNET}"
              elif [[ "$chain_spec" == "${CHAIN_NAME_MAINNET}" ]]; then
                  chain_id="${CHAIN_ID_MAINNET}"
              else
                  echo "Unknown chain spec: ${chain_spec}"
                  return 1
              fi
              shift 2
              ;;
          *)
              echo "Unknown flag: $1"
              shift
              ;;
      esac
  done

  # Check if bin/beacond exists in ${config_dir}/bin and is executable
  local beacond_binary="${config_dir}/bin/beacond"
  if [[ ! -x "${beacond_binary}" ]]; then
      log_error "beacond binary not found or not executable at: ${beacond_binary}"
      return 1
  fi

  # Clean up any existing beacond directory
  if [ -d "${config_dir}/tmp/beacond" ]; then
    log_info "Removing existing beacond directory at ${config_dir}/tmp/beacond"
    rm -rf "${config_dir}/tmp/beacond";
    if [[ $? -ne 0 ]]; then
      log_error "Failed to remove existing beacond directory at ${config_dir}/tmp/beacond"
      return 1
    fi
    log_success "Removed existing beacond directory at ${config_dir}/tmp/beacond"
  fi

  beranode_config_file="${config_dir}/beranodes.config.json"
  if [[ ! -f "${beranode_config_file}" ]]; then
    log_error "Beranode configuration file not found at ${beranode_config_file}"
    return 1
  fi
  # Retrieve all the .nodes from the beranodes.config.json file
  nodes_json=$(jq -c '.nodes' "${beranode_config_file}")
  if [[ $? -ne 0 ]] || [[ -z "$nodes_json" ]]; then
    log_error "Failed to read or parse .nodes from ${beranode_config_file}"
    return 1
  fi
  nodes_count=$(echo "$nodes_json" | jq 'length')
  echo "Number of nodes: $nodes_count"
  
  # Retrieve withdraw address from beranodes.config.json
  withdraw_address="$(jq -r '.wallet_address' "${beranode_config_file}")"
  if [[ $? -ne 0 ]] || [[ -z "$withdraw_address" ]]; then
    log_error "Failed to read or parse .wallet_address from ${beranode_config_file}"
    return 1
  fi

  echo "Initializing beacond nodes..."
  for i in $(seq 1 ${nodes_count}); do
    node_json=$(echo "$nodes_json" | jq ".[$i-1]")
    local moniker=$(echo "$node_json" | jq -r '.moniker')
    local role=$(echo "$node_json" | jq -r '.role')

    mkdir -p "${config_dir}/tmp/beacond"
    ${beacond_binary} init ${moniker} --chain-id ${chain_id} --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond >/dev/null 2>&1;
    if [[ $? -ne 0 ]]; then
      log_error "Failed to initialize beacond node at ${config_dir}/tmp/beacond"
      return 1
    fi
    log_success "Initialized beacond node ${i} - ${moniker} at ${config_dir}/tmp/beacond"

    # Read node_key.json
    node_key_file="${config_dir}/tmp/beacond/config/node_key.json"
    if [[ ! -f "${node_key_file}" ]]; then
      log_error "node_key.json not found at ${node_key_file}"
      return 1
    fi
    node_key_json=$(jq -c '.' "${node_key_file}")
    if [[ $? -ne 0 ]] || [[ -z "$node_key_json" ]]; then
      log_error "Failed to read or parse node_key.json from ${node_key_file}"
      return 1
    fi

    # Read priv_validator_key.json
    priv_validator_key_file="${config_dir}/tmp/beacond/config/priv_validator_key.json"
    if [[ ! -f "${priv_validator_key_file}" ]]; then
      log_error "priv_validator_key.json not found at ${priv_validator_key_file}"
      return 1
    fi
    priv_validator_key_json=$(jq -c '.' "${priv_validator_key_file}")
    if [[ $? -ne 0 ]] || [[ -z "$priv_validator_key_json" ]]; then
      log_error "Failed to read or parse priv_validator_key.json from ${priv_validator_key_file}"
      return 1
    fi

    # Read validator keys
    validator_keys=""
    validator_keys="$(${beacond_binary} deposit validator-keys --home ${config_dir}/tmp/beacond)"
    if [[ $? -ne 0 ]]; then
      log_error "Failed to read validator keys at ${config_dir}/tmp/beacond"
      return 1
    fi
   
    premined_deposit_json="null"
    if [[ "$role" == "validator" ]]; then
      # Add premined deposit
      ${beacond_binary} genesis add-premined-deposit ${GENESIS_DEPOSIT_AMOUNT} "${withdraw_address}" --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond
      if [[ $? -ne 0 ]]; then
        log_error "Failed to add premined deposit at ${config_dir}/tmp/beacond"
        return 1
      fi

      # Get the contents from the premined-deposit-*.json file
      premined_deposit_file=$(ls ${config_dir}/tmp/beacond/config/premined-deposits/premined-deposit-*.json 2>/dev/null | head -n 1)

      if [[ -n "${premined_deposit_file}" && -f "${premined_deposit_file}" ]]; then
        # Ensure the file contains valid JSON, and get as raw object for jq
        premined_deposit_json=$(jq -c '.' "${premined_deposit_file}")
        if [[ $? -ne 0 ]] || [[ -z "$premined_deposit_json" ]]; then
          log_error "Failed to read or parse premined deposit json from ${premined_deposit_file}"
          return 1
        fi
      else
        log_error "premined deposit json file not found for node ${moniker} at ${config_dir}/tmp/beacond/premined-deposits/"
        return 1
      fi
    fi

    # Extract Comet Address
    comet_address=$(echo "$validator_keys" | sed -n '2p' | xargs | tr -d '[:space:]')
    comet_pubkey=$(echo "$validator_keys" | sed -n '5p' | xargs | tr -d '[:space:]')
    eth_beacon_pubkey=$(echo "$validator_keys" | sed -n '8p' | xargs | tr -d '[:space:]')

    # Get deposit amount
    deposit_amount=$GENESIS_DEPOSIT_AMOUNT

    # Generate JWT file
    ${beacond_binary} >/dev/null 2>&1 jwt generate -o ${config_dir}/tmp/beacond/jwt.hex;
    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate JWT file at ${jwt_file}"
        return 1
    fi
    # Add JWT value to beranodes.config.json
    jwt_value=$(cat ${config_dir}/tmp/beacond/jwt.hex)
    if [[ $? -ne 0 ]] || [[ -z "$jwt_value" ]]; then
      log_error "Failed to read JWT value from ${config_dir}/tmp/beacond/jwt.hex"
      return 1
    fi
    
    # Build json object with the validator keys
    tmp_beranode_config="${beranode_config_file}.tmp"
    jq --arg idx "$((i-1))" \
       --argjson node_key "$node_key_json" \
       --argjson priv_validator_key "$priv_validator_key_json" \
       --arg comet_address "$comet_address" \
       --arg comet_pubkey "$comet_pubkey" \
       --arg eth_beacon_pubkey "$eth_beacon_pubkey" \
       --argjson premined_deposit "$premined_deposit_json" \
       --arg deposit_amount "$deposit_amount" \
       --arg jwt "$jwt_value" \
       '
         .nodes |=
           (.[($idx|tonumber)] += {
              node_key: $node_key,
              priv_validator_key: $priv_validator_key,
              comet_address: $comet_address,
              comet_pubkey: $comet_pubkey,
              eth_beacon_pubkey: $eth_beacon_pubkey,
              premined_deposit: $premined_deposit,
              deposit_amount: $deposit_amount,
              jwt: $jwt
           })
       ' "${beranode_config_file}" > "${tmp_beranode_config}"
    if [[ $? -ne 0 ]]; then
      log_error "Failed to add node_key to node $((i-1)) in ${beranode_config_file}"
      rm -f "${tmp_beranode_config}"
      return 1
    fi
    mv "${tmp_beranode_config}" "${beranode_config_file}"

    # Clean up the tmp/beacond folder for each iteration
    if [ -d "${config_dir}/tmp/beacond" ]; then
      rm -rf "${config_dir}/tmp/beacond"
      if [[ $? -ne 0 ]]; then
        log_error "Failed to clean up ${config_dir}/tmp/beacond before initializing node ${moniker}"
        return 1
      fi
      log_info "Cleaned up ${config_dir}/tmp/beacond before initializing node ${moniker}"
    fi

    log_success "Added node_key to node $((i-1)) in ${beranode_config_file}"
  done

  # mkdir -p "${config_dir}/tmp/beacond"
  # cp ${config_dir}/tmp/beacond/config/genesis.json ${config_dir}/tmp/genesis.json
  # if [[ $? -ne 0 ]]; then
  #   log_error "Failed to copy genesis file to ${config_dir}/tmp/genesis.json"
  #   return 1
  # fi
  # log_success "Copied genesis file to ${config_dir}/tmp/genesis.json"

  #   # Generate jwt
  #   echo "Generating JWT file..."
  #   local jwt_file="${config_dir}/tmp/jwt.hex"
  #   if [ -f "${jwt_file}" ]; then
  #     log_info "JWT file already exists at ${jwt_file}"
  #   else
  #     ${beacond_binary} >/dev/null 2>&1 jwt generate -o ${jwt_file}
  #     if [[ $? -ne 0 ]]; then
  #         log_error "Failed to generate JWT file at ${jwt_file}"
  #         return 1
  #     fi
  #   fi

}

# Helper function to generate a genesis.json file
generate_genesis_file() {
  [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_genesis_file" >&2
  local config_dir="$1"
  local chain_spec="$2"
  local chain_id="$3"
  local moniker="TEMP-MONIKER"

  # Parse flags
  while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
          --config-dir)
              config_dir="$2"
              shift 2
              ;;
          --chain-spec)
              chain_spec="$2"
              if [[ "$chain_spec" == "${CHAIN_NAME_DEVNET}" ]]; then
                  chain_id="${CHAIN_ID_DEVNET}"
              elif [[ "$chain_spec" == "${CHAIN_NAME_TESTNET}" ]]; then
                  chain_id="${CHAIN_ID_TESTNET}"
              elif [[ "$chain_spec" == "${CHAIN_NAME_MAINNET}" ]]; then
                  chain_id="${CHAIN_ID_MAINNET}"
              else
                  echo "Unknown chain spec: ${chain_spec}"
                  shift 2
                  return 1
              fi
              shift 2
              ;;
          *)
              echo "Unknown flag: $1"
              shift
              ;;
      esac
  done

  # Check if bin/beacond exists in ${config_dir}/bin and is executable
  local beacond_binary="${config_dir}/bin/beacond"
  if [[ ! -x "${beacond_binary}" ]]; then
      log_error "beacond binary not found or not executable at: ${beacond_binary}"
      return 1
  fi

  # Clean up any existing genesis file
  if [ -d "${config_dir}/tmp/beacond" ]; then
    log_info "Removing existing beacond directory at ${config_dir}/tmp/beacond"
    rm -rf "${config_dir}/tmp/beacond";
    if [[ $? -ne 0 ]]; then
      log_error "Failed to remove existing beacond directory at ${config_dir}/tmp/beacond"
      return 1
    fi
    log_success "Removed existing beacond directory at ${config_dir}/tmp/beacond"
  fi

    # # Check if beacond is working correctly by running `beacond version`
    # local genesis_file="${config_dir}/tmp/genesis.json"
    # if [ -f "${genesis_file}" ]; then
    #   log_info "Genesis file already exists at ${genesis_file}"
    # else
    #   ${beacond_binary} >/dev/null 2>&1 init ${moniker} --chain-id ${chain_id} --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond;
    #   if [[ $? -ne 0 ]]; then
    #     log_error "Failed to generate Genesis file at ${genesis_file}"
    #     return 1
    #   fi
    #   # TEST
    #   # cp ${config_dir}/tmp/beacond/config/genesis.json ${config_dir}/tmp/beacond/config/genesis.bk.json
    # fi

    # # Set deposit storage - eth-genesis.json (execution client - bera-reth)
    # ${beacond_binary} >/dev/null 2>&1 genesis set-deposit-storage ${config_dir}/tmp/eth-genesis.json --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond;
    # if [[ $? -ne 0 ]]; then
    #   log_error "Failed to set deposit storage at ${config_dir}/tmp/eth-genesis.json"
    #   return 1
    # fi
    # log_success "Set deposit storage at ${config_dir}/tmp/eth-genesis.json"

    # # Execution payload - genesis.json (consensus client - beacond)
    # ${beacond_binary} >/dev/null 2>&1 genesis execution-payload ${config_dir}/tmp/eth-genesis.json --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond;
    # if [[ $? -ne 0 ]]; then
    #   log_error "Failed to set execution payload at ${config_dir}/tmp/eth-genesis.json"
    #   return 1
    # fi
    # log_success "Set execution payload at ${config_dir}/tmp/eth-genesis.json"

    # Generate jwt
    echo "Generating JWT file..."
    local jwt_file="${config_dir}/tmp/jwt.hex"
    if [ -f "${jwt_file}" ]; then
      log_info "JWT file already exists at ${jwt_file}"
    else
      ${beacond_binary} >/dev/null 2>&1 jwt generate -o ${jwt_file}
      if [[ $? -ne 0 ]]; then
          log_error "Failed to generate JWT file at ${jwt_file}"
          return 1
      fi
    fi

    echo "Initializing beacond node..."
    local genesis_file="${config_dir}/tmp/genesis.json"
    if [ -f "${genesis_file}" ]; then
      log_info "Genesis file already exists at ${genesis_file}"
    else
      mkdir -p "${config_dir}/tmp/beacond"
      ${beacond_binary} init ${moniker} --chain-id ${chain_id} --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond >/dev/null 2>&1;
      if [[ $? -ne 0 ]]; then
        log_error "Failed to initialize beacond node at ${config_dir}/tmp/beacond"
        return 1
      fi
      cp ${config_dir}/tmp/beacond/config/genesis.json ${config_dir}/tmp/genesis.json
      if [[ $? -ne 0 ]]; then
        log_error "Failed to copy genesis file to ${config_dir}/tmp/genesis.json"
        return 1
      fi
      log_success "Copied genesis file to ${config_dir}/tmp/genesis.json"
    fi
    log_success "Genesis file created at ${config_dir}/tmp/genesis.json"

    rm -rf "${config_dir}/tmp/beacond"
    log_success "Removed beacond directory at ${config_dir}/tmp/beacond"

    log_success "Genesis file created at ${config_dir}/tmp/genesis.json"
}

# Helper function to generate the beacon chain genesis file
generate_beacond_genesis() {
  [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_beacond_genesis" >&2
  local config_dir="$1"
  local chain_spec="$2"
  local chain_id=""
  local beranode_config_file=""

  # Parse flags
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      --config-dir)
        config_dir="$2"
        beranode_config_file="${config_dir}/beranodes.config.json"
        shift 2
        ;;
      --chain-spec)
        chain_spec="$2"
        if [[ "$chain_spec" == "${CHAIN_NAME_DEVNET}" ]]; then
          chain_id="${CHAIN_ID_DEVNET}"
        elif [[ "$chain_spec" == "${CHAIN_NAME_TESTNET}" ]]; then
          chain_id="${CHAIN_ID_TESTNET}"
        elif [[ "$chain_spec" == "${CHAIN_NAME_MAINNET}" ]]; then
          chain_id="${CHAIN_ID_MAINNET}"
        else
          echo "Unknown chain spec: ${chain_spec}"
          shift 2
          return 1
        fi
        shift 2
        ;;
      --chain-id)
        chain_id="$2"
        shift 2
        ;;
      *)
        echo "Unknown flag: $1"
        shift
        ;;
    esac
  done

  # Check if existing genesis.json file exists in ${config_dir}/tmp/genesis.json
  local genesis_file="${config_dir}/tmp/genesis.json"
  if [ -f "${genesis_file}" ]; then
    log_info "Genesis file already exists at ${genesis_file}"
  fi

  # Check if bin/beacond exists in ${config_dir}/bin and is executable
  local beacond_binary="${config_dir}/bin/beacond"
  if [[ ! -x "${beacond_binary}" ]]; then
    log_error "beacond binary not found or not executable at: ${beacond_binary}"
    return 1
  fi

  # Check if beranodes.config.json file exists in ${config_dir}/tmp/beranodes.config.json
  if [[ ! -f "${beranode_config_file}" ]]; then
    log_error "Beranode configuration file not found at ${beranode_config_file}"
    return 1
  fi

  # Retrieve all the .nodes from the beranodes.config.json file
  nodes_json=$(jq -c '.nodes' "${beranode_config_file}")
  if [[ $? -ne 0 ]] || [[ -z "$nodes_json" ]]; then
    log_error "Failed to read or parse .nodes from ${beranode_config_file}"
    return 1
  fi
  nodes_count=$(echo "$nodes_json" | jq 'length')
  echo "Number of nodes: $nodes_count";
  echo "--------------------------------";
  if [[ "$nodes_count" -eq 0 ]]; then
    log_error "No nodes found in ${beranode_config_file}, cannot generate beacond genesis file."
    return 1
  fi

  # Iterate through all the nodes to find role == validator
  for i in $(seq 1 ${nodes_count}); do
    role=$(echo "$node_json" | jq -r '.role')
    if [[ "$role" == "validator" ]]; then
      node_json=$(echo "$nodes_json" | jq ".[$i-1]")
      moniker=$(echo "$node_json" | jq -r '.moniker')
      role=$(echo "$node_json" | jq -r '.role')
      jwt=$(echo "$node_json" | jq -r '.jwt // empty')
      echo "Validator found: $i - $moniker";
    fi
  done

  if [[ -z "$node_json" ]]; then
    log_error "No validator found in ${beranode_config_file}, cannot generate beacond genesis file."
    return 1
  fi
    
  # node key
  node_key_type=$(echo "$node_json" | jq -r '.node_key.type // empty')
  node_key_value=$(echo "$node_json" | jq -r '.node_key.value // empty')

  # priv validator key
  priv_validator_key_address=$(echo "$node_json" | jq -r '.priv_validator_key.address // empty')
  priv_validator_key_pubkey_type=$(echo "$node_json" | jq -r '.priv_validator_key.pub_key.type // empty')
  priv_validator_key_pubkey_value=$(echo "$node_json" | jq -r '.priv_validator_key.pub_key.value // empty')
  priv_validator_key_privkey_type=$(echo "$node_json" | jq -r '.priv_validator_key.priv_key.type // empty')
  priv_validator_key_privkey_value=$(echo "$node_json" | jq -r '.priv_validator_key.priv_key.value // empty')

  # comet address
  comet_address=$(echo "$node_json" | jq -r '.comet_address // empty')
  comet_pubkey=$(echo "$node_json" | jq -r '.comet_pubkey // empty')
  eth_beacon_pubkey=$(echo "$node_json" | jq -r '.eth_beacon_pubkey // empty')

  # deposit amount
  deposit_amount=$(echo "$node_json" | jq -r '.deposit_amount // empty')

  # make tmp/beacond directory
  mkdir -p "${config_dir}/tmp/beacond"
  if [[ $? -ne 0 ]]; then
    log_error "Failed to create tmp/beacond directory at ${config_dir}/tmp/beacond"
    return 1
  fi

  # beacond init
  ${beacond_binary} init ${moniker} --chain-id ${chain_id} --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond >/dev/null 2>&1;
  if [[ $? -ne 0 ]]; then
    log_error "Failed to initialize beacond node at ${config_dir}/tmp/beacond"
    return 1
  fi
  log_success "Initialized beacond node ${i} - ${moniker} at ${config_dir}/tmp/beacond"

  # replace existing node key in the required format
  node_key_file="${config_dir}/tmp/beacond/config/node_key.json"
  cat > "${node_key_file}" <<EOF
{
"priv_key": {
  "type": "${node_key_type}",
  "value": "${node_key_value}"
}
}
EOF
  if [[ $? -ne 0 ]]; then
    log_error "Failed to write new node key format to ${node_key_file}"
    return 1
  fi
  log_success "Replaced existing node key at ${node_key_file} in new format"

  # replace priv_validator_key.json in the required format
  priv_validator_key_file="${config_dir}/tmp/beacond/config/priv_validator_key.json"
  cat > "${priv_validator_key_file}" <<EOF
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
  if [[ $? -ne 0 ]]; then
    log_error "Failed to write new priv_validator_key format to ${priv_validator_key_file}"
    return 1
  fi
  log_success "Replaced existing priv_validator_key at ${priv_validator_key_file} in new format"

  # add jwt
  jwt_file="${config_dir}/tmp/beacond/config/jwt.hex"
  cat > "${jwt_file}" <<EOF
${jwt}
EOF
  if [[ $? -ne 0 ]]; then
    log_error "Failed to write new jwt format to ${jwt_file}"
    return 1
  fi
  log_success "Added jwt at ${jwt_file}"

  # Modify app.toml for jwt-secret-path = ${jwt_file}
  app_toml_file="${config_dir}/tmp/beacond/config/app.toml"
  sed "${SED_OPT[@]}" "s|^jwt-secret-path = \".*\"|jwt-secret-path = \"${jwt_file}\"|" "${app_toml_file}"
  if [[ $? -ne 0 ]]; then
    log_error "Failed to modify app.toml for jwt-secret-path at ${app_toml_file}"
    return 1
  fi
  log_success "Modified app.toml for jwt-secret-path at ${app_toml_file}"

  # add kzg-trusted-setup.json config to app.toml
  kzg_file="${config_dir}/tmp/kzg-trusted-setup.json"
  sed "${SED_OPT[@]}" "s|^trusted-setup-path = \".*\"|trusted-setup-path = \"${kzg_file}\"|" "${app_toml_file}"
  if [[ $? -ne 0 ]]; then
    log_error "Failed to add kzg-trusted-setup.json config to app.toml at ${app_toml_file}"
    return 1
  fi
  log_success "Added kzg-trusted-setup.json config to app.toml at ${app_toml_file}"

  # add premined deposits
  mkdir -p "${config_dir}/tmp/beacond/config/premined-deposits";
  # Check if beranodes.config.json has a key called "genesis_deposits" which is an array
  beranode_config_file="${config_dir}/beranodes.config.json"
  has_genesis_deposits=$(jq 'has("genesis_deposits") and (.genesis_deposits|type == "array")' "${beranode_config_file}" 2>/dev/null)
  if [[ "${has_genesis_deposits}" == "true" ]]; then
    log_info "\"genesis_deposits\" key exists and is an array in ${beranode_config_file}"
  else
    log_warn "\"genesis_deposits\" key not present or not an array in ${beranode_config_file} creating..."

    # Iterate through the "nodes" array in beranodes.config.json and process each node
    nodes_length=$(jq '.nodes | length' "${beranode_config_file}")
    for (( node_idx=0; node_idx<nodes_length; node_idx++ )); do
      # if .node role == validator then add premined deposit
      node_role=$(jq -r ".nodes[${node_idx}].role" "${beranode_config_file}")
      if [[ "$node_role" == "validator" ]]; then
        node=$(jq -c ".nodes[${node_idx}]" "${beranode_config_file}")
        node_moniker=$(jq -r ".nodes[${node_idx}].moniker" "${beranode_config_file}")

        # premined deposit
        preminded_deposit_pubkey=$(echo "$node" | jq -r '.premined_deposit.pubkey // empty')
        preminded_deposit_credentials=$(echo "$node" | jq -r '.premined_deposit.credentials // empty')
        preminded_deposit_amount=$(echo "$node" | jq -r '.premined_deposit.amount // empty')
        preminded_deposit_signature=$(echo "$node" | jq -r '.premined_deposit.signature // empty')
        preminded_deposit_index=$(echo "$node" | jq -r '.premined_deposit.index // empty')
        
        # create a deposit file in "beranodes/tmp/beacond/config/premined-deposits"
        deposit_file="${config_dir}/tmp/beacond/config/premined-deposits/premined-deposit-${preminded_deposit_pubkey}.json"
        cat > "${deposit_file}" <<EOF
{
"pubkey": "${preminded_deposit_pubkey}",
"credentials": "${preminded_deposit_credentials}",
"amount": "${preminded_deposit_amount}",
"signature": "${preminded_deposit_signature}",
"index": ${preminded_deposit_index}
}
EOF
      fi
    done

    ${beacond_binary} genesis collect-premined-deposits --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond;
    if [[ $? -ne 0 ]]; then
      log_error "Failed to collect premined deposits at ${config_dir}/tmp/beacond"
      return 1
    fi
    log_success "Collected premined deposits at ${config_dir}/tmp/beacond"

    # validate if genesis.json has an key called .app_state.beacon.deposits which is an array and it matches the number of premined deposits
    genesis_file="${config_dir}/tmp/beacond/config/genesis.json"
    deposits_count=$(jq '.app_state.beacon.deposits | length' "${genesis_file}")
    if [[ $? -ne 0 ]] || [[ -z "$deposits_count" ]]; then
      log_error "Failed to read or parse .app_state.beacon.deposits from ${genesis_file}"
      return 1
    fi
    # get .validators value beranodes.config.json
    validators_count=$(jq '.validators | length' "${beranode_config_file}")
    if [[ $? -ne 0 ]] || [[ -z "$validators_count" ]]; then
      log_error "Failed to read or parse .validators from ${beranode_config_file}"
      return 1
    fi
    if [[ "$deposits_count" -ne "$validators_count" ]]; then
      log_error "Number of premined deposits does not match the number of nodes in ${genesis_file}"
      return 1
    fi
    log_success "Number of premined deposits matches the number of nodes in ${genesis_file}"

    # copy .app_state.beacon.deposits from ${config_dir}/tmp/beacond/config/genesis.json to beranodes.config.json
    deposits_json=$(jq -c '.app_state.beacon.deposits' "${genesis_file}")
    if [[ $? -ne 0 ]] || [[ -z "$deposits_json" ]]; then
      log_error "Failed to read or parse .app_state.beacon.deposits from ${genesis_file}"
      return 1
    fi
    jq --argjson deposits "$deposits_json" '
      .genesis_deposits = $deposits
    ' "${beranode_config_file}" > "${beranode_config_file}.tmp"
    mv "${beranode_config_file}.tmp" "${beranode_config_file}"
    log_success "Copied .app_state.beacon.deposits from ${config_dir}/tmp/beacond/config/genesis.json to beranodes.config.json"

    # generate validator root
    validator_root=$(${beacond_binary} genesis validator-root ${config_dir}/tmp/beacond/config/genesis.json --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond);
    if [[ $? -ne 0 ]] || [[ -z "$validator_root" ]]; then
      log_error "Failed to generate validator root at ${config_dir}/tmp/beacond/config/genesis.json"
      return 1
    fi
    log_success "Generated validator root at ${config_dir}/tmp/beacond/config/genesis.json"
    echo "Validator root: $validator_root"

    # validator_root to beranodes.config.json
    jq --arg validator_root "$validator_root" '
      .validator_root = $validator_root
    ' "${beranode_config_file}" > "${beranode_config_file}.tmp"
    mv "${beranode_config_file}.tmp" "${beranode_config_file}"
    log_success "Replaced validator root in beranodes.config.json"

    # Modifies eth-genesis.json file to set deposit storage
    # set deposit storage - makes a copy of the eth-genesis.json file to ${config_dir}/tmp/beacond/eth-genesis.json and modifies the 0x4242... storage slots
    ${beacond_binary} genesis set-deposit-storage ${config_dir}/tmp/eth-genesis.json --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond;
    if [[ $? -ne 0 ]] || [[ ! -f "${config_dir}/tmp/beacond/eth-genesis.json" ]]; then
      log_error "Failed to set deposit storage at ${config_dir}/tmp/eth-genesis.json"
      return 1
    fi
    # cp the json object .alloc.0x4242424242424242424242424242424242424242.storage and replace it with the json object from ${config_dir}/tmp/beacond/eth-genesis.json 
    storage_json=$(jq -c '.alloc."0x4242424242424242424242424242424242424242".storage' "${config_dir}/tmp/beacond/eth-genesis.json")
    if [[ $? -ne 0 ]] || [[ -z "$storage_json" ]]; then
      log_error "Failed to read or parse .alloc.\"0x4242424242424242424242424242424242424242\".storage from ${config_dir}/tmp/beacond/eth-genesis.json"
      return 1
    fi
    jq --argjson storage "$storage_json" '
      .alloc."0x4242424242424242424242424242424242424242".storage = $storage
    ' "${config_dir}/tmp/eth-genesis.json" > "${config_dir}/tmp/eth-genesis.json.tmp"
    mv "${config_dir}/tmp/eth-genesis.json.tmp" "${config_dir}/tmp/eth-genesis.json"
    log_success "Replaced .alloc.\"0x4242424242424242424242424242424242424242\".storage in ${config_dir}/tmp/eth-genesis.json"

    # Modifies genesis.json file to set execution payload
    # execution payload
    ${beacond_binary} genesis execution-payload ${config_dir}/tmp/eth-genesis.json --beacon-kit.chain-spec ${chain_spec} --home ${config_dir}/tmp/beacond;
    if [[ $? -ne 0 ]]; then
      log_error "Failed to set execution payload at ${config_dir}/tmp/eth-genesis.json"
      return 1
    fi
    log_success "Set execution payload at ${config_dir}/tmp/eth-genesis.json"

    # Copy genesis.json to beranodes/tmp/genesis.json
    cp ${config_dir}/tmp/beacond/config/genesis.json ${config_dir}/tmp/genesis.json
    if [[ $? -ne 0 ]]; then
      log_error "Failed to copy genesis.json to tmp/genesis.json"
      return 1
    fi
    log_success "Copied genesis.json to tmp/genesis.json"

    # Modify beranodes/tmp/genesis.json to add key values of genesis_file and genesis_eth_file
    jq --arg genesis_file "${config_dir}/tmp/beacond/config/genesis.json" \
        --arg genesis_eth_file "${config_dir}/tmp/eth-genesis.json" '
      .genesis_file = $genesis_file
      | .genesis_eth_file = $genesis_eth_file
    ' "${config_dir}/beranodes.config.json" > "${config_dir}/beranodes.config.json.tmp"
    mv "${config_dir}/beranodes.config.json.tmp" "${config_dir}/beranodes.config.json"
    log_success "Modified beranodes.config.json to add key values of genesis_file and genesis_eth_file"
  fi

  # Ensure the beacond directory is removed, regardless of its existence
  rm -rf "${config_dir}/tmp/beacond"
  if [[ -d "${config_dir}/tmp/beacond" ]]; then
    log_error "Failed to remove beacond directory at ${config_dir}/tmp/beacond"
    return 1
  else
    log_success "Ensured removal of beacond directory at ${config_dir}/tmp/beacond"
  fi
}

# Helper function create a validator node
create_validator_node() {
  [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: create_validator_node" >&2
  local beranodes_dir="$1"
    local local_dir="$2"
    local moniker="$3"
    local network="$4"
    local wallet_address="$5"
    local wallet_balance="$6"
    local bin_beacond="$7"
    local bin_bera_reth="$8"
    local kzg_file="$9"
    local ethrpc_port="$10"
    local ethp2p_port="$11"
    local ethproxy_port="$12"
    local el_ethrpc_port="$14"
    local el_authrpc_port="$15"
    local el_eth_port="$16"
    local el_prometheus_port="$17"
    local cl_prometheus_port="$18"
    local sed_opt=(-i)

    # Ensure the tmp directory exists
    mkdir -p "${local_dir}/beacond"
    mkdir -p "${local_dir}/beacond/config"
    mkdir -p "${local_dir}/bera-reth"

    # Copy the kzg-trusted-setup.json file to the beacond config directory
    cp ${kzg_file} ${local_dir}/beacond/config/kzg-trusted-setup.json
    if [[ $? -ne 0 ]]; then
        log_error "Failed to copy kzg-trusted-setup.json to ${local_dir}/beacond/config/kzg-trusted-setup.json"
        return 1
    fi
    log_success "Copied kzg-trusted-setup.json to ${local_dir}/beacond/config/kzg-trusted-setup.json"

    # # Generate eth-genesis.json file
    # if [[ -f "${beranodes_dir}/tmp/eth-genesis.json" ]]; then
    #     log_success "Found eth-genesis.json at ${beranodes_dir}/tmp/eth-genesis.json"
    # else
    #     log_warn "eth-genesis.json not found at ${beranodes_dir}/tmp/eth-genesis.json creating it..."

    #     # Generates a eth-genesis.json file that is shared with all nodes
    #     generate_eth_genesis_file \
    #       --genesis-file-path "${beranodes_dir}/tmp/eth-genesis.json" \
    #       --local-dir "${local_dir}" \
    #       --chain-id "${CHAIN_ID_DEVNET}" \
    #       --prague1-time ${ETH_GENESIS_PRAGUE1_TIME} \
    #       --prague1-base-fee-change-denominator ${ETH_GENESIS_PRAGUE1_BASE_FEE_CHANGE_DENOMINATOR} \
    #       --prague1-min-base-fee ${ETH_GENESIS_PRAGUE1_MIN_BASE_FEE} \
    #       --prague1-pol-distributor ${ETH_GENESIS_PRAGUE1_POL_DISTRIBUTOR} \
    #       --prague2-time ${ETH_GENESIS_PRAGUE2_TIME} \
    #       --prague2-min-base-fee ${ETH_GENESIS_PRAGUE2_MIN_BASE_FEE} \
    #       --prague3-time ${ETH_GENESIS_PRAGUE3_TIME} \
    #       --prague3-bex-vault ${ETH_GENESIS_PRAGUE3_BEX_VAULT} \
    #       --prague3-rescue-address ${ETH_GENESIS_PRAGUE3_RESCUE_ADDRESS} \
    #       --prague3-blocked-addresses ${ETH_GENESIS_PRAGUE3_BLOCKED_ADDRESSES} \
    #       --prague4-time ${ETH_GENESIS_PRAGUE4_TIME} \
    #       --eth-genesis-custom0-contract-address ${wallet_address} \
    #       --eth-genesis-custom0-contract-balance ${wallet_balance}
    # fi

    # # Initialize the beacond node
    # ${bin_beacond} init --chain-id ${CHAIN_ID_DEVNET} --beacon-kit.chain-spec $CHAIN_NAME_DEVNET --moniker ${moniker} --home ${local_dir}/beacond
    # if [[ $? -ne 0 ]]; then
    #     log_error "Failed to initialize beacond node"
    #     return 1
    # fi
    # log_success "Initialized beacond node"

    # # Check if the validator key file exists
    # CHECK_FILE_VALIDATOR_KEY=${local_dir}/beacond/config/priv_validator_key.json
    # if [ ! -f "$CHECK_FILE_VALIDATOR_KEY" ]; then
    #     log_error "Error: Private validator key was not created at $CHECK_FILE_VALIDATOR_KEY"
    #     return 1
    # fi
    # log_success "Private validator key generated in $CHECK_FILE_VALIDATOR_KEY"

    # ${bin_beacond} jwt generate -o ${local_dir}/beacond/config/jwt.hex
    # CHECK_FILE_JWT_SECRET=${local_dir}/beacond/config/jwt.hex
    # if [ ! -f "$CHECK_FILE_JWT_SECRET" ]; then
    #     log_error "Error: JWT file was not created at $CHECK_FILE_JWT_SECRET"
    #     return 1
    # fi
    # log_success "JWT secret generated in $CHECK_FILE_JWT_SECRET"

    # ${bin_beacond} genesis add-premined-deposit $GENESIS_DEPOSIT_AMOUNT $wallet_address --beacon-kit.chain-spec $network --home ${local_dir}/beacond
    # ${bin_beacond} genesis collect-premined-deposits --beacon-kit.chain-spec $network --home ${local_dir}/beacond

    # if [[ $(uname) == "Darwin" ]]; then
    #     sed_opt=(-i '');
    # fi

    # sed "${SED_OPT[@]}" 's|chain-spec = ".*"|chain-spec = "'$network'"|' "${local_dir}/beacond/config/app.toml"
    # sed "${SED_OPT[@]}" 's|^rpc-dial-url = ".*"|rpc-dial-url = "http://localhost:'$EL_AUTHRPC_PORT'"|' "${local_dir}/beacond/config/app.toml"
    # sed "${SED_OPT[@]}" 's|^jwt-secret-path = ".*"|jwt-secret-path = "'$CHECK_FILE_JWT_SECRET'"|' "${local_dir}/beacond/config/app.toml"
    # sed "${SED_OPT[@]}" 's|^trusted-setup-path = ".*"|trusted-setup-path = "'$local_dir/beacond/config/kzg-trusted-setup.json'"|' "${local_dir}/beacond/config/app.toml"
    # sed "${SED_OPT[@]}" 's|^suggested-fee-recipient = ".*"|suggested-fee-recipient = "'$wallet_address'"|' "${local_dir}/beacond/config/app.toml"
    # sed "${SED_OPT[@]}" 's|^moniker = ".*"|moniker = "'$moniker'"|' "${local_dir}/beacond/config/config.toml"
    # sed "${SED_OPT[@]}" 's|^laddr = ".*26657"|laddr = "tcp://127.0.0.1:'$ethrpc_port'"|' "${local_dir}/beacond/config/config.toml"
    # sed "${SED_OPT[@]}" 's|^laddr = ".*26656"|laddr = "tcp://0.0.0.0:'$ethp2p_port'"|' "${local_dir}/beacond/config/config.toml"
    # sed "${SED_OPT[@]}" 's|^external_address = ".*"|external_address = "'$MY_IP:$ethp2p_port'"|' "$BEACOND_CONFIG/config.toml"
    # sed "${SED_OPT[@]}" 's|^proxy_app = ".*26658"|proxy_app = "tcp://127.0.0.1:'$ethproxy_port'"|' "${local_dir}/beacond/config/config.toml"
    # sed "${SED_OPT[@]}" 's|^prometheus_listen_addr = ".*"|prometheus_listen_addr = "':$cl_prometheus_port'"|' "${local_dir}/beacond/config/config.toml"
    # sed "${SED_OPT[@]}" 's|^prometheus_listen_addr = ".*"|prometheus_listen_addr = "':$el_prometheus_port'"|' "${local_dir}/beacond/config/config.toml"
    # log_success "Config files in ${local_dir}/beacond/config updated"
}
