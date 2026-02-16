# =============================================================================
# [SECTION 1] Help Documentation
# =============================================================================
# Displays comprehensive usage information for the stop command.
# Invoked via: beranode stop --help
# =============================================================================

show_stop_help() {
	cat <<EOF
Usage: beranode stop [OPTIONS]

Stop Berachain nodes.

In docker mode, uses docker compose to stop and remove all containers and
networks defined in the generated docker-compose.yml.

In local mode, stops processes by their PIDs stored in the runs directory.

Options:
  --beranodes-dir <path>    Specify the beranodes directory path
                            (default: \$PWD/beranodes)
  --help|-h                 Display this help message

Examples:
  beranode stop
  beranode stop --beranodes-dir /custom/path
  beranode stop --help

EOF
}

# =============================================================================
# [SECTION 2] Main Stop Command Function
# =============================================================================
# Primary entry point for the stop command. Detects the mode (docker or local)
# from beranodes.config.json and stops nodes accordingly.
# =============================================================================

cmd_stop() {
	# Enable debug output if DEBUG_MODE is set
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_stop" >&2

	# -------------------------------------------------------------------------
	# [STEP 1] Parse command line arguments
	# -------------------------------------------------------------------------
	local beranodes_dir="${BERANODES_PATH_DEFAULT}"

	while [[ $# -gt 0 ]]; do
		case $1 in
		--beranodes-dir)
			beranodes_dir=$(parse_beranodes_dir "$2")
			shift 2
			;;
		--help | -h)
			show_stop_help
			return 0
			;;
		*)
			check_unknown_option "$1" "show_stop_help" || return 1
			;;
		esac
	done

	# -------------------------------------------------------------------------
	# [STEP 2] Detect mode from configuration
	# -------------------------------------------------------------------------
	local config_path="${beranodes_dir}/beranodes.config.json"

	if [[ ! -f "${config_path}" ]]; then
		log_error "Configuration file not found: ${config_path}"
		log_error "Run 'beranode init' first to create a node configuration."
		return 1
	fi

	local mode
	mode=$(jq -r '.mode // "unknown"' "${config_path}") || mode="unknown"

	print_header "Stopping Beranode"

	# -------------------------------------------------------------------------
	# [STEP 3] Stop nodes based on mode
	# -------------------------------------------------------------------------
	if [[ "${mode}" == "docker" ]]; then
		_stop_docker_mode "${beranodes_dir}"
	else
		_stop_local_mode "${beranodes_dir}"
	fi
}

# =============================================================================
# [SECTION 3] Docker Mode Stop
# =============================================================================
# Uses docker compose to stop and remove all containers, networks, and
# orphaned services from the generated docker-compose.yml.
# =============================================================================

_stop_docker_mode() {
	local beranodes_dir="$1"
	local compose_file="${beranodes_dir}/tmp/docker-compose.yml"

	if [[ ! -f "${compose_file}" ]]; then
		log_warn "docker-compose.yml not found at ${compose_file}"
		log_info "Attempting to stop containers by name pattern instead..."

		# Fallback: try to stop containers matching the moniker
		local moniker
		moniker=$(jq -r '.moniker // ""' "${beranodes_dir}/beranodes.config.json") || moniker=""

		if [[ -n "${moniker}" ]]; then
			local containers
			containers=$(docker ps -aq --filter "name=${moniker}" 2>/dev/null) || true

			if [[ -n "${containers}" ]]; then
				log_info "Stopping containers matching '${moniker}'..."
				docker stop ${containers} 2>/dev/null || true
				docker rm ${containers} 2>/dev/null || true
				log_success "Containers stopped and removed."
			else
				log_info "No running containers found matching '${moniker}'."
			fi
		else
			log_warn "No moniker found in config. Cannot identify containers to stop."
		fi

		# Also try removing the beranet network
		docker network rm beranet 2>/dev/null || true
		return 0
	fi

	log_info "Mode: docker"
	log_info "Compose file: ${compose_file}"
	log_info "Stopping and removing containers..."

	# Use docker compose (v2) with fallback to docker-compose (v1)
	if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
		docker compose -f "${compose_file}" down --remove-orphans 2>&1
	elif command -v docker-compose &>/dev/null; then
		docker-compose -f "${compose_file}" down --remove-orphans 2>&1
	else
		log_error "Neither 'docker compose' nor 'docker-compose' found."
		log_error "Please install Docker Compose to manage docker-mode nodes."
		return 1
	fi

	if [[ $? -eq 0 ]]; then
		log_success "All containers stopped and removed."
	else
		log_warn "docker compose down returned non-zero. Some containers may still be running."
		log_info "You can manually stop them with: docker compose -f ${compose_file} down"
	fi
}

# =============================================================================
# [SECTION 4] Local Mode Stop
# =============================================================================
# Stops locally-running beacond and bera-reth processes by reading PID files
# from the runs directory, killing each process, and cleaning up PID files.
# =============================================================================

_stop_local_mode() {
	local beranodes_dir="$1"

	log_info "Mode: local"

	# Find runs directory
	local runs_dir="${beranodes_dir}${BERANODES_PATH_RUNS}"
	if [[ ! -d "${runs_dir}" ]]; then
		log_error "Runs directory not found: ${runs_dir}"
		return 1
	fi

	# Find all PID files in the runs directory
	local pid_files
	pid_files=($(find "${runs_dir}" -name "*.pid" 2>/dev/null)) || pid_files=()

	if [[ ${#pid_files[@]} -eq 0 ]]; then
		log_info "No PID files found in runs directory: ${runs_dir}"
		return 0
	fi

	# Stop each node
	log_info "Stopping nodes..."
	log_info "- Runs directory: ${runs_dir}"
	for pid_file in "${pid_files[@]}"; do
		local pid=$(cat "${pid_file}")
		local file=$(basename "${pid_file}")
		log_info "${file} / PID: ${pid}"
		if kill "${pid}" 2>/dev/null; then
			:
		else
			log_warn "Failed to stop process with PID: ${pid} (may not exist)"
		fi
		# Clean up by removing the PID file
		rm -f "${pid_file}"
	done

	log_info "Killing any remaining processes..."
	pkill -f beacond || true
	pkill -f bera-reth || true

	log_success "Stopped ${#pid_files[@]} nodes"
}
