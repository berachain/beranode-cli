#!/usr/bin/env bash
set -euo pipefail
################################################################################
# network.sh - Per-network helpers for public chains (bepolia / mainnet)
################################################################################
#
# Maps CLI network names to chain IDs, BeaconKit chain-spec flags, bera-reth
# --chain presets, snapshot hosts, seed-data URLs, and recommended versions.
# Adding a network is one case-arm in each helper (plus constants.sh).
#
################################################################################

is_public_network() {
	local network="${1:-}"
	[[ "$network" == "$CHAIN_NAME_TESTNET" || "$network" == "$CHAIN_NAME_MAINNET" ]]
}

network_chain_id() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_DEVNET") echo "$CHAIN_ID_DEVNET" ;;
	"$CHAIN_NAME_TESTNET") echo "$CHAIN_ID_TESTNET" ;;
	"$CHAIN_NAME_MAINNET") echo "$CHAIN_ID_MAINNET" ;;
	*) echo "" ;;
	esac
}

# BeaconKit --beacon-kit.chain-spec value. Bepolia is "testnet", not "bepolia".
network_beacon_chain_spec() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_DEVNET" | "$BEACON_CHAIN_SPEC_DEVNET") echo "$BEACON_CHAIN_SPEC_DEVNET" ;;
	"$CHAIN_NAME_TESTNET" | "$BEACON_CHAIN_SPEC_TESTNET") echo "$BEACON_CHAIN_SPEC_TESTNET" ;;
	"$CHAIN_NAME_MAINNET" | "$BEACON_CHAIN_SPEC_MAINNET") echo "$BEACON_CHAIN_SPEC_MAINNET" ;;
	*) echo "$network" ;;
	esac
}

# bera-reth --chain preset (bepolia | mainnet). Empty for devnet (use genesis file).
network_reth_chain() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_TESTNET") echo "$CHAIN_NAME_TESTNET" ;;
	"$CHAIN_NAME_MAINNET") echo "$CHAIN_NAME_MAINNET" ;;
	*) echo "" ;;
	esac
}

network_snapshot_host() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_TESTNET") echo "$SNAPSHOT_HOST_BEPOLIA" ;;
	"$CHAIN_NAME_MAINNET") echo "$SNAPSHOT_HOST_MAINNET" ;;
	*) echo "" ;;
	esac
}

# Public EL JSON-RPC used by `beranode status` for LIVE EL BLOCK.
# Empty for local/devnet (no public tip to compare against).
network_public_el_rpc() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_TESTNET") echo "$PUBLIC_EL_RPC_BEPOLIA" ;;
	"$CHAIN_NAME_MAINNET") echo "$PUBLIC_EL_RPC_MAINNET" ;;
	*) echo "" ;;
	esac
}

network_snapshot_index_url() {
	local host
	host="$(network_snapshot_host "${1:-}")"
	if [[ -z "$host" ]]; then
		echo ""
		return 1
	fi
	echo "${host}/index.csv"
}

network_seed_data_url() {
	local chain_id
	chain_id="$(network_chain_id "${1:-}")"
	if [[ -z "$chain_id" ]]; then
		echo ""
		return 1
	fi
	echo "${SEED_DATA_BASE_URL}/${chain_id}"
}

network_recommended_beacond_version() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_TESTNET") echo "$RECOMMENDED_BEACOND_VERSION_BEPOLIA" ;;
	"$CHAIN_NAME_MAINNET") echo "$RECOMMENDED_BEACOND_VERSION_MAINNET" ;;
	*) echo "latest" ;;
	esac
}

network_recommended_berareth_version() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_TESTNET") echo "$RECOMMENDED_BERARETH_VERSION_BEPOLIA" ;;
	"$CHAIN_NAME_MAINNET") echo "$RECOMMENDED_BERARETH_VERSION_MAINNET" ;;
	*) echo "latest" ;;
	esac
}

network_seed_genesis_md5() {
	local network="${1:-}"
	case "$network" in
	"$CHAIN_NAME_TESTNET") echo "$SEED_MD5_GENESIS_BEPOLIA" ;;
	"$CHAIN_NAME_MAINNET") echo "$SEED_MD5_GENESIS_MAINNET" ;;
	*) echo "" ;;
	esac
}

# Role → snapshot type. Override (pruned|archive) wins for every role.
snapshot_type_for_role() {
	local role="${1:-}"
	local override="${2:-}"
	if [[ -n "$override" ]]; then
		echo "$override"
		return 0
	fi
	case "$role" in
	rpc-full | full_node) echo "archive" ;;
	*) echo "pruned" ;;
	esac
}

# Unique snapshot types needed for a nodes JSON array (space-separated).
snapshot_needed_types() {
	local nodes_json="${1:-[]}"
	local override="${2:-}"
	if [[ -n "$override" ]]; then
		echo "$override"
		return 0
	fi
	local count i role t
	local has_pruned=false
	local has_archive=false
	count=$(echo "$nodes_json" | jq 'length')
	for ((i = 0; i < count; i++)); do
		role=$(echo "$nodes_json" | jq -r ".[$i].role")
		t=$(snapshot_type_for_role "$role")
		if [[ "$t" == "archive" ]]; then
			has_archive=true
		else
			has_pruned=true
		fi
	done
	local out=""
	if [[ "$has_pruned" == true ]]; then
		out="pruned"
	fi
	if [[ "$has_archive" == true ]]; then
		if [[ -n "$out" ]]; then
			out="${out} archive"
		else
			out="archive"
		fi
	fi
	echo "$out"
}

file_md5() {
	local file_path="$1"
	if command -v md5sum >/dev/null 2>&1; then
		md5sum "$file_path" | awk '{print $1}'
	elif command -v md5 >/dev/null 2>&1; then
		md5 -q "$file_path"
	else
		echo ""
		return 1
	fi
}

# Fetch official seed-data for a public network into dest_dir.
fetch_network_seed_data() {
	local network="$1"
	local dest_dir="$2"
	local base_url
	base_url="$(network_seed_data_url "$network")" || return 1
	if [[ -z "$base_url" ]]; then
		log_error "No seed-data URL for network: ${network}"
		return 1
	fi

	mkdir -p "$dest_dir"
	local file
	for file in genesis.json kzg-trusted-setup.json el-bootnodes.txt el-peers.txt app.toml config.toml; do
		log_info "Fetching ${file} from ${base_url}/${file}"
		if ! curl -fsSL -o "${dest_dir}/${file}" "${base_url}/${file}"; then
			log_error "Failed to download ${file} from ${base_url}/${file}"
			return 1
		fi
	done

	local expected_genesis expected_kzg actual
	expected_genesis="$(network_seed_genesis_md5 "$network")"
	expected_kzg="$SEED_MD5_KZG"
	if [[ -n "$expected_genesis" ]]; then
		actual="$(file_md5 "${dest_dir}/genesis.json" || true)"
		if [[ -n "$actual" && "$actual" != "$expected_genesis" ]]; then
			log_warn "genesis.json md5 is ${actual}, expected ${expected_genesis} (network params may have been updated)"
		else
			log_success "genesis.json md5 matches documented checksum"
		fi
	fi
	actual="$(file_md5 "${dest_dir}/kzg-trusted-setup.json" || true)"
	if [[ -n "$actual" && "$actual" != "$expected_kzg" ]]; then
		log_warn "kzg-trusted-setup.json md5 is ${actual}, expected ${expected_kzg}"
	else
		log_success "kzg-trusted-setup.json md5 matches documented checksum"
	fi
}

# Extract seeds = "..." from an official CometBFT config.toml.
parse_toml_seeds() {
	local config_toml="$1"
	if [[ ! -f "$config_toml" ]]; then
		echo ""
		return 0
	fi
	grep -E '^seeds[[:space:]]*=' "$config_toml" 2>/dev/null | head -1 | sed -E 's/^seeds[[:space:]]*=[[:space:]]*"//;s/"[[:space:]]*$//' || true
}

# Comma-separated enode:// entries from el-bootnodes.txt or el-peers.txt.
# Accepts one enode per line (mainnet, with optional region headers) or a
# single comma-separated line (bepolia).
parse_el_enodes() {
	local peers_file="$1"
	if [[ ! -f "$peers_file" ]]; then
		echo ""
		return 0
	fi
	grep -E '^[[:space:]]*enode://' "$peers_file" 2>/dev/null \
		| tr -d '\r' \
		| tr '\n' ',' \
		| sed 's/,$//' \
		| sed 's/^[[:space:]]*//' || true
}

# Join non-empty comma-separated enode lists.
merge_enodes() {
	local out="" part
	for part in "$@"; do
		[[ -z "$part" ]] && continue
		if [[ -z "$out" ]]; then
			out="$part"
		else
			out="${out},${part}"
		fi
	done
	echo "$out"
}

# Resolve bera-reth --bootnodes / --trusted-peers.
# Public networks omit auto-injected lists so reth uses its --chain preset
# unless the user passed an explicit override.
resolve_reth_enodes() {
	local network="${1:-}"
	local local_enodes="${2:-}"
	local explicit_enodes="${3:-}"
	if is_public_network "${network}"; then
		echo "${explicit_enodes}"
	else
		merge_enodes "${local_enodes}" "${explicit_enodes}"
	fi
}

# Newline-separated bera-reth websocket flags. Empty when --ws is not enabled.
# Defaults when enabled: --ws.addr=0.0.0.0, --ws.port=<default_port>, --ws.origins=*
format_reth_ws_flags() {
	local enabled="${1:-}"
	local addr="${2:-}"
	local port="${3:-}"
	local origins="${4:-}"
	local default_port="${5:-$DEFAULT_EL_WS_PORT}"
	if [[ "${enabled}" != "true" ]]; then
		return 0
	fi
	[[ -z "${addr}" ]] && addr="0.0.0.0"
	[[ -z "${port}" ]] && port="${default_port}"
	[[ -z "${origins}" ]] && origins="*"
	printf '%s\n' \
		"--ws" \
		"--ws.addr=${addr}" \
		"--ws.port=${port}" \
		"--ws.origins=${origins}"
}

# Download missing official EL bootnodes/peers so older inits still join on start.
ensure_el_enode_files() {
	local network="$1"
	local seed_dir="$2"
	local base_url
	base_url="$(network_seed_data_url "$network")" || return 1
	if [[ -z "$base_url" ]]; then
		return 1
	fi
	mkdir -p "$seed_dir"
	local file
	for file in el-bootnodes.txt el-peers.txt; do
		if [[ -f "${seed_dir}/${file}" ]]; then
			continue
		fi
		log_info "Fetching ${file} from ${base_url}/${file}"
		if ! curl -fsSL -o "${seed_dir}/${file}" "${base_url}/${file}"; then
			log_warn "Failed to download ${file} from ${base_url}/${file}"
			rm -f "${seed_dir}/${file}"
		fi
	done
}

detect_external_ip() {
	local ip=""
	ip=$(curl -fsS --max-time 5 https://ipv4.canhazip.com 2>/dev/null || true)
	ip=$(echo "${ip}" | tr -d '[:space:]')
	if [[ -z "$ip" ]]; then
		ip=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
		ip=$(echo "${ip}" | tr -d '[:space:]')
	fi
	echo "$ip"
}

# True when bera-reth should run with --full (pruned). Archive/rpc-full omit --full.
reth_uses_pruning() {
	local role="${1:-}"
	local override="${2:-}"
	[[ "$(snapshot_type_for_role "$role" "$override")" == "pruned" ]]
}
