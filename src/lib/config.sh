#!/usr/bin/env bash
set -euo pipefail
################################################################################
# config.sh - Beranode CLI Configuration Loading Functions
################################################################################
#
# This module provides efficient configuration loading from JSON files.
# Instead of making 80+ separate jq calls, it loads the entire configuration
# into indexed arrays in a single operation, dramatically improving
# performance and reducing code complexity.
#
# NOTE: This implementation is compatible with bash 3.2+ (macOS default)
#
################################################################################

# Global arrays for configuration storage (bash 3.2 compatible)
declare -a BERANODE_CONFIG_KEYS
declare -a BERANODE_CONFIG_VALUES

################################################################################
# Function: load_config
# Description: Loads entire JSON config into associative array with dot notation
#
# This function performs a single jq invocation to extract all scalar values
# from a JSON file and stores them with dot-notation keys (e.g., "network",
# "clienttoml.chain_id", "nodes.0.role").
#
# Arguments:
#   $1 - config_file (string): Path to JSON configuration file
#
# Returns:
#   0 - Success (config loaded)
#   1 - Failure (file not found or invalid JSON)
#
# Example:
#   load_config "/path/to/beranodes.config.json"
#   network=$(get_config "network")
################################################################################
load_config() {
    local config_file="$1"

    # Validate file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    # Validate JSON is well-formed
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "Invalid JSON in config file: $config_file"
        return 1
    fi

    # Clear existing config
    BERANODE_CONFIG_KEYS=()
    BERANODE_CONFIG_VALUES=()

    # Load all scalars into parallel arrays using dot notation
    # This single jq call replaces 80+ separate jq invocations
    local count=0
    while IFS='=' read -r key value; do
        BERANODE_CONFIG_KEYS[$count]="$key"
        BERANODE_CONFIG_VALUES[$count]="$value"
        ((count++))
    done < <(jq -r '
        [paths(scalars) as $p | {($p | join(".")): getpath($p)}]
        | add
        | to_entries[]
        | "\(.key)=\(.value)"
    ' "$config_file" 2>/dev/null)

    if [[ $count -eq 0 ]]; then
        log_error "No configuration values loaded from: $config_file"
        return 1
    fi

    log_info "Loaded $count configuration values from: $config_file"
    return 0
}

################################################################################
# Function: get_config
# Description: Gets a configuration value with optional default
#
# Arguments:
#   $1 - key (string): Configuration key in dot notation (e.g., "network")
#   $2 - default (string, optional): Default value if key doesn't exist
#
# Returns:
#   Always succeeds, prints value or default
#
# Example:
#   network=$(get_config "network" "devnet")
#   port=$(get_config "nodes.0.ethrpc_port" "26657")
################################################################################
get_config() {
    local key="$1"
    local default="${2:-}"

    # Search through keys array to find matching index
    local i
    for i in "${!BERANODE_CONFIG_KEYS[@]}"; do
        if [[ "${BERANODE_CONFIG_KEYS[$i]}" == "$key" ]]; then
            echo "${BERANODE_CONFIG_VALUES[$i]}"
            return 0
        fi
    done

    # Key not found, return default
    echo "$default"
    return 0
}

################################################################################
# Function: get_config_required
# Description: Gets a required configuration value, failing if missing
#
# Arguments:
#   $1 - key (string): Configuration key in dot notation
#
# Returns:
#   0 - Success (prints value)
#   1 - Failure (key missing or value is null)
#
# Example:
#   chain_id=$(get_config_required "clienttoml.chain_id") || return 1
################################################################################
get_config_required() {
    local key="$1"
    local value

    # Search through keys array to find matching index
    local i
    for i in "${!BERANODE_CONFIG_KEYS[@]}"; do
        if [[ "${BERANODE_CONFIG_KEYS[$i]}" == "$key" ]]; then
            value="${BERANODE_CONFIG_VALUES[$i]}"
            if [[ -n "$value" ]] && [[ "$value" != "null" ]]; then
                echo "$value"
                return 0
            fi
        fi
    done

    log_error "Missing required config: $key"
    return 1
}

################################################################################
# Function: has_config
# Description: Checks if a configuration key exists
#
# Arguments:
#   $1 - key (string): Configuration key in dot notation
#
# Returns:
#   0 - Key exists and is not null
#   1 - Key missing or is null
#
# Example:
#   if has_config "optional_field"; then
#       value=$(get_config "optional_field")
#   fi
################################################################################
has_config() {
    local key="$1"

    # Search through keys array to find matching index
    local i
    for i in "${!BERANODE_CONFIG_KEYS[@]}"; do
        if [[ "${BERANODE_CONFIG_KEYS[$i]}" == "$key" ]]; then
            local value="${BERANODE_CONFIG_VALUES[$i]}"
            if [[ -n "$value" ]] && [[ "$value" != "null" ]]; then
                return 0
            fi
        fi
    done

    return 1
}

################################################################################
# Function: clear_config
# Description: Clears the configuration cache
#
# Returns:
#   Always succeeds
#
# Example:
#   clear_config
#   load_config "/new/config.json"
################################################################################
clear_config() {
    BERANODE_CONFIG_KEYS=()
    BERANODE_CONFIG_VALUES=()
    return 0
}

################################################################################
# Function: print_config
# Description: Prints all loaded configuration (for debugging)
#
# Returns:
#   Always succeeds
#
# Example:
#   print_config | grep "network"
################################################################################
print_config() {
    local i
    for i in "${!BERANODE_CONFIG_KEYS[@]}"; do
        echo "${BERANODE_CONFIG_KEYS[$i]}=${BERANODE_CONFIG_VALUES[$i]}"
    done | sort
}

################################################################################
# Function: get_config_count
# Description: Gets the number of loaded configuration values
#
# Returns:
#   Prints the count of configuration entries
#
# Example:
#   count=$(get_config_count)
#   echo "Loaded $count config values"
################################################################################
get_config_count() {
    echo "${#BERANODE_CONFIG_KEYS[@]}"
}

################################################################################
# Function: load_node_config
# Description: Loads configuration for a specific node by index
#
# This is a specialized function for loading node-specific configuration
# from the nodes array in the config file.
#
# Arguments:
#   $1 - config_file (string): Path to JSON configuration file
#   $2 - node_index (integer): Index of the node in the nodes array (0-based)
#
# Returns:
#   0 - Success (node config loaded with "node." prefix)
#   1 - Failure (node not found or invalid index)
#
# Example:
#   load_node_config "/path/to/config.json" 0
#   role=$(get_config "node.role")
#   port=$(get_config "node.ethrpc_port")
################################################################################
load_node_config() {
    local config_file="$1"
    local node_index="$2"

    # Validate file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    # Extract node object and load into config with "node." prefix
    local count=0
    local base_count=${#BERANODE_CONFIG_KEYS[@]}
    while IFS='=' read -r key value; do
        # Prefix all keys with "node." to avoid conflicts
        BERANODE_CONFIG_KEYS[$((base_count + count))]="node.$key"
        BERANODE_CONFIG_VALUES[$((base_count + count))]="$value"
        ((count++))
    done < <(jq -r ".nodes[$node_index] | [paths(scalars) as \$p | {(\$p | join(\".\")): getpath(\$p)}] | add | to_entries[] | \"\(.key)=\(.value)\"" "$config_file" 2>/dev/null)

    if [[ $count -eq 0 ]]; then
        log_error "Node $node_index not found in config file: $config_file"
        return 1
    fi

    log_info "Loaded node $node_index configuration ($count values)"
    return 0
}

################################################################################
# Function: get_node_config
# Description: Gets a node configuration value (shorthand for get_config with node prefix)
#
# Arguments:
#   $1 - key (string): Node configuration key without "node." prefix
#   $2 - default (string, optional): Default value if key doesn't exist
#
# Returns:
#   Always succeeds, prints value or default
#
# Example:
#   role=$(get_node_config "role" "validator")
#   port=$(get_node_config "ethrpc_port" "26657")
################################################################################
get_node_config() {
    local key="$1"
    local default="${2:-}"

    get_config "node.$key" "$default"
}

################################################################################
# Function: set_config
# Description: Sets a configuration value in memory (does not persist to file)
#
# Arguments:
#   $1 - key (string): Configuration key in dot notation
#   $2 - value (string): Value to set
#
# Returns:
#   Always succeeds
#
# Example:
#   set_config "network" "mainnet"
#   set_config "custom.field" "value"
################################################################################
set_config() {
    local key="$1"
    local value="$2"

    # Search for existing key and update, or append new key-value pair
    local i
    for i in "${!BERANODE_CONFIG_KEYS[@]}"; do
        if [[ "${BERANODE_CONFIG_KEYS[$i]}" == "$key" ]]; then
            BERANODE_CONFIG_VALUES[$i]="$value"
            return 0
        fi
    done

    # Key not found, append new entry
    local count=${#BERANODE_CONFIG_KEYS[@]}
    BERANODE_CONFIG_KEYS[$count]="$key"
    BERANODE_CONFIG_VALUES[$count]="$value"
    return 0
}
