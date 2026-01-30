# =============================================================================
# [SECTION 1] Help Documentation
# =============================================================================
# Displays comprehensive usage information for the stop command.
# Invoked via: beranode stop --help
# =============================================================================

show_stop_help() {
	cat <<EOF
Usage: beranode stop [OPTIONS]

Stop Berachain nodes already running based on their PIDs in the runs directory.

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
# Primary entry point for the stop command. Orchestrates the entire node
# stop process from configuration parsing to node stop.
# =============================================================================

cmd_stop() {
	# Enable debug output if DEBUG_MODE is set
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_stop" >&2

	# Parse command line arguments
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
			show_stop_help
			return 0
			;;
		*)
			log_error "Unknown option: $1"
			show_stop_help
			return 1
			;;
		esac
	done

	# Find runs directory
	local runs_dir="${beranodes_dir}${BERANODES_PATH_RUNS}"
	if [[ ! -d "${runs_dir}" ]]; then
		log_error "Runs directory not found: ${runs_dir}"
		return 1
	fi

	# Find all PID files in the runs directory
	local pid_files=($(find "${runs_dir}" -name "*.pid"))
	if [[ ${#pid_files[@]} -eq 0 ]]; then
		log_info "No PID files found in runs directory: ${runs_dir}"
		return 0
	fi

	# Stop each node
	log_info "Stopping nodes in..."
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
