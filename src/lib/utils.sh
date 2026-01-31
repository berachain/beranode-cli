#!/usr/bin/env bash
################################################################################
# utils.sh - Beranode CLI Utility Functions
################################################################################
#
# This module provides general utility functions for the Beranode CLI including:
# - Random name generation for node identifiers
# - EVM key operations (generation and address derivation)
# - Version checking for required dependencies
# - Directory management utilities
#
# LEGEND - Function Reference by Section:
# ──────────────────────────────────────────────────────────────────────────────
# 1. NAME GENERATION
#    └─ generate_random_name()          : Generate random three-word node names
#
# 2. EVM KEY OPERATIONS
#    ├─ generate_evm_private_key()      : Generate new EVM wallet private key
#    └─ get_evm_address_from_private_key() : Derive EVM address from private key
#
# 3. VERSION CHECKING
#    └─ check_cast_version()            : Validate Foundry cast version
#
# 4. DIRECTORY MANAGEMENT
#    └─ ensure_dir_exists()             : Create directory if it doesn't exist
#
################################################################################

################################################################################
# 1. NAME GENERATION
################################################################################

# Generates a random three-part name in the format: "adjective-action-thing"
# This is used to create memorable, unique identifiers for nodes.
#
# Example outputs: "happy-jump-tiger", "brave-fly-mountain", "tiny-hello-star"
#
# Returns:
#   String in format: {adjective}-{action}-{thing}
generate_random_name() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_random_name" >&2

	# Word pools for name generation
	local adjectives=("happy" "quick" "silent" "wise" "brave" "fuzzy" "gentle" "shy" "fancy" "tiny" "giant" "strong")
	local actions=("run" "jump" "fly" "swim" "climb" "read" "hello" "goodbye" "sing" "whisper" "smile" "wink")
	local things=("tiger" "mountain" "river" "cloud" "forest" "moon" "star" "something" "echo" "flame" "ocean" "field")

	# Randomly select one word from each pool using RANDOM modulo array length
	local first="${adjectives[$((RANDOM % ${#adjectives[@]}))]}"
	local second="${actions[$((RANDOM % ${#actions[@]}))]}"
	local third="${things[$((RANDOM % ${#things[@]}))]}"

	# Return hyphen-separated combination
	echo "${first}-${second}-${third}"
}

# Removes all occurrences of a given string from a Bash array.
# Usage:
#   filtered_array=($(array_exclude_element seeds[@] "hello"))
# Parameters:
#   $1 - Name of the array variable (passed as "${array[@]}")
#   $2 - String value to exclude
# Returns:
#   Prints array elements (space-separated), excluding the specified value.
array_exclude_element() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: array_exclude_element" >&2

	local -a input_array
	local exclude_value
	local -a result=()

	# Read input: first arg is (name of) array by reference, second is value to exclude$1
	input_array=("${!1}")
	exclude_value="$2"

	for item in "${input_array[@]}"; do
		if [[ "$item" != "$exclude_value" ]]; then
			result+=("$item")
		fi
	done

	# Return new array (as array, not as string)
	echo "${result[@]}"
}

format_csv_as_string() {
	local origins="$1"
	local result=""
	IFS=',' read -ra origins_array <<<"$origins"
	for origin in "${origins_array[@]}"; do
		origin_trimmed="$(echo "$origin" | xargs)"
		if [ -n "$origin_trimmed" ]; then
			if [ -z "$result" ]; then
				result="\"$origin_trimmed\""
			else
				result="$result,\"$origin_trimmed\""
			fi
		fi
	done
	echo "$result"
}

################################################################################
# 2. EVM KEY OPERATIONS
################################################################################

# Generates a new EVM wallet private key using Foundry's 'cast' tool.
# The private key is a 64-character hexadecimal string (with optional 0x prefix).
#
# Dependencies:
#   - Requires 'cast' from Foundry toolkit to be installed and in PATH
#
# Returns:
#   Private key (64 hex chars) on success
#   Exit code 1 on failure
generate_evm_private_key() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: generate_evm_private_key" >&2

	# Use 'cast wallet new' to generate a new wallet and extract the private key
	# Format: "Private key: 0x..." - we parse this with awk and xargs to trim
	local private_key=$(cast wallet new 2>/dev/null | awk -F': ' '/Private key:/ {print $2}' | xargs)

	# Validate that key generation succeeded and returned a non-empty value
	if [[ $? -ne 0 || -z "$private_key" ]]; then
		log_error "Failed to generate EVM private key using cast."
		return 1
	fi

	echo "$private_key"
}

# Derives the EVM wallet address from a given private key using 'cast'.
# The address is computed using standard Ethereum cryptographic operations.
#
# Parameters:
#   $1 - Private key (64 hex chars, with or without 0x prefix)
#
# Returns:
#   EVM address (0x-prefixed, 40 hex chars) on success
#   Exit code 1 on failure
get_evm_address_from_private_key() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: get_evm_address_from_private_key" >&2

	local priv_key="$1"

	# Use 'cast wallet address' to derive the public address from the private key
	local address=$(cast wallet address --private-key "$priv_key" 2>/dev/null)

	# Validate that address derivation succeeded and returned a non-empty value
	if [[ $? -ne 0 || -z "$address" ]]; then
		log_error "Failed to compute EVM address from private key using cast."
		return 1
	fi

	echo "$address"
}

################################################################################
# 3. VERSION CHECKING
################################################################################

# Validates that 'cast' from Foundry is installed and meets minimum version.
# Compares the installed version against SUPPORTED_CAST_VERSION from constants.
#
# Uses semver comparison logic to handle version numbers like "1.2.3".
# Strips any suffix like "-nightly" before comparison.
#
# Dependencies:
#   - Requires 'cast' command to be available in PATH
#   - Requires SUPPORTED_CAST_VERSION to be set in constants
#
# Returns:
#   Exit code 0 if version requirement is met
#   Exit code 1 if cast is not installed or version is insufficient
check_cast_version() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: check_cast_version" >&2

	# First, verify that 'cast' command exists in PATH
	if ! command -v cast >/dev/null 2>&1; then
		log_error "'cast' (from Foundry) is not installed or not in PATH."
		return 1
	fi

	# Extract version from 'cast --version' output
	# Example output: "cast v0.6.0 (abc123 2024-01-01T00:00:00Z)"
	# We extract the 3rd field and strip any suffix like "-nightly"
	cast_version_raw="$(cast --version 2>/dev/null | head -n1 | awk '{print $3}')"
	cast_version="${cast_version_raw%%-*}" # Strip suffix: "1.2.3-nightly" -> "1.2.3"
	required_version="${SUPPORTED_CAST_VERSION}"

	# ───────────────────────────────────────────────────────────────────────
	# Nested function: Semantic version comparison (>= check)
	# ───────────────────────────────────────────────────────────────────────
	# Compares two semver strings (e.g., "1.2.3" vs "1.2.0")
	# Returns 0 (success) if version1 >= version2, 1 otherwise
	version_ge() {
		# Quick check: if versions are identical, return success immediately
		[ "$1" = "$2" ] && return 0

		local IFS=. # Split on dots
		local i ver1=($1) ver2=($2)

		# Normalize arrays: fill shorter array with zeros
		for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
			ver1[i]=0
		done

		# Compare each version component (major, minor, patch, etc.)
		for ((i = 0; i < ${#ver1[@]}; i++)); do
			[[ -z ${ver2[i]} ]] && ver2[i]=0

			# Use base-10 notation (10#) to avoid octal interpretation
			if ((10#${ver1[i]} > 10#${ver2[i]})); then
				return 0 # ver1 is greater
			elif ((10#${ver1[i]} < 10#${ver2[i]})); then
				return 1 # ver1 is less
			fi
			# If equal, continue to next component
		done

		return 0 # All components equal, so ver1 >= ver2
	}

	# Perform version comparison and return result
	if version_ge "$cast_version" "$required_version"; then
		log_success "Found 'cast' version $cast_version (required >= $required_version)"
		return 0
	else
		log_error "'cast' version $cast_version is less than required $required_version"
		return 1
	fi
}

check_curl_version() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: check_curl_version" >&2

	# First, verify that 'curl' command exists in PATH
	if ! command -v curl >/dev/null 2>&1; then
		log_error "'curl' is not installed or not in PATH."
		return 1
	fi
}

check_tar_gz_version() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: check_tar_gz_version" >&2

	# First, verify that 'tar' command exists in PATH
	if ! command -v tar >/dev/null 2>&1; then
		log_error "'tar' is not installed or not in PATH."
		return 1
	fi
}

################################################################################
# 4. DIRECTORY MANAGEMENT
################################################################################

# Ensures a directory exists, creating it if necessary (including parent directories).
# Provides user-friendly logging with custom descriptions for each directory.
#
# Parameters:
#   $1 - dir_path:    Absolute or relative path to the directory
#   $2 - description: Human-readable description for logging (e.g., "data directory")
#
# Returns:
#   Exit code 0 if directory exists or was created successfully
#   Exit code 1 if path is empty or directory creation fails
ensure_dir_exists() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: ensure_dir_exists" >&2

	local dir_path="$1"
	local description="$2"

	# Validate that a directory path was provided
	if [[ -z "${dir_path}" ]]; then
		log_error "${description} path is not set."
		return 1
	fi

	# Check if directory already exists
	if [[ ! -d "${dir_path}" ]]; then
		log_info "Creating ${description}: ${dir_path}"

		# Create directory with parent directories (-p flag)
		mkdir -p "${dir_path}"

		# Verify creation succeeded
		if [[ $? -ne 0 ]]; then
			log_error "Failed to create ${description}: ${dir_path}"
			return 1
		fi

		log_success "${description} created: ${dir_path}"
	fi

	# Confirm directory exists (either pre-existing or just created)
	log_info "${description} exists: ${dir_path}"
}
