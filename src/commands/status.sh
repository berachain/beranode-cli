#!/usr/bin/env bash
set -euo pipefail
################################################################################
# status.sh - Beranode CLI Status Command
################################################################################
#
# This module implements the `beranode status` command which reads the
# beranodes.config.json configuration file and displays the live status
# of each node in a formatted table.
#
# For each node it queries:
#   - Execution Layer (bera-reth): block height and peer count via JSON-RPC
#   - Consensus Layer (beacond): sync status, block height, block time,
#     peer count, and catching-up flag via CometBFT HTTP RPC
#   - Public EL RPC (LIVE EL BLOCK): chain tip from the official RPC for
#     bepolia/mainnet only (omitted on devnet), refreshed every 10 seconds
#   - Docker container status (when running in docker mode)
#
# VERSION CONTEXT - Beranode CLI v0.9.0
#
# LEGEND - Function Reference by Section:
# ──────────────────────────────────────────────────────────────────────────────
# [SECTION 1] Help Documentation
#    └─ show_status_help()        : Display usage information
#
# [SECTION 2] Status Query Helpers
#    └─ query_el_rpc_block()      : Query any EL JSON-RPC URL for block number
#    └─ query_el_block()          : Query local EL for latest block number
#    └─ query_el_peers()          : Query EL for peer count
#    └─ query_cl_status()         : Query CL for sync info + peer count
#    └─ refresh_live_el_block()   : Refresh cached public-RPC block (every 10s)
#    └─ get_docker_container_status() : Query Docker container state
#    └─ format_block_age()        : Human-readable time since latest CL block
#    └─ colorize_status()         : Apply ANSI color to a status string
#
# [SECTION 3] Table Formatting
#    └─ print_status_row()        : Render a compact-mode row
#    └─ print_verbose_row()       : Render a verbose-mode row
#
# [SECTION 4] Rendering
#    └─ render_status_table()     : Render the full status table (one frame)
#
# [SECTION 5] Main Command Function
#    └─ cmd_status()              : Entry point for the status command
#
################################################################################

# =============================================================================
# [SECTION 1] Help Documentation
# =============================================================================
# Displays comprehensive usage information for the status command.
# Invoked via: beranode status --help
# =============================================================================

show_status_help() {
	cat <<EOF
Usage: beranode status [OPTIONS]

Display the live status of all Berachain nodes defined in the configuration.

Reads beranodes.config.json and queries each node's Execution Layer (bera-reth)
and Consensus Layer (beacond) endpoints to report block height, peer count,
sync status, and more. For bepolia/mainnet, also queries the public RPC for
LIVE EL BLOCK (refreshed every 10 seconds in --watch mode).

Options:
  --verbose|-v              Show each service (beacond, bera-reth) as its own row
  --watch|-w                Live-refresh mode (re-queries every N seconds)
  --interval|-i <seconds>   Refresh interval for watch mode (default: 2)
  --beranodes-dir <path>    Specify the beranodes directory path
                            (default: \$PWD/beranodes)
  --help|-h                 Display this help message

Examples:
  beranode status
  beranode status --verbose
  beranode status --watch
  beranode status --watch --verbose --interval 5
  beranode status --beranodes-dir /custom/path
  beranode status --help

EOF
}

# =============================================================================
# [SECTION 2] Status Query Helpers
# =============================================================================

# -----------------------------------------------------------------------------
# Function: query_el_rpc_block
# Description: Queries an Execution Layer JSON-RPC URL for the current block
#              number via eth_blockNumber.
# Arguments:
#   $1 - url (string): Full JSON-RPC URL (local or public)
# Returns:
#   Prints the hex block number on success, or "--" on failure
# -----------------------------------------------------------------------------
query_el_rpc_block() {
	local url="$1"
	[[ -z "${url}" ]] && { echo "--"; return; }

	local response
	response=$(curl -sf --connect-timeout 2 --max-time 3 \
		-X POST -H 'Content-Type: application/json' \
		-d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
		"${url}" 2>/dev/null) || { echo "--"; return; }

	local result
	result=$(echo "${response}" | jq -r '.result // empty' 2>/dev/null) || { echo "--"; return; }

	if [[ -n "${result}" ]]; then
		echo "${result}"
	else
		echo "--"
	fi
}

# -----------------------------------------------------------------------------
# Function: query_el_block
# Description: Queries the local Execution Layer (bera-reth) for the current
#              block number via eth_blockNumber JSON-RPC call.
# Arguments:
#   $1 - port (integer): The EL HTTP RPC port (el_ethrpc_port)
# Returns:
#   Prints the hex block number on success, or "--" on failure
# -----------------------------------------------------------------------------
query_el_block() {
	query_el_rpc_block "http://localhost:${1}"
}

# -----------------------------------------------------------------------------
# Function: refresh_live_el_block
# Description: Re-reads `network` from beranodes.config.json and queries the
#              matching public EL RPC for the chain tip. Cached for
#              LIVE_EL_REFRESH_SECONDS (10s) so --watch does not hammer the
#              public endpoint on every table refresh.
# Caller-scoped (cmd_status locals):
#   config_path, network, live_el_block, live_el_fetched_at, show_live_el
# -----------------------------------------------------------------------------
refresh_live_el_block() {
	# Re-read network every frame so a mid-watch switch to/from devnet
	# immediately shows or hides the LIVE EL BLOCK column.
	if [[ -n "${config_path:-}" && -f "${config_path}" ]]; then
		network=$(jq -r '.network // "unknown"' "${config_path}") || true
	fi

	local rpc_url
	rpc_url=$(network_public_el_rpc "${network}")
	if [[ -z "${rpc_url}" ]]; then
		live_el_block="--"
		show_live_el="false"
		return 0
	fi
	show_live_el="true"

	local now
	now=$(date +%s 2>/dev/null) || now=0

	if [[ ${live_el_fetched_at} -gt 0 && ${now} -gt 0 ]]; then
		local elapsed=$(( now - live_el_fetched_at ))
		if [[ ${elapsed} -lt ${LIVE_EL_REFRESH_SECONDS} ]]; then
			return 0
		fi
	fi

	local result
	result=$(query_el_rpc_block "${rpc_url}")
	if [[ "${result}" != "--" ]]; then
		live_el_block=$(hex_to_dec "${result}")
	fi
	live_el_fetched_at=${now}
}

# -----------------------------------------------------------------------------
# Function: query_el_peers
# Description: Queries the Execution Layer (bera-reth) for peer count
#              via net_peerCount JSON-RPC call.
# Arguments:
#   $1 - port (integer): The EL HTTP RPC port (el_ethrpc_port)
# Returns:
#   Prints the decimal peer count on success, or "--" on failure
# -----------------------------------------------------------------------------
query_el_peers() {
	local port="$1"
	local response
	response=$(curl -sf --connect-timeout 2 --max-time 3 \
		-X POST -H 'Content-Type: application/json' \
		-d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
		"http://localhost:${port}" 2>/dev/null) || { echo "--"; return; }

	local result
	result=$(echo "${response}" | jq -r '.result // empty' 2>/dev/null) || { echo "--"; return; }

	if [[ -n "${result}" ]]; then
		# Convert hex to decimal
		printf "%d\n" "${result}" 2>/dev/null || echo "--"
	else
		echo "--"
	fi
}

# -----------------------------------------------------------------------------
# Function: query_cl_status
# Description: Queries the Consensus Layer (beacond) CometBFT RPC /status
#              endpoint and extracts sync_info fields, plus /net_info peers.
# Arguments:
#   $1 - port (integer): The CL RPC port (ethrpc_port)
# Returns:
#   Prints four space-separated values:
#     <latest_block_height> <catching_up> <n_peers> <latest_block_time>
#   Uses "--" for any field that cannot be retrieved.
# -----------------------------------------------------------------------------
query_cl_status() {
	local port="$1"

	# Query /status for block height, catching_up, and block time
	local status_response
	status_response=$(curl -sf --connect-timeout 2 --max-time 3 \
		"http://localhost:${port}/status" 2>/dev/null) || { echo "-- -- -- --"; return; }

	local cl_block
	cl_block=$(echo "${status_response}" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null) || cl_block="--"
	[[ -z "${cl_block}" ]] && cl_block="--"

	local catching_up
	catching_up=$(echo "${status_response}" | jq -r 'if .result.sync_info.catching_up != null then (.result.sync_info.catching_up | tostring) else empty end' 2>/dev/null) || catching_up="--"
	[[ -z "${catching_up}" ]] && catching_up="--"

	local block_time
	block_time=$(echo "${status_response}" | jq -r '.result.sync_info.latest_block_time // empty' 2>/dev/null) || block_time="--"
	[[ -z "${block_time}" ]] && block_time="--"

	# Query /net_info for peer count
	local net_response
	net_response=$(curl -sf --connect-timeout 2 --max-time 3 \
		"http://localhost:${port}/net_info" 2>/dev/null) || { echo "${cl_block} ${catching_up} -- ${block_time}"; return; }

	local cl_peers
	cl_peers=$(echo "${net_response}" | jq -r '.result.n_peers // empty' 2>/dev/null) || cl_peers="--"
	[[ -z "${cl_peers}" ]] && cl_peers="--"

	echo "${cl_block} ${catching_up} ${cl_peers} ${block_time}"
}

# -----------------------------------------------------------------------------
# Function: get_docker_container_status
# Description: Gets the status of a Docker container by name pattern.
# Arguments:
#   $1 - container_filter (string): A substring to match against container names
# Returns:
#   Prints the container status (e.g., "running", "exited") or "stopped"
# -----------------------------------------------------------------------------
get_docker_container_status() {
	local container_filter="$1"
	local status
	status=$(docker ps -a --filter "name=${container_filter}" --format '{{.Status}}' 2>/dev/null | head -1) || { echo "unknown"; return; }

	if [[ -z "${status}" ]]; then
		echo "stopped"
	elif echo "${status}" | grep -qi "up"; then
		echo "running"
	elif echo "${status}" | grep -qi "exited"; then
		echo "exited"
	elif echo "${status}" | grep -qi "restarting"; then
		echo "restarting"
	elif echo "${status}" | grep -qi "created"; then
		echo "created"
	else
		echo "${status}"
	fi
}

# -----------------------------------------------------------------------------
# Function: format_block_age
# Description: Converts an ISO-8601 timestamp to a human-readable age string
#              (e.g., "3s", "2m 14s", "1h 5m", "3d 2h").
# Arguments:
#   $1 - iso_timestamp (string): ISO-8601 timestamp from CometBFT
# Returns:
#   Prints a human-readable age string, or "--" on failure
# -----------------------------------------------------------------------------
format_block_age() {
	local ts="$1"
	[[ "${ts}" == "--" || -z "${ts}" ]] && { echo "--"; return; }

	local now_epoch block_epoch diff
	now_epoch=$(date +%s 2>/dev/null) || { echo "--"; return; }

	# macOS and GNU date handle -d / -jf differently
	if [[ "${IS_MACOS}" == "true" ]]; then
		# Trim fractional seconds + Z; parse as UTC (CometBFT times are Zulu)
		local trimmed
		trimmed=$(echo "${ts}" | sed 's/\.[0-9]*Z$/Z/' | sed 's/Z$//')
		block_epoch=$(date -u -jf "%Y-%m-%dT%H:%M:%S" "${trimmed}" +%s 2>/dev/null) || { echo "--"; return; }
	else
		block_epoch=$(date -d "${ts}" +%s 2>/dev/null) || { echo "--"; return; }
	fi

	diff=$(( now_epoch - block_epoch ))
	[[ ${diff} -lt 0 ]] && diff=0

	if [[ ${diff} -lt 60 ]]; then
		echo "${diff}s ago"
	elif [[ ${diff} -lt 3600 ]]; then
		echo "$(( diff / 60 ))m $(( diff % 60 ))s ago"
	elif [[ ${diff} -lt 86400 ]]; then
		echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m ago"
	else
		echo "$(( diff / 86400 ))d $(( (diff % 86400) / 3600 ))h ago"
	fi
}

# -----------------------------------------------------------------------------
# Function: hex_to_dec
# Description: Converts a hex string (e.g., 0x1a3) to decimal.
# Arguments:
#   $1 - hex_value (string): Hex number, with or without 0x prefix
# Returns:
#   Prints the decimal value, or "--" on failure
# -----------------------------------------------------------------------------
hex_to_dec() {
	local hex="$1"
	[[ "${hex}" == "--" || -z "${hex}" ]] && { echo "--"; return; }
	printf "%d\n" "${hex}" 2>/dev/null || echo "--"
}

# -----------------------------------------------------------------------------
# Function: colorize_status
# Description: Applies ANSI color to a status string and pre-pads to a target
#              width so color codes don't break column alignment.
# Arguments:
#   $1 - status (string): The raw status value
#   $2 - width  (integer): Target column width for padding
# Returns:
#   Prints the color-wrapped, pre-padded string
# -----------------------------------------------------------------------------
colorize_status() {
	local status="$1"
	local width="$2"
	local padded
	padded=$(printf "%-${width}s" "${status}")

	case "${status}" in
		running)    echo "${GREEN}${padded}${RESET}" ;;
		exited)     echo "${RED}${padded}${RESET}" ;;
		restarting) echo "${YELLOW}${padded}${RESET}" ;;
		offline)    echo "${RED}${padded}${RESET}" ;;
		stopped)    echo "${RED}${padded}${RESET}" ;;
		*)          echo "${padded}" ;;
	esac
}

# -----------------------------------------------------------------------------
# Function: colorize_catching_up
# Description: Applies color to a catching_up value (true/false/--).
# Arguments:
#   $1 - catching_up (string)
#   $2 - width (integer)
# Returns:
#   Prints the color-wrapped, pre-padded string
# -----------------------------------------------------------------------------
colorize_catching_up() {
	local val="$1"
	local width="$2"
	local padded
	padded=$(printf "%-${width}s" "${val}")

	case "${val}" in
		true)  echo "${YELLOW}${padded}${RESET}" ;;
		false) echo "${GREEN}${padded}${RESET}" ;;
		*)     echo "${padded}" ;;
	esac
}

# =============================================================================
# [SECTION 3] Table Formatting
# =============================================================================

# -----------------------------------------------------------------------------
# Function: print_status_row
# Description: Prints a single row of the compact status table (default mode).
# Arguments:
#   $1  - node_name     $2  - role           $3  - el_status
#   $4  - el_block      $5  - live_el_block  $6  - el_peers
#   $7  - cl_status     $8  - cl_block       $9  - cl_peers
#   $10 - catching_up   $11 - block_age
# -----------------------------------------------------------------------------
print_status_row() {
	if [[ "${show_live_el:-false}" == "true" ]]; then
		printf "  %-28s %-12s %-12s %-12s %-14s %-10s %-12s %-12s %-10s %-12s %-14s\n" \
			"$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}"
	else
		printf "  %-28s %-12s %-12s %-12s %-10s %-12s %-12s %-10s %-12s %-14s\n" \
			"$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"
	fi
}

# -----------------------------------------------------------------------------
# Function: print_verbose_row
# Description: Prints a single row of the verbose status table.
# Arguments:
#   $1 - node_name  $2 - role    $3 - service   $4 - status
#   $5 - block      $6 - live_block  $7 - peers
#   $8 - catching_up  $9 - block_age
# -----------------------------------------------------------------------------
print_verbose_row() {
	if [[ "${show_live_el:-false}" == "true" ]]; then
		printf "  %-28s %-12s %-14s %-12s %-14s %-14s %-10s %-12s %-14s\n" \
			"$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	else
		printf "  %-28s %-12s %-14s %-12s %-14s %-10s %-12s %-14s\n" \
			"$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
	fi
}

# =============================================================================
# [SECTION 4] Rendering
# =============================================================================
# Renders the complete status table for one frame. Called once in normal mode,
# or repeatedly in watch mode.
#
# Arguments (via caller-scoped locals):
#   config_path, network, moniker, mode, total_nodes, chain_id,
#   nodes_json, nodes_count, verbose, watch_mode,
#   live_el_block, live_el_fetched_at, show_live_el
# =============================================================================

render_status_table() {
	refresh_live_el_block

	# -------------------------------------------------------------------------
	# Print header
	# -------------------------------------------------------------------------
	echo ""
	echo -e "${BOLD}Beranode Status${RESET}"
	echo -e "${DIM}$(printf '%.0s─' {1..50})${RESET}"
	echo ""
	echo -e "  ${BOLD}Network:${RESET} ${network}  |  ${BOLD}Chain ID:${RESET} ${chain_id}  |  ${BOLD}Mode:${RESET} ${mode}  |  ${BOLD}Moniker:${RESET} ${moniker}  |  ${BOLD}Nodes:${RESET} ${total_nodes}"
	echo ""

	# -------------------------------------------------------------------------
	# Print table header
	# -------------------------------------------------------------------------
	if [[ "${verbose}" == "true" ]]; then
		if [[ "${show_live_el}" == "true" ]]; then
			print_verbose_row "NODE" "ROLE" "SERVICE" "STATUS" "BLOCK" "LIVE EL BLOCK" "PEERS" "CATCHING UP" "BLOCK AGE"
			echo -e "  ${DIM}$(printf '%.0s─' {1..133})${RESET}"
		else
			print_verbose_row "NODE" "ROLE" "SERVICE" "STATUS" "BLOCK" "PEERS" "CATCHING UP" "BLOCK AGE"
			echo -e "  ${DIM}$(printf '%.0s─' {1..118})${RESET}"
		fi
	else
		if [[ "${show_live_el}" == "true" ]]; then
			print_status_row "NODE" "ROLE" "EL STATUS" "EL BLOCK" "LIVE EL BLOCK" "EL PEERS" "CL STATUS" "CL BLOCK" "CL PEERS" "CATCHING UP" "BLOCK AGE"
			echo -e "  ${DIM}$(printf '%.0s─' {1..151})${RESET}"
		else
			print_status_row "NODE" "ROLE" "EL STATUS" "EL BLOCK" "EL PEERS" "CL STATUS" "CL BLOCK" "CL PEERS" "CATCHING UP" "BLOCK AGE"
			echo -e "  ${DIM}$(printf '%.0s─' {1..136})${RESET}"
		fi
	fi

	# -------------------------------------------------------------------------
	# Query each node and print status rows
	# -------------------------------------------------------------------------
	for ((i = 0; i < nodes_count; i++)); do
		local node_json
		node_json=$(echo "${nodes_json}" | jq -c ".[$i]")

		# Extract node fields from config
		local node_moniker node_role
		node_moniker=$(echo "${node_json}" | jq -r '.moniker')
		node_role=$(echo "${node_json}" | jq -r '.role')

		local el_port cl_port
		el_port=$(echo "${node_json}" | jq -r '.el_ethrpc_port')
		cl_port=$(echo "${node_json}" | jq -r '.ethrpc_port')

		# Abbreviate role for docker container name matching
		local role_short="${node_role}"
		[[ "${node_role}" == "validator" ]] && role_short="val"

		# -- Execution Layer status --
		local el_status="offline"
		local el_block="--"
		local el_peers="--"

		# In docker mode, check container status first
		if [[ "${mode}" == "docker" ]]; then
			el_status=$(get_docker_container_status "${i}-${role_short}.*bera-reth")
		fi

		# Query EL RPC regardless of mode (if reachable, it is running)
		local el_block_result
		el_block_result=$(query_el_block "${el_port}")
		if [[ "${el_block_result}" != "--" ]]; then
			el_block=$(hex_to_dec "${el_block_result}")
			# If we got a response, the EL is running
			[[ "${el_status}" == "offline" ]] && el_status="running"
		fi

		local el_peers_result
		el_peers_result=$(query_el_peers "${el_port}")
		if [[ "${el_peers_result}" != "--" ]]; then
			el_peers="${el_peers_result}"
		fi

		# -- Consensus Layer status --
		local cl_status="offline"
		local cl_block="--"
		local cl_peers="--"
		local catching_up="--"
		local block_time="--"

		# In docker mode, check container status first
		if [[ "${mode}" == "docker" ]]; then
			cl_status=$(get_docker_container_status "${i}-${role_short}.*beacond")
		fi

		# Query CL RPC
		local cl_result
		cl_result=$(query_cl_status "${cl_port}")
		local cl_block_val cl_catching_val cl_peers_val cl_time_val
		cl_block_val=$(echo "${cl_result}" | awk '{print $1}')
		cl_catching_val=$(echo "${cl_result}" | awk '{print $2}')
		cl_peers_val=$(echo "${cl_result}" | awk '{print $3}')
		cl_time_val=$(echo "${cl_result}" | awk '{print $4}')

		if [[ "${cl_block_val}" != "--" ]]; then
			cl_block="${cl_block_val}"
			[[ "${cl_status}" == "offline" ]] && cl_status="running"
		fi
		if [[ "${cl_catching_val}" != "--" ]]; then
			catching_up="${cl_catching_val}"
		fi
		if [[ "${cl_peers_val}" != "--" ]]; then
			cl_peers="${cl_peers_val}"
		fi
		if [[ "${cl_time_val}" != "--" ]]; then
			block_time="${cl_time_val}"
		fi

		# Compute human-readable block age
		local block_age
		block_age=$(format_block_age "${block_time}")

		# -- Render output --
		if [[ "${verbose}" == "true" ]]; then
			# =============================================================
			# VERBOSE MODE: Two rows per node (bera-reth + beacond)
			# =============================================================
			local el_status_display cl_status_display catching_display

			# -- bera-reth row --
			el_status_display=$(colorize_status "${el_status}" 12)

			if [[ "${show_live_el}" == "true" ]]; then
				printf "  %-28s %-12s %-14s %b %-14s %-14s %-10s %-12s %-14s\n" \
					"${node_moniker}" "${node_role}" "bera-reth" \
					"${el_status_display}" "${el_block}" "${live_el_block}" "${el_peers}" "--" "--"
			else
				printf "  %-28s %-12s %-14s %b %-14s %-10s %-12s %-14s\n" \
					"${node_moniker}" "${node_role}" "bera-reth" \
					"${el_status_display}" "${el_block}" "${el_peers}" "--" "--"
			fi

			# -- beacond row (continuation — no node/role repeated) --
			cl_status_display=$(colorize_status "${cl_status}" 12)
			catching_display=$(colorize_catching_up "${catching_up}" 12)

			if [[ "${show_live_el}" == "true" ]]; then
				printf "  %-28s %-12s %-14s %b %-14s %-14s %-10s %b %-14s\n" \
					"" "" "beacond" \
					"${cl_status_display}" "${cl_block}" "--" "${cl_peers}" \
					"${catching_display}" "${block_age}"
			else
				printf "  %-28s %-12s %-14s %b %-14s %-10s %b %-14s\n" \
					"" "" "beacond" \
					"${cl_status_display}" "${cl_block}" "${cl_peers}" \
					"${catching_display}" "${block_age}"
			fi

			# Separator between nodes
			if [[ $((i + 1)) -lt ${nodes_count} ]]; then
				if [[ "${show_live_el}" == "true" ]]; then
					echo -e "  ${DIM}$(printf '%.0s·' {1..133})${RESET}"
				else
					echo -e "  ${DIM}$(printf '%.0s·' {1..118})${RESET}"
				fi
			fi
		else
			# =============================================================
			# COMPACT MODE: One row per node (default)
			# =============================================================
			local el_status_display cl_status_display catching_display

			el_status_display=$(colorize_status "${el_status}" 12)
			cl_status_display=$(colorize_status "${cl_status}" 12)
			catching_display=$(colorize_catching_up "${catching_up}" 12)

			# Print the row — colored fields already include their padding
			if [[ "${show_live_el}" == "true" ]]; then
				printf "  %-28s %-12s %b %-12s %-14s %-10s %b %-12s %-10s %b %-14s\n" \
					"${node_moniker}" "${node_role}" \
					"${el_status_display}" "${el_block}" "${live_el_block}" "${el_peers}" \
					"${cl_status_display}" "${cl_block}" "${cl_peers}" \
					"${catching_display}" "${block_age}"
			else
				printf "  %-28s %-12s %b %-12s %-10s %b %-12s %-10s %b %-14s\n" \
					"${node_moniker}" "${node_role}" \
					"${el_status_display}" "${el_block}" "${el_peers}" \
					"${cl_status_display}" "${cl_block}" "${cl_peers}" \
					"${catching_display}" "${block_age}"
			fi
		fi
	done

	echo ""
}

# =============================================================================
# [SECTION 5] Main Status Command Function
# =============================================================================
# Primary entry point for the status command. Reads configuration, queries
# each node, and displays a formatted status table.  In watch mode, the table
# is re-rendered on a configurable interval.
# =============================================================================

cmd_status() {
	# Enable debug output if DEBUG_MODE is set
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_status" >&2

	# -------------------------------------------------------------------------
	# [STEP 1] Parse command line arguments
	# -------------------------------------------------------------------------
	local beranodes_dir="${BERANODES_PATH_DEFAULT}"
	local verbose="false"
	local watch_mode="false"
	local interval=2

	while [[ $# -gt 0 ]]; do
		case $1 in
		--beranodes-dir)
			beranodes_dir=$(parse_beranodes_dir "$2")
			shift 2
			;;
		--verbose | -v)
			verbose="true"
			shift
			;;
		--watch | -w)
			watch_mode="true"
			shift
			;;
		--interval | -i)
			if [[ -z "${2:-}" || ! "${2}" =~ ^[0-9]+$ ]]; then
				log_error "Invalid interval value. Must be a positive integer."
				return 1
			fi
			interval="$2"
			shift 2
			;;
		--help | -h)
			show_status_help
			return 0
			;;
		*)
			check_unknown_option "$1" "show_status_help" || return 1
			;;
		esac
	done

	# -------------------------------------------------------------------------
	# [STEP 2] Load and validate configuration
	# -------------------------------------------------------------------------
	local config_path="${beranodes_dir}/beranodes.config.json"

	if [[ ! -f "${config_path}" ]]; then
		log_error "Configuration file not found: ${config_path}"
		log_error "Run 'beranode init' first to create a node configuration."
		return 1
	fi

	# Read top-level config values
	local network moniker mode total_nodes chain_id
	network=$(jq -r '.network // "unknown"' "${config_path}") || network="unknown"
	moniker=$(jq -r '.moniker // "unknown"' "${config_path}") || moniker="unknown"
	mode=$(jq -r '.mode // "unknown"' "${config_path}") || mode="unknown"
	total_nodes=$(jq -r '.total_nodes // 0' "${config_path}") || total_nodes=0
	chain_id=$(jq -r '.chain_id // "unknown"' "${config_path}") || chain_id="unknown"

	local nodes_json
	nodes_json=$(jq -c '.nodes // []' "${config_path}") || {
		log_error "Failed to parse nodes from configuration"
		return 1
	}

	local nodes_count
	nodes_count=$(echo "${nodes_json}" | jq 'length') || nodes_count=0

	if [[ "${nodes_count}" -eq 0 ]]; then
		log_warn "No nodes found in configuration"
		return 0
	fi

	# Cached public-RPC tip; refresh_live_el_block updates these every 10s.
	# show_live_el is false on devnet (column omitted) and true on bepolia/mainnet.
	local live_el_block="--"
	local live_el_fetched_at=0
	local show_live_el="false"

	# -------------------------------------------------------------------------
	# [STEP 3] Render — once or in a loop
	# -------------------------------------------------------------------------
	if [[ "${watch_mode}" == "true" ]]; then
		# Ensure terminal is usable for watch mode
		if [[ ! -t 1 ]]; then
			log_error "Watch mode requires an interactive terminal (stdout is not a TTY)."
			return 1
		fi

		# Hide cursor and restore it on exit
		tput civis 2>/dev/null || true

		# Trap SIGINT/SIGTERM to restore terminal state
		trap '_status_watch_cleanup' INT TERM

		# Clear screen once on first render
		printf '\033[H\033[2J'

		while true; do
			# Move cursor to home position (top-left) without clearing
			printf '\033[H'

			render_status_table

			# Footer
			local now_ts
			now_ts=$(date '+%H:%M:%S')
			if [[ "${show_live_el}" == "true" ]]; then
				echo -e "  ${DIM}Last updated: ${now_ts}  |  Refreshing every ${interval}s  |  LIVE EL BLOCK every ${LIVE_EL_REFRESH_SECONDS}s  |  Press Ctrl+C to exit${RESET}"
			else
				echo -e "  ${DIM}Last updated: ${now_ts}  |  Refreshing every ${interval}s  |  Press Ctrl+C to exit${RESET}"
			fi
			echo ""

			# Clear any leftover lines below the current cursor position
			printf '\033[J'

			sleep "${interval}"
		done
	else
		render_status_table
	fi
}

# -----------------------------------------------------------------------------
# Function: _status_watch_cleanup
# Description: Restores terminal state when exiting watch mode.
# -----------------------------------------------------------------------------
_status_watch_cleanup() {
	# Show cursor again
	tput cnorm 2>/dev/null || true
	echo ""
	log_info "Watch mode stopped."
	# Remove the trap so the default handler fires if needed
	trap - INT TERM
	return 0
}
