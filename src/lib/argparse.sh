#!/usr/bin/env bash
set -euo pipefail
################################################################################
# argparse.sh - Beranode CLI Argument Parsing Functions
################################################################################
#
# This module provides shared argument parsing utilities to eliminate
# duplication across command files. It handles common patterns like
# --beranodes-dir and --help flags consistently.
#
################################################################################

################################################################################
# Function: parse_kv_arg
# Description: Parses a key-value argument pair, validating the value exists
#
# Arguments:
#   $1 - option_name (string): Name of the option (e.g., "--beranodes-dir")
#   $2 - next_arg (string): The next argument after the option
#
# Returns:
#   0 - Success (prints value)
#   1 - Failure (value is missing or starts with --)
#
# Example:
#   if value=$(parse_kv_arg "--network" "$2"); then
#       network="$value"
#       shift 2
#   else
#       shift
#   fi
################################################################################
parse_kv_arg() {
    local option_name="$1"
    local next_arg="${2:-}"

    # Check if next argument exists and doesn't look like another option
    if [[ -z "$next_arg" ]] || [[ "$next_arg" == --* ]]; then
        log_warn "${option_name} not provided or missing argument"
        return 1
    fi

    echo "$next_arg"
    return 0
}

################################################################################
# Function: parse_beranodes_dir
# Description: Parses --beranodes-dir argument with default fallback
#
# Arguments:
#   $1 - next_arg (string, optional): The next argument after --beranodes-dir
#
# Returns:
#   Always succeeds, prints directory path (default or provided)
#
# Example:
#   beranodes_dir=$(parse_beranodes_dir "$2")
################################################################################
parse_beranodes_dir() {
    local next_arg="${1:-}"

    if [[ -z "$next_arg" ]] || [[ "$next_arg" == --* ]]; then
        log_warn "--beranodes-dir not provided. Defaulting to: ${BERANODES_PATH_DEFAULT}"
        echo "${BERANODES_PATH_DEFAULT}"
    else
        echo "$next_arg"
    fi
}

################################################################################
# Function: check_unknown_option
# Description: Helper to log error for unknown options and show help
#
# Arguments:
#   $1 - unknown_option (string): The unknown option that was provided
#   $2 - help_function (string): Name of help function to call
#
# Returns:
#   1 - Always fails (this is an error condition)
#
# Example:
#   check_unknown_option "$1" "show_start_help"
################################################################################
check_unknown_option() {
    local unknown_option="$1"
    local help_function="$2"

    log_error "Unknown option: $unknown_option"

    # Call the help function if it exists
    if declare -f "$help_function" >/dev/null; then
        "$help_function"
    fi

    return 1
}

################################################################################
# Function: validate_required_arg
# Description: Validates that a required argument was provided
#
# Arguments:
#   $1 - value (string): The value to check
#   $2 - arg_name (string): Name of the argument (for error message)
#
# Returns:
#   0 - Success (value is not empty)
#   1 - Failure (value is empty)
#
# Example:
#   validate_required_arg "$network" "network" || return 1
################################################################################
validate_required_arg() {
    local value="$1"
    local arg_name="$2"

    if [[ -z "$value" ]]; then
        log_error "Required argument missing: $arg_name"
        return 1
    fi
    return 0
}

################################################################################
# Function: parse_boolean_flag
# Description: Parses a boolean flag (no value needed)
#
# Arguments:
#   $1 - flag_name (string): Name of the flag
#
# Returns:
#   0 - Always succeeds, sets flag to true
#
# Example:
#   case $1 in
#       --force)
#           force=$(parse_boolean_flag "force")
#           shift
#           ;;
#   esac
################################################################################
parse_boolean_flag() {
    echo "true"
    return 0
}

################################################################################
# Function: parse_integer_arg
# Description: Parses an integer argument with validation
#
# Arguments:
#   $1 - option_name (string): Name of the option
#   $2 - value (string): Value to parse as integer
#
# Returns:
#   0 - Success (prints integer value)
#   1 - Failure (value is not a valid integer)
#
# Example:
#   if count=$(parse_integer_arg "--validators" "$2"); then
#       validators="$count"
#       shift 2
#   fi
################################################################################
parse_integer_arg() {
    local option_name="$1"
    local value="${2:-}"

    if [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "${option_name} requires a valid integer value"
        return 1
    fi

    echo "$value"
    return 0
}

################################################################################
# Function: shift_args
# Description: Helper to determine how many positions to shift based on parsing
#
# Arguments:
#   $1 - has_value (boolean): Whether the option has a value (true/false)
#
# Returns:
#   Prints 2 if has_value is true, 1 otherwise
#
# Example:
#   shift $(shift_args true)  # Shifts 2 positions
#   shift $(shift_args false) # Shifts 1 position
################################################################################
shift_args() {
    local has_value="${1:-false}"

    if [[ "$has_value" == "true" ]]; then
        echo 2
    else
        echo 1
    fi
}
