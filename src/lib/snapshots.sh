#!/usr/bin/env bash
set -euo pipefail
################################################################################
# snapshots.sh - Official Berachain chain-state snapshot download / restore
################################################################################
#
# Reads {host}/index.csv, picks the newest beacon-kit-{type} and reth-{type}
# rows, downloads with curl -C - (resume), verifies sha256 when present, and
# extracts .tar.lz4 into beranodes/snapshots/beacond and beranodes/snapshots/reth
# before copying into each node's beacond/data / bera-reth datadir.
#
# Mirrors: https://github.com/berachain/guides/blob/main/apps/node-scripts/fetch-berachain-snapshot.js
#
################################################################################

require_snapshot_tools() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: require_snapshot_tools" >&2

	log_info "Checking that tar and lz4 are installed..."
	local missing=0
	if ! command -v curl >/dev/null 2>&1; then
		log_error "curl is required to download snapshots and is not installed or not in PATH."
		missing=1
	fi
	if ! command -v tar >/dev/null 2>&1; then
		log_error "tar is required to extract snapshots and is not installed or not in PATH."
		missing=1
	fi
	if ! command -v lz4 >/dev/null 2>&1; then
		log_error "lz4 is required to extract official .tar.lz4 snapshots and is not installed or not in PATH."
		log_error "Install it (e.g. 'brew install lz4' or 'apt-get install lz4') and retry."
		missing=1
	fi
	if [[ "$missing" -ne 0 ]]; then
		return 1
	fi
	log_success "tar and lz4 are installed."
	return 0
}

format_bytes() {
	local bytes="${1:-}"
	if [[ -z "$bytes" || "$bytes" == "null" || ! "$bytes" =~ ^[0-9]+$ ]]; then
		echo "unknown size"
		return 0
	fi
	if ((bytes >= 1073741824)); then
		echo "$((bytes / 1073741824)).$(((bytes % 1073741824) * 10 / 1073741824)) GB"
	elif ((bytes >= 1048576)); then
		echo "$((bytes / 1048576)) MB"
	elif ((bytes >= 1024)); then
		echo "$((bytes / 1024)) KB"
	else
		echo "${bytes} B"
	fi
}

# Parse index.csv and print the newest row for a type as:
#   url<TAB>size_bytes<TAB>created_at<TAB>sha256
# sha256 may be empty if the CSV has no such column. Prefers url_s3 over url.
snapshot_select_latest() {
	local csv_file="$1"
	local want_type="$2"

	if [[ ! -f "$csv_file" ]]; then
		log_error "Snapshot index not found: ${csv_file}"
		return 1
	fi

	awk -F',' -v want="$want_type" '
		function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
		NR == 1 {
			for (i = 1; i <= NF; i++) {
				h = trim($i)
				if (h == "url") col_url = i
				else if (h == "url_s3") col_url_s3 = i
				else if (h == "type") col_type = i
				else if (h == "size_bytes") col_size = i
				else if (h == "created_at") col_created = i
				else if (h == "sha256" || h == "checksum" || h == "sha256sum") col_sha = i
			}
			if (!col_url || !col_type) {
				print "ERROR: missing url or type column" > "/dev/stderr"
				exit 1
			}
			next
		}
		NF == 0 { next }
		trim($col_type) == want {
			url = trim($col_url)
			if (col_url_s3 && trim($col_url_s3) != "") url = trim($col_url_s3)
			created = col_created ? trim($col_created) : ""
			size = col_size ? trim($col_size) : ""
			sha = col_sha ? trim($col_sha) : ""
			if (created >= best_created) {
				best_created = created
				best_url = url
				best_size = size
				best_sha = sha
			}
		}
		END {
			if (best_url == "") exit 1
			print best_url "\t" best_size "\t" best_created "\t" best_sha
		}
	' "$csv_file"
}

fetch_snapshot_index() {
	local network="$1"
	local dest_file="$2"
	local index_url
	index_url="$(network_snapshot_index_url "$network")" || return 1
	if [[ -z "$index_url" ]]; then
		log_error "No snapshot index URL for network: ${network}"
		return 1
	fi
	log_info "Fetching snapshot index from ${index_url}"
	mkdir -p "$(dirname "$dest_file")"
	if ! curl -fsSL -o "$dest_file" "$index_url"; then
		log_error "Failed to download snapshot index: ${index_url}"
		return 1
	fi
}

verify_sha256() {
	local file_path="$1"
	local expected="$2"
	if [[ -z "$expected" || "$expected" == "null" ]]; then
		return 0
	fi
	local actual=""
	if command -v sha256sum >/dev/null 2>&1; then
		actual=$(sha256sum "$file_path" | awk '{print $1}')
	elif command -v shasum >/dev/null 2>&1; then
		actual=$(shasum -a 256 "$file_path" | awk '{print $1}')
	else
		log_warn "No sha256 tool available; skipping checksum for $(basename "$file_path")"
		return 0
	fi
	if [[ "$actual" != "$expected" ]]; then
		log_error "Checksum mismatch for $(basename "$file_path")"
		log_error "  expected: ${expected}"
		log_error "  actual:   ${actual}"
		return 1
	fi
	log_success "Checksum verified for $(basename "$file_path")"
}

download_snapshot_file() {
	local url="$1"
	local dest_path="$2"
	local expected_sha="${3:-}"
	mkdir -p "$(dirname "$dest_path")"
	log_info "Downloading $(basename "$dest_path")"
	log_info "  URL: ${url}"
	if ! curl -L -C - --progress-bar -o "$dest_path" "$url"; then
		log_error "Failed to download ${url}"
		return 1
	fi
	verify_sha256 "$dest_path" "$expected_sha" || return 1
	log_success "Downloaded $(basename "$dest_path")"
}

# Canonical on-disk name for the "latest" alias, matching the snapshot site:
#   {network}-beacond-{pruned|archive}-latest.tar.lz4
#   {network}-reth-{pruned|archive}-latest.tar.lz4
snapshot_latest_basename() {
	local network="$1"
	local client="$2" # beacond | reth
	local snap_type="$3"
	echo "${network}-${client}-${snap_type}-latest.tar.lz4"
}

# Path to a local latest alias if one exists (exact name, then glob).
snapshot_local_latest_path() {
	local snapshots_dir="$1"
	local network="$2"
	local client="$3"
	local snap_type="$4"
	local exact="${snapshots_dir}/$(snapshot_latest_basename "$network" "$client" "$snap_type")"
	if [[ -f "$exact" ]]; then
		echo "$exact"
		return 0
	fi
	local match
	match=$(ls -1 "${snapshots_dir}"/*"${client}"*"-${snap_type}-latest.tar.lz4" 2>/dev/null | head -1 || true)
	if [[ -n "$match" && -f "$match" ]]; then
		echo "$match"
		return 0
	fi
	echo ""
	return 1
}

# Returns 0 to overwrite (download fresh), 1 to keep existing local files.
prompt_overwrite_local_snapshots() {
	local cl_path="$1"
	local el_path="$2"
	echo ""
	echo -e "${YELLOW}Existing local snapshots found:${RESET}"
	echo "  Consensus: ${cl_path}"
	echo "  Execution: ${el_path}"
	echo "Overwrite these with a fresh latest snapshot from the network, or continue using the files already on disk?"
	echo ""
	if [[ ! -t 0 ]]; then
		log_warn "Non-interactive session: keeping existing local snapshots"
		return 1
	fi
	local yn=""
	read -p "Overwrite with a fresh latest snapshot? [y/N]: " yn || true
	case "$yn" in
	y | Y | yes | Yes | YES)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# Unzip destination next to the archives:
#   {network}-beacond-*-latest.tar.lz4 -> ${snapshots_dir}/beacond
#   {network}-reth-*-latest.tar.lz4    -> ${snapshots_dir}/reth
snapshot_extract_dir() {
	local snapshots_dir="$1"
	local client="$2" # beacond | reth
	echo "${snapshots_dir}/${client}"
}

extract_lz4_tar() {
	local archive="$1"
	local dest="$2"
	mkdir -p "$dest"
	log_info "Extracting $(basename "$archive") → ${dest}"
	# Same shape as:
	#   mkdir -p beacond && lz4 -dc bepolia-beacond-pruned-latest.tar.lz4 | tar -xvf - -C beacond
	if ! lz4 -dc "$archive" | tar -xvf - -C "$dest"; then
		log_error "Failed to extract ${archive} into ${dest}"
		return 1
	fi
	log_success "Extracted $(basename "$archive") into ${dest}"
}

# Download latest snapshots for the needed types into snapshots_dir.
# Checks for local {network}-beacond|reth-{type}-latest.tar.lz4 first.
# If both consensus and execution latest files exist, prompt to overwrite
# or keep them before fetching the network index. Saves under canonical
# latest names. Prints a preflight summary (types, sizes, dest nodes)
# then continues for any types that still need a download.
download_network_snapshots() {
	local network="$1"
	local snapshots_dir="$2"
	local types_csv="$3" # space-separated: "pruned" or "pruned archive"
	local nodes_json="${4:-[]}"
	local type_override="${5:-}"

	if ! command -v curl >/dev/null 2>&1; then
		log_error "curl is required to download snapshots and is not installed or not in PATH."
		return 1
	fi

	mkdir -p "$snapshots_dir"

	# Prefer local latest aliases before hitting the snapshot host.
	local t types_to_fetch=""
	for t in $types_csv; do
		local cl_existing el_existing
		cl_existing=$(snapshot_local_latest_path "$snapshots_dir" "$network" "beacond" "$t" || true)
		el_existing=$(snapshot_local_latest_path "$snapshots_dir" "$network" "reth" "$t" || true)

		if [[ -n "$cl_existing" && -n "$el_existing" ]]; then
			if prompt_overwrite_local_snapshots "$cl_existing" "$el_existing"; then
				log_info "Removing existing local ${t} snapshots to download a fresh copy"
				rm -f "$cl_existing" "$el_existing"
				types_to_fetch="${types_to_fetch} ${t}"
			else
				log_info "Continuing with existing local ${t} snapshots"
				echo "$(basename "$cl_existing")" >"${snapshots_dir}/beacon-kit-${t}.name"
				echo "$(basename "$el_existing")" >"${snapshots_dir}/reth-${t}.name"
			fi
		else
			types_to_fetch="${types_to_fetch} ${t}"
		fi
	done
	types_to_fetch="${types_to_fetch# }"

	if [[ -z "$types_to_fetch" ]]; then
		log_success "Using existing local snapshots; skipping download"
		return 0
	fi

	local index_file="${snapshots_dir}/index.csv"
	fetch_snapshot_index "$network" "$index_file" || return 1

	echo ""
	echo "========= Snapshot download plan ========="
	echo "Network:         ${network}"
	echo "Index:           $(network_snapshot_index_url "$network")"
	if [[ -n "$type_override" ]]; then
		echo "Type override:   ${type_override} (applies to every node)"
	else
		echo "Type mapping:    validator/rpc-pruned → pruned, rpc-full → archive"
	fi
	echo "Types to fetch:  ${types_to_fetch}"
	echo ""

	local role_list
	local count i role mapped
	count=$(echo "$nodes_json" | jq 'length' 2>/dev/null || echo 0)
	for t in $types_to_fetch; do
		role_list=""
		for ((i = 0; i < count; i++)); do
			role=$(echo "$nodes_json" | jq -r ".[$i].role")
			mapped=$(snapshot_type_for_role "$role" "$type_override")
			if [[ "$mapped" == "$t" ]]; then
				if [[ -n "$role_list" ]]; then
					role_list="${role_list}, "
				fi
				role_list="${role_list}${i}-${role}"
			fi
		done
		local beacon_row el_row
		beacon_row=$(snapshot_select_latest "$index_file" "beacon-kit-${t}") || true
		el_row=$(snapshot_select_latest "$index_file" "reth-${t}") || true
		if [[ -z "$beacon_row" ]]; then
			log_error "No beacon-kit-${t} snapshot found in index"
			return 1
		fi
		if [[ -z "$el_row" ]]; then
			log_error "No reth-${t} snapshot found in index"
			return 1
		fi
		local b_url b_size e_url e_size
		b_url=$(echo "$beacon_row" | awk -F'\t' '{print $1}')
		b_size=$(echo "$beacon_row" | awk -F'\t' '{print $2}')
		e_url=$(echo "$el_row" | awk -F'\t' '{print $1}')
		e_size=$(echo "$el_row" | awk -F'\t' '{print $2}')
		echo "--- ${t} ---"
		echo "  Nodes:     ${role_list:-none}"
		echo "  Consensus: $(basename "$b_url") ($(format_bytes "$b_size"))"
		echo "  Execution: $(basename "$e_url") ($(format_bytes "$e_size"))"
		if [[ "$t" == "archive" ]]; then
			echo "  Note: archive snapshots are large and take significantly longer to download."
		fi
		echo ""
	done
	echo "Downloads are resumable. Starting now..."
	echo "=========================================="
	echo ""

	# Fail before transferring large archives if extract tools are missing.
	require_snapshot_tools || return 1

	for t in $types_to_fetch; do
		local beacon_row el_row
		beacon_row=$(snapshot_select_latest "$index_file" "beacon-kit-${t}") || return 1
		el_row=$(snapshot_select_latest "$index_file" "reth-${t}") || return 1
		local b_url b_size b_sha e_url e_size e_sha
		b_url=$(echo "$beacon_row" | awk -F'\t' '{print $1}')
		b_size=$(echo "$beacon_row" | awk -F'\t' '{print $2}')
		b_sha=$(echo "$beacon_row" | awk -F'\t' '{print $4}')
		e_url=$(echo "$el_row" | awk -F'\t' '{print $1}')
		e_size=$(echo "$el_row" | awk -F'\t' '{print $2}')
		e_sha=$(echo "$el_row" | awk -F'\t' '{print $4}')

		local cl_dest el_dest
		cl_dest="${snapshots_dir}/$(snapshot_latest_basename "$network" "beacond" "$t")"
		el_dest="${snapshots_dir}/$(snapshot_latest_basename "$network" "reth" "$t")"

		download_snapshot_file "$b_url" "$cl_dest" "$b_sha" || return 1
		download_snapshot_file "$e_url" "$el_dest" "$e_sha" || return 1
		# Record latest files for this type so restore can find them without re-parsing.
		echo "$(basename "$cl_dest")" >"${snapshots_dir}/beacon-kit-${t}.name"
		echo "$(basename "$el_dest")" >"${snapshots_dir}/reth-${t}.name"
	done
}

# Resolve downloaded archive path for layer (beacon-kit|reth) + type.
snapshot_archive_path() {
	local snapshots_dir="$1"
	local layer="$2" # beacon-kit or reth
	local snap_type="$3"
	local name_file="${snapshots_dir}/${layer}-${snap_type}.name"
	if [[ -f "$name_file" ]]; then
		local named="${snapshots_dir}/$(cat "$name_file")"
		if [[ -f "$named" ]]; then
			echo "$named"
			return 0
		fi
	fi
	local client="beacond"
	if [[ "$layer" == "reth" ]]; then
		client="reth"
	fi
	local match
	match=$(ls -1 "${snapshots_dir}"/*"${client}"*"-${snap_type}-latest.tar.lz4" 2>/dev/null | head -1 || true)
	if [[ -n "$match" && -f "$match" ]]; then
		echo "$match"
		return 0
	fi
	match=$(ls -1 "${snapshots_dir}"/*"${layer}"*"-${snap_type}"*.tar.lz4 2>/dev/null | head -1 || true)
	echo "$match"
}

# Official beacond tarballs unpack CometBFT DBs (application.db, …) at the
# archive root. Some wrap those DBs in a data/ prefix. Reth archives unpack
# db/ (etc.) at the root. Return the directory whose contents should be copied.
snapshot_restore_copy_source() {
	local extract_dir="$1"
	if [[ -d "${extract_dir}/application.db" || -d "${extract_dir}/blockstore.db" || -d "${extract_dir}/state.db" ]]; then
		echo "${extract_dir}"
		return 0
	fi
	if [[ -d "${extract_dir}/data" ]]; then
		echo "${extract_dir}/data"
		return 0
	fi
	echo "${extract_dir}"
}

# Copy each top-level item from src into dest. Replace existing directories of
# the same name so empty `beacond init` DBs are not merged with snapshot DBs.
# Leaves unrelated dest files (e.g. priv_validator_state.json) in place.
snapshot_copy_tree() {
	local src="$1"
	local dest="$2"
	mkdir -p "$dest"
	local item name
	for item in "${src}"/*; do
		[[ -e "$item" ]] || continue
		name="$(basename "$item")"
		if [[ -d "${dest}/${name}" && -d "$item" ]]; then
			rm -rf "${dest}/${name}"
		fi
		cp -a "$item" "${dest}/"
	done
}

# Extract once into snapshots/{beacond|reth}, then copy into each dest dir
# (newline-separated list). The unzipped tree is kept next to the archives.
snapshot_restore_layer() {
	local archive="$1"
	local extract_dir="$2"
	local dest_list_file="$3"

	if [[ -z "$archive" || ! -f "$archive" ]]; then
		log_error "Snapshot archive not found: ${archive:-<empty>}"
		return 1
	fi

	rm -rf "$extract_dir"
	extract_lz4_tar "$archive" "$extract_dir" || return 1

	if [[ ! -s "$dest_list_file" ]]; then
		log_info "No node destinations for $(basename "$archive"); left extracted at ${extract_dir}"
		return 0
	fi

	local copy_src
	copy_src="$(snapshot_restore_copy_source "$extract_dir")"

	local dest
	while IFS= read -r dest || [[ -n "$dest" ]]; do
		[[ -z "$dest" ]] && continue
		mkdir -p "$dest"
		log_info "Copying snapshot into ${dest}"
		snapshot_copy_tree "$copy_src" "$dest"
	done <"$dest_list_file"
}

# Restore downloaded snapshots into per-node beacond/data and reth datadirs.
# nodes_json is the .nodes array. beranodes_dir is the data root.
restore_network_snapshots() {
	local beranodes_dir="$1"
	local nodes_json="$2"
	local type_override="${3:-}"
	local reset_data="${4:-false}"

	local snapshots_dir="${beranodes_dir}${BERANODES_PATH_SNAPSHOTS}"
	local types
	types=$(snapshot_needed_types "$nodes_json" "$type_override")
	if [[ -z "$types" ]]; then
		log_warn "No snapshot types to restore"
		return 0
	fi

	require_snapshot_tools || return 1

	local t i count role mapped node_dir
	count=$(echo "$nodes_json" | jq 'length')

	for t in $types; do
		local cl_dests el_dests
		cl_dests=$(mktemp)
		el_dests=$(mktemp)
		for ((i = 0; i < count; i++)); do
			role=$(echo "$nodes_json" | jq -r ".[$i].role")
			mapped=$(snapshot_type_for_role "$role" "$type_override")
			if [[ "$mapped" != "$t" ]]; then
				continue
			fi
			node_dir="${beranodes_dir}${BERANODES_PATH_NODES}/${i}-${role}"
			mkdir -p "${node_dir}/beacond" "${node_dir}/bera-reth"
			if [[ "$reset_data" == true ]]; then
				rm -rf "${node_dir}/beacond/data"
				# Keep jwt / discovery-secret; wipe chain db folders only.
				rm -rf "${node_dir}/bera-reth/db" "${node_dir}/bera-reth/rocksdb" "${node_dir}/bera-reth/blobstore" "${node_dir}/bera-reth/static_files"
			fi
			# Older restores copied CometBFT DBs into the beacond home; drop those so
			# only beacond/data is used after this restore.
			rm -rf "${node_dir}/beacond/application.db" \
				"${node_dir}/beacond/blockstore.db" \
				"${node_dir}/beacond/state.db" \
				"${node_dir}/beacond/evidence.db" \
				"${node_dir}/beacond/deposits.db"
			echo "${node_dir}/beacond/data" >>"$cl_dests"
			echo "${node_dir}/bera-reth" >>"$el_dests"
		done

		local cl_archive el_archive
		cl_archive=$(snapshot_archive_path "$snapshots_dir" "beacon-kit" "$t")
		el_archive=$(snapshot_archive_path "$snapshots_dir" "reth" "$t")
		snapshot_restore_layer "$cl_archive" "$(snapshot_extract_dir "$snapshots_dir" "beacond")" "$cl_dests" || {
			rm -f "$cl_dests" "$el_dests"
			return 1
		}
		snapshot_restore_layer "$el_archive" "$(snapshot_extract_dir "$snapshots_dir" "reth")" "$el_dests" || {
			rm -f "$cl_dests" "$el_dests"
			return 1
		}
		rm -f "$cl_dests" "$el_dests"
	done
	log_success "Snapshot restore complete"
}

# High-level: download needed types then restore into node dirs.
apply_network_snapshots() {
	local network="$1"
	local beranodes_dir="$2"
	local nodes_json="$3"
	local type_override="${4:-}"
	local reset_data="${5:-false}"

	local types
	types=$(snapshot_needed_types "$nodes_json" "$type_override")
	if [[ -z "$types" ]]; then
		log_warn "No nodes to apply snapshots to"
		return 0
	fi
	download_network_snapshots "$network" "${beranodes_dir}${BERANODES_PATH_SNAPSHOTS}" "$types" "$nodes_json" "$type_override" || return 1
	restore_network_snapshots "$beranodes_dir" "$nodes_json" "$type_override" "$reset_data" || return 1
}
