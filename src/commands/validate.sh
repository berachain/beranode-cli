#!/usr/bin/env bash
set -euo pipefail
################################################################################
# validate.sh - Validate beranodes.config.json
################################################################################
#
# This command validates the beranodes.config.json file to ensure all fields
# are correctly formatted using regex patterns.
#
# Usage:
#   ./beranode validate [config_path]
#
# Arguments:
#   config_path - Path to beranodes.config.json (optional, defaults to ./beranodes/beranodes.config.json)
#
################################################################################

# Note: No set -euo pipefail here because it conflicts with optional parameters
# when built into beranode. The main beranode file already has set -e.

# Initialize DEBUG_MODE if not set
: "${DEBUG_MODE:=false}"

# Note: When built into the beranode executable, logging.sh and validation.sh
# are already included by build.sh. These source statements are only needed
# when running this script standalone for testing purposes.
if [[ ! $(type -t log_info) == "function" ]]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	source "${SCRIPT_DIR}/../lib/logging.sh"
	source "${SCRIPT_DIR}/../lib/validation.sh"
fi

# Main validation command
cmd_validate() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_validate" >&2

	# Check for help flag
	if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
		cmd_validate_help
		return 0
	fi

	local config_path="${1:-}"

	# Default config path if not provided
	if [[ -z "$config_path" ]]; then
		config_path="./beranodes/beranodes.config.json"
	fi

	# Convert to absolute path if relative
	if [[ ! "$config_path" = /* ]]; then
		config_path="$(pwd)/$config_path"
	fi

	log_info "Starting validation of beranodes configuration"
	log_info "Config file: $config_path"
	echo ""

	# Run validation
	if validate_beranodes_config "$config_path"; then
		echo ""
		log_success "Configuration validation completed successfully!"
		return 0
	else
		echo ""
		log_error "Configuration validation failed. Please fix the errors above."
		return 1
	fi
}

# Show help
cmd_validate_help() {
	cat <<EOF
Validate beranodes configuration file

USAGE:
    beranode validate [config_path]

ARGUMENTS:
    config_path    Path to beranodes.config.json file (optional)
                   Default: ./beranodes/beranodes.config.json

DESCRIPTION:
    Validates all fields in the beranodes.config.json file using regex patterns
    to ensure correct formatting. Checks include:

    - String formats (monikers, network names, etc.)
    - Boolean values (true/false)
    - Integer numbers and port ranges
    - Hex addresses (0x + 40 characters)
    - Private keys (0x + 64 characters)
    - JWT tokens
    - URLs and paths
    - Time durations (e.g., 5m0s, 10s)
    - Node and deposit object structures

EXAMPLES:
    # Validate default config
    beranode validate

    # Validate specific config file
    beranode validate ./custom/path/beranodes.config.json

    # Validate config in different directory
    beranode validate /absolute/path/to/beranodes.config.json

EXIT STATUS:
    0    All validations passed
    1    Validation errors found

EOF
}

# Note: Standalone execution code removed to prevent conflicts when built into beranode.
# When running standalone for testing, call cmd_validate directly:
#   source this_file.sh && cmd_validate "$@"
