#!/usr/bin/env bash
#
# logging.sh - Beranode CLI Logging Functions
#
# This module provides colored logging output and formatting functions
# for the beranode CLI.
#

# =============================================================================
# Color Definitions
# =============================================================================

# Color definitions
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    DIM=''
    RESET=''
fi

# =============================================================================
# Logging Functions
# =============================================================================

# Print a header
print_header() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: print_header" >&2
    echo ""
    echo -e "${BOLD}$*${RESET}"
    echo -e "${DIM}$(printf '%.0s─' {1..50})${RESET}"
}

# Logging functions
log_info() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_info" >&2
    echo -e "${BLUE}[INFO]${RESET} $*"
}

log_success() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_success" >&2
    echo -e "${GREEN}[OK]${RESET} $*"
}

log_warn() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_warn" >&2
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

log_error() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: log_error" >&2
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}
