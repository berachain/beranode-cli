#!/usr/bin/env bash
#
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                    BERANODE CLI LOGGING MODULE v0.2.1                     ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# FILE:         logging.sh
# PURPOSE:      Provides colored logging output and formatting functions
# SINCE:        v0.1.0
# MODIFIED:     v0.2.1 - Enhanced formatting and documentation
#
# DESCRIPTION:
#   This module is the central logging system for the Beranode CLI. It provides
#   terminal-aware colored output that automatically disables when output is
#   redirected or when running in non-interactive environments. All logging
#   functions support DEBUG_MODE for development troubleshooting.
#
# VERSION CONTEXT:
#   In v0.2.1, this logging system is used throughout the CLI for consistent
#   user feedback during node initialization, configuration, startup, and
#   runtime operations. It integrates with the help system (--help commands)
#   and provides the primary interface for user notifications.
#
# USAGE:
#   source ./src/lib/logging.sh
#   log_info "Starting node initialization..."
#   log_success "Node successfully started!"
#   log_warn "Port 8545 already in use, trying alternative..."
#   log_error "Failed to connect to execution layer"
#   print_header "Node Configuration"
#
# LEGEND (Function Reference):
#   [1] Color Detection System  - Automatically enables/disables colors
#   [2] print_header()          - Displays formatted section headers
#   [3] log_info()             - Informational messages (blue)
#   [4] log_success()          - Success confirmations (green)
#   [5] log_warn()             - Warning messages (yellow)
#   [6] log_error()            - Error messages (red, stderr)
#
# DEBUG MODE:
#   Set DEBUG_MODE=true to see function call traces:
#   $ DEBUG_MODE=true ./beranode start
#
# =============================================================================

# =============================================================================
# [1] COLOR DEFINITIONS - Terminal-Aware Color Codes
# =============================================================================
#
# This section detects whether the output is to a terminal and whether colors
# are supported. Colors are automatically disabled when:
#   - Output is redirected to a file or pipe
#   - Running in a non-TTY environment (CI/CD, scripts)
#   - TERM variable is set to "dumb"
#
# ANSI Color Codes:
#   RED:    Error messages and critical issues
#   GREEN:  Success messages and confirmations
#   YELLOW: Warnings and deprecation notices
#   BLUE:   Informational messages
#   BOLD:   Headers and emphasis
#   DIM:    Subtle text like separators
#   RESET:  Clears all formatting
#
# =============================================================================

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
	# Terminal supports colors - enable ANSI escape codes
	readonly RED='\033[0;31m'
	readonly GREEN='\033[0;32m'
	readonly YELLOW='\033[0;33m'
	readonly BLUE='\033[0;34m'
	readonly BOLD='\033[1m'
	readonly DIM='\033[2m'
	readonly RESET='\033[0m'
else
	# Non-interactive or unsupported terminal - disable colors
	readonly RED=''
	readonly GREEN=''
	readonly YELLOW=''
	readonly BLUE=''
	readonly BOLD=''
	readonly DIM=''
	readonly RESET=''
fi

# =============================================================================
# [2] PRINT_HEADER - Section Header Formatter
# =============================================================================
#
# FUNCTION:     print_header
# PURPOSE:      Displays a formatted section header with separator line
# PARAMETERS:   $* - Header text (all arguments concatenated)
# OUTPUT:       Stdout
# DEBUG:        Traces when DEBUG_MODE=true
#
# DESCRIPTION:
#   Creates visually distinct section headers in the CLI output. Used to
#   separate major operations like "Node Initialization", "Starting Services",
#   "Configuration Validation", etc.
#
# EXAMPLE:
#   print_header "Beranode Configuration"
#
# OUTPUT:
#
#   Beranode Configuration
#   ──────────────────────────────────────────────────
#
# =============================================================================

print_header() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: print_header" >&2

	echo ""
	echo -e "${BOLD}$*${RESET}"
	echo -e "${DIM}$(printf '%.0s─' {1..50})${RESET}"
}

# =============================================================================
# [3] LOG_INFO - Informational Messages
# =============================================================================
#
# FUNCTION:     log_info
# PURPOSE:      Display informational messages to the user
# PARAMETERS:   $* - Message text (all arguments concatenated)
# OUTPUT:       Stdout
# COLOR:        Blue [INFO] prefix
# DEBUG:        Traces when DEBUG_MODE=true
#
# DESCRIPTION:
#   Used for general informational messages that don't require user action.
#   Examples include progress updates, status information, and configuration
#   values being applied.
#
# EXAMPLE:
#   log_info "Detected 4 CPU cores, optimizing thread pool..."
#   log_info "Loading configuration from beranode.config"
#
# =============================================================================

log_info() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_info" >&2

	echo -e "${BLUE}[INFO]${RESET} $*"
}

# =============================================================================
# [4] LOG_SUCCESS - Success Confirmations
# =============================================================================
#
# FUNCTION:     log_success
# PURPOSE:      Display success messages for completed operations
# PARAMETERS:   $* - Message text (all arguments concatenated)
# OUTPUT:       Stdout
# COLOR:        Green [OK] prefix
# DEBUG:        Traces when DEBUG_MODE=true
#
# DESCRIPTION:
#   Confirms successful completion of operations. Used after critical steps
#   complete successfully, such as node startup, configuration validation,
#   service health checks, etc.
#
# EXAMPLE:
#   log_success "Node started successfully on port 8545"
#   log_success "All health checks passed"
#
# =============================================================================

log_success() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_success" >&2

	echo -e "${GREEN}[OK]${RESET} $*"
}

# =============================================================================
# [5] LOG_WARN - Warning Messages
# =============================================================================
#
# FUNCTION:     log_warn
# PURPOSE:      Display warning messages for non-critical issues
# PARAMETERS:   $* - Message text (all arguments concatenated)
# OUTPUT:       Stdout
# COLOR:        Yellow [WARN] prefix
# DEBUG:        Traces when DEBUG_MODE=true
#
# DESCRIPTION:
#   Alerts users to potential issues that don't prevent operation but may
#   require attention. Examples include deprecated options, suboptimal
#   configurations, resource constraints, or fallback behaviors.
#
# EXAMPLE:
#   log_warn "Port 8545 already in use, using 8645 instead"
#   log_warn "Running with default configuration (no beranode.config found)"
#
# =============================================================================

log_warn() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_warn" >&2

	echo -e "${YELLOW}[WARN]${RESET} $*"
}

# =============================================================================
# [6] LOG_ERROR - Error Messages
# =============================================================================
#
# FUNCTION:     log_error
# PURPOSE:      Display error messages for failures and critical issues
# PARAMETERS:   $* - Message text (all arguments concatenated)
# OUTPUT:       Stderr (error stream)
# COLOR:        Red [ERROR] prefix
# DEBUG:        Traces when DEBUG_MODE=true
#
# DESCRIPTION:
#   Communicates errors and failures to the user. These messages indicate
#   operations that could not complete successfully. Always outputs to stderr
#   to ensure proper error stream handling in scripts and logs.
#
# NOTE:
#   This function does NOT exit the script - it only displays the message.
#   The calling code is responsible for handling the error and determining
#   whether to exit, retry, or continue.
#
# EXAMPLE:
#   log_error "Failed to connect to execution layer at localhost:8551"
#   log_error "Invalid chain ID: expected 80087, got 80088"
#
# =============================================================================

log_error() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_error" >&2

	echo -e "${RED}[ERROR]${RESET} $*" >&2
}

# =============================================================================
# END OF LOGGING MODULE
# =============================================================================
