# 🐻🛰️ Beranode CLI

A command-line tool for managing Berachain nodes.

> **⚠️⚠️  EXPERIMENTAL!  ⚠️⚠️**
>
> **This CLI is in an early experimental phase and is actively being worked on.**
>
> **Do _not_ use in production environments. Functionality, configuration, and output formats may change rapidly.**

## Overview

`beranode` is a CLI tool that simplifies the process of setting up and managing Berachain blockchain nodes. It supports multiple networks (`devnet`, `bepolia`, `mainnet`) and can manage validator, full, and pruned nodes.

## Prerequisites

- Bash shell
- Cast CLI version 1.4.3 or higher - https://getfoundry.sh
- `curl`, `tar`
- `lz4` — required to extract official chain-state snapshots (`brew install lz4` or `apt-get install lz4`)
- Required Berachain binaries (downloaded by `init` if missing):
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
- `--skip-snapshot` - Skip official snapshot download on bepolia/mainnet (sync from genesis instead)
- `--snapshot-type <pruned|archive>` - Force one snapshot type for every node (default: role-mapped)
- `--beacond-version <tag>` - BeaconKit release tag (`latest`, `vX.Y.Z`, or `vX.Y.Z-rc.N`)
- `--berareth-version <tag>` - bera-reth release tag (`latest`, `vX.Y.Z`, or `vX.Y.Z-rc.N`)
- `--force` - Force initialization (overwrite existing configuration)
- `--mode <local|docker|serviceman>` - Process runtime (default: `local`)
- `--docker` - Docker mode (alias for `--mode docker`)
- `--serviceman` - Serviceman mode (alias for `--mode serviceman`). macOS launchd only
- `--wallet-private-key <key>` - Private key for the wallet
- `--wallet-address <address>` - Wallet address
- `--wallet-balance <amount>` - Initial wallet balance (default: 1000000000000000000000000000)

**Example:**
```bash
# Initialize a devnet validator node
./beranode init --network devnet --validators 1

# Initialize a Bepolia testnet node (official genesis + snapshots)
./beranode init --network bepolia --validators 1

# Initialize under launchd on macOS (start/stop manage the service)
./beranode init --network bepolia --pruned-nodes 1 --mode serviceman

# Initialize multiple nodes with custom moniker
./beranode init --moniker mynode --validators 2 --full-nodes 1
```

#### Start a Node

```bash
./beranode start [options]
```

Start a Berachain node that has been initialized. Network is read from `beranodes.config.json`. In `serviceman` mode this loads launchd jobs instead of backgrounding PIDs.

**Options:**
- `--beranodes-dir <path>` - Beranodes data directory (default: `./beranodes`)
- `--external-ip <ip>` - Public IP advertised to peers (bepolia/mainnet)
- `--bootnodes <enodes>` - Comma-separated EL bootnodes. On bepolia/mainnet, `--bootnodes` is omitted unless this is set (reth's `--chain` preset handles discovery)
- `--trusted-peers <enodes>` - Comma-separated EL trusted peers. On bepolia/mainnet, `--trusted-peers` is omitted unless this is set
- `--ws` - Enable the EL websocket RPC. Without this, `--ws`, `--ws.addr`, `--ws.port`, and `--ws.origins` are omitted
- `--ws.addr <addr>` - Websocket bind address (requires `--ws`; default: `0.0.0.0`)
- `--ws.port <port>` - Websocket port (requires `--ws`; default: `8546` / node `el_ws_port`)
- `--ws.origin <origins>` - Websocket allowed origins (requires `--ws`; default: `*`). Alias: `--ws.origins`
- `--logs-reset` - Remove existing files in `beranodes/logs` without prompting (same as answering `y` to the log-reset prompt)

**Example:**
```bash
./beranode start
```

#### Stop a Node

```bash
./beranode stop [options]
```

Stop nodes from `beranodes.config.json`. Local mode kills PID files; Docker uses compose down; serviceman unloads launchd jobs.

**Example:**
```bash
./beranode stop
```

#### Check Status

```bash
./beranode status [options]
```

Display live node status (EL/CL block height, peers, sync) plus host storage: total volume capacity, space used on the device, and the size of `beranodes/nodes`.

**Options:**
- `--verbose|-v` - One row per service (`beacond`, `bera-reth`)
- `--watch|-w` - Live-refresh mode
- `--interval|-i <seconds>` - Watch refresh interval (default: `2`)
- `--json` - Machine-readable JSON (incompatible with `--watch`)
- `--beranodes-dir <path>` - Beranodes data directory (default: `./beranodes`)

**Example:**
```bash
./beranode status
./beranode status --watch
./beranode status --json
```

#### Snapshots (bepolia / mainnet)

```bash
./beranode snapshot [download|restore] [options]
```

Download and restore official chain-state snapshots from [bepolia.snapshots.berachain.com](https://bepolia.snapshots.berachain.com) or [snapshots.berachain.com](https://snapshots.berachain.com).

`init --network bepolia` (or `mainnet`) does this automatically. Use `beranode snapshot` to refresh later. Nodes must be stopped before `restore`.

**Defaults:** `rpc-pruned` and `validator` nodes get **pruned** snapshots; `rpc-full` nodes get **archive**. `--snapshot-type pruned|archive` overrides every node.

Pruned Bepolia execution snapshots are ~10.5 GB; archive execution is ~42 GB. Mainnet archive execution is ~1 TB. The CLI prints types, sizes, and destination nodes, then continues. If `{network}-beacond-{type}-latest.tar.lz4` and `{network}-reth-{type}-latest.tar.lz4` are already in `beranodes/snapshots/`, you are prompted first: overwrite with a fresh network download (`y`) or keep the local files (`N`, default). Keeping them skips the download. Re-running `init` on an existing `beranodes` directory preserves `beranodes/snapshots/` so previously downloaded archives are not deleted.

Validator keys are generated on public networks, but the node is **not** in the public validator set until you deposit separately. This CLI does not automate that deposit.

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
├── runs/         # PID files for running nodes (local mode)
├── services/     # launchd plists + launchd.json (serviceman mode)
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

### Serviceman mode (macOS launchd)

`serviceman` is local-mode binaries supervised by launchd. Init still downloads native `beacond` / `bera-reth`; the difference is start/stop/logs.

```bash
./beranode init --network bepolia --pruned-nodes 1 --serviceman
./beranode start
./beranode stop
```

- Requires macOS and `launchctl`. Linux systemd is not implemented yet; init fails instead of falling back to local.
- Jobs are user LaunchAgents (`~/Library/LaunchAgents/com.berachain.beranode.<hash>.<moniker>.<index>.<component>.plist`), not system daemons (no root).
- `KeepAlive` restarts a crashed process. `beranode stop` unloads the jobs and removes those LaunchAgents so they do not come back at login. Plist copies remain in `beranodes/services/` for inspection.
- Stdout and stderr go to the same files as local mode under `beranodes/logs/`.
- Do not combine `--docker` and `--serviceman`.

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
- **[test_download.sh](tests/test_download.sh)** - Tests for GitHub release asset URL matching
- **[test_snapshots.sh](tests/test_snapshots.sh)** - Tests for public-network URL mapping, role→snapshot type, and index.csv selection

### Running Tests

Execute tests from the tests directory:

```bash
cd tests
./test_validation.sh
./test_download.sh
./test_snapshots.sh
```

Or run from the project root:

```bash
bash tests/test_validation.sh
bash tests/test_download.sh
bash tests/test_snapshots.sh
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

## Changelog

User-facing changes are recorded in [CHANGELOG.md](CHANGELOG.md) using [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Write new work under `[Unreleased]` in the matching category:

- **Added** — new features
- **Changed** — changes in existing behavior
- **Deprecated** — soon-to-be-removed features
- **Removed** — removed features
- **Fixed** — bug fixes
- **Security** — vulnerability fixes

Do not edit historical `## [X.Y.Z]` sections. When releasing, promote `[Unreleased]` by hand:

1. Move the `[Unreleased]` entries into a dated `## [X.Y.Z] - YYYY-MM-DD` section
2. Leave a fresh empty `[Unreleased]` template (with the six category headings) above it
3. Optionally add **Summary** and **Changed Files**
4. Update the compare links at the bottom (`[Unreleased]: …compare/vX.Y.Z...HEAD` and `[X.Y.Z]: …compare/vPREV...vX.Y.Z`)

[.github/workflows/release.yml](.github/workflows/release.yml) copies that version section into the GitHub Release body.

## Versioning

This project follows [Semantic Versioning](https://semver.org/) (SemVer). The current CLI version is **0.11.0**. The single source of truth is `BERANODE_VERSION` in [src/lib/constants.sh](src/lib/constants.sh). `build.sh` reads that value when it generates the `beranode` binary. `beranode version` / `--version` / `-v` print `beranode v${BERANODE_VERSION}`.

Version numbers use `MAJOR.MINOR.PATCH`, with optional prereleases:

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality in a backwards-compatible manner
- **PATCH**: Backwards-compatible bug fixes
- **Prerelease**: `X.Y.Z-rc.N`, `X.Y.Z-alpha.N`, `X.Y.Z-beta.N`, or `X.Y.Z-pre.N`

Do not rewrite every `vX.Y.Z` string in the tree. Runtime version output always comes from `BERANODE_VERSION`.

### Client versions (beacond / bera-reth)

`init` downloads client binaries when they are missing. On `bepolia` and `mainnet`, `latest` (the default) is replaced with the recommended tags in [src/lib/constants.sh](src/lib/constants.sh) / [src/lib/network.sh](src/lib/network.sh):

| Network | beacond | bera-reth |
| --- | --- | --- |
| bepolia | `v1.4.1` | `v1.4.4` |
| mainnet | `v1.4.1` | `v1.4.4` |
| devnet | GitHub `latest` | GitHub `latest` |

Override with `--beacond-version` / `--berareth-version`. Accepted tags: `latest`, `vX.Y.Z`, `vX.Y.Z-rc.N`, or `vX.Y.Z-rcN`.

### Releasing

1. Set `BERANODE_VERSION` in [src/lib/constants.sh](src/lib/constants.sh) (and the VERSION header in [src/core/dispatcher.sh](src/core/dispatcher.sh) if it is present)
2. Promote `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) as described above
3. Rebuild the binary: `./build.sh`
4. Commit those files and create an annotated tag matching the version:

```bash
git tag -a v0.10.0 -m "Release v0.10.0"
git push origin HEAD
git push origin v0.10.0
```

Pushing a `vX.Y.Z` or `vX.Y.Z-*` tag triggers [.github/workflows/release.yml](.github/workflows/release.yml). The workflow reads the matching changelog section, marks prerelease tags as prereleases, and creates a [GitHub Release](https://github.com/berachain/beranode-cli/releases) with the `beranode` binary attached (or uploads `beranode` onto an existing release).

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

When contributing:
1. Document your changes in [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]` (see [Changelog](#changelog))
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
