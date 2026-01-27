# =============================================================================
# Command Dispatcher
# =============================================================================
# This module contains the main command routing logic that dispatches user
# commands to their respective handler functions.
#
# Functions:
#   - show_help: Display help information
#   - show_version: Display version information
#   - show_interactive_menu: Display interactive menu
#   - main: The primary entry point that routes commands to handlers
# =============================================================================

show_help() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: show_help" >&2
    cat <<EOF
beranode - CLI for managing Berachain nodes

USAGE:
    beranode <command> [options]

COMMANDS:
    init        Initialize a new Berachain node configuration
    start       Start the Berachain node
    help        Show this help message
    version     Show version information

OPTIONS:
    -h, --help     Show this help message
    -v, --version  Show version information

EXAMPLES:
    beranode init --network devnet --validators 1
    beranode start

For more information, visit: https://github.com/berachain/beranode-cli2
EOF
}

show_version() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: show_version" >&2
    echo "beranode v0.1.0"
}

show_interactive_menu() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: show_interactive_menu" >&2
    cat <<EOF

Welcome to beranode CLI!

Please run 'beranode --help' to see available commands.

EOF
}

main() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: main" >&2
    # No arguments - show interactive menu
    if [[ $# -eq 0 ]]; then
        show_interactive_menu
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        -h|--help|help)
            show_help
            ;;
        -v|--version|version)
            show_version
            ;;
        init)
            cmd_init "$@"
            ;;
        start)
            cmd_start "$@"
            ;;
        # stop)
        #     stop_node "$@"
        #     ;;
        # restart)
        #     restart_node "$@"
        #     ;;
        # status)
        #     show_node_status
        #     ;;
        # logs)
        #     show_logs "$@"
        #     ;;
        # config)
        #     show_config
        #     ;;
        # update)
        #     update_node
        #     ;;
        *)
            log_error "Unknown command: ${command}"
            echo ""
            show_help
            exit 1
            ;;
    esac
    # return 0
}
