#!/usr/bin/env bash
set -euo pipefail
################################################################################
# json.sh - Beranode CLI JSON Processing Functions
################################################################################
#
# This module provides safe JSON processing utilities using jq, with built-in
# null checking and error handling. It prevents common errors from missing or
# null JSON fields.
#
################################################################################

################################################################################
# Function: jq_get
# Description: Safely extracts a JSON value with optional default fallback
#
# Arguments:
#   $1 - file (string): Path to JSON file
#   $2 - path (string): jq path expression (e.g., '.field' or '.nested.field')
#   $3 - default (string, optional): Default value if field is null/missing
#
# Returns:
#   0 - Success (prints value or default)
#   1 - Failure (jq command failed)
#
# Example:
#   value=$(jq_get "config.json" ".network" "devnet")
#   echo "Network: $value"
################################################################################
jq_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"
    local value

    # Execute jq and capture value, treating errors as "null"
    if ! value=$(jq -r "$path" "$file" 2>/dev/null); then
        value="null"
    fi

    # Return default if value is null or empty
    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi

    return 0
}

################################################################################
# Function: jq_get_required
# Description: Extracts a required JSON value, failing if it's null or missing
#
# Arguments:
#   $1 - file (string): Path to JSON file
#   $2 - path (string): jq path expression (e.g., '.field' or '.nested.field')
#
# Returns:
#   0 - Success (prints value)
#   1 - Failure (field is null, missing, or jq failed)
#
# Example:
#   chain_id=$(jq_get_required "config.json" ".chain_id") || return 1
################################################################################
jq_get_required() {
    local file="$1"
    local path="$2"
    local value

    # Check if file exists
    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi

    # Execute jq and capture value
    if ! value=$(jq -r "$path" "$file" 2>/dev/null); then
        log_error "Failed to parse JSON field: $path in $file"
        return 1
    fi

    # Fail if value is null or empty
    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        log_error "Missing required field: $path in $file"
        return 1
    fi

    echo "$value"
    return 0
}

################################################################################
# Function: jq_has_field
# Description: Checks if a JSON file contains a specific field
#
# Arguments:
#   $1 - file (string): Path to JSON file
#   $2 - path (string): jq path expression
#
# Returns:
#   0 - Success (field exists and is not null)
#   1 - Failure (field is missing or null)
#
# Example:
#   if jq_has_field "config.json" ".optional_field"; then
#       value=$(jq_get "config.json" ".optional_field")
#   fi
################################################################################
jq_has_field() {
    local file="$1"
    local path="$2"
    local value

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    if ! value=$(jq -r "$path" "$file" 2>/dev/null); then
        return 1
    fi

    if [[ "$value" == "null" ]]; then
        return 1
    fi

    return 0
}

################################################################################
# Function: jq_validate_json
# Description: Validates that a file contains valid JSON
#
# Arguments:
#   $1 - file (string): Path to JSON file
#
# Returns:
#   0 - Success (file contains valid JSON)
#   1 - Failure (file not found or contains invalid JSON)
#
# Example:
#   if jq_validate_json "config.json"; then
#       echo "Config is valid JSON"
#   fi
################################################################################
jq_validate_json() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi

    if ! jq empty "$file" 2>/dev/null; then
        log_error "Invalid JSON in file: $file"
        return 1
    fi

    return 0
}

################################################################################
# Function: jq_get_array_length
# Description: Gets the length of a JSON array
#
# Arguments:
#   $1 - file (string): Path to JSON file
#   $2 - path (string): jq path expression to array
#
# Returns:
#   0 - Success (prints array length)
#   1 - Failure (field is not an array or doesn't exist)
#
# Example:
#   count=$(jq_get_array_length "config.json" ".nodes")
#   echo "Found $count nodes"
################################################################################
jq_get_array_length() {
    local file="$1"
    local path="$2"
    local length

    if ! length=$(jq -r "${path} | length" "$file" 2>/dev/null); then
        log_error "Failed to get array length: $path in $file"
        return 1
    fi

    if [[ "$length" == "null" ]]; then
        log_error "Field is not an array: $path in $file"
        return 1
    fi

    echo "$length"
    return 0
}

################################################################################
# Function: jq_get_array_item
# Description: Gets a specific item from a JSON array by index
#
# Arguments:
#   $1 - file (string): Path to JSON file
#   $2 - path (string): jq path expression to array
#   $3 - index (integer): Array index (0-based)
#
# Returns:
#   0 - Success (prints array item as JSON)
#   1 - Failure (array doesn't exist or index out of bounds)
#
# Example:
#   first_node=$(jq_get_array_item "config.json" ".nodes" 0)
#   echo "First node: $first_node"
################################################################################
jq_get_array_item() {
    local file="$1"
    local path="$2"
    local index="$3"
    local item

    if ! item=$(jq -r "${path}[${index}]" "$file" 2>/dev/null); then
        log_error "Failed to get array item: ${path}[${index}] in $file"
        return 1
    fi

    if [[ "$item" == "null" ]]; then
        log_error "Array index out of bounds: ${path}[${index}] in $file"
        return 1
    fi

    echo "$item"
    return 0
}

################################################################################
# Function: jq_set_field
# Description: Sets a field value in a JSON file (modifies file in place)
#
# Arguments:
#   $1 - file (string): Path to JSON file
#   $2 - path (string): jq path expression
#   $3 - value (string): New value for the field
#
# Returns:
#   0 - Success (field updated)
#   1 - Failure (unable to update file)
#
# Example:
#   jq_set_field "config.json" ".network" "mainnet"
################################################################################
jq_set_field() {
    local file="$1"
    local path="$2"
    local value="$3"
    local temp_file

    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi

    temp_file=$(mktemp)

    # Update field and write to temp file
    if ! jq "${path} = \"${value}\"" "$file" > "$temp_file" 2>/dev/null; then
        log_error "Failed to set field: $path in $file"
        rm -f "$temp_file"
        return 1
    fi

    # Replace original file with updated version
    if ! mv "$temp_file" "$file"; then
        log_error "Failed to update file: $file"
        rm -f "$temp_file"
        return 1
    fi

    return 0
}

################################################################################
# Function: jq_pretty_print
# Description: Pretty-prints a JSON file with proper indentation
#
# Arguments:
#   $1 - file (string): Path to JSON file
#
# Returns:
#   0 - Success (prints formatted JSON)
#   1 - Failure (invalid JSON)
#
# Example:
#   jq_pretty_print "config.json"
################################################################################
jq_pretty_print() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi

    if ! jq '.' "$file" 2>/dev/null; then
        log_error "Invalid JSON in file: $file"
        return 1
    fi

    return 0
}
