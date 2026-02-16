#!/usr/bin/env bash
set -euo pipefail
################################################################################
# test_framework.sh - Beranode CLI Test Framework
################################################################################
#
# This module provides a lightweight testing framework for bash scripts.
# It includes assertion functions, test suite management, and result reporting.
#
################################################################################

# Test counters (global - bash 3.2 compatible)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_SUITE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

################################################################################
# Function: test_suite
# Description: Starts a new test suite
#
# Arguments:
#   $1 - suite_name: Name of the test suite
#
# Example:
#   test_suite "Validation Functions"
################################################################################
test_suite() {
	CURRENT_SUITE="$1"
	echo ""
	echo -e "${BLUE}=== Test Suite: $CURRENT_SUITE ===${RESET}"
}

################################################################################
# Function: assert_equals
# Description: Asserts that two values are equal
#
# Arguments:
#   $1 - expected: Expected value
#   $2 - actual: Actual value
#   $3 - message: Test description (optional)
#
# Returns:
#   0 - Assertion passed
#   1 - Assertion failed
#
# Example:
#   assert_equals "expected" "actual" "Values should match"
################################################################################
assert_equals() {
	local expected="$1"
	local actual="$2"
	local message="${3:-Assertion failed}"

	((TESTS_RUN++))

	if [[ "$expected" == "$actual" ]]; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    Expected: '$expected'"
		echo -e "    Got:      '$actual'"
		return 1
	fi
}

################################################################################
# Function: assert_success
# Description: Asserts that a command succeeds (returns 0)
#
# Arguments:
#   $1 - command: Command to execute
#   $2 - message: Test description (optional)
#
# Returns:
#   0 - Command succeeded
#   1 - Command failed
#
# Example:
#   assert_success "validate_port 8545" "Valid port should pass"
################################################################################
assert_success() {
	local command="$1"
	local message="${2:-Command should succeed}"

	((TESTS_RUN++))

	if eval "$command" &>/dev/null; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    Command: $command"
		return 1
	fi
}

################################################################################
# Function: assert_failure
# Description: Asserts that a command fails (returns non-zero)
#
# Arguments:
#   $1 - command: Command to execute
#   $2 - message: Test description (optional)
#
# Returns:
#   0 - Command failed as expected
#   1 - Command succeeded when it should have failed
#
# Example:
#   assert_failure "validate_port 0" "Invalid port should fail"
################################################################################
assert_failure() {
	local command="$1"
	local message="${2:-Command should fail}"

	((TESTS_RUN++))

	if ! eval "$command" &>/dev/null; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    Command: $command"
		return 1
	fi
}

################################################################################
# Function: assert_contains
# Description: Asserts that a string contains a substring
#
# Arguments:
#   $1 - haystack: String to search in
#   $2 - needle: Substring to search for
#   $3 - message: Test description (optional)
#
# Returns:
#   0 - String contains substring
#   1 - String does not contain substring
#
# Example:
#   assert_contains "Hello World" "World" "Should contain World"
################################################################################
assert_contains() {
	local haystack="$1"
	local needle="$2"
	local message="${3:-Should contain substring}"

	((TESTS_RUN++))

	if [[ "$haystack" == *"$needle"* ]]; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    Expected substring: '$needle'"
		echo -e "    In string: '$haystack'"
		return 1
	fi
}

################################################################################
# Function: assert_not_contains
# Description: Asserts that a string does NOT contain a substring
#
# Arguments:
#   $1 - haystack: String to search in
#   $2 - needle: Substring that should not be present
#   $3 - message: Test description (optional)
#
# Returns:
#   0 - String does not contain substring
#   1 - String contains substring
#
# Example:
#   assert_not_contains "Hello World" "Foo" "Should not contain Foo"
################################################################################
assert_not_contains() {
	local haystack="$1"
	local needle="$2"
	local message="${3:-Should not contain substring}"

	((TESTS_RUN++))

	if [[ "$haystack" != *"$needle"* ]]; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    Unexpected substring: '$needle'"
		echo -e "    In string: '$haystack'"
		return 1
	fi
}

################################################################################
# Function: assert_file_exists
# Description: Asserts that a file exists
#
# Arguments:
#   $1 - file_path: Path to file
#   $2 - message: Test description (optional)
#
# Returns:
#   0 - File exists
#   1 - File does not exist
#
# Example:
#   assert_file_exists "/path/to/file" "File should exist"
################################################################################
assert_file_exists() {
	local file_path="$1"
	local message="${2:-File should exist}"

	((TESTS_RUN++))

	if [[ -f "$file_path" ]]; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    File not found: $file_path"
		return 1
	fi
}

################################################################################
# Function: assert_dir_exists
# Description: Asserts that a directory exists
#
# Arguments:
#   $1 - dir_path: Path to directory
#   $2 - message: Test description (optional)
#
# Returns:
#   0 - Directory exists
#   1 - Directory does not exist
#
# Example:
#   assert_dir_exists "/path/to/dir" "Directory should exist"
################################################################################
assert_dir_exists() {
	local dir_path="$1"
	local message="${2:-Directory should exist}"

	((TESTS_RUN++))

	if [[ -d "$dir_path" ]]; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    Directory not found: $dir_path"
		return 1
	fi
}

################################################################################
# Function: assert_not_empty
# Description: Asserts that a string is not empty
#
# Arguments:
#   $1 - value: String to check
#   $2 - message: Test description (optional)
#
# Returns:
#   0 - String is not empty
#   1 - String is empty
#
# Example:
#   assert_not_empty "$variable" "Variable should not be empty"
################################################################################
assert_not_empty() {
	local value="$1"
	local message="${2:-Value should not be empty}"

	((TESTS_RUN++))

	if [[ -n "$value" ]]; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		return 1
	fi
}

################################################################################
# Function: assert_empty
# Description: Asserts that a string is empty
#
# Arguments:
#   $1 - value: String to check
#   $2 - message: Test description (optional)
#
# Returns:
#   0 - String is empty
#   1 - String is not empty
#
# Example:
#   assert_empty "$variable" "Variable should be empty"
################################################################################
assert_empty() {
	local value="$1"
	local message="${2:-Value should be empty}"

	((TESTS_RUN++))

	if [[ -z "$value" ]]; then
		((TESTS_PASSED++))
		echo -e "  ${GREEN}✓${RESET} $message"
		return 0
	else
		((TESTS_FAILED++))
		echo -e "  ${RED}✗${RESET} $message"
		echo -e "    Expected empty, got: '$value'"
		return 1
	fi
}

################################################################################
# Function: print_results
# Description: Prints test results summary and returns appropriate exit code
#
# Returns:
#   0 - All tests passed
#   1 - Some tests failed
#
# Example:
#   print_results
################################################################################
print_results() {
	echo ""
	echo -e "${BLUE}========================================${RESET}"
	echo -e "${BLUE}Test Results${RESET}"
	echo -e "${BLUE}========================================${RESET}"
	echo -e "Total:  $TESTS_RUN"
	echo -e "Passed: ${GREEN}$TESTS_PASSED${RESET}"
	echo -e "Failed: ${RED}$TESTS_FAILED${RESET}"
	echo -e "${BLUE}========================================${RESET}"

	if [[ $TESTS_FAILED -eq 0 ]]; then
		echo -e "${GREEN}✓ All tests passed!${RESET}"
		return 0
	else
		echo -e "${RED}✗ Some tests failed${RESET}"
		return 1
	fi
}

################################################################################
# Function: skip_test
# Description: Marks a test as skipped
#
# Arguments:
#   $1 - message: Reason for skipping
#
# Example:
#   skip_test "Requires network connection"
################################################################################
skip_test() {
	local message="${1:-Test skipped}"
	echo -e "  ${YELLOW}⊘${RESET} $message (skipped)"
}
