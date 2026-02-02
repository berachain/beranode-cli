#!/usr/bin/env bash
################################################################################
# test_validation.sh - Tests for validation.sh module
################################################################################

cd "$(dirname "$0")"
source test_framework.sh
source ../src/lib/logging.sh
source ../src/lib/constants.sh
source ../src/lib/validation.sh

test_suite "Port Validation"

# Valid ports
assert_success 'validate_port 1' "Port 1 is valid"
assert_success 'validate_port 8545' "Port 8545 is valid"
assert_success 'validate_port 65535' "Port 65535 is valid (max)"

# Invalid ports
assert_failure 'validate_port 0' "Port 0 is invalid"
assert_failure 'validate_port 65536' "Port 65536 is invalid (over max)"
assert_failure 'validate_port -1' "Negative port is invalid"
assert_failure 'validate_port abc' "Non-numeric port is invalid"
assert_failure 'validate_port ""' "Empty port is invalid"

test_suite "Network Validation"

# Valid networks (alphanumeric with hyphens/underscores)
assert_success 'validate_network devnet' "devnet is valid"
assert_success 'validate_network testnet' "testnet is valid"
assert_success 'validate_network bepolia' "bepolia is valid"
assert_success 'validate_network mainnet' "mainnet is valid"
assert_success 'validate_network custom-network' "custom network with hyphen is valid"
assert_success 'validate_network my_network' "custom network with underscore is valid"
assert_success 'validate_network Network123' "alphanumeric network is valid"

# Invalid networks
assert_failure 'validate_network ""' "empty network name fails"
assert_failure 'validate_network "network with spaces"' "network with spaces fails"
assert_failure 'validate_network "network@special"' "network with special chars fails"

test_suite "Boolean Validation"

# Valid booleans
assert_success 'validate_boolean true' "true is valid"
assert_success 'validate_boolean false' "false is valid"

# Invalid booleans
assert_failure 'validate_boolean True' "True (capital) is invalid"
assert_failure 'validate_boolean 1' "1 is invalid"
assert_failure 'validate_boolean yes' "yes is invalid"
assert_failure 'validate_boolean ""' "empty is invalid"

test_suite "Integer Validation"

# Valid integers
assert_success 'validate_integer 0' "0 is valid"
assert_success 'validate_integer 1' "1 is valid"
assert_success 'validate_integer 12345' "12345 is valid"

# Invalid integers
assert_failure 'validate_integer -1' "negative is invalid"
assert_failure 'validate_integer 1.5' "decimal is invalid"
assert_failure 'validate_integer abc' "non-numeric is invalid"
assert_failure 'validate_integer ""' "empty is invalid"

test_suite "Ethereum Address Validation"

# Valid addresses
assert_success 'validate_hex_address 0x1234567890123456789012345678901234567890' "Valid 40-char address"
assert_success 'validate_hex_address 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' "Address with uppercase hex"

# Invalid addresses
assert_failure 'validate_hex_address 0x123' "Too short address"
assert_failure 'validate_hex_address 1234567890123456789012345678901234567890' "Missing 0x prefix"
assert_failure 'validate_hex_address 0x12345678901234567890123456789012345678ZZ' "Non-hex characters"
assert_failure 'validate_hex_address 0x123456789012345678901234567890123456789' "39 chars (too short)"
assert_failure 'validate_hex_address 0x12345678901234567890123456789012345678901' "41 chars (too long)"

test_suite "Private Key Validation"

# Valid private keys
assert_success 'validate_hex_string 0x1234567890123456789012345678901234567890123456789012345678901234 64' "Valid 64-char private key"

# Invalid private keys
assert_failure 'validate_hex_string 0x123 64' "Too short private key"
assert_failure 'validate_hex_string 1234567890123456789012345678901234567890123456789012345678901234 64' "Missing 0x prefix"
assert_failure 'validate_hex_string 0x123456789012345678901234567890123456789012345678901234567890123Z 64' "Non-hex character"

test_suite "URL Validation"

# Valid URLs
assert_success 'validate_url http://example.com' "http URL is valid"
assert_success 'validate_url https://example.com' "https URL is valid"
assert_success 'validate_url tcp://localhost:8545' "tcp URL is valid"
assert_success 'validate_url ws://localhost:8546' "ws URL is valid"
assert_success 'validate_url wss://example.com/socket' "wss URL is valid"

# Invalid URLs
assert_failure 'validate_url example.com' "Missing protocol is invalid"
assert_failure 'validate_url ftp://example.com' "ftp protocol is invalid"
assert_failure 'validate_url ""' "Empty URL is invalid"

test_suite "Moniker Validation"

# Valid monikers
assert_success 'validate_moniker abc' "3-char moniker (min length)"
assert_success 'validate_moniker my-node-1' "Moniker with hyphens and numbers"
assert_success 'validate_moniker "$(printf "a%.0s" {1..64})"' "64-char moniker (max length)"

# Invalid monikers
assert_failure 'validate_moniker ab' "2-char moniker (too short)"
assert_failure 'validate_moniker "$(printf "a%.0s" {1..65})"' "65-char moniker (too long)"
assert_failure 'validate_moniker ""' "Empty moniker"

test_suite "Duration Validation"

# Valid durations
assert_success 'validate_duration 1s' "1 second"
assert_success 'validate_duration 5m' "5 minutes"
assert_success 'validate_duration 2h' "2 hours"
assert_success 'validate_duration 100ms' "100 milliseconds"
assert_success 'validate_duration 1000us' "1000 microseconds"
assert_success 'validate_duration 1000000ns' "1000000 nanoseconds"
assert_success 'validate_duration 1h30m' "Complex duration"

# Invalid durations
assert_failure 'validate_duration 1' "Missing unit"
assert_failure 'validate_duration s' "Missing number"
assert_failure 'validate_duration 1x' "Invalid unit"
assert_failure 'validate_duration ""' "Empty duration"

print_results
