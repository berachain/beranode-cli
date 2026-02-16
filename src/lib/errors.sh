#!/usr/bin/env bash
set -euo pipefail
################################################################################
# errors.sh - Beranode CLI Error Handling Functions
################################################################################
#
# This module provides robust error handling utilities for the beranode CLI.
# It replaces error-prone `if [[ $? -ne 0 ]]` patterns with cleaner, more
# maintainable error handling functions.
#
################################################################################

################################################################################
# Function: run_or_fail
# Description: Executes a command and captures output, failing with error if
#              the command exits with non-zero status
#
# Arguments:
#   $1 - command (string): Command to execute
#   $2 - error_msg (string, optional): Error message prefix to display on failure
#
# Returns:
#   0 - Success (prints command output to stdout)
#   1 - Failure (logs error with output to stderr)
#
# Example:
#   output=$(run_or_fail "curl -sL https://example.com/data" "Failed to download data")
#   echo "Downloaded: $output"
################################################################################
run_or_fail() {
	local cmd="$1"
	local error_msg="${2:-Command failed}"
	local output
	local exit_code=0

	# Execute command and capture both stdout and stderr
	if ! output=$(eval "$cmd" 2>&1); then
		exit_code=$?
		log_error "$error_msg"
		log_error "Command: $cmd"
		log_error "Output: $output"
		log_error "Exit code: $exit_code"
		return 1
	fi

	echo "$output"
	return 0
}

################################################################################
# Function: assert_success
# Description: Asserts that a command succeeds, logging error if it fails
#
# Arguments:
#   $1 - command (string): Command to execute
#   $2 - error_msg (string, optional): Error message to display on failure
#
# Returns:
#   0 - Success (command succeeded)
#   1 - Failure (command failed)
#
# Example:
#   assert_success "[ -f /path/to/file ]" "Required file not found"
################################################################################
assert_success() {
	local cmd="$1"
	local error_msg="${2:-Assertion failed}"

	if ! eval "$cmd" >/dev/null 2>&1; then
		log_error "$error_msg"
		log_error "Command: $cmd"
		return 1
	fi
	return 0
}

################################################################################
# Function: assert_file_exists
# Description: Asserts that a file exists, logging error if not
#
# Arguments:
#   $1 - file_path (string): Path to file that must exist
#   $2 - error_msg (string, optional): Custom error message
#
# Returns:
#   0 - Success (file exists)
#   1 - Failure (file does not exist)
#
# Example:
#   assert_file_exists "/etc/config.json" "Config file not found"
################################################################################
assert_file_exists() {
	local file_path="$1"
	local error_msg="${2:-File not found: $file_path}"

	if [[ ! -f "$file_path" ]]; then
		log_error "$error_msg"
		return 1
	fi
	return 0
}

################################################################################
# Function: assert_dir_exists
# Description: Asserts that a directory exists, logging error if not
#
# Arguments:
#   $1 - dir_path (string): Path to directory that must exist
#   $2 - error_msg (string, optional): Custom error message
#
# Returns:
#   0 - Success (directory exists)
#   1 - Failure (directory does not exist)
#
# Example:
#   assert_dir_exists "/var/lib/beranode" "Node directory not found"
################################################################################
assert_dir_exists() {
	local dir_path="$1"
	local error_msg="${2:-Directory not found: $dir_path}"

	if [[ ! -d "$dir_path" ]]; then
		log_error "$error_msg"
		return 1
	fi
	return 0
}

################################################################################
# Function: assert_not_empty
# Description: Asserts that a variable is not empty, logging error if it is
#
# Arguments:
#   $1 - value (string): Value to check
#   $2 - var_name (string): Name of variable (for error message)
#   $3 - error_msg (string, optional): Custom error message
#
# Returns:
#   0 - Success (value is not empty)
#   1 - Failure (value is empty)
#
# Example:
#   assert_not_empty "$api_key" "API_KEY" "API key is required"
################################################################################
assert_not_empty() {
	local value="$1"
	local var_name="$2"
	local error_msg="${3:-Variable is empty: $var_name}"

	if [[ -z "$value" ]]; then
		log_error "$error_msg"
		return 1
	fi
	return 0
}

################################################################################
# Function: run_with_retry
# Description: Executes a command with retry logic on failure
#
# Arguments:
#   $1 - command (string): Command to execute
#   $2 - max_retries (integer, optional): Maximum number of retries (default: 3)
#   $3 - retry_delay (integer, optional): Delay between retries in seconds (default: 5)
#
# Returns:
#   0 - Success (command succeeded)
#   1 - Failure (command failed after all retries)
#
# Example:
#   run_with_retry "curl -sL https://api.example.com" 5 10
################################################################################
run_with_retry() {
	local cmd="$1"
	local max_retries="${2:-3}"
	local retry_delay="${3:-5}"
	local attempt=1
	local exit_code=0

	while ((attempt <= max_retries)); do
		if eval "$cmd" >/dev/null 2>&1; then
			return 0
		fi
		exit_code=$?

		if ((attempt < max_retries)); then
			log_warn "Command failed (attempt $attempt/$max_retries), retrying in ${retry_delay}s..."
			sleep "$retry_delay"
		fi

		((attempt++))
	done

	log_error "Command failed after $max_retries attempts"
	log_error "Command: $cmd"
	return $exit_code
}

################################################################################
# Function: exit_on_error
# Description: Exits the entire script if previous command failed
#
# Arguments:
#   $1 - exit_code (integer): Exit code from previous command
#   $2 - error_msg (string): Error message to display
#
# Returns:
#   Never returns if exit_code is non-zero (exits script)
#
# Example:
#   some_command
#   exit_on_error $? "Critical failure: unable to proceed"
################################################################################
exit_on_error() {
	local exit_code="$1"
	local error_msg="$2"

	if [[ "$exit_code" -ne 0 ]]; then
		log_error "$error_msg"
		log_error "Exiting with code: $exit_code"
		exit "$exit_code"
	fi
}
