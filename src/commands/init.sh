#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# BERANODE INIT COMMAND
# =============================================================================
# File: src/commands/init.sh
# Version: Compatible with Beranode CLI v0.7.1
# Description: Initializes Berachain node configurations including validator,
#              full nodes, and pruned nodes with comprehensive configuration
#              management for client.toml, app.toml, and config.toml files.
#
# =============================================================================
# NUMBERED LEGEND - EXECUTION FLOW
# =============================================================================
# This script follows a structured initialization process:
#
# [1] HELP & VALIDATION
#     └─ Display help message if requested
#     └─ Check dependencies (cast version)
#
# [2] VARIABLE INITIALIZATION
#     └─ Initialize default configuration variables
#     └─ Set up client.toml defaults
#     └─ Set up app.toml defaults
#     └─ Set up config.toml defaults
#
# [3] ARGUMENT PARSING
#     └─ Parse command-line arguments
#     └─ Override defaults with user-provided values
#     └─ Validate network selection (devnet/bepolia/mainnet)
#
# [4] CONFIGURATION VALIDATION
#     └─ Validate node counts (validators, full nodes, pruned nodes)
#     └─ Apply network-specific defaults
#     └─ Display configuration summary
#
# [5] DIRECTORY STRUCTURE SETUP
#     └─ Create beranodes directory structure
#     └─ Ensure bin/, tmp/, log/, nodes/ directories exist
#
# [6] BINARY VERIFICATION
#     └─ Check for beacond binary
#     └─ Check for bera-reth binary
#     └─ Verify binary executability and versions
#
# [7] WALLET GENERATION
#     └─ Generate EVM private key
#     └─ Derive wallet address from private key
#
# [8] CONFIGURATION FILE GENERATION
#     └─ Create beranodes.config.json with all settings
#     └─ Prompt for overwrite if config already exists
#     └─ Generate node configurations (validators, full nodes, pruned nodes)
#
# [9] GENESIS FILE SETUP
#     └─ Download kzg-trusted-setup.json if needed
#     └─ Generate eth-genesis.json with Prague upgrade configs
#     └─ Apply wallet balance to genesis
#
# [10] BEACOND INITIALIZATION
#      └─ Generate beacond keys (validator keys, node keys)
#      └─ Generate beacond genesis.json
#
# =============================================================================
# RELATIONSHIP TO CURRENT VERSION (v0.7.1)
# =============================================================================
# This init.sh file is part of the Beranode CLI v0.7.1 and works in
# conjunction with:
#
# - src/lib/constants.sh     : Provides network constants, default ports, and
#                               genesis contract configurations
# - src/lib/utils.sh         : Utility functions for key generation, file ops
# - src/lib/logging.sh       : Logging functions for user feedback
# - src/core/dispatcher.sh   : Main command dispatcher
# - src/commands/start.sh    : Node startup command (uses config from init)
#
# Version Compatibility:
# - Beacond: Uses beacond binary from beranodes/bin/
# - Bera-Reth: Uses bera-reth binary from beranodes/bin/
# - Network Support: devnet (80087), bepolia (80069), mainnet (80094)
# - Prague Upgrades: Supports Prague1-4 upgrade configurations
# - Configuration Format: JSON-based beranodes.config.json
#
# =============================================================================
# SECTION 1: HELP FUNCTION
# =============================================================================
# Displays comprehensive help information for the init command including all
# available options for general settings, client.toml, app.toml, and config.toml
# =============================================================================

show_init_help() {
	cat <<EOF
beranode init - Initialize a new Berachain node configuration

USAGE:
    beranode init [OPTIONS]

GENERAL OPTIONS:
    --beranodes-dir <path>           Directory for beranodes data (default: ./beranodes)
    --moniker <name>                Custom name for your node
    --network <network>             Network to connect to: devnet, bepolia, mainnet (default: devnet)
    --validators <count>            Number of validator nodes (default: 1)
    --full-nodes <count>            Number of full nodes (default: 0)
    --pruned-nodes <count>          Number of pruned nodes (default: 0)
    --docker                        Enable Docker mode
    --wallet-private-key <key>      Private key for the wallet
    --wallet-address <address>      Wallet address
    --wallet-balance <amount>       Initial wallet balance
    --help|-h                       Display this help message

CLIENT.TOML OPTIONS:
    --clienttoml-chain-id <id>                      Chain ID
    --clienttoml-keyring-backend <backend>          Keyring backend
    --clienttoml-keyring-default-keyname <name>     Default keyring keyname
    --clienttoml-output <format>                    Output format
    --clienttoml-node <url>                         Node URL
    --clienttoml-broadcast-mode <mode>              Broadcast mode
    --clienttoml-grpc-address <address>             gRPC address
    --clienttoml-grpc-insecure <bool>               gRPC insecure mode

APP.TOML OPTIONS:
  Base Configuration:
    --apptoml-pruning <strategy>                    Pruning strategy
    --apptoml-pruning-keep-recent <num>             Number of recent states to keep
    --apptoml-pruning-interval <num>                Pruning interval
    --apptoml-halt-height <height>                  Block height to halt
    --apptoml-halt-time <time>                      Time to halt
    --apptoml-min-retain-blocks <num>               Minimum blocks to retain
    --apptoml-inter-block-cache <bool>              Enable inter-block cache
    --apptoml-iavl-cache-size <size>                IAVL cache size
    --apptoml-iavl-disable-fastnode <bool>          Disable IAVL fastnode
    --apptoml-app-db-backend <backend>              Application database backend

  Telemetry Configuration:
    --apptoml-telemetry-service-name <name>         Service name for telemetry
    --apptoml-telemetry-enabled <bool>              Enable telemetry
    --apptoml-telemetry-enable-hostname <bool>      Include hostname in metrics
    --apptoml-telemetry-enable-hostname-label <bool> Enable hostname label
    --apptoml-telemetry-enable-service-label <bool> Enable service label
    --apptoml-telemetry-prometheus-retention-time <time> Prometheus retention time
    --apptoml-telemetry-metrics-sink <sink>         Metrics sink
    --apptoml-telemetry-statsd-addr <address>       StatsD address
    --apptoml-telemetry-datadog-hostname <host>     Datadog hostname

  BeaconKit Configuration:
    --apptoml-beacon-kit-chain-spec <spec>          Chain specification
    --apptoml-beacon-kit-chain-spec-file <file>     Chain specification file
    --apptoml-beacon-kit-shutdown-timeout <time>    Shutdown timeout

  BeaconKit Engine Configuration:
    --apptoml-beacon-kit-engine-rpc-dial-url <url>              Engine RPC dial URL
    --apptoml-beacon-kit-engine-rpc-timeout <time>              Engine RPC timeout
    --apptoml-beacon-kit-engine-rpc-retry-interval <time>       Engine RPC retry interval
    --apptoml-beacon-kit-engine-rpc-max-retry-interval <time>   Engine RPC max retry interval
    --apptoml-beacon-kit-engine-rpc-startup-check-interval <time> Engine startup check interval
    --apptoml-beacon-kit-engine-rpc-jwt-refresh-interval <time> JWT refresh interval
    --apptoml-beacon-kit-engine-jwt-secret-path <path>          JWT secret file path

  BeaconKit Logger Configuration:
    --apptoml-beacon-kit-logger-time-format <format> Logger time format
    --apptoml-beacon-kit-logger-log-level <level>    Logger level
    --apptoml-beacon-kit-logger-style <style>        Logger style

  BeaconKit KZG Configuration:
    --apptoml-beacon-kit-kzg-trusted-setup-path <path> KZG trusted setup path
    --apptoml-beacon-kit-kzg-implementation <impl>     KZG implementation

  BeaconKit Payload Builder Configuration:
    --apptoml-beacon-kit-payload-builder-enabled <bool> Enable payload builder
    --apptoml-beacon-kit-payload-builder-suggested-fee-recipient <address> Fee recipient
    --apptoml-beacon-kit-payload-builder-payload-timeout <time> Payload timeout

  BeaconKit Validator Configuration:
    --apptoml-beacon-kit-validator-graffiti <text>          Validator graffiti
    --apptoml-beacon-kit-validator-availability-window <num> Availability window

  BeaconKit Node API Configuration:
    --apptoml-beacon-kit-node-api-enabled <bool>    Enable node API
    --apptoml-beacon-kit-node-api-address <address> Node API address
    --apptoml-beacon-kit-node-api-logging <bool>    Enable node API logging

CONFIG.TOML OPTIONS:
  Base Configuration:
    --configtoml-version <version>                  Config version
    --configtoml-proxy-app <url>                    Proxy app URL
    --configtoml-db-backend <backend>               Database backend
    --configtoml-db-dir <path>                      Database directory
    --configtoml-log-level <level>                  Log level
    --configtoml-log-format <format>                Log format
    --configtoml-genesis-file <path>                Genesis file path
    --configtoml-priv-validator-key-file <path>     Private validator key file
    --configtoml-priv-validator-state-file <path>   Private validator state file
    --configtoml-priv-validator-laddr <address>     Private validator listen address
    --configtoml-node-key-file <path>               Node key file
    --configtoml-abci <type>                        ABCI type
    --configtoml-filter-peers <bool>                Filter peers

  RPC Server Configuration:
    --configtoml-rpc-laddr <address>                                 RPC listen address
    --configtoml-rpc-unsafe <bool>                                   Enable unsafe RPC
    --configtoml-rpc-cors-allowed-origins <origins>                  CORS allowed origins
    --configtoml-rpc-cors-allowed-methods <methods>                  CORS allowed methods
    --configtoml-rpc-cors-allowed-headers <headers>                  CORS allowed headers
    --configtoml-rpc-max-open-connections <num>                      Max open connections
    --configtoml-rpc-max-subscription-clients <num>                  Max subscription clients
    --configtoml-rpc-max-subscriptions-per-client <num>              Max subscriptions per client
    --configtoml-rpc-experimental-subscription-buffer-size <size>    Subscription buffer size
    --configtoml-rpc-experimental-websocket-write-buffer-size <size> WebSocket write buffer size
    --configtoml-rpc-experimental-close-on-slow-client <bool>        Close on slow client
    --configtoml-rpc-timeout-broadcast-tx-commit <time>              Broadcast TX commit timeout
    --configtoml-rpc-max-request-batch-size <size>                   Max request batch size
    --configtoml-rpc-max-body-bytes <bytes>                          Max body bytes
    --configtoml-rpc-max-header-bytes <bytes>                        Max header bytes
    --configtoml-rpc-tls-cert-file <path>                            TLS certificate file
    --configtoml-rpc-tls-key-file <path>                             TLS key file
    --configtoml-rpc-pprof-laddr <address>                           Pprof listen address

  gRPC Server Configuration:
    --configtoml-grpc-laddr <address>                           gRPC listen address
    --configtoml-grpc-version-service-enabled <bool>            Enable version service
    --configtoml-grpc-block-service-enabled <bool>              Enable block service
    --configtoml-grpc-block-results-service-enabled <bool>      Enable block results service
    --configtoml-grpc-privileged-laddr <address>                Privileged gRPC address
    --configtoml-grpc-privileged-pruning-service-enabled <bool> Enable privileged pruning service

  P2P Configuration:
    --configtoml-p2p-laddr <address>                                        P2P listen address
    --configtoml-p2p-external-address <address>                             External address
    --configtoml-p2p-seeds <peers>                                          Seed nodes
    --configtoml-p2p-persistent-peers <peers>                               Persistent peers
    --configtoml-p2p-addr-book-file <path>                                  Address book file
    --configtoml-p2p-addr-book-strict <bool>                                Strict address book
    --configtoml-p2p-max-num-inbound-peers <num>                            Max inbound peers
    --configtoml-p2p-max-num-outbound-peers <num>                           Max outbound peers
    --configtoml-p2p-unconditional-peer-ids <ids>                           Unconditional peer IDs
    --configtoml-p2p-persistent-peers-max-dial-period <time>                Max dial period
    --configtoml-p2p-flush-throttle-timeout <time>                          Flush throttle timeout
    --configtoml-p2p-max-packet-msg-payload-size <size>                     Max packet message payload size
    --configtoml-p2p-send-rate <rate>                                       Send rate
    --configtoml-p2p-recv-rate <rate>                                       Receive rate
    --configtoml-p2p-pex <bool>                                             Enable peer exchange
    --configtoml-p2p-seed-mode <bool>                                       Seed mode
    --configtoml-p2p-private-peer-ids <ids>                                 Private peer IDs
    --configtoml-p2p-allow-duplicate-ip <bool>                              Allow duplicate IP
    --configtoml-p2p-handshake-timeout <time>                               Handshake timeout
    --configtoml-p2p-dial-timeout <time>                                    Dial timeout

  Mempool Configuration:
    --configtoml-mempool-type <type>                                                        Mempool type
    --configtoml-mempool-recheck <bool>                                                     Enable recheck
    --configtoml-mempool-recheck-timeout <time>                                             Recheck timeout
    --configtoml-mempool-broadcast <bool>                                                   Enable broadcast
    --configtoml-mempool-wal-dir <path>                                                     WAL directory
    --configtoml-mempool-size <size>                                                        Mempool size
    --configtoml-mempool-max-tx-bytes <bytes>                                               Max transaction bytes
    --configtoml-mempool-max-txs-bytes <bytes>                                              Max transactions bytes
    --configtoml-mempool-cache-size <size>                                                  Cache size
    --configtoml-mempool-keep-invalid-txs-in-cache <bool>                                   Keep invalid transactions
    --configtoml-mempool-experimental-max-gossip-connections-to-persistent-peers <num>      Max gossip to persistent peers
    --configtoml-mempool-experimental-max-gossip-connections-to-non-persistent-peers <num>  Max gossip to non-persistent peers

  State Sync Configuration:
    --configtoml-statesync-enable <bool>                 Enable state sync
    --configtoml-statesync-rpc-servers <servers>         RPC servers
    --configtoml-statesync-trust-height <height>         Trust height
    --configtoml-statesync-trust-hash <hash>             Trust hash
    --configtoml-statesync-trust-period <time>           Trust period
    --configtoml-statesync-discovery-time <time>         Discovery time
    --configtoml-statesync-temp-dir <path>               Temp directory
    --configtoml-statesync-chunk-request-timeout <time>  Chunk request timeout
    --configtoml-statesync-chunk-fetchers <num>          Number of chunk fetchers

  Block Sync Configuration:
    --configtoml-blocksync-version <version>    Block sync version

  Consensus Configuration:
    --configtoml-consensus-wal-file <path>                            WAL file
    --configtoml-consensus-timeout-propose <time>                     Propose timeout
    --configtoml-consensus-timeout-propose-delta <time>               Propose delta timeout
    --configtoml-consensus-timeout-prevote <time>                     Prevote timeout
    --configtoml-consensus-timeout-prevote-delta <time>               Prevote delta timeout
    --configtoml-consensus-timeout-precommit <time>                   Precommit timeout
    --configtoml-consensus-timeout-precommit-delta <time>             Precommit delta timeout
    --configtoml-consensus-timeout-commit <time>                      Commit timeout
    --configtoml-consensus-skip-timeout-commit <bool>                 Skip commit timeout
    --configtoml-consensus-double-sign-check-height <height>          Double sign check height
    --configtoml-consensus-create-empty-blocks <bool>                 Create empty blocks
    --configtoml-consensus-create-empty-blocks-interval <time>        Empty blocks interval
    --configtoml-consensus-peer-gossip-sleep-duration <time>          Peer gossip sleep duration
    --configtoml-consensus-peer-gossip-intraloop-sleep-duration <time> Intraloop sleep duration
    --configtoml-consensus-peer-query-maj23-sleep-duration <time>     Query maj23 sleep duration

  Storage Configuration:
    --configtoml-storage-discard-abci-responses <bool>                              Discard ABCI responses
    --configtoml-storage-experimental-db-key-layout <layout>                         DB key layout
    --configtoml-storage-compact <bool>                                              Enable compaction
    --configtoml-storage-compaction-interval <time>                                  Compaction interval
    --configtoml-storage-pruning-interval <time>                                     Pruning interval
    --configtoml-storage-pruning-data-companion-enabled <bool>                       Enable data companion pruning
    --configtoml-storage-pruning-data-companion-initial-block-retain-height <height> Initial block retain height
    --configtoml-storage-pruning-data-companion-initial-block-results-retain-height <height> Initial block results retain height

  Transaction Indexer Configuration:
    --configtoml-tx-index-indexer <indexer>     Transaction indexer
    --configtoml-tx-index-psql-conn <conn>      PostgreSQL connection string

  Instrumentation Configuration:
    --configtoml-instrumentation-prometheus <bool>             Enable Prometheus metrics
    --configtoml-instrumentation-prometheus-listen-addr <addr> Prometheus listen address
    --configtoml-instrumentation-max-open-connections <num>    Max open connections
    --configtoml-instrumentation-namespace <namespace>         Metrics namespace

EXAMPLES:
    beranode init --network devnet --validators 1
    beranode init --moniker mynode --validators 2 --full-nodes 1
    beranode init --network bepolia --validators 1 --wallet-balance 5000000000000000000000000000

For more information, visit: https://github.com/berachain/beranode-cli2
EOF
}

# =============================================================================
# SECTION 2: MAIN INIT COMMAND
# =============================================================================
# The cmd_init function is the entry point for the init command. It orchestrates
# the entire initialization process following the numbered legend above.
# =============================================================================

cmd_init() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_init" >&2

	# =========================================================================
	# [1] HELP & VALIDATION
	# =========================================================================
	# Check for help flag first before any other processing

	if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
		show_init_help
		return 0
	fi

	# Check dependencies - cast version must be supported
	print_header "Checking Dependencies"
	check_cast_version
	if [[ $? -ne 0 ]]; then
		log_error "Cast version is not supported. Please upgrade to version $SUPPORTED_CAST_VERSION or higher."
		return 1
	fi
	log_success "Cast version is supported."

  # Check curl version
  check_curl_version
  if [[ $? -ne 0 ]]; then
    log_error "Curl version is not supported. Please upgrade to version $SUPPORTED_CURL_VERSION or higher."
    return 1
  fi
  log_success "Curl version is supported."

	print_header "Initializing Berachain Node"

  # Check for .tar.gz installed locally
  check_tar_gz_version
  if [[ $? -ne 0 ]]; then
    log_error "Tar.gz version is not supported. Please upgrade to version $SUPPORTED_TAR_GZ_VERSION or higher."
    return 1
  fi
  log_success "Tar.gz version is supported."

	# =========================================================================
	# [2] VARIABLE INITIALIZATION
	# =========================================================================
	# Initialize all configuration variables with defaults from constants.sh

	# General settings
	local moniker="$(generate_random_name)"
	local network=$CHAIN_NAME_DEVNET
	local chain_id=$CHAIN_ID_DEVNET
	local force=false
	local skip_genesis=false
	local total_nodes=0
	local validators=1
	local full_nodes=0
	local pruned_nodes=0
	local docker_mode=false
  local docker_tag_beacond="latest"
  local docker_tag_berareth="latest"
	local mode="local"
	local wallet_private_key=""
	local wallet_address=""
	local wallet_balance=${DEFAULT_WALLET_BALANCE}
  local beacond_version="latest"
  local berareth_version="latest"

	# Client.toml configuration variables
	local clienttoml_chain_id="${CLIENTTOML_CHAIN_ID}"
	local clienttoml_keyring_backend="${CLIENTTOML_KEYRING_BACKEND}"
	local clienttoml_keyring_default_keyname="${CLIENTTOML_KEYRING_DEFAULT_KEYNAME}"
	local clienttoml_output="${CLIENTTOML_OUTPUT}"
	local clienttoml_node="${CLIENTTOML_NODE}"
	local clienttoml_broadcast_mode="${CLIENTTOML_BROADCAST_MODE}"
	local clienttoml_grpc_address="${CLIENTTOML_GRPC_ADDRESS}"
	local clienttoml_grpc_insecure="${CLIENTTOML_GRPC_INSECURE}"

	# App.toml configuration variables - Base Configuration
	local apptoml_pruning="${APPTOML_PRUNING}"
	local apptoml_pruning_keep_recent="${APPTOML_PRUNING_KEEP_RECENT}"
	local apptoml_pruning_interval="${APPTOML_PRUNING_INTERVAL}"
	local apptoml_halt_height="${APPTOML_HALT_HEIGHT}"
	local apptoml_halt_time="${APPTOML_HALT_TIME}"
	local apptoml_min_retain_blocks="${APPTOML_MIN_RETAIN_BLOCKS}"
	local apptoml_inter_block_cache="${APPTOML_INTER_BLOCK_CACHE}"
	local apptoml_iavl_cache_size="${APPTOML_IAVL_CACHE_SIZE}"
	local apptoml_iavl_disable_fastnode="${APPTOML_IAVL_DISABLE_FASTNODE}"
	local apptoml_app_db_backend="${APPTOML_APP_DB_BACKEND}"

	# App.toml - Telemetry Configuration
	local apptoml_telemetry_service_name="${APPTOML_TELEMETRY_SERVICE_NAME}"
	local apptoml_telemetry_enabled="${APPTOML_TELEMETRY_ENABLED}"
	local apptoml_telemetry_enable_hostname="${APPTOML_TELEMETRY_ENABLE_HOSTNAME}"
	local apptoml_telemetry_enable_hostname_label="${APPTOML_TELEMETRY_ENABLE_HOSTNAME_LABEL}"
	local apptoml_telemetry_enable_service_label="${APPTOML_TELEMETRY_ENABLE_SERVICE_LABEL}"
	local apptoml_telemetry_prometheus_retention_time="${APPTOML_TELEMETRY_PROMETHEUS_RETENTION_TIME}"
	local apptoml_telemetry_global_labels="${APPTOML_TELEMETRY_GLOBAL_LABELS}"
	local apptoml_telemetry_metrics_sink="${APPTOML_TELEMETRY_METRICS_SINK}"
	local apptoml_telemetry_statsd_addr="${APPTOML_TELEMETRY_STATSD_ADDR}"
	local apptoml_telemetry_datadog_hostname="${APPTOML_TELEMETRY_DATADOG_HOSTNAME}"

	# App.toml - BeaconKit Configuration
	local apptoml_beacon_kit_chain_spec="${APPTOML_BEACON_KIT_CHAIN_SPEC}"
	local apptoml_beacon_kit_chain_spec_file="${APPTOML_BEACON_KIT_CHAIN_SPEC_FILE}"
	local apptoml_beacon_kit_shutdown_timeout="${APPTOML_BEACON_KIT_SHUTDOWN_TIMEOUT}"

	# App.toml - BeaconKit Engine Configuration
	local apptoml_beacon_kit_engine_rpc_dial_url="${APPTOML_BEACON_KIT_ENGINE_RPC_DIAL_URL}"
	local apptoml_beacon_kit_engine_rpc_timeout="${APPTOML_BEACON_KIT_ENGINE_RPC_TIMEOUT}"
	local apptoml_beacon_kit_engine_rpc_retry_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_RETRY_INTERVAL}"
	local apptoml_beacon_kit_engine_rpc_max_retry_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_MAX_RETRY_INTERVAL}"
	local apptoml_beacon_kit_engine_rpc_startup_check_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_STARTUP_CHECK_INTERVAL}"
	local apptoml_beacon_kit_engine_rpc_jwt_refresh_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_JWT_REFRESH_INTERVAL}"
	local apptoml_beacon_kit_engine_jwt_secret_path="${APPTOML_BEACON_KIT_ENGINE_JWT_SECRET_PATH}"

	# App.toml - BeaconKit Logger Configuration
	local apptoml_beacon_kit_logger_time_format="${APPTOML_BEACON_KIT_LOGGER_TIME_FORMAT}"
	local apptoml_beacon_kit_logger_log_level="${APPTOML_BEACON_KIT_LOGGER_LOG_LEVEL}"
	local apptoml_beacon_kit_logger_style="${APPTOML_BEACON_KIT_LOGGER_STYLE}"

	# App.toml - BeaconKit KZG Configuration
	local apptoml_beacon_kit_kzg_trusted_setup_path="${APPTOML_BEACON_KIT_KZG_TRUSTED_SETUP_PATH}"
	local apptoml_beacon_kit_kzg_implementation="${APPTOML_BEACON_KIT_KZG_IMPLEMENTATION}"

	# App.toml - BeaconKit Payload Builder Configuration
	local apptoml_beacon_kit_payload_builder_enabled="${APPTOML_BEACON_KIT_PAYLOAD_BUILDER_ENABLED}"
	local apptoml_beacon_kit_payload_builder_suggested_fee_recipient="${APPTOML_BEACON_KIT_PAYLOAD_BUILDER_SUGGESTED_FEE_RECIPIENT}"
	local apptoml_beacon_kit_payload_builder_payload_timeout="${APPTOML_BEACON_KIT_PAYLOAD_BUILDER_PAYLOAD_TIMEOUT}"

	# App.toml - BeaconKit Validator Configuration
	local apptoml_beacon_kit_validator_graffiti="${APPTOML_BEACON_KIT_VALIDATOR_GRAFFITI}"
	local apptoml_beacon_kit_validator_availability_window="${APPTOML_BEACON_KIT_VALIDATOR_AVAILABILITY_WINDOW}"

	# App.toml - BeaconKit Node API Configuration
	local apptoml_beacon_kit_node_api_enabled="${APPTOML_BEACON_KIT_NODE_API_ENABLED}"
	local apptoml_beacon_kit_node_api_address="${APPTOML_BEACON_KIT_NODE_API_ADDRESS}"
	local apptoml_beacon_kit_node_api_logging="${APPTOML_BEACON_KIT_NODE_API_LOGGING}"

	# Config.toml configuration variables - Base Configuration
	local configtoml_version="${CONFIGTOML_VERSION}"
	local configtoml_proxy_app="${CONFIGTOML_PROXY_APP}"
	local configtoml_moniker="${CONFIGTOML_MONIKER}"
	local configtoml_db_backend="${CONFIGTOML_DB_BACKEND}"
	local configtoml_db_dir="${CONFIGTOML_DB_DIR}"
	local configtoml_log_level="${CONFIGTOML_LOG_LEVEL}"
	local configtoml_log_format="${CONFIGTOML_LOG_FORMAT}"
	local configtoml_genesis_file="${CONFIGTOML_GENESIS_FILE}"
	local configtoml_priv_validator_key_file="${CONFIGTOML_PRIV_VALIDATOR_KEY_FILE}"
	local configtoml_priv_validator_state_file="${CONFIGTOML_PRIV_VALIDATOR_STATE_FILE}"
	local configtoml_priv_validator_laddr="${CONFIGTOML_PRIV_VALIDATOR_LADDR}"
	local configtoml_node_key_file="${CONFIGTOML_NODE_KEY_FILE}"
	local configtoml_abci="${CONFIGTOML_ABCI}"
	local configtoml_filter_peers="${CONFIGTOML_FILTER_PEERS}"

	# Config.toml - RPC Server Configuration
	local configtoml_rpc_laddr="${CONFIGTOML_RPC_LADDR}"
	local configtoml_rpc_unsafe="${CONFIGTOML_RPC_UNSAFE}"
	local configtoml_rpc_cors_allowed_origins="$(
		IFS=,
		echo "${CONFIGTOML_RPC_CORS_ALLOWED_ORIGINS[*]+"${CONFIGTOML_RPC_CORS_ALLOWED_ORIGINS[*]}"}"
	)"
	local configtoml_rpc_cors_allowed_methods="$(
		IFS=,
		echo "${CONFIGTOML_RPC_CORS_ALLOWED_METHODS[*]+"${CONFIGTOML_RPC_CORS_ALLOWED_METHODS[*]}"}"
	)"
	local configtoml_rpc_cors_allowed_headers="$(
		IFS=,
		echo "${CONFIGTOML_RPC_CORS_ALLOWED_HEADERS[*]+"${CONFIGTOML_RPC_CORS_ALLOWED_HEADERS[*]}"}"
	)"
	local configtoml_rpc_max_open_connections="${CONFIGTOML_RPC_MAX_OPEN_CONNECTIONS}"
	local configtoml_rpc_max_subscription_clients="${CONFIGTOML_RPC_MAX_SUBSCRIPTION_CLIENTS}"
	local configtoml_rpc_max_subscriptions_per_client="${CONFIGTOML_RPC_MAX_SUBSCRIPTIONS_PER_CLIENT}"
	local configtoml_rpc_experimental_subscription_buffer_size="${CONFIGTOML_RPC_EXPERIMENTAL_SUBSCRIPTION_BUFFER_SIZE}"
	local configtoml_rpc_experimental_websocket_write_buffer_size="${CONFIGTOML_RPC_EXPERIMENTAL_WEBSOCKET_WRITE_BUFFER_SIZE}"
	local configtoml_rpc_experimental_close_on_slow_client="${CONFIGTOML_RPC_EXPERIMENTAL_CLOSE_ON_SLOW_CLIENT}"
	local configtoml_rpc_timeout_broadcast_tx_commit="${CONFIGTOML_RPC_TIMEOUT_BROADCAST_TX_COMMIT}"
	local configtoml_rpc_max_request_batch_size="${CONFIGTOML_RPC_MAX_REQUEST_BATCH_SIZE}"
	local configtoml_rpc_max_body_bytes="${CONFIGTOML_RPC_MAX_BODY_BYTES}"
	local configtoml_rpc_max_header_bytes="${CONFIGTOML_RPC_MAX_HEADER_BYTES}"
	local configtoml_rpc_tls_cert_file="${CONFIGTOML_RPC_TLS_CERT_FILE}"
	local configtoml_rpc_tls_key_file="${CONFIGTOML_RPC_TLS_KEY_FILE}"
	local configtoml_rpc_pprof_laddr="${CONFIGTOML_RPC_PPROF_LADDR}"

	# Config.toml - gRPC Server Configuration
	local configtoml_grpc_laddr="${CONFIGTOML_GRPC_LADDR}"
	local configtoml_grpc_version_service_enabled="${CONFIGTOML_GRPC_VERSION_SERVICE_ENABLED}"
	local configtoml_grpc_block_service_enabled="${CONFIGTOML_GRPC_BLOCK_SERVICE_ENABLED}"
	local configtoml_grpc_block_results_service_enabled="${CONFIGTOML_GRPC_BLOCK_RESULTS_SERVICE_ENABLED}"
	local configtoml_grpc_privileged_laddr="${CONFIGTOML_GRPC_PRIVILEGED_LADDR}"
	local configtoml_grpc_privileged_pruning_service_enabled="${CONFIGTOML_GRPC_PRIVILEGED_PRUNING_SERVICE_ENABLED}"

	# Config.toml - P2P Configuration
	local configtoml_p2p_laddr="${CONFIGTOML_P2P_LADDR}"
	local configtoml_p2p_external_address="${CONFIGTOML_P2P_EXTERNAL_ADDRESS}"
	local configtoml_p2p_seeds="${CONFIGTOML_P2P_SEEDS}"
	local configtoml_p2p_persistent_peers="${CONFIGTOML_P2P_PERSISTENT_PEERS}"
	local configtoml_p2p_addr_book_file="${CONFIGTOML_P2P_ADDR_BOOK_FILE}"
	local configtoml_p2p_addr_book_strict="${CONFIGTOML_P2P_ADDR_BOOK_STRICT}"
	local configtoml_p2p_max_num_inbound_peers="${CONFIGTOML_P2P_MAX_NUM_INBOUND_PEERS}"
	local configtoml_p2p_max_num_outbound_peers="${CONFIGTOML_P2P_MAX_NUM_OUTBOUND_PEERS}"
	local configtoml_p2p_unconditional_peer_ids="${CONFIGTOML_P2P_UNCONDITIONAL_PEER_IDS}"
	local configtoml_p2p_persistent_peers_max_dial_period="${CONFIGTOML_P2P_PERSISTENT_PEERS_MAX_DIAL_PERIOD}"
	local configtoml_p2p_flush_throttle_timeout="${CONFIGTOML_P2P_FLUSH_THROTTLE_TIMEOUT}"
	local configtoml_p2p_max_packet_msg_payload_size="${CONFIGTOML_P2P_MAX_PACKET_MSG_PAYLOAD_SIZE}"
	local configtoml_p2p_send_rate="${CONFIGTOML_P2P_SEND_RATE}"
	local configtoml_p2p_recv_rate="${CONFIGTOML_P2P_RECV_RATE}"
	local configtoml_p2p_pex="${CONFIGTOML_P2P_PEX}"
	local configtoml_p2p_seed_mode="${CONFIGTOML_P2P_SEED_MODE}"
	local configtoml_p2p_private_peer_ids="${CONFIGTOML_P2P_PRIVATE_PEER_IDS}"
	local configtoml_p2p_allow_duplicate_ip="${CONFIGTOML_P2P_ALLOW_DUPLICATE_IP}"
	local configtoml_p2p_handshake_timeout="${CONFIGTOML_P2P_HANDSHAKE_TIMEOUT}"
	local configtoml_p2p_dial_timeout="${CONFIGTOML_P2P_DIAL_TIMEOUT}"

	# Config.toml - Mempool Configuration
	local configtoml_mempool_type="${CONFIGTOML_MEMPOOL_TYPE}"
	local configtoml_mempool_recheck="${CONFIGTOML_MEMPOOL_RECHECK}"
	local configtoml_mempool_recheck_timeout="${CONFIGTOML_MEMPOOL_RECHECK_TIMEOUT}"
	local configtoml_mempool_broadcast="${CONFIGTOML_MEMPOOL_BROADCAST}"
	local configtoml_mempool_wal_dir="${CONFIGTOML_MEMPOOL_WAL_DIR}"
	local configtoml_mempool_size="${CONFIGTOML_MEMPOOL_SIZE}"
	local configtoml_mempool_max_tx_bytes="${CONFIGTOML_MEMPOOL_MAX_TX_BYTES}"
	local configtoml_mempool_max_txs_bytes="${CONFIGTOML_MEMPOOL_MAX_TXS_BYTES}"
	local configtoml_mempool_cache_size="${CONFIGTOML_MEMPOOL_CACHE_SIZE}"
	local configtoml_mempool_keep_invalid_txs_in_cache="${CONFIGTOML_MEMPOOL_KEEP_INVALID_TXS_IN_CACHE}"
	local configtoml_mempool_experimental_max_gossip_connections_to_persistent_peers="${CONFIGTOML_MEMPOOL_EXPERIMENTAL_MAX_GOSSIP_CONNECTIONS_TO_PERSISTENT_PEERS}"
	local configtoml_mempool_experimental_max_gossip_connections_to_non_persistent_peers="${CONFIGTOML_MEMPOOL_EXPERIMENTAL_MAX_GOSSIP_CONNECTIONS_TO_NON_PERSISTENT_PEERS}"

	# Config.toml - State Sync Configuration
	local configtoml_statesync_enable="${CONFIGTOML_STATESYNC_ENABLE}"
	local configtoml_statesync_rpc_servers="${CONFIGTOML_STATESYNC_RPC_SERVERS}"
	local configtoml_statesync_trust_height="${CONFIGTOML_STATESYNC_TRUST_HEIGHT}"
	local configtoml_statesync_trust_hash="${CONFIGTOML_STATESYNC_TRUST_HASH}"
	local configtoml_statesync_trust_period="${CONFIGTOML_STATESYNC_TRUST_PERIOD}"
	local configtoml_statesync_discovery_time="${CONFIGTOML_STATESYNC_DISCOVERY_TIME}"
	local configtoml_statesync_temp_dir="${CONFIGTOML_STATESYNC_TEMP_DIR}"
	local configtoml_statesync_chunk_request_timeout="${CONFIGTOML_STATESYNC_CHUNK_REQUEST_TIMEOUT}"
	local configtoml_statesync_chunk_fetchers="${CONFIGTOML_STATESYNC_CHUNK_FETCHERS}"

	# Config.toml - Block Sync Configuration
	local configtoml_blocksync_version="${CONFIGTOML_BLOCKSYNC_VERSION}"

	# Config.toml - Consensus Configuration
	local configtoml_consensus_wal_file="${CONFIGTOML_CONSENSUS_WAL_FILE}"
	local configtoml_consensus_timeout_propose="${CONFIGTOML_CONSENSUS_TIMEOUT_PROPOSE}"
	local configtoml_consensus_timeout_propose_delta="${CONFIGTOML_CONSENSUS_TIMEOUT_PROPOSE_DELTA}"
	local configtoml_consensus_timeout_prevote="${CONFIGTOML_CONSENSUS_TIMEOUT_PREVOTE}"
	local configtoml_consensus_timeout_prevote_delta="${CONFIGTOML_CONSENSUS_TIMEOUT_PREVOTE_DELTA}"
	local configtoml_consensus_timeout_precommit="${CONFIGTOML_CONSENSUS_TIMEOUT_PRECOMMIT}"
	local configtoml_consensus_timeout_precommit_delta="${CONFIGTOML_CONSENSUS_TIMEOUT_PRECOMMIT_DELTA}"
	local configtoml_consensus_timeout_commit="${CONFIGTOML_CONSENSUS_TIMEOUT_COMMIT}"
	local configtoml_consensus_skip_timeout_commit="${CONFIGTOML_CONSENSUS_SKIP_TIMEOUT_COMMIT}"
	local configtoml_consensus_double_sign_check_height="${CONFIGTOML_CONSENSUS_DOUBLE_SIGN_CHECK_HEIGHT}"
	local configtoml_consensus_create_empty_blocks="${CONFIGTOML_CONSENSUS_CREATE_EMPTY_BLOCKS}"
	local configtoml_consensus_create_empty_blocks_interval="${CONFIGTOML_CONSENSUS_CREATE_EMPTY_BLOCKS_INTERVAL}"
	local configtoml_consensus_peer_gossip_sleep_duration="${CONFIGTOML_CONSENSUS_PEER_GOSSIP_SLEEP_DURATION}"
	local configtoml_consensus_peer_gossip_intraloop_sleep_duration="${CONFIGTOML_CONSENSUS_PEER_GOSSIP_INTRALOOP_SLEEP_DURATION}"
	local configtoml_consensus_peer_query_maj23_sleep_duration="${CONFIGTOML_CONSENSUS_PEER_QUERY_MAJ23_SLEEP_DURATION}"

	# Config.toml - Storage Configuration
	local configtoml_storage_discard_abci_responses="${CONFIGTOML_STORAGE_DISCARD_ABCI_RESPONSES}"
	local configtoml_storage_experimental_db_key_layout="${CONFIGTOML_STORAGE_EXPERIMENTAL_DB_KEY_LAYOUT}"
	local configtoml_storage_compact="${CONFIGTOML_STORAGE_COMPACT}"
	local configtoml_storage_compaction_interval="${CONFIGTOML_STORAGE_COMPACTION_INTERVAL}"
	local configtoml_storage_pruning_interval="${CONFIGTOML_STORAGE_PRUNING_INTERVAL}"
	local configtoml_storage_pruning_data_companion_enabled="${CONFIGTOML_STORAGE_PRUNING_DATA_COMPANION_ENABLED}"
	local configtoml_storage_pruning_data_companion_initial_block_retain_height="${CONFIGTOML_STORAGE_PRUNING_DATA_COMPANION_INITIAL_BLOCK_RETAIN_HEIGHT}"
	local configtoml_storage_pruning_data_companion_initial_block_results_retain_height="${CONFIGTOML_STORAGE_PRUNING_DATA_COMPANION_INITIAL_BLOCK_RESULTS_RETAIN_HEIGHT}"

	# Config.toml - Transaction Indexer Configuration
	local configtoml_tx_index_indexer="${CONFIGTOML_TX_INDEX_INDEXER}"
	local configtoml_tx_index_psql_conn="${CONFIGTOML_TX_INDEX_PSQL_CONN}"

	# Config.toml - Instrumentation Configuration
	local configtoml_instrumentation_prometheus="${CONFIGTOML_INSTRUMENTATION_PROMETHEUS}"
	local configtoml_instrumentation_prometheus_listen_addr="${CONFIGTOML_INSTRUMENTATION_PROMETHEUS_LISTEN_ADDR}"
	local configtoml_instrumentation_max_open_connections="${CONFIGTOML_INSTRUMENTATION_MAX_OPEN_CONNECTIONS}"
	local configtoml_instrumentation_namespace="${CONFIGTOML_INSTRUMENTATION_NAMESPACE}"

	# =========================================================================
	# [3] ARGUMENT PARSING
	# =========================================================================
	# Parse all command-line arguments and override default values

	while [[ $# -gt 0 ]]; do
		case "$1" in
    --beacond-version)
      if [[ -n "$2" ]]; then
        check_beacond_version="$2"
        if [[ ! "$check_beacond_version" =~ ^(latest|v\.?[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+(\.[0-9]+)?)?)$ ]]; then
          log_warn "--beacond-version must match format (latest or v<MAJ>.<MIN>.<PATCH> or v<MAJ>.<MIN>.<PATCH>-rc<N>) (e.g., latest, v0.7.1, v0.7.1-rc2)"
          log_warn "defaulting to ${beacond_version}..."
        else
          beacond_version="$check_beacond_version"
        fi
        log_info "Using beacond version: $beacond_version"
        shift 2
      else
        log_warn "--beacond-version is not set. defaulting to ${beacond_version}"
        shift
      fi
      ;;
    --berareth-version)
      if [[ -n "$2" ]]; then
        check_berareth_version="$2"
        if [[ ! "$check_berareth_version" =~ ^(latest|v\.?[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+(\.[0-9]+)?)?)$ ]]; then
          log_warn "--berareth-version must match format (latest or v<MAJ>.<MIN>.<PATCH> or v<MAJ>.<MIN>.<PATCH>-rc<N>) (e.g., latest, v0.7.1, v0.7.1-rc2)"
          log_warn "defaulting to ${berareth_version}..."
        else
          berareth_version="$check_berareth_version"
        fi
        log_info "Using berareth version: $berareth_version"
        shift 2
      else
        log_warn "--berareth-version is not set. defaulting to ${berareth_version}"
        shift
      fi
      ;;
		--beranodes-dir)
			BERANODES_PATH=$(parse_beranodes_dir "$2")
			shift 2
			;;
		--docker)
			docker_mode=true
			mode="docker"
			# Check if Docker is installed
			if ! command -v docker &> /dev/null; then
				log_error "Docker is not installed or not found in PATH. Please install Docker to continue."
				exit 1
			fi

			# Check if Docker daemon is running
			if ! docker info &> /dev/null; then
				log_error "Docker daemon is not running. Please start Docker to continue."
				exit 1
			fi

			# Check Docker version is at least 20.10.0
			docker_version=$(docker version --format '{{.Server.Version}}')
			if [[ -z "$docker_version" ]]; then
				log_warn "Could not determine Docker version. Proceeding, but issues may occur."
			else
				if [[ "$docker_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
					docker_major="${BASH_REMATCH[1]}"
					docker_minor="${BASH_REMATCH[2]}"
					docker_patch="${BASH_REMATCH[3]}"
					# Compare version (minimum required: 20.10.0)
					if (( docker_major < 20 )) || { (( docker_major == 20 )) && (( docker_minor < 10 )); }; then
						log_error "Docker version 20.10.0 or newer is required. Current version: $docker_version"
						exit 1
					fi
				else
					log_warn "Could not parse Docker version: $docker_version. Proceeding, but issues may occur."
				fi
			fi
			shift
			;;
    --docker-tag-berareth)
      if [[ -n "$2" ]]; then
        docker_tag_berareth="$2"
        shift 2
      else
        log_warn "--docker-tag-berareth is not set. defaulting to latest"
        docker_tag_berareth="latest"
      fi
      ;;
    --docker-tag-beacond)
      if [[ -n "$2" ]]; then
        docker_tag_beacond="$2"
        shift 2
      else
        log_warn "--docker-tag-beacond is not set. defaulting to latest"
        docker_tag_beacond="latest"
      fi
      ;;
		--moniker)
			if [[ -n "$2" ]]; then
				moniker="$2"
				configtoml_moniker="$2"
				shift 2
			else
				log_warn "--moniker is not set. defaulting to a random name"
				moniker="$(generate_random_name)"
				configtoml_moniker="$moniker"
				shift
			fi
			;;
		--network)
			if [[ -n "$2" ]]; then
				network="$2"
				if [[ "$network" == "$CHAIN_NAME_DEVNET" ]]; then
					chain_id=$CHAIN_ID_DEVNET
					shift 2
				elif [[ "$network" == "$CHAIN_NAME_TESTNET" ]]; then
					chain_id=$CHAIN_ID_TESTNET
					shift 2
				elif [[ "$network" == "$CHAIN_NAME_MAINNET" ]]; then
					chain_id=$CHAIN_ID_MAINNET
					shift 2
				else
					log_warn "Unknown network: $network. Defaulting to $CHAIN_NAME_DEVNET"
					network=$CHAIN_NAME_DEVNET
					chain_id=$CHAIN_ID_DEVNET
					shift 2
				fi
			else
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
		# client.toml configuration variables
		--clienttoml-chain-id)
			if [[ -n "$2" ]]; then
				clienttoml_chain_id="$2"
				shift 2
			else
				clienttoml_chain_id="${CLIENTTOML_CHAIN_ID}"
				shift
			fi
			;;
		--clienttoml-keyring-backend)
			if [[ -n "$2" ]]; then
				clienttoml_keyring_backend="$2"
				shift 2
			else
				clienttoml_keyring_backend="${CLIENTTOML_KEYRING_BACKEND}"
				shift
			fi
			;;
		--clienttoml-keyring-default-keyname)
			if [[ -n "$2" ]]; then
				clienttoml_keyring_default_keyname="$2"
				shift 2
			else
				clienttoml_keyring_default_keyname="${CLIENTTOML_KEYRING_DEFAULT_KEYNAME}"
				shift
			fi
			;;
		--clienttoml-output)
			if [[ -n "$2" ]]; then
				clienttoml_output="$2"
				shift 2
			else
				clienttoml_output="${CLIENTTOML_OUTPUT}"
				shift
			fi
			;;
		--clienttoml-node)
			if [[ -n "$2" ]]; then
				clienttoml_node="$2"
				shift 2
			else
				clienttoml_node="${CLIENTTOML_NODE}"
				shift
			fi
			;;
		--clienttoml-broadcast-mode)
			if [[ -n "$2" ]]; then
				clienttoml_broadcast_mode="$2"
				shift 2
			else
				clienttoml_broadcast_mode="${CLIENTTOML_BROADCAST_MODE}"
				shift
			fi
			;;
		--clienttoml-grpc-address)
			if [[ -n "$2" ]]; then
				clienttoml_grpc_address="$2"
				shift 2
			else
				clienttoml_grpc_address="${CLIENTTOML_GRPC_ADDRESS}"
				shift
			fi
			;;
		--clienttoml-grpc-insecure)
			if [[ -n "$2" ]]; then
				clienttoml_grpc_insecure="$2"
				shift 2
			else
				clienttoml_grpc_insecure="${CLIENTTOML_GRPC_INSECURE}"
				shift
			fi
			;;
		# app.toml configuration variables
		--apptoml-pruning)
			if [[ -n "$2" ]]; then
				apptoml_pruning="$2"
				shift 2
			else
				apptoml_pruning="${APPTOML_PRUNING}"
				shift
			fi
			;;
		--apptoml-pruning-keep-recent)
			if [[ -n "$2" ]]; then
				apptoml_pruning_keep_recent="$2"
				shift 2
			else
				apptoml_pruning_keep_recent="${APPTOML_PRUNING_KEEP_RECENT}"
				shift
			fi
			;;
		--apptoml-pruning-interval)
			if [[ -n "$2" ]]; then
				apptoml_pruning_interval="$2"
				shift 2
			else
				apptoml_pruning_interval="${APPTOML_PRUNING_INTERVAL}"
				shift
			fi
			;;
		--apptoml-halt-height)
			if [[ -n "$2" ]]; then
				apptoml_halt_height="$2"
				shift 2
			else
				apptoml_halt_height="${APPTOML_HALT_HEIGHT}"
				shift
			fi
			;;
		--apptoml-halt-time)
			if [[ -n "$2" ]]; then
				apptoml_halt_time="$2"
				shift 2
			else
				apptoml_halt_time="${APPTOML_HALT_TIME}"
				shift
			fi
			;;
		--apptoml-min-retain-blocks)
			if [[ -n "$2" ]]; then
				apptoml_min_retain_blocks="$2"
				shift 2
			else
				apptoml_min_retain_blocks="${APPTOML_MIN_RETAIN_BLOCKS}"
				shift
			fi
			;;
		--apptoml-inter-block-cache)
			if [[ -n "$2" ]]; then
				apptoml_inter_block_cache="$2"
				shift 2
			else
				apptoml_inter_block_cache="${APPTOML_INTER_BLOCK_CACHE}"
				shift
			fi
			;;
		--apptoml-iavl-cache-size)
			if [[ -n "$2" ]]; then
				apptoml_iavl_cache_size="$2"
				shift 2
			else
				apptoml_iavl_cache_size="${APPTOML_IAVL_CACHE_SIZE}"
				shift
			fi
			;;
		--apptoml-iavl-disable-fastnode)
			if [[ -n "$2" ]]; then
				apptoml_iavl_disable_fastnode="$2"
				shift 2
			else
				apptoml_iavl_disable_fastnode="${APPTOML_IAVL_DISABLE_FASTNODE}"
				shift
			fi
			;;
		--apptoml-app-db-backend)
			if [[ -n "$2" ]]; then
				apptoml_app_db_backend="$2"
				shift 2
			else
				apptoml_app_db_backend="${APPTOML_APP_DB_BACKEND}"
				shift
			fi
			;;
		# - Telemetry Configuration
		--apptoml-telemetry-service-name)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_service_name="$2"
				shift 2
			else
				apptoml_telemetry_service_name="${APPTOML_TELEMETRY_SERVICE_NAME}"
				shift
			fi
			;;
		--apptoml-telemetry-enabled)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_enabled="$2"
				shift 2
			else
				apptoml_telemetry_enabled="${APPTOML_TELEMETRY_ENABLED}"
				shift
			fi
			;;
		--apptoml-telemetry-enable-hostname)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_enable_hostname="$2"
				shift 2
			else
				apptoml_telemetry_enable_hostname="${APPTOML_TELEMETRY_ENABLE_HOSTNAME}"
				shift
			fi
			;;
		--apptoml-telemetry-enable-hostname-label)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_enable_hostname_label="$2"
				shift 2
			else
				apptoml_telemetry_enable_hostname_label="${APPTOML_TELEMETRY_ENABLE_HOSTNAME_LABEL}"
				shift
			fi
			;;
		--apptoml-telemetry-enable-service-label)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_enable_service_label="$2"
				shift 2
			else
				apptoml_telemetry_enable_service_label="${APPTOML_TELEMETRY_ENABLE_SERVICE_LABEL}"
				shift
			fi
			;;
		--apptoml-telemetry-prometheus-retention-time)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_prometheus_retention_time="$2"
				shift 2
			else
				apptoml_telemetry_prometheus_retention_time="${APPTOML_TELEMETRY_PROMETHEUS_RETENTION_TIME}"
				shift
			fi
			;;
		--apptoml-telemetry-metrics-sink)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_metrics_sink="$2"
				shift 2
			else
				apptoml_telemetry_metrics_sink="${APPTOML_TELEMETRY_METRICS_SINK}"
				shift
			fi
			;;
		--apptoml-telemetry-statsd-addr)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_statsd_addr="$2"
				shift 2
			else
				apptoml_telemetry_statsd_addr="${APPTOML_TELEMETRY_STATSD_ADDR}"
				shift
			fi
			;;
		--apptoml-telemetry-datadog-hostname)
			if [[ -n "$2" ]]; then
				apptoml_telemetry_datadog_hostname="$2"
				shift 2
			else
				apptoml_telemetry_datadog_hostname="${APPTOML_TELEMETRY_DATADOG_HOSTNAME}"
				shift
			fi
			;;
		# - BeacondKit Configuration
		--apptoml-beacon-kit-chain-spec)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_chain_spec="$2"
				shift 2
			else
				apptoml_beacon_kit_chain_spec="${APPTOML_BEACON_KIT_CHAIN_SPEC}"
				shift
			fi
			;;
		--apptoml-beacon-kit-chain-spec-file)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_chain_spec_file="$2"
				shift 2
			else
				apptoml_beacon_kit_chain_spec_file="${APPTOML_BEACON_KIT_CHAIN_SPEC_FILE}"
				shift
			fi
			;;
		--apptoml-beacon-kit-shutdown-timeout)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_shutdown_timeout="$2"
				shift 2
			else
				apptoml_beacon_kit_shutdown_timeout="${APPTOML_BEACON_KIT_SHUTDOWN_TIMEOUT}"
				shift
			fi
			;;
		# - BeaconKit Engine Configuration
		--apptoml-beacon-kit-engine-rpc-dial-url)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_engine_rpc_dial_url="$2"
				shift 2
			else
				apptoml_beacon_kit_engine_rpc_dial_url="${APPTOML_BEACON_KIT_ENGINE_RPC_DIAL_URL}"
				shift
			fi
			;;
		--apptoml-beacon-kit-engine-rpc-timeout)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_engine_rpc_timeout="$2"
				shift 2
			else
				apptoml_beacon_kit_engine_rpc_timeout="${APPTOML_BEACON_KIT_ENGINE_RPC_TIMEOUT}"
				shift
			fi
			;;
		--apptoml-beacon-kit-engine-rpc-retry-interval)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_engine_rpc_retry_interval="$2"
				shift 2
			else
				apptoml_beacon_kit_engine_rpc_retry_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_RETRY_INTERVAL}"
				shift
			fi
			;;
		--apptoml-beacon-kit-engine-rpc-max-retry-interval)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_engine_rpc_max_retry_interval="$2"
				shift 2
			else
				apptoml_beacon_kit_engine_rpc_max_retry_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_MAX_RETRY_INTERVAL}"
				shift
			fi
			;;
		--apptoml-beacon-kit-engine-rpc-startup-check-interval)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_engine_rpc_startup_check_interval="$2"
				shift 2
			else
				apptoml_beacon_kit_engine_rpc_startup_check_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_STARTUP_CHECK_INTERVAL}"
				shift
			fi
			;;
		--apptoml-beacon-kit-engine-rpc-jwt-refresh-interval)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_engine_rpc_jwt_refresh_interval="$2"
				shift 2
			else
				apptoml_beacon_kit_engine_rpc_jwt_refresh_interval="${APPTOML_BEACON_KIT_ENGINE_RPC_JWT_REFRESH_INTERVAL}"
				shift
			fi
			;;
		--apptoml-beacon-kit-engine-jwt-secret-path)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_engine_jwt_secret_path="$2"
				shift 2
			else
				apptoml_beacon_kit_engine_jwt_secret_path="${APPTOML_BEACON_KIT_ENGINE_JWT_SECRET_PATH}"
				shift
			fi
			;;
		# - BeaconKit Logger Configuration
		--apptoml-beacon-kit-logger-time-format)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_logger_time_format="$2"
				shift 2
			else
				apptoml_beacon_kit_logger_time_format="${APPTOML_BEACON_KIT_LOGGER_TIME_FORMAT}"
				shift
			fi
			;;
		--apptoml-beacon-kit-logger-log-level)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_logger_log_level="$2"
				shift 2
			else
				apptoml_beacon_kit_logger_log_level="${APPTOML_BEACON_KIT_LOGGER_LOG_LEVEL}"
				shift
			fi
			;;
		--apptoml-beacon-kit-logger-style)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_logger_style="$2"
				shift 2
			else
				apptoml_beacon_kit_logger_style="${APPTOML_BEACON_KIT_LOGGER_STYLE}"
				shift
			fi
			;;
		# - BeaconKit KZG Configuration
		--apptoml-beacon-kit-kzg-trusted-setup-path)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_kzg_trusted_setup_path="$2"
				shift 2
			else
				apptoml_beacon_kit_kzg_trusted_setup_path="${APPTOML_BEACON_KIT_KZG_TRUSTED_SETUP_PATH}"
				shift
			fi
			;;
		--apptoml-beacon-kit-kzg-implementation)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_kzg_implementation="$2"
				shift 2
			else
				apptoml_beacon_kit_kzg_implementation="${APPTOML_BEACON_KIT_KZG_IMPLEMENTATION}"
				shift
			fi
			;;
		# - BeaconKit Payload Builder Configuration
		--apptoml-beacon-kit-payload-builder-enabled)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_payload_builder_enabled="$2"
				shift 2
			else
				apptoml_beacon_kit_payload_builder_enabled="${APPTOML_BEACON_KIT_PAYLOAD_BUILDER_ENABLED}"
				shift
			fi
			;;
		--apptoml-beacon-kit-payload-builder-suggested-fee-recipient)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_payload_builder_suggested_fee_recipient="$2"
				shift 2
			else
				apptoml_beacon_kit_payload_builder_suggested_fee_recipient="${APPTOML_BEACON_KIT_PAYLOAD_BUILDER_SUGGESTED_FEE_RECIPIENT}"
				shift
			fi
			;;
		--apptoml-beacon-kit-payload-builder-payload-timeout)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_payload_builder_payload_timeout="$2"
				shift 2
			else
				apptoml_beacon_kit_payload_builder_payload_timeout="${APPTOML_BEACON_KIT_PAYLOAD_BUILDER_PAYLOAD_TIMEOUT}"
				shift
			fi
			;;
		--apptoml-beacon-kit-validator-graffiti)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_validator_graffiti="$2"
				shift 2
			else
				apptoml_beacon_kit_validator_graffiti="${APPTOML_BEACON_KIT_VALIDATOR_GRAFFITI}"
				shift
			fi
			;;
		--apptoml-beacon-kit-validator-availability-window)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_validator_availability_window="$2"
				shift 2
			else
				apptoml_beacon_kit_validator_availability_window="${APPTOML_BEACON_KIT_VALIDATOR_AVAILABILITY_WINDOW}"
				shift
			fi
			;;
		# - BeaconKit Validator Configuration
		--apptoml-beacon-kit-node-api-enabled)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_node_api_enabled="$2"
				shift 2
			else
				apptoml_beacon_kit_node_api_enabled="${APPTOML_BEACON_KIT_NODE_API_ENABLED}"
				shift
			fi
			;;
		--apptoml-beacon-kit-node-api-address)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_node_api_address="$2"
				shift 2
			else
				apptoml_beacon_kit_node_api_address="${APPTOML_BEACON_KIT_NODE_API_ADDRESS}"
				shift
			fi
			;;
		--apptoml-beacon-kit-node-api-logging)
			if [[ -n "$2" ]]; then
				apptoml_beacon_kit_node_api_logging="$2"
				shift 2
			else
				apptoml_beacon_kit_node_api_logging="${APPTOML_BEACON_KIT_NODE_API_LOGGING}"
				shift
			fi
			;;
		# config.toml configuration variables
		--configtoml-version)
			if [[ -n "$2" ]]; then
				configtoml_version="$2"
				shift 2
			else
				configtoml_version="${CONFIGTOML_VERSION}"
				shift
			fi
			;;
		--configtoml-proxy-app)
			if [[ -n "$2" ]]; then
				configtoml_proxy_app="$2"
				shift 2
			else
				configtoml_proxy_app="${CONFIGTOML_PROXY_APP}"
				shift
			fi
			;;
		# --configtoml-moniker)
		#     if [[ -n "$2" ]]; then configtoml_moniker="$2"; shift 2; else configtoml_moniker="${CONFIGTOML_MONIKER}"; shift; fi ;;
		--configtoml-db-backend)
			if [[ -n "$2" ]]; then
				configtoml_db_backend="$2"
				shift 2
			else
				configtoml_db_backend="${CONFIGTOML_DB_BACKEND}"
				shift
			fi
			;;
		--configtoml-db-dir)
			if [[ -n "$2" ]]; then
				configtoml_db_dir="$2"
				shift 2
			else
				configtoml_db_dir="${CONFIGTOML_DB_DIR}"
				shift
			fi
			;;
		--configtoml-log-level)
			if [[ -n "$2" ]]; then
				configtoml_log_level="$2"
				shift 2
			else
				configtoml_log_level="${CONFIGTOML_LOG_LEVEL}"
				shift
			fi
			;;
		--configtoml-log-format)
			if [[ -n "$2" ]]; then
				configtoml_log_format="$2"
				shift 2
			else
				configtoml_log_format="${CONFIGTOML_LOG_FORMAT}"
				shift
			fi
			;;
		--configtoml-genesis-file)
			if [[ -n "$2" ]]; then
				configtoml_genesis_file="$2"
				shift 2
			else
				configtoml_genesis_file="${CONFIGTOML_GENESIS_FILE}"
				shift
			fi
			;;
		--configtoml-priv-validator-key-file)
			if [[ -n "$2" ]]; then
				configtoml_priv_validator_key_file="$2"
				shift 2
			else
				configtoml_priv_validator_key_file="${CONFIGTOML_PRIV_VALIDATOR_KEY_FILE}"
				shift
			fi
			;;
		--configtoml-priv-validator-state-file)
			if [[ -n "$2" ]]; then
				configtoml_priv_validator_state_file="$2"
				shift 2
			else
				configtoml_priv_validator_state_file="${CONFIGTOML_PRIV_VALIDATOR_STATE_FILE}"
				shift
			fi
			;;
		--configtoml-priv-validator-laddr)
			if [[ -n "$2" ]]; then
				configtoml_priv_validator_laddr="$2"
				shift 2
			else
				configtoml_priv_validator_laddr="${CONFIGTOML_PRIV_VALIDATOR_LADDR}"
				shift
			fi
			;;
		--configtoml-node-key-file)
			if [[ -n "$2" ]]; then
				configtoml_node_key_file="$2"
				shift 2
			else
				configtoml_node_key_file="${CONFIGTOML_NODE_KEY_FILE}"
				shift
			fi
			;;
		--configtoml-abci)
			if [[ -n "$2" ]]; then
				configtoml_abci="$2"
				shift 2
			else
				configtoml_abci="${CONFIGTOML_ABCI}"
				shift
			fi
			;;
		--configtoml-filter-peers)
			if [[ -n "$2" ]]; then
				configtoml_filter_peers="$2"
				shift 2
			else
				configtoml_filter_peers="${CONFIGTOML_FILTER_PEERS}"
				shift
			fi
			;;
		# - RPC Server Configuration
		--configtoml-rpc-laddr)
			if [[ -n "$2" ]]; then
				configtoml_rpc_laddr="$2"
				shift 2
			else
				configtoml_rpc_laddr="${CONFIGTOML_RPC_LADDR}"
				shift
			fi
			;;
		--configtoml-rpc-unsafe)
			if [[ -n "$2" ]]; then
				configtoml_rpc_unsafe="$2"
				shift 2
			else
				configtoml_rpc_unsafe="${CONFIGTOML_RPC_UNSAFE}"
				shift
			fi
			;;
		--configtoml-rpc-cors-allowed-origins)
			if [[ -n "$2" ]]; then
				configtoml_rpc_cors_allowed_origins="$2"
				shift 2
			else
				configtoml_rpc_cors_allowed_origins="${CONFIGTOML_RPC_CORS_ALLOWED_ORIGINS}"
				shift
			fi
			;;
		--configtoml-rpc-cors-allowed-methods)
			if [[ -n "$2" ]]; then
				configtoml_rpc_cors_allowed_methods="$2"
				shift 2
			else
				configtoml_rpc_cors_allowed_methods="${CONFIGTOML_RPC_CORS_ALLOWED_METHODS}"
				shift
			fi
			;;
		--configtoml-rpc-cors-allowed-methods)
			if [[ -n "$2" ]]; then
				configtoml_rpc_cors_allowed_headers="$2"
				shift 2
			else
				configtoml_rpc_cors_allowed_headers="${CONFIGTOML_RPC_CORS_ALLOWED_HEADERS}"
				shift
			fi
			;;
		--configtoml-rpc-max-open-connections)
			if [[ -n "$2" ]]; then
				configtoml_rpc_max_open_connections="$2"
				shift 2
			else
				configtoml_rpc_max_open_connections="${CONFIGTOML_RPC_MAX_OPEN_CONNECTIONS}"
				shift
			fi
			;;
		--configtoml-rpc-max-subscription-clients)
			if [[ -n "$2" ]]; then
				configtoml_rpc_max_subscription_clients="$2"
				shift 2
			else
				configtoml_rpc_max_subscription_clients="${CONFIGTOML_RPC_MAX_SUBSCRIPTION_CLIENTS}"
				shift
			fi
			;;
		--configtoml-rpc-max-subscriptions-per-client)
			if [[ -n "$2" ]]; then
				configtoml_rpc_max_subscriptions_per_client="$2"
				shift 2
			else
				configtoml_rpc_max_subscriptions_per_client="${CONFIGTOML_RPC_MAX_SUBSCRIPTIONS_PER_CLIENT}"
				shift
			fi
			;;
		--configtoml-rpc-experimental-subscription-buffer-size)
			if [[ -n "$2" ]]; then
				configtoml_rpc_experimental_subscription_buffer_size="$2"
				shift 2
			else
				configtoml_rpc_experimental_subscription_buffer_size="${CONFIGTOML_RPC_EXPERIMENTAL_SUBSCRIPTION_BUFFER_SIZE}"
				shift
			fi
			;;
		--configtoml-rpc-experimental-websocket-write-buffer-size)
			if [[ -n "$2" ]]; then
				configtoml_rpc_experimental_websocket_write_buffer_size="$2"
				shift 2
			else
				configtoml_rpc_experimental_websocket_write_buffer_size="${CONFIGTOML_RPC_EXPERIMENTAL_WEBSOCKET_WRITE_BUFFER_SIZE}"
				shift
			fi
			;;
		--configtoml-rpc-experimental-close-on-slow-client)
			if [[ -n "$2" ]]; then
				configtoml_rpc_experimental_close_on_slow_client="$2"
				shift 2
			else
				configtoml_rpc_experimental_close_on_slow_client="${CONFIGTOML_RPC_EXPERIMENTAL_CLOSE_ON_SLOW_CLIENT}"
				shift
			fi
			;;
		--configtoml-rpc-timeout-broadcast-tx-commit)
			if [[ -n "$2" ]]; then
				configtoml_rpc_timeout_broadcast_tx_commit="$2"
				shift 2
			else
				configtoml_rpc_timeout_broadcast_tx_commit="${CONFIGTOML_RPC_TIMEOUT_BROADCAST_TX_COMMIT}"
				shift
			fi
			;;
		--configtoml-rpc-max-request-batch-size)
			if [[ -n "$2" ]]; then
				configtoml_rpc_max_request_batch_size="$2"
				shift 2
			else
				configtoml_rpc_max_request_batch_size="${CONFIGTOML_RPC_MAX_REQUEST_BATCH_SIZE}"
				shift
			fi
			;;
		--configtoml-rpc-max-body-bytes)
			if [[ -n "$2" ]]; then
				configtoml_rpc_max_body_bytes="$2"
				shift 2
			else
				configtoml_rpc_max_body_bytes="${CONFIGTOML_RPC_MAX_BODY_BYTES}"
				shift
			fi
			;;
		--configtoml-rpc-max-header-bytes)
			if [[ -n "$2" ]]; then
				configtoml_rpc_max_header_bytes="$2"
				shift 2
			else
				configtoml_rpc_max_header_bytes="${CONFIGTOML_RPC_MAX_HEADER_BYTES}"
				shift
			fi
			;;
		--configtoml-rpc-tls-cert-file)
			if [[ -n "$2" ]]; then
				configtoml_rpc_tls_cert_file="$2"
				shift 2
			else
				configtoml_rpc_tls_cert_file="${CONFIGTOML_RPC_TLS_CERT_FILE}"
				shift
			fi
			;;
		--configtoml-rpc-tls-key-file)
			if [[ -n "$2" ]]; then
				configtoml_rpc_tls_key_file="$2"
				shift 2
			else
				configtoml_rpc_tls_key_file="${CONFIGTOML_RPC_TLS_KEY_FILE}"
				shift
			fi
			;;
		--configtoml-rpc-pprof-laddr)
			if [[ -n "$2" ]]; then
				configtoml_rpc_pprof_laddr="$2"
				shift 2
			else
				configtoml_rpc_pprof_laddr="${CONFIGTOML_RPC_PPROF_LADDR}"
				shift
			fi
			;;
		# - gRPC Server Configuration
		--configtoml-grpc-laddr)
			if [[ -n "$2" ]]; then
				configtoml_grpc_laddr="$2"
				shift 2
			else
				configtoml_grpc_laddr="${CONFIGTOML_GRPC_LADDR}"
				shift
			fi
			;;
		--configtoml-grpc-version-service-enabled)
			if [[ -n "$2" ]]; then
				configtoml_grpc_version_service_enabled="$2"
				shift 2
			else
				configtoml_grpc_version_service_enabled="${CONFIGTOML_GRPC_VERSION_SERVICE_ENABLED}"
				shift
			fi
			;;
		--configtoml-grpc-block-service-enabled)
			if [[ -n "$2" ]]; then
				configtoml_grpc_block_service_enabled="$2"
				shift 2
			else
				configtoml_grpc_block_service_enabled="${CONFIGTOML_GRPC_BLOCK_SERVICE_ENABLED}"
				shift
			fi
			;;
		--configtoml-grpc-block-results-service-enabled)
			if [[ -n "$2" ]]; then
				configtoml_grpc_block_results_service_enabled="$2"
				shift 2
			else
				configtoml_grpc_block_results_service_enabled="${CONFIGTOML_GRPC_BLOCK_RESULTS_SERVICE_ENABLED}"
				shift
			fi
			;;
		--configtoml-grpc-privileged-laddr)
			if [[ -n "$2" ]]; then
				configtoml_grpc_privileged_laddr="$2"
				shift 2
			else
				configtoml_grpc_privileged_laddr="${CONFIGTOML_GRPC_PRIVILEGED_LADDR}"
				shift
			fi
			;;
		--configtoml-grpc-privileged-pruning-service-enabled)
			if [[ -n "$2" ]]; then
				configtoml_grpc_privileged_pruning_service_enabled="$2"
				shift 2
			else
				configtoml_grpc_privileged_pruning_service_enabled="${CONFIGTOML_GRPC_PRIVILEGED_PRUNING_SERVICE_ENABLED}"
				shift
			fi
			;;
		# - P2P Configuration
		--configtoml-p2p-laddr)
			if [[ -n "$2" ]]; then
				configtoml_p2p_laddr="$2"
				shift 2
			else
				configtoml_p2p_laddr="${CONFIGTOML_P2P_LADDR}"
				shift
			fi
			;;
		--configtoml-p2p-external-address)
			if [[ -n "$2" ]]; then
				configtoml_p2p_external_address="$2"
				shift 2
			else
				configtoml_p2p_external_address="${CONFIGTOML_P2P_EXTERNAL_ADDRESS}"
				shift
			fi
			;;
		--configtoml-p2p-seeds)
			if [[ -n "$2" ]]; then
				configtoml_p2p_seeds="$2"
				shift 2
			else
				configtoml_p2p_seeds="${CONFIGTOML_P2P_SEEDS}"
				shift
			fi
			;;
		--configtoml-p2p-persistent-peers)
			if [[ -n "$2" ]]; then
				configtoml_p2p_persistent_peers="$2"
				shift 2
			else
				configtoml_p2p_persistent_peers="${CONFIGTOML_P2P_PERSISTENT_PEERS}"
				shift
			fi
			;;
		--configtoml-p2p-addr-book-file)
			if [[ -n "$2" ]]; then
				configtoml_p2p_addr_book_file="$2"
				shift 2
			else
				configtoml_p2p_addr_book_file="${CONFIGTOML_P2P_ADDR_BOOK_FILE}"
				shift
			fi
			;;
		--configtoml-p2p-addr-book-strict)
			if [[ -n "$2" ]]; then
				configtoml_p2p_addr_book_strict="$2"
				shift 2
			else
				configtoml_p2p_addr_book_strict="${CONFIGTOML_P2P_ADDR_BOOK_STRICT}"
				shift
			fi
			;;
		--configtoml-p2p-max-num-inbound-peers)
			if [[ -n "$2" ]]; then
				configtoml_p2p_max_num_inbound_peers="$2"
				shift 2
			else
				configtoml_p2p_max_num_inbound_peers="${CONFIGTOML_P2P_MAX_NUM_INBOUND_PEERS}"
				shift
			fi
			;;
		--configtoml-p2p-max-num-outbound-peers)
			if [[ -n "$2" ]]; then
				configtoml_p2p_max_num_outbound_peers="$2"
				shift 2
			else
				configtoml_p2p_max_num_outbound_peers="${CONFIGTOML_P2P_MAX_NUM_OUTBOUND_PEERS}"
				shift
			fi
			;;
		--configtoml-p2p-unconditional-peer-ids)
			if [[ -n "$2" ]]; then
				configtoml_p2p_unconditional_peer_ids="$2"
				shift 2
			else
				configtoml_p2p_unconditional_peer_ids="${CONFIGTOML_P2P_UNCONDITIONAL_PEER_IDS}"
				shift
			fi
			;;
		--configtoml-p2p-persistent-peers-max-dial-period)
			if [[ -n "$2" ]]; then
				configtoml_p2p_persistent_peers_max_dial_period="$2"
				shift 2
			else
				configtoml_p2p_persistent_peers_max_dial_period="${CONFIGTOML_P2P_PERSISTENT_PEERS_MAX_DIAL_PERIOD}"
				shift
			fi
			;;
		--configtoml-p2p-flush-throttle-timeout)
			if [[ -n "$2" ]]; then
				configtoml_p2p_flush_throttle_timeout="$2"
				shift 2
			else
				configtoml_p2p_flush_throttle_timeout="${CONFIGTOML_P2P_FLUSH_THROTTLE_TIMEOUT}"
				shift
			fi
			;;
		--configtoml-p2p-max-packet-msg-payload-size)
			if [[ -n "$2" ]]; then
				configtoml_p2p_max_packet_msg_payload_size="$2"
				shift 2
			else
				configtoml_p2p_max_packet_msg_payload_size="${CONFIGTOML_P2P_MAX_PACKET_MSG_PAYLOAD_SIZE}"
				shift
			fi
			;;
		--configtoml-p2p-send-rate)
			if [[ -n "$2" ]]; then
				configtoml_p2p_send_rate="$2"
				shift 2
			else
				configtoml_p2p_send_rate="${CONFIGTOML_P2P_SEND_RATE}"
				shift
			fi
			;;
		--configtoml-p2p-recv-rate)
			if [[ -n "$2" ]]; then
				configtoml_p2p_recv_rate="$2"
				shift 2
			else
				configtoml_p2p_recv_rate="${CONFIGTOML_P2P_RECV_RATE}"
				shift
			fi
			;;
		--configtoml-p2p-pex)
			if [[ -n "$2" ]]; then
				configtoml_p2p_pex="$2"
				shift 2
			else
				configtoml_p2p_pex="${CONFIGTOML_P2P_PEX}"
				shift
			fi
			;;
		--configtoml-p2p-seed-mode)
			if [[ -n "$2" ]]; then
				configtoml_p2p_seed_mode="$2"
				shift 2
			else
				configtoml_p2p_seed_mode="${CONFIGTOML_P2P_SEED_MODE}"
				shift
			fi
			;;
		--configtoml-p2p-private-peer-ids)
			if [[ -n "$2" ]]; then
				configtoml_p2p_private_peer_ids="$2"
				shift 2
			else
				configtoml_p2p_private_peer_ids="${CONFIGTOML_P2P_PRIVATE_PEER_IDS}"
				shift
			fi
			;;
		--configtoml-p2p-allow-duplicate-ip)
			if [[ -n "$2" ]]; then
				configtoml_p2p_allow_duplicate_ip="$2"
				shift 2
			else
				configtoml_p2p_allow_duplicate_ip="${CONFIGTOML_P2P_ALLOW_DUPLICATE_IP}"
				shift
			fi
			;;
		--configtoml-p2p-handshake-timeout)
			if [[ -n "$2" ]]; then
				configtoml_p2p_handshake_timeout="$2"
				shift 2
			else
				configtoml_p2p_handshake_timeout="${CONFIGTOML_P2P_HANDSHAKE_TIMEOUT}"
				shift
			fi
			;;
		--configtoml-p2p-dial-timeout)
			if [[ -n "$2" ]]; then
				configtoml_p2p_dial_timeout="$2"
				shift 2
			else
				configtoml_p2p_dial_timeout="${CONFIGTOML_P2P_DIAL_TIMEOUT}"
				shift
			fi
			;;
		# - Mempool Configuration
		--configtoml-mempool-type)
			if [[ -n "$2" ]]; then
				configtoml_mempool_type="$2"
				shift 2
			else
				configtoml_mempool_type="${CONFIGTOML_MEMPOOL_TYPE}"
				shift
			fi
			;;
		--configtoml-mempool-recheck)
			if [[ -n "$2" ]]; then
				configtoml_mempool_recheck="$2"
				shift 2
			else
				configtoml_mempool_recheck="${CONFIGTOML_MEMPOOL_RECHECK}"
				shift
			fi
			;;
		--configtoml-mempool-recheck-timeout)
			if [[ -n "$2" ]]; then
				configtoml_mempool_recheck_timeout="$2"
				shift 2
			else
				configtoml_mempool_recheck_timeout="${CONFIGTOML_MEMPOOL_RECHECK_TIMEOUT}"
				shift
			fi
			;;
		--configtoml-mempool-broadcast)
			if [[ -n "$2" ]]; then
				configtoml_mempool_broadcast="$2"
				shift 2
			else
				configtoml_mempool_broadcast="${CONFIGTOML_MEMPOOL_BROADCAST}"
				shift
			fi
			;;
		--configtoml-mempool-wal-dir)
			if [[ -n "$2" ]]; then
				configtoml_mempool_wal_dir="$2"
				shift 2
			else
				configtoml_mempool_wal_dir="${CONFIGTOML_MEMPOOL_WAL_DIR}"
				shift
			fi
			;;
		--configtoml-mempool-size)
			if [[ -n "$2" ]]; then
				configtoml_mempool_size="$2"
				shift 2
			else
				configtoml_mempool_size="${CONFIGTOML_MEMPOOL_SIZE}"
				shift
			fi
			;;
		--configtoml-mempool-max-tx-bytes)
			if [[ -n "$2" ]]; then
				configtoml_mempool_max_tx_bytes="$2"
				shift 2
			else
				configtoml_mempool_max_tx_bytes="${CONFIGTOML_MEMPOOL_MAX_TX_BYTES}"
				shift
			fi
			;;
		--configtoml-mempool-max-txs-bytes)
			if [[ -n "$2" ]]; then
				configtoml_mempool_max_txs_bytes="$2"
				shift 2
			else
				configtoml_mempool_max_txs_bytes="${CONFIGTOML_MEMPOOL_MAX_TXS_BYTES}"
				shift
			fi
			;;
		--configtoml-mempool-cache-size)
			if [[ -n "$2" ]]; then
				configtoml_mempool_cache_size="$2"
				shift 2
			else
				configtoml_mempool_cache_size="${CONFIGTOML_MEMPOOL_CACHE_SIZE}"
				shift
			fi
			;;
		--configtoml-mempool-keep-invalid-txs-in-cache)
			if [[ -n "$2" ]]; then
				configtoml_mempool_keep_invalid_txs_in_cache="$2"
				shift 2
			else
				configtoml_mempool_keep_invalid_txs_in_cache="${CONFIGTOML_MEMPOOL_KEEP_INVALID_TXS_IN_CACHE}"
				shift
			fi
			;;
		--configtoml-mempool-experimental-max-gossip-connections-to-persistent-peers)
			if [[ -n "$2" ]]; then
				configtoml_mempool_experimental_max_gossip_connections_to_persistent_peers="$2"
				shift 2
			else
				configtoml_mempool_experimental_max_gossip_connections_to_persistent_peers="${CONFIGTOML_MEMPOOL_EXPERIMENTAL_MAX_GOSSIP_CONNECTIONS_TO_PERSISTENT_PEERS}"
				shift
			fi
			;;
		--configtoml-mempool-experimental-max-gossip-connections-to-non-persistent-peers)
			if [[ -n "$2" ]]; then
				configtoml_mempool_experimental_max_gossip_connections_to_non_persistent_peers="$2"
				shift 2
			else
				configtoml_mempool_experimental_max_gossip_connections_to_non_persistent_peers="${CONFIGTOML_MEMPOOL_EXPERIMENTAL_MAX_GOSSIP_CONNECTIONS_TO_NON_PERSISTENT_PEERS}"
				shift
			fi
			;;
		# - State Sync Configuration
		--configtoml-statesync-enable)
			if [[ -n "$2" ]]; then
				configtoml_statesync_enable="$2"
				shift 2
			else
				configtoml_statesync_enable="${CONFIGTOML_STATESYNC_ENABLE}"
				shift
			fi
			;;
		--configtoml-statesync-rpc-servers)
			if [[ -n "$2" ]]; then
				configtoml_statesync_rpc_servers="$2"
				shift 2
			else
				configtoml_statesync_rpc_servers="${CONFIGTOML_STATESYNC_RPC_SERVERS}"
				shift
			fi
			;;
		--configtoml-statesync-trust-height)
			if [[ -n "$2" ]]; then
				configtoml_statesync_trust_height="$2"
				shift 2
			else
				configtoml_statesync_trust_height="${CONFIGTOML_STATESYNC_TRUST_HEIGHT}"
				shift
			fi
			;;
		--configtoml-statesync-trust-hash)
			if [[ -n "$2" ]]; then
				configtoml_statesync_trust_hash="$2"
				shift 2
			else
				configtoml_statesync_trust_hash="${CONFIGTOML_STATESYNC_TRUST_HASH}"
				shift
			fi
			;;
		--configtoml-statesync-trust-period)
			if [[ -n "$2" ]]; then
				configtoml_statesync_trust_period="$2"
				shift 2
			else
				configtoml_statesync_trust_period="${CONFIGTOML_STATESYNC_TRUST_PERIOD}"
				shift
			fi
			;;
		--configtoml-statesync-discovery-time)
			if [[ -n "$2" ]]; then
				configtoml_statesync_discovery_time="$2"
				shift 2
			else
				configtoml_statesync_discovery_time="${CONFIGTOML_STATESYNC_DISCOVERY_TIME}"
				shift
			fi
			;;
		--configtoml-statesync-temp-dir)
			if [[ -n "$2" ]]; then
				configtoml_statesync_temp_dir="$2"
				shift 2
			else
				configtoml_statesync_temp_dir="${CONFIGTOML_STATESYNC_TEMP_DIR}"
				shift
			fi
			;;
		--configtoml-statesync-chunk-request-timeout)
			if [[ -n "$2" ]]; then
				configtoml_statesync_chunk_request_timeout="$2"
				shift 2
			else
				configtoml_statesync_chunk_request_timeout="${CONFIGTOML_STATESYNC_CHUNK_REQUEST_TIMEOUT}"
				shift
			fi
			;;
		--configtoml-statesync-chunk-fetchers)
			if [[ -n "$2" ]]; then
				configtoml_statesync_chunk_fetchers="$2"
				shift 2
			else
				configtoml_statesync_chunk_fetchers="${CONFIGTOML_STATESYNC_CHUNK_FETCHERS}"
				shift
			fi
			;;
		# - Block Sync Configuration
		--configtoml-blocksync-version)
			if [[ -n "$2" ]]; then
				configtoml_blocksync_version="$2"
				shift 2
			else
				configtoml_blocksync_version="${CONFIGTOML_BLOCKSYNC_VERSION}"
				shift
			fi
			;;
		# - Consensus Configuration
		--configtoml-consensus-wal-file)
			if [[ -n "$2" ]]; then
				configtoml_consensus_wal_file="$2"
				shift 2
			else
				configtoml_consensus_wal_file="${CONFIGTOML_CONSENSUS_WAL_FILE}"
				shift
			fi
			;;
		--configtoml-consensus-timeout-propose)
			if [[ -n "$2" ]]; then
				configtoml_consensus_timeout_propose="$2"
				shift 2
			else
				configtoml_consensus_timeout_propose="${CONFIGTOML_CONSENSUS_TIMEOUT_PROPOSE}"
				shift
			fi
			;;
		--configtoml-consensus-timeout-propose-delta)
			if [[ -n "$2" ]]; then
				configtoml_consensus_timeout_propose_delta="$2"
				shift 2
			else
				configtoml_consensus_timeout_propose_delta="${CONFIGTOML_CONSENSUS_TIMEOUT_PROPOSE_DELTA}"
				shift
			fi
			;;
		--configtoml-consensus-timeout-prevote)
			if [[ -n "$2" ]]; then
				configtoml_consensus_timeout_prevote="$2"
				shift 2
			else
				configtoml_consensus_timeout_prevote="${CONFIGTOML_CONSENSUS_TIMEOUT_PREVOTE}"
				shift
			fi
			;;
		--configtoml-consensus-timeout-prevote-delta)
			if [[ -n "$2" ]]; then
				configtoml_consensus_timeout_prevote_delta="$2"
				shift 2
			else
				configtoml_consensus_timeout_prevote_delta="${CONFIGTOML_CONSENSUS_TIMEOUT_PREVOTE_DELTA}"
				shift
			fi
			;;
		--configtoml-consensus-timeout-precommit)
			if [[ -n "$2" ]]; then
				configtoml_consensus_timeout_precommit="$2"
				shift 2
			else
				configtoml_consensus_timeout_precommit="${CONFIGTOML_CONSENSUS_TIMEOUT_PRECOMMIT}"
				shift
			fi
			;;
		--configtoml-consensus-timeout-precommit-delta)
			if [[ -n "$2" ]]; then
				configtoml_consensus_timeout_precommit_delta="$2"
				shift 2
			else
				configtoml_consensus_timeout_precommit_delta="${CONFIGTOML_CONSENSUS_TIMEOUT_PRECOMMIT_DELTA}"
				shift
			fi
			;;
		--configtoml-consensus-timeout-commit)
			if [[ -n "$2" ]]; then
				configtoml_consensus_timeout_commit="$2"
				shift 2
			else
				configtoml_consensus_timeout_commit="${CONFIGTOML_CONSENSUS_TIMEOUT_COMMIT}"
				shift
			fi
			;;
		--configtoml-consensus-skip-timeout-commit)
			if [[ -n "$2" ]]; then
				configtoml_consensus_skip_timeout_commit="$2"
				shift 2
			else
				configtoml_consensus_skip_timeout_commit="${CONFIGTOML_CONSENSUS_SKIP_TIMEOUT_COMMIT}"
				shift
			fi
			;;
		--configtoml-consensus-double-sign-check-height)
			if [[ -n "$2" ]]; then
				configtoml_consensus_double_sign_check_height="$2"
				shift 2
			else
				configtoml_consensus_double_sign_check_height="${CONFIGTOML_CONSENSUS_DOUBLE_SIGN_CHECK_HEIGHT}"
				shift
			fi
			;;
		--configtoml-consensus-create-empty-blocks)
			if [[ -n "$2" ]]; then
				configtoml_consensus_create_empty_blocks="$2"
				shift 2
			else
				configtoml_consensus_create_empty_blocks="${CONFIGTOML_CONSENSUS_CREATE_EMPTY_BLOCKS}"
				shift
			fi
			;;
		--configtoml-consensus-create-empty-blocks-interval)
			if [[ -n "$2" ]]; then
				configtoml_consensus_create_empty_blocks_interval="$2"
				shift 2
			else
				configtoml_consensus_create_empty_blocks_interval="${CONFIGTOML_CONSENSUS_CREATE_EMPTY_BLOCKS_INTERVAL}"
				shift
			fi
			;;
		--configtoml-consensus-peer-gossip-sleep-duration)
			if [[ -n "$2" ]]; then
				configtoml_consensus_peer_gossip_sleep_duration="$2"
				shift 2
			else
				configtoml_consensus_peer_gossip_sleep_duration="${CONFIGTOML_CONSENSUS_PEER_GOSSIP_SLEEP_DURATION}"
				shift
			fi
			;;
		--configtoml-consensus-peer-gossip-intraloop-sleep-duration)
			if [[ -n "$2" ]]; then
				configtoml_consensus_peer_gossip_intraloop_sleep_duration="$2"
				shift 2
			else
				configtoml_consensus_peer_gossip_intraloop_sleep_duration="${CONFIGTOML_CONSENSUS_PEER_GOSSIP_INTRALOOP_SLEEP_DURATION}"
				shift
			fi
			;;
		--configtoml-consensus-peer-query-maj23-sleep-duration)
			if [[ -n "$2" ]]; then
				configtoml_consensus_peer_query_maj23_sleep_duration="$2"
				shift 2
			else
				configtoml_consensus_peer_query_maj23_sleep_duration="${CONFIGTOML_CONSENSUS_PEER_QUERY_MAJ23_SLEEP_DURATION}"
				shift
			fi
			;;
		# - Storage Configuration
		--configtoml-storage-discard-abci-responses)
			if [[ -n "$2" ]]; then
				configtoml_storage_discard_abci_responses="$2"
				shift 2
			else
				configtoml_storage_discard_abci_responses="${CONFIGTOML_STORAGE_DISCARD_ABCI_RESPONSES}"
				shift
			fi
			;;
		--configtoml-storage-experimental-db-key-layout)
			if [[ -n "$2" ]]; then
				configtoml_storage_experimental_db_key_layout="$2"
				shift 2
			else
				configtoml_storage_experimental_db_key_layout="${CONFIGTOML_STORAGE_EXPERIMENTAL_DB_KEY_LAYOUT}"
				shift
			fi
			;;
		--configtoml-storage-compact)
			if [[ -n "$2" ]]; then
				configtoml_storage_compact="$2"
				shift 2
			else
				configtoml_storage_compact="${CONFIGTOML_STORAGE_COMPACT}"
				shift
			fi
			;;
		--configtoml-storage-compaction-interval)
			if [[ -n "$2" ]]; then
				configtoml_storage_compaction_interval="$2"
				shift 2
			else
				configtoml_storage_compaction_interval="${CONFIGTOML_STORAGE_COMPACTION_INTERVAL}"
				shift
			fi
			;;
		--configtoml-storage-pruning-interval)
			if [[ -n "$2" ]]; then
				configtoml_storage_pruning_interval="$2"
				shift 2
			else
				configtoml_storage_pruning_interval="${CONFIGTOML_STORAGE_PRUNING_INTERVAL}"
				shift
			fi
			;;
		--configtoml-storage-pruning-data-companion-enabled)
			if [[ -n "$2" ]]; then
				configtoml_storage_pruning_data_companion_enabled="$2"
				shift 2
			else
				configtoml_storage_pruning_data_companion_enabled="${CONFIGTOML_STORAGE_PRUNING_DATA_COMPANION_ENABLED}"
				shift
			fi
			;;
		--configtoml-storage-pruning-data-companion-initial-block-retain-height)
			if [[ -n "$2" ]]; then
				configtoml_storage_pruning_data_companion_initial_block_retain_height="$2"
				shift 2
			else
				configtoml_storage_pruning_data_companion_initial_block_retain_height="${CONFIGTOML_STORAGE_PRUNING_DATA_COMPANION_INITIAL_BLOCK_RETAIN_HEIGHT}"
				shift
			fi
			;;
		--configtoml-storage-pruning-data-companion-initial-block-results-retain-height)
			if [[ -n "$2" ]]; then
				configtoml_storage_pruning_data_companion_initial_block_results_retain_height="$2"
				shift 2
			else
				configtoml_storage_pruning_data_companion_initial_block_results_retain_height="${CONFIGTOML_STORAGE_PRUNING_DATA_COMPANION_INITIAL_BLOCK_RESULTS_RETAIN_HEIGHT}"
				shift
			fi
			;;
		# - Transaction Indexer Configuration
		--configtoml-tx-index-indexer)
			if [[ -n "$2" ]]; then
				configtoml_tx_index_indexer="$2"
				shift 2
			else
				configtoml_tx_index_indexer="${CONFIGTOML_TX_INDEX_INDEXER}"
				shift
			fi
			;;
		--configtoml-tx-index-psql-conn)
			if [[ -n "$2" ]]; then
				configtoml_tx_index_psql_conn="$2"
				shift 2
			else
				configtoml_tx_index_psql_conn="${CONFIGTOML_TX_INDEX_PSQL_CONN}"
				shift
			fi
			;;
		# - Instrumentation Configuration
		--configtoml-instrumentation-prometheus)
			if [[ -n "$2" ]]; then
				configtoml_instrumentation_prometheus="$2"
				shift 2
			else
				configtoml_instrumentation_prometheus="${CONFIGTOML_INSTRUMENTATION_PROMETHEUS}"
				shift
			fi
			;;
		--configtoml-instrumentation-prometheus-listen-addr)
			if [[ -n "$2" ]]; then
				configtoml_instrumentation_prometheus_listen_addr="$2"
				shift 2
			else
				configtoml_instrumentation_prometheus_listen_addr="${CONFIGTOML_INSTRUMENTATION_PROMETHEUS_LISTEN_ADDR}"
				shift
			fi
			;;
		--configtoml-instrumentation-max-open-connections)
			if [[ -n "$2" ]]; then
				configtoml_instrumentation_max_open_connections="$2"
				shift 2
			else
				configtoml_instrumentation_max_open_connections="${CONFIGTOML_INSTRUMENTATION_MAX_OPEN_CONNECTIONS}"
				shift
			fi
			;;
		--configtoml-instrumentation-namespace)
			if [[ -n "$2" ]]; then
				configtoml_instrumentation_namespace="$2"
				shift 2
			else
				configtoml_instrumentation_namespace="${CONFIGTOML_INSTRUMENTATION_NAMESPACE}"
				shift
			fi
			;;
		*)
			log_error "Unknown option: $1"
			show_init_help
			return 1
			;;
		esac
	done

	# =========================================================================
	# [4] CONFIGURATION VALIDATION
	# =========================================================================
	# Validate node counts and apply network-specific defaults

	# Port overrides - placeholder to be replaced per-node during config generation
	PORT_DEFINED_BY_NODE="<PORT_DEFINED_BY_NODE>"
	clienttoml_chain_id="${network}-beacon-${chain_id}"
	clienttoml_node="tcp://localhost:$PORT_DEFINED_BY_NODE"
	apptoml_beacon_kit_engine_rpc_dial_url="http://localhost:$PORT_DEFINED_BY_NODE"
	apptoml_beacon_kit_node_api_address="0.0.0.0:$PORT_DEFINED_BY_NODE"
	configtoml_proxy_app="tcp://127.0.0.1:$PORT_DEFINED_BY_NODE"
	configtoml_rpc_laddr="tcp://127.0.0.1:$PORT_DEFINED_BY_NODE"
	configtoml_p2p_laddr="tcp://0.0.0.0:$PORT_DEFINED_BY_NODE"
	configtoml_instrumentation_prometheus_listen_addr="$PORT_DEFINED_BY_NODE"
	configtoml_moniker="$moniker"

	# Validate validator count - must be a positive integer
	if ! [[ "$validators" =~ ^[0-9]+$ ]] || [[ "$validators" -le 0 ]]; then
		log_warn "validators is not a valid positive integer. defaulting to 1"
		validators=1
	fi

	total_nodes=$(((${validators:-1} + ${full_nodes:-0} + ${pruned_nodes:-0})))
	# devnet defaults
	if [[ "${network}" == "${CHAIN_NAME_DEVNET}" ]]; then
		if [[ ${total_nodes} -eq 0 ]]; then
			total_nodes=$(((${validators} + ${full_nodes} + ${pruned_nodes})))
			log_warn "total nodes is 0. defaulting to ${validators} validator, ${full_nodes} rpc full node, and ${pruned_nodes} rpc pruned node"
		fi
	fi
	# testnet defaults
	# TODO
	# mainnet defaults
	# TODO

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
	echo ""

	# =========================================================================
	# [5] DIRECTORY STRUCTURE SETUP
	# =========================================================================
	# Create all required beranodes directory structure

	ensure_dir_exists "${BERANODES_PATH}" "beranode directory" || return 1
	ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_BIN}" "beranode binary directory" || return 1
	ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_TMP}" "beranode temporary directory" || return 1
	ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_LOGS}" "beranode log directory" || return 1
	ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_NODES}" "beranode nodes directory" || return 1
	ensure_dir_exists "${BERANODES_PATH}${BERANODES_PATH_RUNS}" "beranode runs directory" || return 1

	# =========================================================================
	# [6] BINARY VERIFICATION
	# =========================================================================
	# Verify beacond and bera-reth binaries exist and are executable

  if [[ "$mode" == "local" ]]; then
    missing_binaries=0
    # - beacond
    is_beacond_installed=false
    if [[ ! -x "${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BEACONKIT}" ]]; then
      log_warn "Binary '${BIN_BEACONKIT}' not found or not executable: ${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BEACONKIT}"
    else
      # Check if 'beacond version' command executes successfully
      beacon_version="$("${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BEACONKIT}" version 2>/dev/null)"
      if [[ $? -eq 0 ]]; then
        log_success "'${BIN_BEACONKIT} version' works as expected."
        log_info "${BIN_BEACONKIT} version:\n${beacon_version}\n"
        is_beacond_installed=true
      else
        log_error "'${BIN_BEACONKIT} version' did not work as expected."
      fi
    fi

    if [[ "$is_beacond_installed" == false ]]; then
      log_info "Installing beacond binary..."
      download_beranodes_binary \
        --config-dir "${BERANODES_PATH}" \
        --binary-to-download "${BIN_BEACONKIT}" \
        --version-tag "latest"
    fi

    # - berareth
    is_berareth_installed=false
    if [[ ! -x "${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BERARETH}" ]]; then
      log_warn "Binary '${BIN_BERARETH}' not found or not executable: ${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BERARETH}"
      missing_binaries=1
    else
      # Check if 'berareth version' command executes successfully
      bera_reth_version="$("${BERANODES_PATH}${BERANODES_PATH_BIN}/${BIN_BERARETH}" --version 2>/dev/null)"
      if [[ $? -eq 0 ]]; then
        log_success "'${BIN_BERARETH} --version' works as expected."
        log_info "${BIN_BERARETH} version:\n${bera_reth_version}\n"
        is_berareth_installed=true
      else
        log_error "'${BIN_BERARETH} --version' did not work as expected."
      fi
    fi

    if [[ "$is_berareth_installed" == false ]]; then
      log_info "Installing bera-reth binary..."
      download_beranodes_binary \
        --config-dir "${BERANODES_PATH}" \
        --binary-to-download "${BIN_BERARETH}" \
        --version-tag "latest"
    fi

  elif [[ "$mode" == "docker" ]]; then
    # Check for existing bera-reth docker image
    bera_reth_image=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'bera-reth-docker' || true)
    if [[ -n "$bera_reth_image" ]]; then
      bera_reth_tag=$(echo "$bera_reth_image" | awk -F: '{print $2}')
      log_success "Found existing bera-reth docker image: $bera_reth_image (tag: $bera_reth_tag)"
    else
      log_info "No bera-reth-docker image found. Downloading '${docker_tag_berareth}'..."
      download_beranodes_docker_image --binary-to-download "${BIN_BERARETH}" --version-tag "${docker_tag_berareth}"
    fi

    # Check for existing beacond docker image
    beacond_image=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'beacond-docker' || true)
    if [[ -n "$beacond_image" ]]; then
      beacond_tag=$(echo "$beacond_image" | awk -F: '{print $2}')
      log_success "Found existing beacond docker image: $beacond_image (tag: $beacond_tag)"
    else
      log_info "No beacond-docker image found. Downloading '${docker_tag_beacond}..."
      download_beranodes_docker_image --binary-to-download "${BIN_BEACONKIT}" --version-tag "${docker_tag_beacond}"
    fi
  fi

	# =========================================================================
	# [7] WALLET GENERATION
	# =========================================================================
	# Wallet generation or use existing
	if [[ -n "${wallet_address:-}" ]]; then
		# --wallet-address was supplied; validate it and optionally use private key if provided

		# Validate that the address starts with 0x and is 42 chars (including 0x)
		if [[ ! "${wallet_address}" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
			log_error "Provided wallet address (${wallet_address}) is not in the correct format (should start with 0x and be 42 characters long)."
			return 1
		else
			log_success "Using provided wallet address:\n${wallet_address}"
		fi

		# Optionally read wallet private key
		if [[ -n "${wallet_private_key:-}" ]]; then
			# Use cast to derive address from the provided private key and compare
			if command -v cast >/dev/null 2>&1; then
				derived_address=$(cast wallet address "${wallet_private_key}" 2>/dev/null)
				if [[ "$derived_address" == "${wallet_address}" ]]; then
					log_success "Using provided wallet private key. Address matches provided wallet address."
				else
					log_error "Provided private key does NOT match the provided wallet address.\nProvided address: ${wallet_address}\nDerived address from private key: ${derived_address}\nPlease check both your private key and wallet address."
					return 1
				fi
			else
				log_warn "cast command not found. Skipping private key and address validation."
				log_success "Using provided wallet private key."
			fi
		else
			wallet_private_key=""
			log_warn "No wallet private key supplied; proceeding with only public address."
		fi
	else
		# No wallet address supplied, must generate both
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
	fi

	# =========================================================================
	# [8] CONFIGURATION FILE GENERATION
	# =========================================================================
	# Create beranodes.config.json with all node configurations

	print_header "Creating base beranodes.config.json file..."

	# Create beranodes.config.json with settings as JSON
	config_json_path="${BERANODES_PATH}/beranodes.config.json"
	# Check if the configuration file already exists, and don't overwrite it
	local_config_exists=false
	if [[ -f "${config_json_path}" ]]; then
		log_warn "Configuration already exists at ${config_json_path}. Will not overwrite."
		local_config_exists=true
		# Prompt the user to overwrite or use the existing config
		while true; do
			echo -e "${YELLOW}A configuration file already exists at ${config_json_path}.${RESET}"
			read -p "Do you want to overwrite it? [y/n]: " yn
			case "$yn" in
			[Yy]*)
				log_warn "Overwriting existing configuration file at ${config_json_path}."
				rm -f "${config_json_path}"
				log_info "Previous configuration file removed."
				local_config_exists=false
				break
				;;
			[Nn]* | "")
				log_success "Using existing configuration file at ${config_json_path}."
				break
				;;
			*)
				echo "Please answer yes (y) or no (n)."
				;;
			esac
		done
	fi

	# Create all new setup
	if [[ "${local_config_exists}" = false ]]; then
		log_info "Creating new configuration file: ${config_json_path}"

		nodes_validators=""
		node_ethrpc_port=${DEFAULT_CL_ETHRPC_PORT}
		node_ethp2p_port=${DEFAULT_CL_ETHP2P_PORT}
		node_ethproxy_port=${DEFAULT_CL_ETHPROXY_PORT}
		node_el_ethrpc_port=${DEFAULT_EL_ETHRPC_PORT}
		node_el_ws_port=${DEFAULT_EL_WS_PORT}
		node_el_authrpc_port=${DEFAULT_EL_AUTHRPC_PORT}
		node_el_eth_port=${DEFAULT_DEFAULT_EL_ETH_PORT}
		node_el_prometheus_port=${DEFAULT_EL_PROMETHEUS_PORT}
		node_cl_prometheus_port=${DEFAULT_CL_PROMETHEUS_PORT}
		node_beacond_node_port=${DEFAULT_BEACON_NODE_API_PORT}
		node_port_increment=${DEFAULT_PORT_INCREMENT}
		node_configtoml_grpc_laddr="${DEFAULT_GRPC_LADDR_PORT}"
		node_configtoml_grpc_privileged_laddr="${DEFAULT_GRPC_PRIVILEGED_LADDR_PORT}"
		current_node_ethrpc_port=${node_ethrpc_port}
		current_node_ethp2p_port=${node_ethp2p_port}
		current_node_ethproxy_port=${node_ethproxy_port}
		current_node_el_ethrpc_port=${node_el_ethrpc_port}
		current_node_el_ws_port=${node_el_ws_port}
		current_node_el_authrpc_port=${node_el_authrpc_port}
		current_node_el_eth_port=${node_el_eth_port}
		current_node_el_prometheus_port=${node_el_prometheus_port}
		current_node_cl_prometheus_port=${node_cl_prometheus_port}
		current_node_beacond_node_port=${node_beacond_node_port}
		current_node_configtoml_grpc_laddr=${node_configtoml_grpc_laddr}
		current_node_configtoml_grpc_privileged_laddr=${node_configtoml_grpc_privileged_laddr}

		if [[ ${validators} -gt 0 ]]; then
			for i in $(seq 1 ${validators}); do
				if [[ $i -eq ${validators} ]]; then
					nodes_validators="${nodes_validators}{
						\"role\": \"validator\",
						\"moniker\": \"${moniker}-val-$(($i - 1))\",
						\"network\": \"${network}\",
						\"wallet_address\": \"${wallet_address}\",
						\"ethrpc_port\": ${current_node_ethrpc_port},
						\"ethp2p_port\": ${current_node_ethp2p_port},
						\"ethproxy_port\": ${current_node_ethproxy_port},
						\"el_ethrpc_port\": ${current_node_el_ethrpc_port},
            \"el_ws_port\": ${current_node_el_ws_port},
						\"el_authrpc_port\": ${current_node_el_authrpc_port},
						\"el_eth_port\": ${current_node_el_eth_port},
						\"el_prometheus_port\": ${current_node_el_prometheus_port},
						\"cl_prometheus_port\": ${current_node_cl_prometheus_port},
            \"beacond_node_port\": ${current_node_beacond_node_port},
            \"configtoml_grpc_laddr\": ${current_node_configtoml_grpc_laddr},
            \"configtoml_grpc_privileged_laddr\": ${current_node_configtoml_grpc_privileged_laddr}
					}"
				else
					nodes_validators="${nodes_validators}{
						\"role\": \"validator\",
						\"moniker\": \"${moniker}-val-$(($i - 1))\",
						\"network\": \"${network}\",
						\"wallet_address\": \"${wallet_address}\",
						\"ethrpc_port\": ${current_node_ethrpc_port},
						\"ethp2p_port\": ${current_node_ethp2p_port},
						\"ethproxy_port\": ${current_node_ethproxy_port},
						\"el_ethrpc_port\": ${current_node_el_ethrpc_port},
            \"el_ws_port\": ${current_node_el_ws_port},
						\"el_authrpc_port\": ${current_node_el_authrpc_port},
						\"el_eth_port\": ${current_node_el_eth_port},
						\"el_prometheus_port\": ${current_node_el_prometheus_port},
						\"cl_prometheus_port\": ${current_node_cl_prometheus_port},
            \"beacond_node_port\": ${current_node_beacond_node_port},
            \"configtoml_grpc_laddr\": ${current_node_configtoml_grpc_laddr},
            \"configtoml_grpc_privileged_laddr\": ${current_node_configtoml_grpc_privileged_laddr}
					},"
				fi

				if [[ "${docker_mode}" = false ]]; then
					current_node_ethrpc_port=$((current_node_ethrpc_port + 10000))
					current_node_ethp2p_port=$((current_node_ethp2p_port + 10000))
					current_node_ethproxy_port=$((current_node_ethproxy_port + 10000))
					current_node_el_ethrpc_port=$((current_node_el_ethrpc_port + node_port_increment))
					current_node_el_ws_port=$((current_node_el_ws_port + node_port_increment))
					current_node_el_authrpc_port=$((current_node_el_authrpc_port + 100))
					current_node_el_eth_port=$((current_node_el_eth_port + node_port_increment))
					current_node_el_prometheus_port=$((current_node_el_prometheus_port + node_port_increment))
					current_node_cl_prometheus_port=$((current_node_cl_prometheus_port + 10000))
					current_node_beacond_node_port=$((current_node_beacond_node_port + 100))
					current_node_configtoml_grpc_laddr=$((current_node_configtoml_grpc_laddr + 100))
					current_node_configtoml_grpc_privileged_laddr=$((current_node_configtoml_grpc_privileged_laddr + 100))
				fi
			done
		fi

		nodes_full_nodes=""
		if [[ ${full_nodes} -gt 0 ]]; then
			for i in $(seq 1 ${full_nodes}); do
				if [[ $i -eq ${full_nodes} ]]; then
					nodes_full_nodes="${nodes_full_nodes}{
						\"role\": \"rpc-full\",
						\"moniker\": \"${moniker}-rpc-full-$(($i - 1))\",
						\"network\": \"${network}\",
						\"wallet_address\": \"${wallet_address}\",
						\"ethrpc_port\": ${current_node_ethrpc_port},
						\"ethp2p_port\": ${current_node_ethp2p_port},
						\"ethproxy_port\": ${current_node_ethproxy_port},
						\"el_ethrpc_port\": ${current_node_el_ethrpc_port},
            \"el_ws_port\": ${current_node_el_ws_port},
						\"el_authrpc_port\": ${current_node_el_authrpc_port},
						\"el_eth_port\": ${current_node_el_eth_port},
						\"el_prometheus_port\": ${current_node_el_prometheus_port},
						\"cl_prometheus_port\": ${current_node_cl_prometheus_port},
            \"beacond_node_port\": ${current_node_beacond_node_port},
            \"configtoml_grpc_laddr\": ${current_node_configtoml_grpc_laddr},
            \"configtoml_grpc_privileged_laddr\": ${current_node_configtoml_grpc_privileged_laddr}
					}"
				else
					nodes_full_nodes="${nodes_full_nodes}{
						\"role\": \"rpc-full\",
						\"moniker\": \"${moniker}-rpc-full-$(($i - 1))\",
						\"network\": \"${network}\",
						\"wallet_address\": \"${wallet_address}\",
						\"ethrpc_port\": ${current_node_ethrpc_port},
						\"ethp2p_port\": ${current_node_ethp2p_port},
						\"ethproxy_port\": ${current_node_ethproxy_port},
						\"el_ethrpc_port\": ${current_node_el_ethrpc_port},
            \"el_ws_port\": ${current_node_el_ws_port},
						\"el_authrpc_port\": ${current_node_el_authrpc_port},
						\"el_eth_port\": ${current_node_el_eth_port},
						\"el_prometheus_port\": ${current_node_el_prometheus_port},
						\"cl_prometheus_port\": ${current_node_cl_prometheus_port},
            \"beacond_node_port\": ${current_node_beacond_node_port},
            \"configtoml_grpc_laddr\": ${current_node_configtoml_grpc_laddr},
            \"configtoml_grpc_privileged_laddr\": ${current_node_configtoml_grpc_privileged_laddr}
					},"
				fi

				if [[ "${docker_mode}" = false ]]; then
					current_node_ethrpc_port=$((current_node_ethrpc_port + 10000))
					current_node_ethp2p_port=$((current_node_ethp2p_port + 10000))
					current_node_ethproxy_port=$((current_node_ethproxy_port + 10000))
					current_node_el_ethrpc_port=$((current_node_el_ethrpc_port + node_port_increment))
					current_node_el_ws_port=$((current_node_el_ws_port + node_port_increment))
					current_node_el_authrpc_port=$((current_node_el_authrpc_port + 100))
					current_node_el_eth_port=$((current_node_el_eth_port + node_port_increment))
					current_node_el_prometheus_port=$((current_node_el_prometheus_port + node_port_increment))
					current_node_cl_prometheus_port=$((current_node_cl_prometheus_port + 10000))
					current_node_beacond_node_port=$((current_node_beacond_node_port + 100))
					current_node_configtoml_grpc_laddr=$((current_node_configtoml_grpc_laddr + 100))
					current_node_configtoml_grpc_privileged_laddr=$((current_node_configtoml_grpc_privileged_laddr + 100))
				fi
			done
		fi

		nodes_pruned_nodes=""
		if [[ ${pruned_nodes} -gt 0 ]]; then
			for i in $(seq 1 ${pruned_nodes}); do
				if [[ $i -eq ${pruned_nodes} ]]; then
					nodes_pruned_nodes="${nodes_pruned_nodes}{
						\"role\": \"rpc-pruned\",
						\"moniker\": \"${moniker}-rpc-pruned-$(($i - 1))\",
						\"network\": \"${network}\",
						\"wallet_address\": \"${wallet_address}\",
						\"ethrpc_port\": ${current_node_ethrpc_port},
						\"ethp2p_port\": ${current_node_ethp2p_port},
						\"ethproxy_port\": ${current_node_ethproxy_port},
						\"el_ethrpc_port\": ${current_node_el_ethrpc_port},
						\"el_ws_port\": ${current_node_el_ws_port},
						\"el_authrpc_port\": ${current_node_el_authrpc_port},
						\"el_eth_port\": ${current_node_el_eth_port},
						\"el_prometheus_port\": ${current_node_el_prometheus_port},
						\"cl_prometheus_port\": ${current_node_cl_prometheus_port},
            \"beacond_node_port\": ${current_node_beacond_node_port},
            \"configtoml_grpc_laddr\": ${current_node_configtoml_grpc_laddr},
            \"configtoml_grpc_privileged_laddr\": ${current_node_configtoml_grpc_privileged_laddr}
					}"
				else
					nodes_pruned_nodes="${nodes_pruned_nodes}{
						\"role\": \"rpc-pruned\",
						\"moniker\": \"${moniker}-rpc-pruned-$(($i - 1))\",
						\"network\": \"${network}\",
						\"wallet_address\": \"${wallet_address}\",
						\"ethrpc_port\": ${current_node_ethrpc_port},
						\"ethp2p_port\": ${current_node_ethp2p_port},
						\"ethproxy_port\": ${current_node_ethproxy_port},
						\"el_ethrpc_port\": ${current_node_el_ethrpc_port},
						\"el_ws_port\": ${current_node_el_ws_port},
						\"el_authrpc_port\": ${current_node_el_authrpc_port},
						\"el_eth_port\": ${current_node_el_eth_port},
						\"el_prometheus_port\": ${current_node_el_prometheus_port},
						\"cl_prometheus_port\": ${current_node_cl_prometheus_port},
            \"beacond_node_port\": ${current_node_beacond_node_port},
            \"configtoml_grpc_laddr\": ${current_node_configtoml_grpc_laddr},
            \"configtoml_grpc_privileged_laddr\": ${current_node_configtoml_grpc_privileged_laddr}
					},"
				fi

				if [[ "${docker_mode}" = false ]]; then
					current_node_ethrpc_port=$((current_node_ethrpc_port + 10000))
					current_node_ethp2p_port=$((current_node_ethp2p_port + 10000))
					current_node_ethproxy_port=$((current_node_ethproxy_port + 10000))
					current_node_el_ethrpc_port=$((current_node_el_ethrpc_port + node_port_increment))
					current_node_el_ws_port=$((current_node_el_ws_port + node_port_increment))
					current_node_el_authrpc_port=$((current_node_el_authrpc_port + 100))
					current_node_el_eth_port=$((current_node_el_eth_port + node_port_increment))
					current_node_el_prometheus_port=$((current_node_el_prometheus_port + node_port_increment))
					current_node_cl_prometheus_port=$((current_node_cl_prometheus_port + 10000))
					current_node_beacond_node_port=$((current_node_beacond_node_port + 100))
					current_node_configtoml_grpc_laddr=$((current_node_configtoml_grpc_laddr + 100))
					current_node_configtoml_grpc_privileged_laddr=$((current_node_configtoml_grpc_privileged_laddr + 100))
				fi
			done
		fi

		# Combine all defined node groups into a properly formatted JSON nodes array.
		nodes_combined=""

		# Prepare a list of all potential node groups. Add new ones here if needed.
		all_groups=("$nodes_validators" "$nodes_full_nodes" "$nodes_pruned_nodes")
		for group in "${all_groups[@]}"; do
			if [[ -n "$group" ]]; then
				if [[ -z "$nodes_combined" ]]; then
					nodes_combined="$group"
				else
					nodes_combined="${nodes_combined},${group}"
				fi
			fi
		done

		clienttoml="{
      \"chain_id\": \"${clienttoml_chain_id}\",
      \"keyring_backend\": \"${clienttoml_keyring_backend}\",
      \"keyring_default_keyname\": \"${clienttoml_keyring_default_keyname}\",
      \"output\": \"${clienttoml_output}\",
      \"node\": \"${clienttoml_node}\",
      \"broadcast_mode\": \"${clienttoml_broadcast_mode}\",
      \"grpc_address\": \"${clienttoml_grpc_address}\",
      \"grpc_insecure\": \"${clienttoml_grpc_insecure}\"
    }"
		apptoml="{
      \"pruning\": \"${apptoml_pruning}\",
      \"pruning_keep_recent\": \"${apptoml_pruning_keep_recent}\",
      \"pruning_interval\": \"${apptoml_pruning_interval}\",
      \"halt_height\": \"${apptoml_halt_height}\",
      \"halt_time\": \"${apptoml_halt_time}\",
      \"min_retain_blocks\": \"${apptoml_min_retain_blocks}\",
      \"inter_block_cache\": \"${apptoml_inter_block_cache}\",
      \"iavl_cache_size\": \"${apptoml_iavl_cache_size}\",
      \"iavl_disable_fastnode\": \"${apptoml_iavl_disable_fastnode}\",
      \"app_db_backend\": \"${apptoml_app_db_backend}\",
      \"telemetry_service_name\": \"${apptoml_telemetry_service_name}\",
      \"telemetry_enabled\": \"${apptoml_telemetry_enabled}\",
      \"telemetry_enable_hostname\": \"${apptoml_telemetry_enable_hostname}\",
      \"telemetry_enable_hostname_label\": \"${apptoml_telemetry_enable_hostname_label}\",
      \"telemetry_enable_service_label\": \"${apptoml_telemetry_enable_service_label}\",
      \"telemetry_prometheus_retention_time\": \"${apptoml_telemetry_prometheus_retention_time}\",
      \"telemetry_global_labels\": \"${apptoml_telemetry_global_labels}\",
      \"telemetry_metrics_sink\": \"${apptoml_telemetry_metrics_sink}\",
      \"telemetry_statsd_addr\": \"${apptoml_telemetry_statsd_addr}\",
      \"telemetry_datadog_hostname\": \"${apptoml_telemetry_datadog_hostname}\",
      \"beacon_kit_chain_spec\": \"${apptoml_beacon_kit_chain_spec}\",
      \"beacon_kit_chain_spec_file\": \"${apptoml_beacon_kit_chain_spec_file}\",
      \"beacon_kit_shutdown_timeout\": \"${apptoml_beacon_kit_shutdown_timeout}\",
      \"beacon_kit_engine_rpc_dial_url\": \"${apptoml_beacon_kit_engine_rpc_dial_url}\",
      \"beacon_kit_engine_rpc_timeout\": \"${apptoml_beacon_kit_engine_rpc_timeout}\",
      \"beacon_kit_engine_rpc_retry_interval\": \"${apptoml_beacon_kit_engine_rpc_retry_interval}\",
      \"beacon_kit_engine_rpc_max_retry_interval\": \"${apptoml_beacon_kit_engine_rpc_max_retry_interval}\",
      \"beacon_kit_engine_rpc_startup_check_interval\": \"${apptoml_beacon_kit_engine_rpc_startup_check_interval}\",
      \"beacon_kit_engine_rpc_jwt_refresh_interval\": \"${apptoml_beacon_kit_engine_rpc_jwt_refresh_interval}\",
      \"beacon_kit_engine_jwt_secret_path\": \"${apptoml_beacon_kit_engine_jwt_secret_path}\",
      \"beacon_kit_logger_time_format\": \"${apptoml_beacon_kit_logger_time_format}\",
      \"beacon_kit_logger_log_level\": \"${apptoml_beacon_kit_logger_log_level}\",
      \"beacon_kit_logger_style\": \"${apptoml_beacon_kit_logger_style}\",
      \"beacon_kit_kzg_trusted_setup_path\": \"${apptoml_beacon_kit_kzg_trusted_setup_path}\",
      \"beacon_kit_kzg_implementation\": \"${apptoml_beacon_kit_kzg_implementation}\",
      \"beacon_kit_payload_builder_enabled\": \"${apptoml_beacon_kit_payload_builder_enabled}\",
      \"beacon_kit_payload_builder_suggested_fee_recipient\": \"${apptoml_beacon_kit_payload_builder_suggested_fee_recipient}\",
      \"beacon_kit_payload_builder_payload_timeout\": \"${apptoml_beacon_kit_payload_builder_payload_timeout}\",
      \"beacon_kit_validator_graffiti\": \"${apptoml_beacon_kit_validator_graffiti}\",
      \"beacon_kit_validator_availability_window\": \"${apptoml_beacon_kit_validator_availability_window}\",
      \"beacon_kit_node_api_enabled\": \"${apptoml_beacon_kit_node_api_enabled}\",
      \"beacon_kit_node_api_address\": \"${apptoml_beacon_kit_node_api_address}\",
      \"beacon_kit_node_api_logging\": \"${apptoml_beacon_kit_node_api_logging}\"
    }"
		configtoml="{
      \"version\": \"${configtoml_version}\",
      \"proxy_app\": \"${configtoml_proxy_app}\",
      \"moniker\": \"${configtoml_moniker}\",
      \"db_backend\": \"${configtoml_db_backend}\",
      \"db_dir\": \"${configtoml_db_dir}\",
      \"log_level\": \"${configtoml_log_level}\",
      \"log_format\": \"${configtoml_log_format}\",
      \"genesis_file\": \"${configtoml_genesis_file}\",
      \"priv_validator_key_file\": \"${configtoml_priv_validator_key_file}\",
      \"priv_validator_state_file\": \"${configtoml_priv_validator_state_file}\",
      \"priv_validator_laddr\": \"${configtoml_priv_validator_laddr}\",
      \"node_key_file\": \"${configtoml_node_key_file}\",
      \"abci\": \"${configtoml_abci}\",
      \"filter_peers\": \"${configtoml_filter_peers}\",
      \"rpc_laddr\": \"${configtoml_rpc_laddr}\",
      \"rpc_unsafe\": \"${configtoml_rpc_unsafe}\",
      \"rpc_cors_allowed_origins\": \"${configtoml_rpc_cors_allowed_origins}\",
      \"rpc_cors_allowed_methods\": \"${configtoml_rpc_cors_allowed_methods}\",
      \"rpc_cors_allowed_headers\": \"${configtoml_rpc_cors_allowed_headers}\",
      \"rpc_max_open_connections\": \"${configtoml_rpc_max_open_connections}\",
      \"rpc_max_subscription_clients\": \"${configtoml_rpc_max_subscription_clients}\",
      \"rpc_max_subscriptions_per_client\": \"${configtoml_rpc_max_subscriptions_per_client}\",
      \"rpc_experimental_subscription_buffer_size\": \"${configtoml_rpc_experimental_subscription_buffer_size}\",
      \"rpc_experimental_websocket_write_buffer_size\": \"${configtoml_rpc_experimental_websocket_write_buffer_size}\",
      \"rpc_experimental_close_on_slow_client\": \"${configtoml_rpc_experimental_close_on_slow_client}\",
      \"rpc_timeout_broadcast_tx_commit\": \"${configtoml_rpc_timeout_broadcast_tx_commit}\",
      \"rpc_max_request_batch_size\": \"${configtoml_rpc_max_request_batch_size}\",
      \"rpc_max_body_bytes\": \"${configtoml_rpc_max_body_bytes}\",
      \"rpc_max_header_bytes\": \"${configtoml_rpc_max_header_bytes}\",
      \"rpc_tls_cert_file\": \"${configtoml_rpc_tls_cert_file}\",
      \"rpc_tls_key_file\": \"${configtoml_rpc_tls_key_file}\",
      \"rpc_pprof_laddr\": \"${configtoml_rpc_pprof_laddr}\",
      \"grpc_laddr\": \"${configtoml_grpc_laddr}\",
      \"grpc_version_service_enabled\": \"${configtoml_grpc_version_service_enabled}\",
      \"grpc_block_service_enabled\": \"${configtoml_grpc_block_service_enabled}\",
      \"grpc_block_results_service_enabled\": \"${configtoml_grpc_block_results_service_enabled}\",
      \"grpc_privileged_laddr\": \"${configtoml_grpc_privileged_laddr}\",
      \"grpc_privileged_pruning_service_enabled\": \"${configtoml_grpc_privileged_pruning_service_enabled}\",
      \"p2p_laddr\": \"${configtoml_p2p_laddr}\",
      \"p2p_external_address\": \"${configtoml_p2p_external_address}\",
      \"p2p_seeds\": \"${configtoml_p2p_seeds}\",
      \"p2p_persistent_peers\": \"${configtoml_p2p_persistent_peers}\",
      \"p2p_addr_book_file\": \"${configtoml_p2p_addr_book_file}\",
      \"p2p_addr_book_strict\": \"${configtoml_p2p_addr_book_strict}\",
      \"p2p_max_num_inbound_peers\": \"${configtoml_p2p_max_num_inbound_peers}\",
      \"p2p_max_num_outbound_peers\": \"${configtoml_p2p_max_num_outbound_peers}\",
      \"p2p_unconditional_peer_ids\": \"${configtoml_p2p_unconditional_peer_ids}\",
      \"p2p_persistent_peers_max_dial_period\": \"${configtoml_p2p_persistent_peers_max_dial_period}\",
      \"p2p_flush_throttle_timeout\": \"${configtoml_p2p_flush_throttle_timeout}\",
      \"p2p_max_packet_msg_payload_size\": \"${configtoml_p2p_max_packet_msg_payload_size}\",
      \"p2p_send_rate\": \"${configtoml_p2p_send_rate}\",
      \"p2p_recv_rate\": \"${configtoml_p2p_recv_rate}\",
      \"p2p_pex\": \"${configtoml_p2p_pex}\",
      \"p2p_seed_mode\": \"${configtoml_p2p_seed_mode}\",
      \"p2p_private_peer_ids\": \"${configtoml_p2p_private_peer_ids}\",
      \"p2p_allow_duplicate_ip\": \"${configtoml_p2p_allow_duplicate_ip}\",
      \"p2p_handshake_timeout\": \"${configtoml_p2p_handshake_timeout}\",
      \"p2p_dial_timeout\": \"${configtoml_p2p_dial_timeout}\",
      \"mempool_type\": \"${configtoml_mempool_type}\",
      \"mempool_recheck\": \"${configtoml_mempool_recheck}\",
      \"mempool_recheck_timeout\": \"${configtoml_mempool_recheck_timeout}\",
      \"mempool_broadcast\": \"${configtoml_mempool_broadcast}\",
      \"mempool_wal_dir\": \"${configtoml_mempool_wal_dir}\",
      \"mempool_size\": \"${configtoml_mempool_size}\",
      \"mempool_max_tx_bytes\": \"${configtoml_mempool_max_tx_bytes}\",
      \"mempool_max_txs_bytes\": \"${configtoml_mempool_max_txs_bytes}\",
      \"mempool_cache_size\": \"${configtoml_mempool_cache_size}\",
      \"mempool_keep_invalid_txs_in_cache\": \"${configtoml_mempool_keep_invalid_txs_in_cache}\",
      \"mempool_experimental_max_gossip_connections_to_persistent_peers\": \"${configtoml_mempool_experimental_max_gossip_connections_to_persistent_peers}\",
      \"mempool_experimental_max_gossip_connections_to_non_persistent_peers\": \"${configtoml_mempool_experimental_max_gossip_connections_to_non_persistent_peers}\",
      \"statesync_enable\": \"${configtoml_statesync_enable}\",
      \"statesync_rpc_servers\": \"${configtoml_statesync_rpc_servers}\",
      \"statesync_trust_height\": \"${configtoml_statesync_trust_height}\",
      \"statesync_trust_hash\": \"${configtoml_statesync_trust_hash}\",
      \"statesync_trust_period\": \"${configtoml_statesync_trust_period}\",
      \"statesync_discovery_time\": \"${configtoml_statesync_discovery_time}\",
      \"statesync_temp_dir\": \"${configtoml_statesync_temp_dir}\",
      \"statesync_chunk_request_timeout\": \"${configtoml_statesync_chunk_request_timeout}\",
      \"statesync_chunk_fetchers\": \"${configtoml_statesync_chunk_fetchers}\",
      \"blocksync_version\": \"${configtoml_blocksync_version}\",
      \"consensus_wal_file\": \"${configtoml_consensus_wal_file}\",
      \"consensus_timeout_propose\": \"${configtoml_consensus_timeout_propose}\",
      \"consensus_timeout_propose_delta\": \"${configtoml_consensus_timeout_propose_delta}\",
      \"consensus_timeout_prevote\": \"${configtoml_consensus_timeout_prevote}\",
      \"consensus_timeout_prevote_delta\": \"${configtoml_consensus_timeout_prevote_delta}\",
      \"consensus_timeout_precommit\": \"${configtoml_consensus_timeout_precommit}\",
      \"consensus_timeout_precommit_delta\": \"${configtoml_consensus_timeout_precommit_delta}\",
      \"consensus_timeout_commit\": \"${configtoml_consensus_timeout_commit}\",
      \"consensus_skip_timeout_commit\": \"${configtoml_consensus_skip_timeout_commit}\",
      \"consensus_double_sign_check_height\": \"${configtoml_consensus_double_sign_check_height}\",
      \"consensus_create_empty_blocks\": \"${configtoml_consensus_create_empty_blocks}\",
      \"consensus_create_empty_blocks_interval\": \"${configtoml_consensus_create_empty_blocks_interval}\",
      \"consensus_peer_gossip_sleep_duration\": \"${configtoml_consensus_peer_gossip_sleep_duration}\",
      \"consensus_peer_gossip_intraloop_sleep_duration\": \"${configtoml_consensus_peer_gossip_intraloop_sleep_duration}\",
      \"consensus_peer_query_maj23_sleep_duration\": \"${configtoml_consensus_peer_query_maj23_sleep_duration}\",
      \"storage_discard_abci_responses\": \"${configtoml_storage_discard_abci_responses}\",
	    \"storage_experimental_db_key_layout\": \"${configtoml_storage_experimental_db_key_layout}\",
      \"storage_compact\": \"${configtoml_storage_compact}\",
      \"storage_compaction_interval\": \"${configtoml_storage_compaction_interval}\",
      \"storage_pruning_interval\": \"${configtoml_storage_pruning_interval}\",
      \"storage_pruning_data_companion_enabled\": \"${configtoml_storage_pruning_data_companion_enabled}\",
      \"storage_pruning_data_companion_initial_block_retain_height\": \"${configtoml_storage_pruning_data_companion_initial_block_retain_height}\",
      \"storage_pruning_data_companion_initial_block_results_retain_height\": \"${configtoml_storage_pruning_data_companion_initial_block_results_retain_height}\",
      \"tx_index_indexer\": \"${configtoml_tx_index_indexer}\",
      \"tx_index_psql_conn\": \"${configtoml_tx_index_psql_conn}\",
      \"instrumentation_prometheus\": \"${configtoml_instrumentation_prometheus}\",
      \"instrumentation_prometheus_listen_addr\": \"${configtoml_instrumentation_prometheus_listen_addr}\",
      \"instrumentation_max_open_connections\": \"${configtoml_instrumentation_max_open_connections}\",
      \"instrumentation_namespace\": \"${configtoml_instrumentation_namespace}\"
    }"

		jq -n \
			--arg chain_id "$chain_id" \
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
			--argjson clienttoml "$clienttoml" \
			--argjson apptoml "$apptoml" \
			--argjson configtoml "$configtoml" \
			'{
            chain_id: $chain_id,
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
            nodes: $nodes,
            clienttoml: $clienttoml,
            apptoml: $apptoml,
            configtoml: $configtoml
          }' >"${config_json_path}"

		if [[ $? -eq 0 ]]; then
			log_success "Beranode configuration written to ${config_json_path}"
		else
			log_error "Could not write configuration to ${config_json_path}"
			return 1
		fi

		# =========================================================================
		# [9] KZG TRUSTED SETUP FILE SETUP
		# =========================================================================
		# Download kzg-trusted-setup.json and generate eth-genesis.json

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

		# =========================================================================
		# [10] GENESIS FILE SETUP
		# =========================================================================
		# Step 1: Generate base beranodes.config.json file
		generate_base_beacond_config \
			--config-dir "${BERANODES_PATH}" \
			--chain-spec "${network}"

		# Step 2: Generates a eth-genesis.json file that is shared with all nodes
		generate_eth_genesis_file \
			--config-dir "${BERANODES_PATH}" \
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

		# Step X: Generate beacon-kit genesis.json, configured premined deposits and deposit storage in eth-genesis.json
		generate_beacond_genesis_file_and_premined_deposits_storage \
			--config-dir "${BERANODES_PATH}" \
			--chain-spec "${network}"
	fi
}
