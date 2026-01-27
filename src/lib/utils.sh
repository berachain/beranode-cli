#!/usr/bin/env bash
#
# utils.sh - Beranode CLI Utility Functions
#
# This module provides general utility functions including random name generation,
# EVM key operations, version checking, and directory management.
#

# =============================================================================
# Name Generation
# =============================================================================

# Helper to generate a random name in the format "hello-goodbye-something"
generate_random_name() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_random_name" >&2
    local adjectives=("happy" "quick" "silent" "wise" "brave" "fuzzy" "gentle" "shy" "fancy" "tiny" "giant" "strong")
    local actions=("run" "jump" "fly" "swim" "climb" "read" "hello" "goodbye" "sing" "whisper" "smile" "wink")
    local things=("tiger" "mountain" "river" "cloud" "forest" "moon" "star" "something" "echo" "flame" "ocean" "field")

    # Select one random adjective, one random action, and one random thing
    local first="${adjectives[$((RANDOM % ${#adjectives[@]}))]}"
    local second="${actions[$((RANDOM % ${#actions[@]}))]}"
    local third="${things[$((RANDOM % ${#things[@]}))]}"

    echo "${first}-${second}-${third}"
}

# =============================================================================
# EVM Key Operations
# =============================================================================

# Helper to generate an EVM wallet private key (64 hex chars) using Foundry's 'forge'
generate_evm_private_key() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_evm_private_key" >&2
    local private_key=$(cast wallet new 2>/dev/null | awk -F': ' '/Private key:/ {print $2}' | xargs)
    if [[ $? -ne 0 || -z "$private_key" ]]; then
        log_error "Failed to generate EVM private key using cast."
        return 1
    fi
    echo "$private_key"
}

# Helper to derive an EVM wallet address from a private key (64 hex chars) using 'cast'
get_evm_address_from_private_key() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: get_evm_address_from_private_key" >&2
    local priv_key="$1"
    local address=$(cast wallet address --private-key "$priv_key" 2>/dev/null)
    if [[ $? -ne 0 || -z "$address" ]]; then
        log_error "Failed to compute EVM address from private key using cast."
        return 1
    fi
    echo "$address"
}

# =============================================================================
# Version Checking
# =============================================================================

# Checks if `cast` is installed and meets SUPPORTED_CAST_VERSION.
check_cast_version() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: check_cast_version" >&2
    if ! command -v cast >/dev/null 2>&1; then
        log_error "'cast' (from Foundry) is not installed or not in PATH."
        return 1
    fi

    # Get current version ignoring "nightly". Extract first version in output (semver)
    cast_version_raw="$(cast --version 2>/dev/null | head -n1 | awk '{print $3}')"
    cast_version="${cast_version_raw%%-*}"  # Remove any -nightly or -foo
    required_version="${SUPPORTED_CAST_VERSION}"

    # Compare versions function (returns 0 if arg1 >= arg2)
    version_ge() {
        [ "$1" = "$2" ] && return 0
        local IFS=.
        local i ver1=($1) ver2=($2)
        # Fill empty fields in ver1 with zeros
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
            ver1[i]=0
        done
        for ((i=0; i<${#ver1[@]}; i++)); do
            [[ -z ${ver2[i]} ]] && ver2[i]=0
            if ((10#${ver1[i]} > 10#${ver2[i]})); then
                return 0
            elif ((10#${ver1[i]} < 10#${ver2[i]})); then
                return 1
            fi
        done
        return 0
    }

    if version_ge "$cast_version" "$required_version"; then
        log_success "Found 'cast' version $cast_version (required >= $required_version)"
        return 0
    else
        log_error "'cast' version $cast_version is less than required $required_version"
        return 1
    fi
}

# =============================================================================
# Directory Management
# =============================================================================

# Helper function to ensure a directory exists, creating it if necessary
ensure_dir_exists() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: ensure_dir_exists" >&2
    local dir_path="$1"
    local description="$2"

    if [[ -z "${dir_path}" ]]; then
        log_error "${description} path is not set."
        return 1
    fi
    if [[ ! -d "${dir_path}" ]]; then
        log_info "Creating ${description}: ${dir_path}"
        mkdir -p "${dir_path}"
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create ${description}: ${dir_path}"
            return 1
        fi
        log_success "${description} created: ${dir_path}"
    fi
    log_info "${description} exists: ${dir_path}"
}
