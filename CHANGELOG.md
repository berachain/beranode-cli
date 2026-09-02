# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Summary

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.11.0] - 2026-09-02

### Summary

macOS `serviceman` mode runs the same native binaries as local under launchd. `beranode status` reports host storage and can emit JSON. Public-network `bera-reth` start is opt-in for bootnodes, trusted peers, and websocket RPC (discovery uses the `--chain` preset). Init no longer mixes RPC nodes with validators on bepolia/mainnet, and bepolia's recommended beacond is `v1.4.1`. Wallet generation and path validation work with current Foundry and GNU bash.

### Added

- `beranode init --mode serviceman` and `--serviceman`: same native binaries as local mode, with `"mode": "serviceman"` in `beranodes.config.json`. macOS-only (launchd); Linux systemd is not implemented yet (init fails instead of falling back to local)
- `beranode start` / `stop` in serviceman mode load and unload user LaunchAgents (`~/Library/LaunchAgents/com.berachain.beranode.*`). Jobs use `KeepAlive` and `RunAtLoad` (10s throttle); `stop` removes those LaunchAgents so they do not restart at login. Logs use `beranodes/logs/` via launchd `StandardOutPath` / `StandardErrorPath`; plist copies and `launchd.json` live in `beranodes/services/`
- `beranode init --mode local|docker|serviceman` as the canonical mode flag (`--docker` and `--serviceman` remain shorthands). Combining modes is rejected
- `beranode start --bootnodes` and `--trusted-peers` to pass EL enodes when you want them (local, Docker, and serviceman)
- `beranode start --ws` to enable the EL websocket RPC, with optional `--ws.addr`, `--ws.port`, and `--ws.origin` overrides (local, Docker, and serviceman; Docker maps the WS port only when `--ws` is set)
- `beranode start --logs-reset` to remove existing files in `beranodes/logs` without prompting (answers `y` to the log-reset prompt)
- `beranode status` Storage footer: total volume capacity, device used, and `beranodes/nodes` size (macOS APFS container via diskutil with df fallback; Linux df). In `--watch`, storage is refreshed every 30 seconds
- `beranode status --json` for a machine-readable snapshot of network, nodes, and storage (incompatible with `--watch`)
- `beranode status` in serviceman mode reports launchd job state (`running` / `stopped` / `offline`) for beacond and bera-reth

### Changed

- Public-network `bera-reth` (bepolia/mainnet) no longer includes `--bootnodes` or `--trusted-peers` unless those start flags are set; discovery uses the `--chain` preset instead of official `el-bootnodes.txt` / `el-peers.txt`
- `bera-reth` no longer includes `--ws`, `--ws.addr`, `--ws.port`, or `--ws.origins` unless `beranode start --ws` is set
- Recommended beacond for bepolia is `v1.4.1` (was `v1.4.2-rc.0`)
- `beranode init --network bepolia|mainnet` with `--full-nodes` or `--pruned-nodes` forces `--validators` to 0 so public RPC nodes are not created as validators
- `beranode init` unloads leftover LaunchAgents for the target directory before wiping it on re-init
- `beranode snapshot` treats serviceman launchd jobs as running nodes (blocks restore while they are up)

### Deprecated

### Removed

### Fixed

- `cast wallet new --json` parsing accepts both the current object shape (`.data[0].private_key`) and the legacy array shape (`.[0].private_key`), so EVM wallet generation and bera-reth discovery keys work with newer Foundry
- `validate_path` no longer uses `=~ $'\0'`, which GNU bash treats as an empty regex and rejected every path (including `beranode_dir`)
- `beranode status` BLOCK AGE now treats CometBFT timestamps as UTC on macOS, so a synced node no longer shows an age equal to the local timezone offset
- Local/devnet `bera-reth` mesh uses `127.0.0.1` in `--bootnodes` / `--trusted-peers` (reth cannot dial `localhost`, which may be `::1`) and `--disable-dns-discovery` (local, Docker, and serviceman) so nodes peer with each other instead of public bootnodes

### Security

## [0.10.0] - 2026-08-28

### Added

- Public-network support for Bepolia and Mainnet: `init --network bepolia|mainnet` fetches official seed-data (genesis, KZG, seeds), generates keys without a local genesis, and restores official snapshots
- `beranode snapshot download|restore` for [bepolia.snapshots.berachain.com](https://bepolia.snapshots.berachain.com) and [snapshots.berachain.com](https://snapshots.berachain.com)
- Preflight check that `tar` and `lz4` are installed immediately before snapshot archive downloads
- `--skip-snapshot` and `--snapshot-type pruned|archive` on init; role-mapped defaults (validator/rpc-pruned → pruned, rpc-full → archive)
- `start --external-ip` and bera-reth `--chain bepolia|mainnet` (with `--full` for pruned nodes)
- GitHub Actions workflow that creates a release when a `vX.Y.Z` or `vX.Y.Z-*` tag is pushed
- Prerelease versions (`X.Y.Z-rc.N`, `-alpha.N`, `-beta.N`, `-pre.N`)
- `beranode start` prints each node's listening ports after configure and after start, grouped under `-- bera-reth --` and `-- beacon-kit --`
- `beranode status` shows a `LIVE EL BLOCK` column from the public RPC (`https://bepolia.rpc.berachain.com` or `https://rpc.berachain.com`) on bepolia/mainnet only (omitted on devnet), re-reading `network` from `beranodes.config.json` every 10 seconds

### Changed

- `build.sh` reads `BERANODE_VERSION` from `src/lib/constants.sh` instead of hardcoding it
- Versioning is manual: edit `BERANODE_VERSION`, promote `[Unreleased]`, run `build.sh`, and push a `vX.Y.Z` tag
- `beranode start` launches bepolia/mainnet from `beranodes.config.json` instead of silently no-oping
- Snapshot download asks before overwriting existing `{network}-beacond|reth-{type}-latest.tar.lz4` files; answering no reuses the local copies
- Snapshot restore unzips `{network}-beacond-*-latest.tar.lz4` into `beranodes/snapshots/beacond` and `{network}-reth-*-latest.tar.lz4` into `beranodes/snapshots/reth` (`lz4 -dc … | tar -xvf - -C <dir>`), then copies beacond DBs into each node's `beacond/data` and reth into `bera-reth`
- `beranode init` preserves `beranodes/snapshots/` when re-initializing an existing directory, and mentions that in the overwrite warning
- README changelog and versioning docs match the manual release flow and recommended beacond / bera-reth tags

### Deprecated

### Removed

- `scripts/bump-version.sh` (version bumps are now a manual edit of `BERANODE_VERSION` plus a git tag)

### Fixed

- Beacond snapshot restore now copies CometBFT DBs into `beacond/data` (the `db_dir`) instead of the beacond home, so handshake uses the snapshot height instead of genesis
- Public-network bera-reth now uses official `el-bootnodes.txt` for `--bootnodes` and `el-peers.txt` for `--trusted-peers` (local and Docker), instead of skipping bootnodes or reusing peers as bootnodes
- Download URL matching now recognizes bera-reth cargo target triples (`aarch64-apple-darwin`, `x86_64-unknown-linux-gnu`) in addition to beacond's Go `GOOS-GOARCH` names, so macOS ARM pre-built binaries are used instead of failing with "No download URL found for 'darwin-arm64'"
- GitHub release JSON is no longer mixed with `[INFO]` logs on stdout, which made `jq` fail with `Invalid numeric literal at line 1, column 2` and skip pre-built darwin-arm64 binaries

### Security

## [0.9.0] - 2026-02-16

### Summary

New status and stop functionality for both local and docker modes

### Changed Files

- beranode
- build.sh
- src/commands/common.sh
- src/commands/init.sh
- src/commands/start.sh
- src/commands/stop.sh
- src/core/dispatcher.sh
- src/lib/constants.sh
- src/lib/download.sh
- src/lib/genesis.sh
- src/lib/logging.sh
- src/lib/utils.sh
- CHANGELOG.md.tmp
- src/commands/status.sh
- test.sh
- tests/test_status.sh

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.8.0] - 2026-02-15

### Summary

Full support for docker on mac os

### Changed Files

- beranode
- build.sh
- src/commands/common.sh
- src/commands/init.sh
- src/commands/start.sh
- src/core/dispatcher.sh
- src/lib/constants.sh
- src/lib/download.sh
- src/lib/genesis.sh
- src/lib/logging.sh
- src/lib/utils.sh
- CHANGELOG.md.tmp
- test.sh

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.7.1] - 2026-02-02

### Summary

Refactored for better readibility, fixed pruned-node issues, added initial support for docker

### Changed Files

- README.md
- beranode
- build.sh
- scripts/bump-version.sh
- src/commands/common.sh
- src/commands/init.sh
- src/commands/start.sh
- src/commands/stop.sh
- src/commands/validate.sh
- src/core/dispatcher.sh
- src/lib/constants.sh
- src/lib/download.sh
- src/lib/genesis.sh
- src/lib/logging.sh
- src/lib/utils.sh
- src/lib/validation.sh
- CHANGELOG.md.tmp
- src/lib/argparse.sh
- src/lib/config.sh
- src/lib/errors.sh
- src/lib/json.sh
- tests/

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.6.0] - 2026-01-31

### Summary

Fix bug for one node setup, allow automatic download of binaries and setup

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.6.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.6.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.5.0] - 2026-01-31

### Summary

Support for multiple nodes, refactored beranodes.config.json, and made sure ports aren't conflicting

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.5.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.5.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.4.1] - 2026-01-29

### Summary

Ability to update versioning in files and show all files modified

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.4.1
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.4.1

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.4.0] - 2026-01-29

### Summary

New stop command, and ability to start 1 full val node

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.4.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.4.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.3.0] - 2026-01-27

### Summary

Added validation functionlality for beranodes.config.json

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.3.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.3.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.2.1] - 2026-01-27

### Summary

Added additional help commands for init and start

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.2.1
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.2.1

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.2.0] - 2026-01-27

### Summary

Support for config.toml,client.toml, and app.toml configurations to beranodes.config.json

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.2.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.2.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.2] - 2026-01-27

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.1.2
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.1.2

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.1] - 2026-01-27

### Summary

Add version management with description support and changelog automation

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.1.1
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.1.1

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.0] - 2026-01-26

### Added

- Initial release of beranode CLI
- Node management commands
- Network configuration support

[Unreleased]: https://github.com/berachain/beranode-cli/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/berachain/beranode-cli/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/berachain/beranode-cli/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/berachain/beranode-cli/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/berachain/beranode-cli/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/berachain/beranode-cli/compare/v0.8.0...v0.7.1
[0.6.0]: https://github.com/berachain/beranode-cli/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/berachain/beranode-cli/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/berachain/beranode-cli/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/berachain/beranode-cli/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/berachain/beranode-cli/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/berachain/beranode-cli/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/berachain/beranode-cli/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/berachain/beranode-cli/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/berachain/beranode-cli/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/berachain/beranode-cli/releases/tag/v0.1.0
