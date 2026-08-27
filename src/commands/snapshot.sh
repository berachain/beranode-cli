#!/usr/bin/env bash
set -euo pipefail
################################################################################
# snapshot.sh - Download and restore official Berachain chain-state snapshots
################################################################################
#
# Subcommands:
#   beranode snapshot                 Download latest matching snapshots and restore
#   beranode snapshot download        Download only
#   beranode snapshot restore         Restore already-downloaded archives
#
################################################################################

show_snapshot_help() {
	cat <<EOF
beranode snapshot - Download and restore official chain-state snapshots

USAGE:
    beranode snapshot [download|restore] [OPTIONS]

SUBCOMMANDS:
    download    Fetch the latest matching snapshots into beranodes/snapshots/
    restore     Unzip into snapshots/beacond and snapshots/reth, then copy into
                beacond/data and bera-reth (nodes must be stopped)
    (none)      Download then restore

OPTIONS:
    --beranodes-dir <path>           Directory for beranodes data (default: ./beranodes)
    --network <bepolia|mainnet>      Override network from beranodes.config.json
    --snapshot-type <pruned|archive> Force one type for every node
    --beacon-only                    Download consensus-layer snapshot only
    --execution-only|--el-only       Download execution-layer snapshot only
    --help|-h                        Display this help message

EXAMPLES:
    beranode snapshot
    beranode snapshot download --network bepolia --snapshot-type pruned
    beranode snapshot restore

Snapshots are read from index.csv:
    bepolia  https://bepolia.snapshots.berachain.com/index.csv
    mainnet  https://snapshots.berachain.com/index.csv

Archives unzip next to the downloads:
    {network}-beacond-{type}-latest.tar.lz4 → beranodes/snapshots/beacond
    {network}-reth-{type}-latest.tar.lz4    → beranodes/snapshots/reth
    then copy into each node's beacond/data and bera-reth
    mkdir -p beacond && lz4 -dc {archive} | tar -xvf - -C beacond

Requires curl, tar, and lz4. Archive snapshots are large and take longer.
EOF
}

cmd_snapshot() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_snapshot" >&2

	local subcommand=""
	if [[ "${1:-}" == "download" || "${1:-}" == "restore" ]]; then
		subcommand="$1"
		shift
	fi

	local beranodes_dir="${BERANODES_PATH_DEFAULT}"
	local network_override=""
	local snapshot_type=""
	local beacon_only=false
	local el_only=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--beranodes-dir)
			beranodes_dir=$(parse_beranodes_dir "$2")
			shift 2
			;;
		--network)
			if [[ "${2:-}" != "$CHAIN_NAME_TESTNET" && "${2:-}" != "$CHAIN_NAME_MAINNET" ]]; then
				log_error "--network must be ${CHAIN_NAME_TESTNET} or ${CHAIN_NAME_MAINNET}"
				return 1
			fi
			network_override="$2"
			shift 2
			;;
		--snapshot-type | --type)
			if [[ "${2:-}" != "pruned" && "${2:-}" != "archive" ]]; then
				log_error "--snapshot-type must be pruned or archive"
				return 1
			fi
			snapshot_type="$2"
			shift 2
			;;
		--beacon-only)
			beacon_only=true
			shift
			;;
		--execution-only | --el-only)
			el_only=true
			shift
			;;
		--help | -h)
			show_snapshot_help
			return 0
			;;
		*)
			log_error "Unknown option: $1"
			show_snapshot_help
			return 1
			;;
		esac
	done

	if [[ "$beacon_only" == true && "$el_only" == true ]]; then
		log_error "Use only one of --beacon-only and --execution-only"
		return 1
	fi

	local config_json_path="${beranodes_dir}/beranodes.config.json"
	local network=""
	local nodes_json="[]"

	if [[ -f "$config_json_path" ]]; then
		network=$(jq -r '.network' "$config_json_path")
		nodes_json=$(jq -c '.nodes' "$config_json_path")
		if [[ -z "$snapshot_type" ]]; then
			snapshot_type=$(jq -r '.snapshot_type // empty' "$config_json_path")
		fi
	fi
	if [[ -n "$network_override" ]]; then
		network="$network_override"
	fi
	if [[ -z "$network" ]]; then
		log_error "Network not set. Pass --network bepolia|mainnet or run 'beranode init' first."
		return 1
	fi
	if ! is_public_network "$network"; then
		log_error "Snapshots are only available for ${CHAIN_NAME_TESTNET} and ${CHAIN_NAME_MAINNET} (got: ${network})"
		return 1
	fi

	local types
	types=$(snapshot_needed_types "$nodes_json" "$snapshot_type")
	if [[ -z "$types" ]]; then
		types="${snapshot_type:-pruned}"
	fi

	ensure_dir_exists "${beranodes_dir}${BERANODES_PATH_SNAPSHOTS}" "snapshots directory" || return 1
	ensure_dir_exists "${beranodes_dir}${BERANODES_PATH_TMP}" "temporary directory" || return 1

	case "$subcommand" in
	download)
		if [[ "$beacon_only" == true || "$el_only" == true ]]; then
			log_warn "--beacon-only / --execution-only download the matching pair's layer after index select; both types still resolved from the index."
		fi
		download_network_snapshots "$network" "${beranodes_dir}${BERANODES_PATH_SNAPSHOTS}" "$types" "$nodes_json" "$snapshot_type" || return 1
		;;
	restore)
		if snapshot_nodes_appear_running "$beranodes_dir"; then
			log_error "Nodes appear to be running. Stop them with 'beranode stop' before restoring snapshots."
			return 1
		fi
		restore_network_snapshots "$beranodes_dir" "$nodes_json" "$snapshot_type" "true" || return 1
		;;
	*)
		if snapshot_nodes_appear_running "$beranodes_dir"; then
			log_error "Nodes appear to be running. Stop them with 'beranode stop' before restoring snapshots."
			return 1
		fi
		apply_network_snapshots "$network" "$beranodes_dir" "$nodes_json" "$snapshot_type" "true" || return 1
		;;
	esac
}

snapshot_nodes_appear_running() {
	local beranodes_dir="$1"
	local runs="${beranodes_dir}${BERANODES_PATH_RUNS}"
	if [[ ! -d "$runs" ]]; then
		return 1
	fi
	local pidfile pid
	for pidfile in "${runs}"/*.pid; do
		[[ -f "$pidfile" ]] || continue
		pid=$(cat "$pidfile" 2>/dev/null || true)
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			return 0
		fi
	done
	return 1
}
