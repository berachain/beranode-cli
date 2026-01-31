# =============================================================================
# Command Dispatcher - Core Routing Module
# =============================================================================
#
# VERSION: v0.6.0 (Current)
#
# PURPOSE:
#   This module serves as the central command router for the beranode CLI,
#   dispatching user commands to their respective handler functions and
#   managing the primary control flow of the application.
#
# CHANGELOG (Recent):
#   v0.6.0 - Added --help flag support for init and start commands
#   v0.6.0 - Implemented semantic versioning (semver) support
#   v0.1.x - Added beacond TOML configurations
#
# =============================================================================
# NUMBERED SECTION LEGEND
# =============================================================================
#   [1] USER-FACING OUTPUT FUNCTIONS
#       - show_help()              : Display comprehensive CLI help message
#       - show_version()           : Display current version number
#       - show_interactive_menu()  : Show welcome message for no-argument calls
#
#   [2] MAIN DISPATCHER FUNCTION
#       - main()                   : Primary entry point and command router
#
#   [3] COMMAND ROUTING TABLE
#       - Help/Version flags       : -h, --help, -v, --version
#       - Active commands          : init, start, validate
#       - Placeholder commands     : stop, restart, status, logs, config, update
#
# =============================================================================

# =============================================================================
# [1] USER-FACING OUTPUT FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: show_help
# Description: Displays comprehensive help information including usage,
#              available commands, options, and examples.
# Arguments: None
# Returns: None (outputs to stdout)
# -----------------------------------------------------------------------------
show_help() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: show_help" >&2

	cat <<EOF
beranode - CLI for managing Berachain nodes

USAGE:
    beranode <command> [options]

COMMANDS:
    init        Initialize a new Berachain node configuration
    start       Start the Berachain node
    validate    Validate beranodes configuration file
    help        Show this help message
    version     Show version information

OPTIONS:
    -h, --help     Show this help message
    -v, --version  Show version information

EXAMPLES:
    beranode init --network devnet --validators 1
    beranode start
    beranode validate

For more information, visit: https://github.com/berachain/beranode-cli2
EOF
}

# -----------------------------------------------------------------------------
# Function: show_version
# Description: Displays the current version of beranode CLI
# Arguments: None
# Returns: None (outputs version string to stdout)
# Variables Used:
#   - BERANODE_VERSION: Defined in src/lib/constants.sh
# -----------------------------------------------------------------------------
show_version() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: show_version" >&2

	echo "beranode v${BERANODE_VERSION}"
}

# -----------------------------------------------------------------------------
# Function: show_interactive_menu
# Description: Displays a welcome message when beranode is called without
#              any arguments, guiding users to use --help for more info.
# Arguments: None
# Returns: None (outputs to stdout)
# -----------------------------------------------------------------------------
show_interactive_menu() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: show_interactive_menu" >&2

	cat <<EOF

Welcome to beranode CLI!

Please run 'beranode --help' to see available commands.

EOF
}

# =============================================================================
# [2] MAIN DISPATCHER FUNCTION
# =============================================================================

# -----------------------------------------------------------------------------
# Function: main
# Description: Primary entry point for command routing. Parses the first
#              argument as a command and delegates to the appropriate handler.
#              If no arguments are provided, displays the interactive menu.
# Arguments:
#   $@ - All command-line arguments passed to beranode
# Returns:
#   0 - Success
#   1 - Unknown command or error
# Flow:
#   1. Check if arguments exist, show menu if none
#   2. Extract command from first argument
#   3. Route to appropriate handler via case statement
#   4. Pass remaining arguments to the handler function
# -----------------------------------------------------------------------------
main() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: main" >&2

	# [2.1] Handle no-argument invocation
	if [[ $# -eq 0 ]]; then
		show_interactive_menu
		exit 0
	fi

	# [2.2] Extract command and shift arguments
	local command="$1"
	shift

	# =========================================================================
	# [3] COMMAND ROUTING TABLE
	# =========================================================================
	# This case statement maps user commands to their handler functions.
	# Each active command calls a cmd_* function defined in src/commands/
	# =========================================================================

	case "$command" in
	# ---------------------------------------------------------------------
	# [3.1] Help and Version Flags
	# Handles: -h, --help, help, -v, --version, version
	# Added in: v0.6.0 with enhanced --help support
	# ---------------------------------------------------------------------
	-h | --help | help)
		show_help
		;;
	-v | --version | version)
		show_version
		;;

	# ---------------------------------------------------------------------
	# [3.2] Active Commands
	# These commands are currently implemented and functional
	# ---------------------------------------------------------------------
	init)
		# Initialize new node configuration
		# Handler: cmd_init() in src/commands/init.sh
		# Added: v0.1.x, Enhanced: v0.6.0 with --help flag
		cmd_init "$@"
		;;
	start)
		# Start the Berachain node
		# Handler: cmd_start() in src/commands/start.sh
		# Added: v0.1.x, Enhanced: v0.6.0 with --help flag
		cmd_start "$@"
		;;
	stop)
		# Stop the Berachain node
		# Handler: cmd_stop() in src/commands/stop.sh
		# Added: v0.6.0 with --help flag
		cmd_stop "$@"
		;;
	validate)
		# Validate beranodes configuration file
		# Handler: cmd_validate() in src/commands/validate.sh
		# Added: v0.6.0 with regex-based validation
		cmd_validate "$@"
		;;

	# ---------------------------------------------------------------------
	# [3.3] Placeholder Commands (Future Implementation)
	# These commands are reserved for future versions
	# ---------------------------------------------------------------------
	# stop)
	#     # Stop running node gracefully
	#     stop_node "$@"
	#     ;;
	# restart)
	#     # Restart node (stop + start)
	#     restart_node "$@"
	#     ;;
	# status)
	#     # Display current node status
	#     show_node_status
	#     ;;
	# logs)
	#     # Display and follow node logs
	#     show_logs "$@"
	#     ;;
	# config)
	#     # Display current configuration
	#     show_config
	#     ;;
	# update)
	#     # Update node to latest version
	#     update_node
	#     ;;

	# ---------------------------------------------------------------------
	# [3.4] Unknown Command Handler
	# Displays error message and help text for unrecognized commands
	# ---------------------------------------------------------------------
	*)
		log_error "Unknown command: ${command}"
		echo ""
		show_help
		exit 1
		;;
	esac
}
