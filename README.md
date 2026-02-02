# 🐻🛰️ Beranode CLI

A command-line tool for managing Berachain nodes.

> **⚠️⚠️  EXPERIMENTAL!  ⚠️⚠️**
>
> **This CLI is in an early experimental phase and is actively being worked on.**
>
> **Do _not_ use in production environments. Functionality, configuration, and output formats may change rapidly.**

## Overview

`beranode` is a CLI tool that simplifies the process of setting up and managing Berachain blockchain nodes. It supports multiple networks (devnet, testnet, mainnet) and can manage validator, full, and pruned nodes.

## Prerequisites

- Bash shell
- Cast CLI version 1.4.3 or higher - https://getfoundry.sh
- Required Berachain binaries:
  - `beacond` (BeaconKit consensus client)
  - `bera-reth` (Reth execution client)

## Installation

1. Clone this repository
2. Make the script executable:
   ```bash
   chmod +x beranode
   ```
3. Optionally, add to your PATH or create a symlink

## Usage

### Basic Commands

#### Initialize a Node

```bash
./beranode init [options]
```

Initialize a new Berachain node with specified configuration.

**Options:**
- `--moniker <name>` - Set a custom name for your node
- `--network <network>` - Network to connect to: `devnet`, `bepolia`, or `mainnet` (default: `devnet`)
- `--validators <count>` - Number of validator nodes to create
- `--full-nodes <count>` - Number of full nodes to create
- `--pruned-nodes <count>` - Number of pruned nodes to create
- `--force` - Force initialization (overwrite existing configuration)
- `--wallet-private-key <key>` - Private key for the wallet
- `--wallet-address <address>` - Wallet address
- `--wallet-balance <amount>` - Initial wallet balance (default: 1000000000000000000000000000)

**Example:**
```bash
# Initialize a devnet validator node
./beranode init --network devnet --validators 1

# Initialize multiple nodes with custom moniker
./beranode init --moniker mynode --validators 2 --full-nodes 1
```

#### Start a Node

```bash
./beranode start [options]
```

Start a Berachain node that has been initialized.

**Options:**
- `--moniker <name>` - Node name to start
- `--network <network>` - Network specification

**Example:**
```bash
# Start a node
./beranode start --moniker mynode --network devnet
```

#### Validate Configuration

```bash
./beranode validate [config_path]
```

Validate the `beranodes.config.json` file to ensure all fields are correctly formatted using regex patterns.

**Arguments:**
- `config_path` - Path to beranodes.config.json (optional, defaults to `./beranodes/beranodes.config.json`)

**What it validates:**
- String formats (monikers, network names, paths)
- Boolean values (true/false)
- Integer numbers and port ranges (1-65535)
- Ethereum addresses (0x + 40 hex chars)
- Private keys and JWT tokens (0x + 64 hex chars)
- BLS public keys (0x + 96 hex chars)
- URLs and time durations (e.g., 5m0s, 10s)
- Node and deposit object structures

**Example:**
```bash
# Validate default config
./beranode validate

# Validate specific config file
./beranode validate ./custom/path/beranodes.config.json
```

**Example output:**
```
[INFO] Starting validation of beranodes configuration
[INFO] Config file: ./beranodes/beranodes.config.json

Validating beranodes configuration: ./beranodes/beranodes.config.json
✓ All validations passed successfully

[OK] Configuration validation completed successfully!
```

For detailed documentation on validation functions and programmatic usage, see [docs/VALIDATION.md](docs/VALIDATION.md).

#### Show Help

```bash
./beranode --help
./beranode -h
./beranode help
```

Display help information about available commands.

#### Show Version

```bash
./beranode --version
./beranode -v
./beranode version
```

Display the current version of the beranode CLI.

#### Interactive Menu

```bash
./beranode
```

Running `beranode` without any arguments will launch an interactive menu to guide you through the available options.

## Network Configuration

### Supported Networks

- **Devnet**: Chain ID 80087 (name: `devnet`)
- **Testnet**: Chain ID 80069 (name: `bepolia`)
- **Mainnet**: Chain ID 80094 (name: `mainnet`)

### Default Ports

- Consensus Layer (CL) RPC: 26657
- Consensus Layer (CL) P2P: 26656
- Consensus Layer (CL) Proxy: 26658
- Execution Layer (EL) RPC: 8545
- Execution Layer (EL) Auth RPC: 8551
- Execution Layer (EL) P2P: 30303
- Execution Layer (EL) Prometheus: 9101
- Consensus Layer (CL) Prometheus: 9102

## Directory Structure

The beranode CLI creates the following directory structure:

```
beranodes/
├── bin/          # Binary files (beacond, bera-reth)
├── tmp/          # Temporary files
├── logs/         # Log files (e.g., silent-smile-forest-0-val-beacond.log)
├── runs/         # PID files for running nodes
└── nodes/        # Node configurations
    ├── 0-validator       # Validator node 0
    ├── 1-validator       # Validator node 1
    ├── 2-rpc-full        # RPC full node 2
    └── 3-rpc-pruned      # RPC pruned node 3
```

## Examples

### Quick Start - Devnet Validator

```bash
# Initialize a single validator node on devnet
./beranode init --network devnet --validators 1

# Start the node
./beranode start
```

### Multi-Node Setup

```bash
# Initialize a network with multiple node types
./beranode init \
  --moniker mynetwork \
  --network devnet \
  --validators 2 \
  --full-nodes 1 \
  --pruned-nodes 1
```

### Custom Wallet Configuration

```bash
# Initialize with custom wallet settings
./beranode init \
  --network devnet \
  --validators 1 \
  --wallet-address 0x1234... \
  --wallet-private-key 0xabcd... \
  --wallet-balance 5000000000000000000000000000
```

## Testing Your Node

Once your node is running, you can test the RPC endpoints using the following curl commands:

### Test Execution Layer RPC (JSON-RPC)

Check the current block number on the execution layer:

```bash
curl -s --location 'http://localhost:8545' \
--header 'Content-Type: application/json' \
--data '{
  "jsonrpc": "2.0",
  "method": "eth_blockNumber",
  "params": [],
  "id": 420
}' | jq;
```
### Test Execution Layer RPC For Peers

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8545
```

### Test Consensus Layer RPC (CometBFT)

Check the number of connected peers on the consensus layer:

```bash
curl -s --location 'http://localhost:26657/net_info' | jq .result.n_peers;
```

### Test Beacon Node API

Check the latest slot on the beacon node:

```bash
curl -s --location 'http://localhost:3500/eth/v2/debug/beacon/states/head' | jq .data.latest_block_header.slot;

# [Expected]:
# null
# ...
# "0x3"
# "0x4"
```

## Troubleshooting

### Check Cast Version

Ensure you have the correct version of Cast installed:
```bash
cast --version
```

Required version: 1.4.3 or higher

### Verify Binaries

Make sure the required binaries are available:
```bash
which beacond
which bera-reth
```

## Testing

The [tests/](tests/) directory contains a comprehensive test suite for validating the beranode CLI functionality.

### Test Framework

The test suite uses a custom lightweight bash testing framework ([tests/test_framework.sh](tests/test_framework.sh)) that provides:

- **Assertion Functions**: `assert_equals`, `assert_success`, `assert_failure`, `assert_contains`, `assert_not_contains`, `assert_file_exists`, `assert_dir_exists`, `assert_empty`, `assert_not_empty`
- **Test Organization**: Group tests into suites with `test_suite "Suite Name"`
- **Result Reporting**: Colored output with pass/fail statistics
- **Test Management**: Skip tests when needed with `skip_test`

### Available Tests

- **[test_validation.sh](tests/test_validation.sh)** - Tests for validation functions including:
  - Port validation (valid ranges, edge cases)
  - Network name validation
  - Boolean validation (true/false)
  - Integer validation
  - Ethereum address validation (0x + 40 hex chars)
  - Private key validation (0x + 64 hex chars)
  - URL validation (http, https, tcp, ws, wss)
  - Moniker validation (length and format)
  - Duration validation (s, m, h, ms, us, ns)

### Running Tests

Execute all tests from the tests directory:

```bash
cd tests
./test_validation.sh
```

Or run from the project root:

```bash
bash tests/test_validation.sh
```

### Test Output Example

```
=== Test Suite: Port Validation ===
  ✓ Port 1 is valid
  ✓ Port 8545 is valid
  ✓ Port 65535 is valid (max)
  ✓ Port 0 is invalid
  ✓ Port 65536 is invalid (over max)

========================================
Test Results
========================================
Total:  45
Passed: 45
Failed: 0
========================================
✓ All tests passed!
```

### Writing New Tests

To add new tests, create a new test file or extend existing ones:

1. Source the test framework: `source test_framework.sh`
2. Source any modules you need to test
3. Organize tests with `test_suite "Your Suite Name"`
4. Use assertion functions to validate behavior
5. Call `print_results` at the end

Example test structure:

```bash
#!/usr/bin/env bash
source test_framework.sh
source ../src/lib/your_module.sh

test_suite "Feature Tests"
assert_success 'your_function "valid input"' "Should handle valid input"
assert_failure 'your_function "invalid input"' "Should reject invalid input"

print_results
```

## Versioning

This project follows [Semantic Versioning](https://semver.org/) (SemVer). Version numbers follow the format `MAJOR.MINOR.PATCH`:

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality in a backwards-compatible manner
- **PATCH**: Backwards-compatible bug fixes

### Bumping Versions

Use the [scripts/bump-version.sh](scripts/bump-version.sh) script to manage version updates:

```bash
# Increment patch version (e.g., 0.1.0 -> 0.1.1)
./scripts/bump-version.sh patch

# Increment minor version (e.g., 0.1.0 -> 0.2.0)
./scripts/bump-version.sh minor

# Increment major version (e.g., 0.1.0 -> 1.0.0)
./scripts/bump-version.sh major

# Set a specific version (e.g., 2.5.3)
./scripts/bump-version.sh 2.5.3
```

### Script Options

- `--dry-run` - Preview changes without modifying files
- `--tag` - Automatically create a git tag and commit
- `-m, --message TEXT` - Add a description of changes for commit and tag messages
- `-h, --help` - Show help information

### Examples

**Preview a version bump:**
```bash
./scripts/bump-version.sh patch --dry-run
```

**Bump version and create a git tag:**
```bash
./scripts/bump-version.sh minor --tag
```

**Bump version with a description:**
```bash
./scripts/bump-version.sh patch --tag -m "Fix authentication bug and improve error handling"
```

**Manual release workflow:**
```bash
# 1. Update CHANGELOG.md with your changes
# 2. Bump the version
./scripts/bump-version.sh minor

# 3. Review the changes
git diff

# 4. Commit and tag
git add -A
git commit -m "chore: release v0.2.0"
git tag -a v0.2.0 -m "Release v0.2.0"

# 5. Push to remote
git push origin main --tags
```

**Automated release workflow with description:**
```bash
# 1. Update CHANGELOG.md with your changes
# 2. Bump version, commit, and tag in one step
./scripts/bump-version.sh minor --tag -m "Add new user profile feature"

# 3. Push to remote
git push origin main --tags
```

### What the Script Does

The `bump-version.sh` script automatically:
1. Updates `BERANODE_VERSION` in [src/lib/constants.sh](src/lib/constants.sh)
2. Rebuilds the [beranode](beranode) file from sources
3. Updates [CHANGELOG.md](CHANGELOG.md) with:
   - A new version section (newest versions at top, chronological order)
   - Summary section (if `-m, --message` is provided)
   - Changed Files section listing all modified files
   - Standard changelog categories (Added, Changed, Deprecated, Removed, Fixed, Security)
4. Updates version comparison links in the changelog
5. Optionally creates a git commit and tag (with `--tag` flag)
6. Includes a custom description in commit and tag messages (with `-m, --message` flag)

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

When contributing:
1. Document your changes in the [CHANGELOG.md](CHANGELOG.md) under the `[Unreleased]` section
2. Follow the existing code style and conventions
3. Test your changes thoroughly before submitting

### Code Formatting

All shell scripts should be formatted using [shfmt](https://github.com/mvdan/sh):

**Installation:**
```bash
brew install shfmt
```

**Format all shell scripts:**
```bash
shfmt -w .
```

**Check formatting before committing:**
```bash
shfmt -d .
```

## License

See LICENSE file for details.
